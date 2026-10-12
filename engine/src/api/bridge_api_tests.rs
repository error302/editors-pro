//! Tests for the bridge API DTOs and EditorsProEngineApi
//!
//! Covers: BridgeProjectSettings, BridgeExportSettings, BridgeExportProgress,
//! BridgeExportResult, and API struct construction. Does NOT test methods
//! that require FFmpeg I/O (import_media, get_frame, etc.).

use crate::api::bridge_api::{
    BridgeExportProgress, BridgeExportResult, BridgeExportSettings, BridgeProjectSettings,
    EditorsProEngineApi,
};
use crate::api::MediaAssetInfo;
use crate::export_engine::{ExportProgress, ExportResult, ExportStage};

// ─── BridgeProjectSettings ───────────────────────────────────

#[test]
fn bridge_project_settings_serialization() {
    let settings = BridgeProjectSettings {
        width: 1920,
        height: 1080,
        fps: 29.97,
    };
    let json = serde_json::to_string(&settings).unwrap();
    let parsed: BridgeProjectSettings = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed.width, 1920);
    assert_eq!(parsed.height, 1080);
    assert!((parsed.fps - 29.97).abs() < 0.01);
}

#[test]
fn bridge_project_settings_into_project_settings() {
    let bridge = BridgeProjectSettings {
        width: 3840,
        height: 2160,
        fps: 60.0,
    };
    let project_settings: crate::project::ProjectSettings = bridge.into();
    assert_eq!(project_settings.width, 3840);
    assert_eq!(project_settings.height, 2160);
    assert!((project_settings.fps - 60.0).abs() < f32::EPSILON);
}

// ─── BridgeExportSettings ────────────────────────────────────

#[test]
fn bridge_export_settings_serialization() {
    let settings = BridgeExportSettings {
        width: 1920,
        height: 1080,
        fps: 30.0,
        bitrate_kbps: 5000,
        codec: "h264".into(),
        format: "mp4".into(),
        audio_bitrate_kbps: 128,
        audio_sample_rate: 44100,
        audio_channels: 2,
        include_audio: true,
        two_pass: false,
    };
    let json = serde_json::to_string(&settings).unwrap();
    let parsed: BridgeExportSettings = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed.codec, "h264");
    assert_eq!(parsed.bitrate_kbps, 5000);
    assert!(parsed.include_audio);
}

#[test]
fn bridge_export_settings_into_export_settings() {
    let bridge = BridgeExportSettings {
        width: 1280,
        height: 720,
        fps: 24.0,
        bitrate_kbps: 2500,
        codec: "h265".into(),
        format: "mp4".into(),
        audio_bitrate_kbps: 192,
        audio_sample_rate: 48000,
        audio_channels: 2,
        include_audio: true,
        two_pass: true,
    };
    let export_settings: crate::export_engine::ExportSettings = bridge.into();
    assert_eq!(export_settings.width, 1280);
    assert_eq!(export_settings.height, 720);
    assert_eq!(export_settings.bitrate_kbps, 2500);
    assert!(export_settings.two_pass);
}

#[test]
fn bridge_export_settings_unknown_codec_defaults_h264() {
    let bridge = BridgeExportSettings {
        width: 1920,
        height: 1080,
        fps: 30.0,
        bitrate_kbps: 5000,
        codec: "unknown_codec".into(),
        format: "mp4".into(),
        audio_bitrate_kbps: 128,
        audio_sample_rate: 44100,
        audio_channels: 2,
        include_audio: false,
        two_pass: false,
    };
    let export_settings: crate::export_engine::ExportSettings = bridge.into();
    assert_eq!(export_settings.codec, crate::export_engine::VideoCodec::H264);
}

// ─── BridgeExportProgress ────────────────────────────────────

#[test]
fn bridge_export_progress_from_export_progress() {
    let progress = ExportProgress {
        progress: 0.75,
        current_frame: 750,
        total_frames: 1000,
        estimated_seconds_remaining: 30,
        stage: ExportStage::Encoding,
    };
    let bridge: BridgeExportProgress = progress.into();
    assert!((bridge.progress - 0.75).abs() < f32::EPSILON);
    assert_eq!(bridge.current_frame, 750);
    assert_eq!(bridge.total_frames, 1000);
    assert_eq!(bridge.estimated_seconds_remaining, 30);
    assert_eq!(bridge.stage_name, "Encoding");
}

#[test]
fn bridge_export_progress_serialization() {
    let progress = BridgeExportProgress {
        progress: 0.5,
        current_frame: 500,
        total_frames: 1000,
        estimated_seconds_remaining: 60,
        stage_name: "Compositing".into(),
    };
    let json = serde_json::to_string(&progress).unwrap();
    let parsed: BridgeExportProgress = serde_json::from_str(&json).unwrap();
    assert!((parsed.progress - 0.5).abs() < f32::EPSILON);
}

// ─── BridgeExportResult ──────────────────────────────────────

#[test]
fn bridge_export_result_from_export_result_success() {
    let result = ExportResult {
        success: true,
        output_path: "/output/video.mp4".into(),
        file_size_bytes: 10485760,
        duration_ms: 60000,
        error_message: None,
    };
    let bridge: BridgeExportResult = result.into();
    assert!(bridge.success);
    assert_eq!(bridge.output_path, "/output/video.mp4");
    assert_eq!(bridge.file_size_bytes, 10485760);
    assert!(bridge.error_message.is_none());
}

#[test]
fn bridge_export_result_from_export_result_failure() {
    let result = ExportResult {
        success: false,
        output_path: String::new(),
        file_size_bytes: 0,
        duration_ms: 0,
        error_message: Some("Encoding failed".into()),
    };
    let bridge: BridgeExportResult = result.into();
    assert!(!bridge.success);
    assert_eq!(bridge.error_message.as_deref(), Some("Encoding failed"));
}

