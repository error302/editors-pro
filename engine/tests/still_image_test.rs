use editors_pro_engine::api::EditorsProEngine;
use editors_pro_engine::timeline::track::TrackType;
use image::{Rgba, RgbaImage};

#[test]
fn imported_still_image_remains_visible_across_its_timeline_duration() {
    let directory = tempfile::tempdir().unwrap();
    let image_path = directory.path().join("photo.png");
    RgbaImage::from_pixel(4, 3, Rgba([12, 34, 56, 255]))
        .save(&image_path)
        .unwrap();

    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Still image QA", None).unwrap();
    let photo_track = engine
        .add_track(TrackType::Video, Some("Photo".to_string()))
        .unwrap();
    let asset = engine.import_media(image_path.to_str().unwrap()).unwrap();

    assert_eq!(asset.media_type, "Image");
    assert_eq!((asset.width, asset.height), (Some(4), Some(3)));
    engine
        .add_clip(&photo_track.id, &asset.id, 0, 5_000)
        .unwrap();

    for time_ms in [0, 2_500, 4_999] {
        let frame = engine.get_frame(time_ms).unwrap();
        assert_eq!(&frame.data[..4], &[12, 34, 56, 255]);
    }

    let project_path = directory.path().join("still-image.epp");
    engine.save_project(project_path.to_str().unwrap()).unwrap();
    engine.load_project(project_path.to_str().unwrap()).unwrap();

    let timeline = engine.get_timeline_state().unwrap();
    assert!(timeline.tracks.iter().any(|track| {
        track.id == photo_track.id
            && track
                .clips
                .iter()
                .any(|clip| clip.asset_id == asset.id && clip.duration_ms == 5_000)
    }));
    for time_ms in [0, 2_500, 4_999] {
        let frame = engine.get_frame(time_ms).unwrap();
        assert_eq!(&frame.data[..4], &[12, 34, 56, 255]);
    }
}
