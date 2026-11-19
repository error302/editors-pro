use editors_pro_engine::api::EditorsProEngine;
use editors_pro_engine::project::{Project, ProjectSettings};
use editors_pro_engine::timeline::track::TrackType;
use image::{Rgba, RgbaImage};

fn settings(width: u32, height: u32) -> ProjectSettings {
    ProjectSettings { width, height, ..ProjectSettings::default() }
}

#[test]
fn empty_portrait_canvas_has_requested_size_and_opaque_background() {
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Portrait", Some(settings(32, 48))).unwrap();
    let frame = engine.get_frame(300).unwrap();
    assert_eq!((frame.width, frame.height), (32, 48));
    assert!(frame.data.chunks_exact(4).all(|pixel| pixel == [0, 0, 0, 255]));
    assert_eq!(frame.timestamp_ms, 300);
}

#[test]
fn photographs_fit_the_project_canvas_without_stretching() {
    let directory = tempfile::tempdir().unwrap();
    let source = directory.path().join("wide.png");
    RgbaImage::from_pixel(8, 4, Rgba([200, 40, 20, 255])).save(&source).unwrap();
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Square photo", Some(settings(32, 32))).unwrap();
    let track = engine.add_track(TrackType::Video, Some("Photo".into())).unwrap();
    let asset = engine.import_media(source.to_str().unwrap()).unwrap();
    engine.add_clip(&track.id, &asset.id, 0, 1_000).unwrap();
    let frame = engine.get_frame(500).unwrap();
    assert_eq!((frame.width, frame.height), (32, 32));
    assert_eq!(&frame.data[..4], &[0, 0, 0, 255]);
    let center = ((16 * 32 + 16) * 4) as usize;
    assert_eq!(&frame.data[center..center + 4], &[200, 40, 20, 255]);
}

#[test]
fn visible_video_tracks_blend_in_order_and_hidden_tracks_do_not_render() {
    let directory = tempfile::tempdir().unwrap();
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Layers", Some(settings(16, 16))).unwrap();
    let mut track_ids = Vec::new();
    let mut clip_ids = Vec::new();
    for (name, color) in [("Base", [255, 0, 0, 255]), ("Top", [0, 0, 255, 255])] {
        let source = directory.path().join(format!("{name}.png"));
        RgbaImage::from_pixel(16, 16, Rgba(color)).save(&source).unwrap();
        let track = engine.add_track(TrackType::Video, Some(name.into())).unwrap();
        let asset = engine.import_media(source.to_str().unwrap()).unwrap();
        let clip = engine.add_clip(&track.id, &asset.id, 0, 1_000).unwrap();
        track_ids.push(track.id);
        clip_ids.push(clip.id);
    }
    let path = directory.path().join("layers.epp");
    engine.save_project(path.to_str().unwrap()).unwrap();
    let mut saved = Project::load_from_epp(&path).unwrap();
    for track in &mut saved.timeline.tracks {
        if track.id == track_ids[0] { track.order_index = 1; }
        if track.id == track_ids[1] { track.order_index = 0; track.clips[0].opacity = 0.5; }
    }
    saved.save_as_epp(&path).unwrap();
    engine.load_project(path.to_str().unwrap()).unwrap();
    let frame = engine.get_frame(500).unwrap();
    assert_eq!((frame.width, frame.height), (16, 16));
    assert!((i16::from(frame.data[0]) - 128).abs() <= 1);
    assert_eq!(frame.data[1], 0);
    assert!((i16::from(frame.data[2]) - 128).abs() <= 1);
    assert_eq!(frame.data[3], 255);

    saved.timeline.tracks.iter_mut().find(|track| track.id == track_ids[1]).unwrap().visible = false;
    saved.save_as_epp(&path).unwrap();
    engine.load_project(path.to_str().unwrap()).unwrap();
    assert_eq!(&engine.get_frame(500).unwrap().data[..4], &[255, 0, 0, 255]);
}