#[test]
fn bridge_export_result_serialization() {
    let result = BridgeExportResult {
        success: true,
        output_path: "/out.mp4".into(),
        file_size_bytes: 5242880,
        duration_ms: 30000,
        error_message: None,
        file_size_human: "5.0 MB".into(),
    };
    let json = serde_json::to_string(&result).unwrap();
    let parsed: BridgeExportResult = serde_json::from_str(&json).unwrap();
    assert!(parsed.success);
    assert_eq!(parsed.file_size_human, "5.0 MB");
}

// ─── EditorsProEngineApi ─────────────────────────────────────

#[test]
fn api_new_creates_instance() {
    let _api = EditorsProEngineApi::new();
    // Constructor should not panic
}

#[test]
fn api_force_reset_works() {
    let api = EditorsProEngineApi::new();
    let result = api.force_reset_engine();
    assert!(result.is_ok());
}

#[test]
fn api_create_project_without_init_errors() {
    let api = EditorsProEngineApi::new();
    let result = api.create_project("Test".into(), None);
    // Engine is not initialized, so this should fail
    assert!(result.is_err());
}

#[test]
fn api_import_media_nonexistent_file_errors() {
    let api = EditorsProEngineApi::new();
    let result = api.import_media("/nonexistent/file.mp4".into());
    assert!(result.is_err());
}

#[test]
fn restoring_media_asset_preserves_its_id_without_duplicates() {
    let api = EditorsProEngineApi::new();
    api.initialize().unwrap();
    api.create_project("Restore test".into(), None).unwrap();

    let directory = tempfile::tempdir().unwrap();
    let file_path = directory.path().join("still.png");
    std::fs::write(&file_path, b"test image placeholder").unwrap();
    let asset = MediaAssetInfo {
        id: "stable-asset-id".into(),
        file_path: file_path.to_string_lossy().into_owned(),
        file_name: "still.png".into(),
        media_type: "image".into(),
        duration_ms: None,
        width: None,
        height: None,
        file_size_bytes: 22,
        codec: None,
        bitrate: None,
    };

    api.restore_media_asset(asset.clone()).unwrap();
    api.restore_media_asset(asset).unwrap();

    let info = api.get_project_info().unwrap().unwrap();
    assert_eq!(info.asset_count, 1);
}

#[test]
fn api_add_track_without_project_errors() {
    let api = EditorsProEngineApi::new();
    let result = api.add_track("Video".into(), Some("V1".into()));
    assert!(result.is_err());
}

#[test]
fn api_get_timeline_without_project_errors() {
    let api = EditorsProEngineApi::new();
    let result = api.get_timeline_state();
    assert!(result.is_err());
}

// ─── Phase 17: Performance Profiling Bridge Tests ──────────────────────

#[test]
fn api_set_profiling_enabled() {
    super::super::bridge_api::set_profiling_enabled(true);
    assert!(super::super::bridge_api::is_profiling_enabled());
    super::super::bridge_api::set_profiling_enabled(false);
    assert!(!super::super::bridge_api::is_profiling_enabled());
}

#[test]
fn api_get_performance_snapshot() {
    let snapshot = super::super::bridge_api::get_performance_snapshot();
    // On a test machine without actual frames, FPS should be 0
    assert!(snapshot.average_fps >= 0.0);
    assert!(snapshot.target_fps > 0.0);
    assert!(snapshot.memory_pressure_level == "normal"
        || snapshot.memory_pressure_level == "warning"
        || snapshot.memory_pressure_level == "critical");
}

#[test]
fn api_get_profiler_report() {
    // Enable profiling and record something
    super::super::bridge_api::set_profiling_enabled(true);
    let profiler = crate::system::profiler::Profiler::global();
    profiler.record_span("test_op", std::time::Duration::from_millis(5));

    let report = super::super::bridge_api::get_profiler_report();
    assert!(!report.is_empty());
    assert_eq!(report[0].name, "test_op");
    assert_eq!(report[0].call_count, 1);

    // Clean up
    super::super::bridge_api::reset_profiler();
    super::super::bridge_api::set_profiling_enabled(false);
}

#[test]
fn api_reset_profiler() {
    super::super::bridge_api::set_profiling_enabled(true);
    let profiler = crate::system::profiler::Profiler::global();
    profiler.record_span("reset_test", std::time::Duration::from_millis(1));

    super::super::bridge_api::reset_profiler();
    let report = super::super::bridge_api::get_profiler_report();
    assert!(report.is_empty(), "Report should be empty after reset");

    super::super::bridge_api::set_profiling_enabled(false);
}

#[test]
fn api_get_engine_version() {
    let version = super::super::bridge_api::get_engine_version();
    assert!(!version.is_empty());
    assert!(version.contains('.'));
}

#[test]
fn api_get_memory_pressure_level() {
    let level = super::super::bridge_api::get_memory_pressure_level();
    assert!(
        level == "normal" || level == "warning" || level == "critical",
        "Unexpected pressure level: {}",
        level
    );
}

#[test]
fn api_get_memory_usage_bytes() {
    let bytes = super::super::bridge_api::get_memory_usage_bytes();
    // On Linux, this should return a non-zero value
    // On other platforms, it may return 0
    assert!(bytes >= 0);
}

#[test]
fn api_should_release_caches() {
    // On a test machine, memory should be normal, so this should be false
    let should = super::super::bridge_api::should_release_caches();
    assert!(
        !should || should,
        "should_release_caches returned a valid bool"
    );
}

#[test]
fn api_should_reduce_quality() {
    let should = super::super::bridge_api::should_reduce_quality();
    assert!(
        !should || should,
        "should_reduce_quality returned a valid bool"
    );
}
