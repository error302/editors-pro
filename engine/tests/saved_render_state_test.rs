use editors_pro_engine::api::EditorsProEngine;
use editors_pro_engine::audio::effects::{EqBand, EqSettings};
use editors_pro_engine::effects::lut::{Lut, Lut1D};
use editors_pro_engine::project::{Project, ProjectRenderState, ProjectSettings};
use editors_pro_engine::timeline::track::TrackType;
use image::{Rgba, RgbaImage};

fn engine() -> EditorsProEngine {
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine
}

fn invert_lut() -> Lut {
    Lut::Lut1D(Lut1D {
        size: 2,
        table: [vec![1.0, 0.0], vec![1.0, 0.0], vec![1.0, 0.0]],
    })
}

#[test]
fn saved_lut_and_track_audio_edits_restore_in_a_private_preview_engine() {
    let directory = tempfile::tempdir_in(env!("CARGO_MANIFEST_DIR")).unwrap();
    let source = directory.path().join("portrait.png");
    RgbaImage::from_pixel(4, 6, Rgba([32, 64, 96, 255]))
        .save(&source)
        .unwrap();
    let mut editing = engine();
    editing
        .create_project(
            "Edited portrait",
            Some(ProjectSettings {
                width: 32,
                height: 48,
                ..Default::default()
            }),
        )
        .unwrap();
    let video = editing.add_track(TrackType::Video, None).unwrap();
    let audio = editing.add_track(TrackType::Audio, None).unwrap();
    let asset = editing.import_media(source.to_str().unwrap()).unwrap();
    editing.add_clip(&video.id, &asset.id, 0, 1000).unwrap();
    let original = editing.get_frame(250).unwrap();
    editing.set_active_lut(invert_lut(), 0.4);
    editing.set_track_pan(&audio.id, -0.75);
    editing.set_track_solo(&audio.id, true);
    let eq = EqSettings {
        enabled: true,
        high_pass_hz: 80.0,
        low_pass_hz: 15000.0,
        bands: vec![EqBand {
            frequency: 1000.0,
            gain_db: 4.5,
            q: 1.2,
            enabled: true,
        }],
    };
    editing.set_track_eq_settings(&audio.id, eq.clone());
    editing.set_ducking(audio.id.clone(), true, 0.2).unwrap();
    let edited = editing.get_frame(250).unwrap();
    assert_eq!((edited.width, edited.height), (32, 48));
    assert_ne!(
        edited.data, original.data,
        "LUT must visibly change rendered pixels"
    );
    let saved = directory.path().join("edited.epp");
    editing.save_project(saved.to_str().unwrap()).unwrap();

    let mut isolated_preview = engine();
    isolated_preview
        .load_project(saved.to_str().unwrap())
        .unwrap();
    assert_eq!(isolated_preview.get_frame(250).unwrap().data, edited.data);
    assert_eq!(isolated_preview.get_active_lut().unwrap().1, 0.4);
    assert_eq!(isolated_preview.get_track_pan(&audio.id), -0.75);
    assert!(isolated_preview.get_track_solo(&audio.id));
    assert_eq!(
        serde_json::to_value(isolated_preview.get_track_eq_settings(&audio.id)).unwrap(),
        serde_json::to_value(Some(&eq)).unwrap()
    );
    assert_eq!(
        isolated_preview.get_ducking_config(&audio.id).duck_level,
        0.2
    );
    assert!(isolated_preview.get_ducking_config(&audio.id).enabled);

    // The editing engine remains on its own state while private previews are loaded.
    isolated_preview
        .create_project(
            "Another project",
            Some(ProjectSettings {
                width: 16,
                height: 16,
                ..Default::default()
            }),
        )
        .unwrap();
    assert!(isolated_preview.get_active_lut().is_none());
    assert!(!isolated_preview.any_track_soloed());
    assert_eq!(isolated_preview.get_track_pan(&audio.id), 0.0);
    assert!(isolated_preview.get_track_eq_settings(&audio.id).is_none());
    assert!(!isolated_preview.get_ducking_config(&audio.id).enabled);
    assert_eq!(editing.get_frame(250).unwrap().data, edited.data);

    editing.clear_active_lut();
    editing.save_project(saved.to_str().unwrap()).unwrap();
    isolated_preview
        .load_project(saved.to_str().unwrap())
        .unwrap();
    assert!(isolated_preview.get_active_lut().is_none());
    assert_eq!(isolated_preview.get_frame(250).unwrap().data, original.data);
}

