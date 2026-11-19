use editors_pro_engine::api::EditorsProEngine;
use editors_pro_engine::effects::{Effect, EffectsPipeline};
use editors_pro_engine::effects::filters::{FilterPreset, FilterType};
use editors_pro_engine::project::ProjectSettings;
use editors_pro_engine::timeline::track::TrackType;
use image::{Rgba, RgbaImage};

fn patches() -> Vec<u8> {
    [[160, 90, 55, 255], [20, 160, 90, 127], [50, 80, 180, 255], [128, 128, 128, 0]]
        .into_iter().flatten().collect()
}

#[test]
fn every_native_look_changes_pixels_and_zero_or_bypass_is_exact_identity() {
    let original = patches();
    let recipes = FilterPreset::built_in_presets();
    assert_eq!(recipes.len(), 8);
    for recipe in recipes {
        let mut full = original.clone();
        EffectsPipeline::new(recipe.to_effects()).apply(&mut full, 2, 2);
        assert_ne!(full, original, "{} must visibly affect representative pixels", recipe.id);
        for (intensity, enabled) in [(0.0, true), (1.0, false)] {
            let mut actual = original.clone();
            EffectsPipeline::new(recipe.to_effects_with_intensity(intensity, enabled).unwrap()).apply(&mut actual, 2, 2);
            assert_eq!(actual, original, "{} intensity={intensity} enabled={enabled}", recipe.id);
        }
        for (before, after) in original.chunks_exact(4).zip(full.chunks_exact(4)) {
            assert_eq!(before[3], after[3], "Look must preserve alpha");
        }
        let half = recipe.to_effects_with_intensity(0.5, true).unwrap();
        for (full_effect, half_effect) in recipe.to_effects().iter().zip(&half) {
            for (target, actual) in full_effect.parameters.iter().zip(&half_effect.parameters) {
                if target.name.starts_with("__look_") || target.name == "vignette_radius" { continue; }
                let neutral = if target.name == "saturation" { 1.0 } else { 0.0 };
                assert!((actual.value - (neutral + target.value) / 2.0).abs() < 1e-6);
            }
        }
    }
}

#[test]
fn invalid_intensity_and_filter_parameters_are_rejected_without_mutation() {
    let recipe = FilterPreset::built_in_presets().remove(0);
    for value in [f32::NAN, f32::INFINITY, -0.1, 1.1] {
        assert!(recipe.to_effects_with_intensity(value, true).is_err());
    }
    let mut effect = FilterType::Brightness.to_effect();
    for value in [f32::NAN, f32::INFINITY, -1.1, 1.1] {
        assert!(effect.set_parameter("brightness", value).is_err());
        assert_eq!(effect.get_parameter("brightness"), Some(0.0));
    }
    assert!(effect.set_parameter("made_up_parameter", 0.2).is_err());
}

#[test]
fn look_change_reset_and_undo_preserve_manual_and_chroma_effects() {
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Look history", None).unwrap();
    let track = engine.add_track(TrackType::Video, Some("Photo".into())).unwrap();
    let directory = tempfile::tempdir_in(env!("CARGO_MANIFEST_DIR")).unwrap();
    let photo = directory.path().join("history.png");
    RgbaImage::from_pixel(2, 2, Rgba([160, 90, 55, 255])).save(&photo).unwrap();
    let asset = engine.import_media(photo.to_str().unwrap()).unwrap();
    let clip = engine.add_clip(&track.id, &asset.id, 0, 1000).unwrap();
    let brightness = engine.add_effect(&clip.id, "Brightness").unwrap();
    engine.set_effect_parameter(&clip.id, &brightness.id, "brightness", 0.1).unwrap();
    engine.add_effect(&clip.id, "Chroma Key").unwrap();
    let before = serde_json::to_value(engine.get_clip_effects(&clip.id).unwrap()).unwrap();
    engine.set_filter_look(&clip.id, "warm", 0.7, true).unwrap();
    let warm = serde_json::to_value(engine.get_clip_effects(&clip.id).unwrap()).unwrap();
    assert_eq!(&warm.as_array().unwrap()[..2], before.as_array().unwrap());
    engine.undo().unwrap();
    assert_eq!(serde_json::to_value(engine.get_clip_effects(&clip.id).unwrap()).unwrap(), before);
    engine.redo().unwrap();
    assert_eq!(serde_json::to_value(engine.get_clip_effects(&clip.id).unwrap()).unwrap(), warm);
    engine.set_filter_look(&clip.id, "noir", 0.4, true).unwrap();
    engine.undo().unwrap();
    assert_eq!(serde_json::to_value(engine.get_clip_effects(&clip.id).unwrap()).unwrap(), warm);
    engine.set_filter_look(&clip.id, "", 1.0, true).unwrap();
    assert_eq!(serde_json::to_value(engine.get_clip_effects(&clip.id).unwrap()).unwrap(), before);
    engine.undo().unwrap();
    assert_eq!(serde_json::to_value(engine.get_clip_effects(&clip.id).unwrap()).unwrap(), warm);
    assert!(engine.set_filter_look(&clip.id, "not_supported", 0.5, true).is_err());
    assert_eq!(serde_json::to_value(engine.get_clip_effects(&clip.id).unwrap()).unwrap(), warm);
    // Adjustments added after a look retain their position when its length changes.
    let trailing = engine.add_effect(&clip.id, "Hue").unwrap();
    let before_change = serde_json::to_value(engine.get_clip_effects(&clip.id).unwrap()).unwrap();
    engine.set_filter_look(&clip.id, "cinematic", 0.5, true).unwrap();
    let changed = engine.get_clip_effects(&clip.id).unwrap();
    assert_eq!(changed.last().unwrap().id, trailing.id);
    engine.undo().unwrap();
    assert_eq!(serde_json::to_value(engine.get_clip_effects(&clip.id).unwrap()).unwrap(), before_change);
}

#[test]
fn look_recipe_metadata_and_pixels_survive_real_project_save_reload() {
    let directory = tempfile::tempdir_in(env!("CARGO_MANIFEST_DIR")).unwrap();
    let photo = directory.path().join("patches.png");
    RgbaImage::from_pixel(4, 4, Rgba([160, 90, 55, 255])).save(&photo).unwrap();
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Look persistence", Some(ProjectSettings { width: 4, height: 4, ..Default::default() })).unwrap();
    let track = engine.add_track(TrackType::Video, Some("Photo".into())).unwrap();
    let asset = engine.import_media(photo.to_str().unwrap()).unwrap();
    let clip = engine.add_clip(&track.id, &asset.id, 0, 1000).unwrap();
    engine.set_filter_look(&clip.id, "warm", 0.65, true).unwrap();
    let before = engine.get_frame(500).unwrap();
    let effects = serde_json::to_value(engine.get_clip_effects(&clip.id).unwrap()).unwrap();
    let project = directory.path().join("look.epp");
    engine.save_project(project.to_str().unwrap()).unwrap();
    engine.load_project(project.to_str().unwrap()).unwrap();
    assert_eq!(serde_json::to_value(engine.get_clip_effects(&clip.id).unwrap()).unwrap(), effects);
    assert_eq!(engine.get_frame(500).unwrap().data, before.data);
    let encoded = serde_json::to_string(&FilterPreset::built_in_presets()[0].to_effects()).unwrap();
    let decoded: Vec<Effect> = serde_json::from_str(&encoded).unwrap();
    assert!(decoded[0].id.starts_with("look:clean:"));
    assert_eq!(decoded[0].get_parameter("__look_version"), Some(1.0));
}
