use std::ffi::{CStr, CString};
use std::time::{Duration, Instant};

use editors_pro_engine::api::ffi_dispatch::{editors_pro_dispatch, editors_pro_free_string};
use editors_pro_engine::api::project_preview::{
    clone_saved_project, job_status, release_job, start_job, CloneRequest, PreviewRequest,
};
use editors_pro_engine::api::EditorsProEngine;
use editors_pro_engine::project::Project;
use editors_pro_engine::timeline::track::TrackType;
use image::{Rgba, RgbaImage};
use serde_json::{json, Value};

fn dispatch(method: &str, args: Value) -> Value {
    let method = CString::new(method).unwrap();
    let args = CString::new(args.to_string()).unwrap();
    unsafe {
        let result = editors_pro_dispatch(method.as_ptr(), args.as_ptr());
        let response: Value = serde_json::from_slice(CStr::from_ptr(result).to_bytes()).unwrap();
        editors_pro_free_string(result);
        assert_eq!(response["ok"], true, "{response}");
        response["data"].clone()
    }
}

#[test]
fn saved_edited_cover_does_not_change_active_project_or_undo_history() {
    let directory = tempfile::tempdir().unwrap();
    let source = directory.path().join("blue.png");
    RgbaImage::from_pixel(16, 9, Rgba([0, 0, 200, 255]))
        .save(&source)
        .unwrap();
    let saved = directory.path().join("saved-b.epp");
    let mut builder = EditorsProEngine::new();
    builder.initialize().unwrap();
    builder.create_project("Saved B", None).unwrap();
    let track = builder
        .add_track(TrackType::Video, Some("B".into()))
        .unwrap();
    let asset = builder.import_media(source.to_str().unwrap()).unwrap();
    builder.add_clip(&track.id, &asset.id, 500, 2000).unwrap();
    builder.save_project(saved.to_str().unwrap()).unwrap();
    // A visible timeline edit makes the expected cover differ from source pixels.
    let mut edited = Project::load_from_epp(&saved).unwrap();
    edited
        .timeline
        .tracks
        .iter_mut()
        .flat_map(|track| track.clips.iter_mut())
        .for_each(|clip| clip.opacity = 0.5);
    edited.save_as_epp(&saved).unwrap();
    let original_bytes = std::fs::read(&saved).unwrap();

    dispatch("initialize", json!({}));
    dispatch("create_project", json!({"name": "Unsaved active A"}));
    let active_asset = dispatch("import_media", json!({"file_path": source}));
    let active_track = dispatch("add_track", json!({"track_type": "Video", "name": "A"}));
    dispatch(
        "add_clip",
        json!({"track_id": active_track["id"], "asset_id": active_asset["id"], "start_ms": 0, "duration_ms": 9000}),
    );
    let active_info = dispatch("get_project_info", json!({}));
    let active_timeline = dispatch("get_timeline_state", json!({}));
    let undo = dispatch("can_undo", json!({}));
    assert_eq!(undo, true);

    let copy_path = directory.path().join("copy.epp");
    let copy = clone_saved_project(CloneRequest {
        source_path: saved.to_string_lossy().into_owned(),
        output_path: copy_path.to_string_lossy().into_owned(),
        project_id: "copied-project".into(),
        name: "Saved B (copy)".into(),
    })
    .unwrap();
    assert_eq!(copy.name, "Saved B (copy)");
    assert_eq!(copy.id, "copied-project");
    assert_ne!(copy.media_assets[0].id, edited.media_assets[0].id);
    assert_eq!(
        copy.media_assets[0].file_path,
        edited.media_assets[0].file_path
    );
    let copied_clip = copy
        .timeline
        .tracks
        .iter()
        .flat_map(|track| track.clips.iter())
        .next()
        .unwrap();
    assert_eq!(copied_clip.asset_id, copy.media_assets[0].id);
    assert_eq!(copied_clip.opacity, 0.5);
    assert_eq!(copied_clip.start_ms, 500);
    assert_eq!(copied_clip.duration_ms, 2000);
    assert_eq!(dispatch("get_project_info", json!({})), active_info);
    assert_eq!(dispatch("get_timeline_state", json!({})), active_timeline);
    assert_eq!(dispatch("can_undo", json!({})), undo);

    let cover = directory.path().join("cover.png");
    let status = start_job(PreviewRequest {
        project_path: saved.to_string_lossy().into_owned(),
        cover_path: cover.to_string_lossy().into_owned(),
        video_path: None,
    })
    .unwrap();
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        let status = job_status(&status.job_id).unwrap();
        if status.finished {
            assert!(status.error.is_none(), "{:?}", status.error);
            assert!(status.cover_ready);
            assert!(!status.video_ready);
            assert_eq!(status.duration_ms, 2500);
            release_job(&status.job_id).unwrap();
            break;
        }
        assert!(Instant::now() < deadline, "preview worker did not finish");
        std::thread::sleep(Duration::from_millis(10));
    }
    let cover = image::open(cover).unwrap().to_rgba8();
    assert_eq!((cover.width(), cover.height()), (854, 480));
    assert_eq!(
        cover.get_pixel(427, 240)[2],
        100,
        "cover must include saved opacity edit"
    );
    assert_eq!(std::fs::read(saved).unwrap(), original_bytes);
    assert_eq!(dispatch("get_project_info", json!({})), active_info);
    assert_eq!(dispatch("get_timeline_state", json!({})), active_timeline);
    assert_eq!(dispatch("can_undo", json!({})), undo);
}