#[test]
fn switching_projects_clears_decoded_image_and_audio_caches_even_when_asset_ids_repeat() {
    let directory = tempfile::tempdir_in(env!("CARGO_MANIFEST_DIR")).unwrap();
    let red = directory.path().join("red.png");
    let blue = directory.path().join("blue.png");
    RgbaImage::from_pixel(16, 16, Rgba([255, 0, 0, 255]))
        .save(&red)
        .unwrap();
    RgbaImage::from_pixel(16, 16, Rgba([0, 0, 255, 255]))
        .save(&blue)
        .unwrap();
    let mut editing = engine();
    editing
        .create_project(
            "Red",
            Some(ProjectSettings {
                width: 16,
                height: 16,
                ..Default::default()
            }),
        )
        .unwrap();
    let track = editing.add_track(TrackType::Video, None).unwrap();
    let asset = editing.import_media(red.to_str().unwrap()).unwrap();
    editing.add_clip(&track.id, &asset.id, 0, 1000).unwrap();
    assert_eq!(
        &editing.get_frame(250).unwrap().data[..4],
        &[255, 0, 0, 255]
    );
    editing.set_audio_samples("cache-only", vec![0.1; 16], 44100, 2);
    assert!(editing.get_audio_samples("cache-only").is_ok());
    let first = directory.path().join("red.epp");
    editing.save_project(first.to_str().unwrap()).unwrap();
    let mut second = Project::load_from_epp(&first).unwrap();
    second.id = "different-project-with-shared-asset-id".into();
    second.name = "Blue".into();
    second.media_assets[0].file_path = blue.to_str().unwrap().into();
    let second_path = directory.path().join("blue.epp");
    second.save_as_epp(&second_path).unwrap();
    editing.load_project(second_path.to_str().unwrap()).unwrap();
    assert_eq!(
        &editing.get_frame(250).unwrap().data[..4],
        &[0, 0, 255, 255]
    );
    assert!(editing.get_audio_samples("cache-only").is_err());
    editing.load_project(first.to_str().unwrap()).unwrap();
    assert_eq!(
        &editing.get_frame(250).unwrap().data[..4],
        &[255, 0, 0, 255]
    );
}

#[test]
fn legacy_projects_default_render_state_and_corrupt_loads_preserve_the_open_project() {
    let directory = tempfile::tempdir_in(env!("CARGO_MANIFEST_DIR")).unwrap();
    let legacy = Project::with_settings(
        "Legacy",
        ProjectSettings {
            width: 12,
            height: 20,
            ..Default::default()
        },
    );
    let mut json = serde_json::to_value(&legacy).unwrap();
    json.as_object_mut().unwrap().remove("render_state");
    let legacy: Project = serde_json::from_value(json).unwrap();
    assert!(legacy.render_state.is_none());
    let path = directory.path().join("legacy.epp");
    legacy.save_as_epp(&path).unwrap();
    let mut editing = engine();
    editing.create_project("Before legacy", None).unwrap();
    editing.set_active_lut(invert_lut(), 1.0);
    editing.set_track_pan("old-track", 0.5);
    editing.set_track_solo("old-track", true);
    editing.load_project(path.to_str().unwrap()).unwrap();
    assert!(editing.get_active_lut().is_none());
    assert!(!editing.any_track_soloed());
    assert_eq!(
        (
            editing.get_frame(0).unwrap().width,
            editing.get_frame(0).unwrap().height
        ),
        (12, 20)
    );
    let before_id = editing.get_project_info().unwrap().id;

    let mut invalid = legacy.clone();
    invalid.render_state = Some(ProjectRenderState {
        active_lut: Some(Lut::Lut1D(Lut1D {
            size: 2,
            table: [vec![], vec![], vec![]],
        })),
        ..Default::default()
    });
    let corrupt = directory.path().join("corrupt.epp");
    invalid.save_as_epp(&corrupt).unwrap();
    assert!(editing.load_project(corrupt.to_str().unwrap()).is_err());
    assert_eq!(editing.get_project_info().unwrap().id, before_id);
    invalid.render_state = None;
    invalid.settings.width = 0;
    invalid.save_as_epp(&corrupt).unwrap();
    assert!(editing.load_project(corrupt.to_str().unwrap()).is_err());
    assert_eq!(editing.get_project_info().unwrap().id, before_id);
    assert!(ProjectSettings {
        width: 7680,
        height: 4320,
        ..Default::default()
    }
    .validate_for_rendering()
    .is_ok());
    assert!(ProjectSettings {
        width: 8193,
        height: 1,
        ..Default::default()
    }
    .validate_for_rendering()
    .is_err());
}
