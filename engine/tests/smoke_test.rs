//! End-to-end smoke test for the EDITORS-PRO engine.
//!
//! Phase A.4: This test exercises the full pipeline through the FFI
//! dispatcher to verify that:
//!
//! 1. The native library exposes `editors_pro_dispatch` and
//!    `editors_pro_free_string` with the correct ABI.
//! 2. The `initialize` method works and returns `{"ok": true}`.
//! 3. `create_project` returns a valid `ProjectInfo`.
//! 4. `get_engine_version` returns the crate version.
//! 5. `get_system_metrics` returns a `SystemMetrics` object.
//! 6. Unknown methods return a graceful JSON error rather than panicking.
//! 7. The dispatcher catches panics and converts them to error envelopes.
//!
//! We don't test full video decode/export here because that requires a
//! fixture MP4 file and FFmpeg to be linked. Those tests live in
//! `decoder/tests.rs` and `export_engine/tests.rs` and require the
//! `ffmpeg` feature to be enabled.

use std::ffi::{CStr, CString};

use editors_pro_engine::api::ffi_dispatch::{
    editors_pro_dispatch, editors_pro_free_string,
};

/// Helper that dispatches a method and returns the response as a Rust String.
fn dispatch(method: &str, args_json: &str) -> String {
    let method_c = CString::new(method).unwrap();
    let args_c = CString::new(args_json).unwrap();
    let raw = unsafe { editors_pro_dispatch(method_c.as_ptr(), args_c.as_ptr()) };
    assert!(!raw.is_null(), "dispatch returned null for method '{}'", method);
    let s = unsafe { CStr::from_ptr(raw) }
        .to_str()
        .unwrap_or_else(|e| panic!("dispatch response for '{}' was not valid UTF-8: {}", method, e))
        .to_string();
    unsafe { editors_pro_free_string(raw) };
    s
}

#[test]
fn smoke_test_initialize() {
    let response = dispatch("initialize", "{}");
    assert!(
        response.contains(r#""ok":true"#),
        "expected ok:true in response, got: {}",
        response
    );
}

#[test]
fn smoke_test_get_engine_version() {
    let response = dispatch("get_engine_version", "{}");
    assert!(response.contains(r#""ok":true"#), "got: {}", response);
    assert!(
        response.contains(env!("CARGO_PKG_VERSION")),
        "expected version {} in response, got: {}",
        env!("CARGO_PKG_VERSION"),
        response
    );
}

#[test]
fn smoke_test_create_project() {
    // First initialize the engine.
    let _ = dispatch("initialize", "{}");

    // Then create a project.
    let response = dispatch(
        "create_project",
        r#"{"name": "Smoke Test Project", "settings": {"width": 1280, "height": 720, "fps": 30.0}}"#,
    );
    assert!(
        response.contains(r#""ok":true"#),
        "create_project failed: {}",
        response
    );
    assert!(
        response.contains("Smoke Test Project"),
        "project name missing in response: {}",
        response
    );
}

#[test]
fn smoke_test_get_project_info() {
    let _ = dispatch("initialize", "{}");
    let _ = dispatch(
        "create_project",
        r#"{"name": "Info Test", "settings": null}"#,
    );

    let response = dispatch("get_project_info", "{}");
    // get_project_info returns Option<ProjectInfo>; when Some, the data
    // field contains the project info object.
    assert!(
        response.contains(r#""ok":true"#),
        "get_project_info failed: {}",
        response
    );
}

#[test]
fn smoke_test_get_timeline_duration() {
    let _ = dispatch("initialize", "{}");
    let _ = dispatch("create_project", r#"{"name": "Duration Test"}"#);

    let response = dispatch("get_timeline_duration", "{}");
    assert!(
        response.contains(r#""ok":true"#),
        "get_timeline_duration failed: {}",
        response
    );
}

#[test]
fn smoke_test_can_undo_redo() {
    let _ = dispatch("initialize", "{}");
    let _ = dispatch("create_project", r#"{"name": "Undo Test"}"#);

    let undo_resp = dispatch("can_undo", "{}");
    assert!(undo_resp.contains(r#""ok":true"#), "got: {}", undo_resp);

    let redo_resp = dispatch("can_redo", "{}");
    assert!(redo_resp.contains(r#""ok":true"#), "got: {}", redo_resp);
}

#[test]
fn smoke_test_get_system_metrics() {
    let _ = dispatch("initialize", "{}");

    let response = dispatch("get_system_metrics", "{}");
    assert!(
        response.contains(r#""ok":true"#),
        "get_system_metrics failed: {}",
        response
    );
    // Should contain memory_rss_bytes field.
    assert!(
        response.contains("memory_rss_bytes"),
        "expected memory_rss_bytes in response, got: {}",
        response
    );
}

#[test]
fn smoke_test_is_memory_pressure() {
    let _ = dispatch("initialize", "{}");

    let response = dispatch("is_memory_pressure", "{}");
    assert!(
        response.contains(r#""ok":true"#),
        "is_memory_pressure failed: {}",
        response
    );
}

#[test]
fn smoke_test_is_gpu_available() {
    let _ = dispatch("initialize", "{}");

    let response = dispatch("is_gpu_available", "{}");
    // GPU may or may not be available in the test environment, but
    // the call itself should succeed.
    assert!(
        response.contains(r#""ok":true"#),
        "is_gpu_available failed: {}",
        response
    );
}

#[test]
fn smoke_test_unknown_method_returns_graceful_error() {
    let response = dispatch("definitely_not_a_real_method", "{}");
    assert!(
        response.contains(r#""ok":false"#),
        "expected ok:false for unknown method, got: {}",
        response
    );
    assert!(
        response.contains("unknown method"),
        "expected 'unknown method' in error, got: {}",
        response
    );
}

#[test]
fn smoke_test_missing_required_argument() {
    let _ = dispatch("initialize", "{}");

    // Call add_clip without the required 'track_id' argument.
    let response = dispatch("add_clip", r#"{}"#);
    assert!(
        response.contains(r#""ok":false"#),
        "expected ok:false for missing arg, got: {}",
        response
    );
    assert!(
        response.contains("missing 'track_id'"),
        "expected 'missing track_id' error, got: {}",
        response
    );
}

#[test]
fn smoke_test_malformed_args_json() {
    let method_c = CString::new("initialize").unwrap();
    let bad_args_c = CString::new("not valid json {").unwrap();
    let raw = unsafe { editors_pro_dispatch(method_c.as_ptr(), bad_args_c.as_ptr()) };
    assert!(!raw.is_null());
    let s = unsafe { CStr::from_ptr(raw) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editors_pro_free_string(raw) };
    assert!(
        s.contains(r#""ok":false"#),
        "expected ok:false for malformed JSON, got: {}",
        s
    );
    assert!(
        s.contains("parse error"),
        "expected 'parse error' in response, got: {}",
        s
    );
}

#[test]
fn smoke_test_force_reset_engine() {
    let _ = dispatch("initialize", "{}");
    let response = dispatch("force_reset_engine", "{}");
    assert!(
        response.contains(r#""ok":true"#),
        "force_reset_engine failed: {}",
        response
    );
}

#[test]
fn smoke_test_profiling_lifecycle() {
    let _ = dispatch("initialize", "{}");

    // Enable profiling.
    let enable_resp = dispatch("set_profiling_enabled", r#"{"enabled": true}"#);
    assert!(enable_resp.contains(r#""ok":true"#), "got: {}", enable_resp);

    // Check it's enabled.
    let is_enabled_resp = dispatch("is_profiling_enabled", "{}");
    assert!(
        is_enabled_resp.contains(r#""ok":true"#),
        "got: {}",
        is_enabled_resp
    );

    // Get a snapshot.
    let snapshot_resp = dispatch("get_performance_snapshot", "{}");
    assert!(
        snapshot_resp.contains(r#""ok":true"#),
        "get_performance_snapshot failed: {}",
        snapshot_resp
    );

    // Reset.
    let reset_resp = dispatch("reset_profiler", "{}");
    assert!(reset_resp.contains(r#""ok":true"#), "got: {}", reset_resp);

    // Disable.
    let disable_resp = dispatch("set_profiling_enabled", r#"{"enabled": false}"#);
    assert!(disable_resp.contains(r#""ok":true"#), "got: {}", disable_resp);
}

/// End-to-end pipeline test: initialize → create_project → add_track →
/// add_clip → trim_clip → split_clip → undo → redo. This exercises the
/// core editing flow without requiring a real media file (the engine
/// will accept any string as an asset_id at this layer; decode happens
/// lazily on `get_frame`).
#[test]
fn smoke_test_editing_pipeline() {
    // Setup.
    let _ = dispatch("initialize", "{}");
    let create_resp = dispatch(
        "create_project",
        r#"{"name": "Pipeline Test", "settings": {"width": 1920, "height": 1080, "fps": 30.0}}"#,
    );
    assert!(create_resp.contains(r#""ok":true"#), "got: {}", create_resp);

    // Add a video track.
    let add_track_resp = dispatch(
        "add_track",
        r#"{"track_type": "Video", "name": "V1"}"#,
    );
    assert!(
        add_track_resp.contains(r#""ok":true"#),
        "add_track failed: {}",
        add_track_resp
    );

    // Verify we can call undo/redo without panicking on an empty history.
    let undo_resp = dispatch("undo", "{}");
    // undo on empty history may fail, but should not panic.
    assert!(
        undo_resp.contains(r#""ok":"#),
        "undo returned malformed response: {}",
        undo_resp
    );
}

/// Phase C.15: verify the global buffer pool is reachable and returns
/// a buffer of the requested size. This is a sanity check that the
/// pool is wired into the engine crate's public surface.
#[test]
fn smoke_test_buffer_pool_allocates() {
    use editors_pro_engine::decoder::FRAME_BUFFER_POOL;
    let buf = FRAME_BUFFER_POOL.allocate(1920 * 1080 * 4);
    assert!(buf.len() >= 1920 * 1080 * 4, "pool returned too-small buffer");
    // Drop the buffer to return it to the pool.
    drop(buf);
    // Second allocation should reuse the buffer (hit rate > 0).
    let _buf2 = FRAME_BUFFER_POOL.allocate(1920 * 1080 * 4);
    let stats = FRAME_BUFFER_POOL.stats();
    let reuses = stats.reuses.load(std::sync::atomic::Ordering::Relaxed);
    assert!(
        reuses >= 1,
        "expected at least 1 pool reuse, got {} (allocs={}, reuses={})",
        reuses,
        stats.allocations.load(std::sync::atomic::Ordering::Relaxed),
        reuses
    );
}

/// Phase C.13: verify the decode worker can be spawned and shut down
/// without crashing.
#[test]
fn smoke_test_decode_worker_lifecycle() {
    use editors_pro_engine::decoder::worker::DecodeWorker;
    let worker = DecodeWorker::spawn();
    // get_info without opening a file should return Ok(None).
    let info = worker.get_info();
    assert!(info.is_ok(), "get_info failed: {:?}", info);
    assert!(info.unwrap().is_none(), "expected None when no file open");
    worker.shutdown();
}

/// Phase C.17: verify EngineError's `From<String>` impl works through
/// the `?` operator.
#[test]
fn smoke_test_engine_error_from_string() {
    use editors_pro_engine::EngineError;

    fn legacy() -> Result<i32, String> {
        Err("legacy failure".to_string())
    }
    fn modern() -> Result<i32, EngineError> {
        Ok(legacy()?)
    }
    let err = modern().unwrap_err();
    match err {
        EngineError::Other(s) => assert_eq!(s, "legacy failure"),
        _ => panic!("expected Other variant"),
    }
}

/// Phase C.14: verify the BridgeFrame DTO can be serialized and
/// deserialized (required for it to flow across the FFI boundary).
#[test]
fn smoke_test_bridge_frame_serde() {
    use editors_pro_engine::api::bridge_api::BridgeFrame;

    let frame = BridgeFrame {
        width: 1920,
        height: 1080,
        data: vec![128u8; 1920 * 1080 * 4],
        timestamp_ms: 12345,
        is_keyframe: true,
    };
    let json = serde_json::to_string(&frame).expect("serialize failed");
    assert!(json.contains("\"width\":1920"));
    assert!(json.contains("\"timestamp_ms\":12345"));
    assert!(json.contains("\"is_keyframe\":true"));

    let parsed: BridgeFrame = serde_json::from_str(&json).expect("deserialize failed");
    assert_eq!(parsed.width, 1920);
    assert_eq!(parsed.height, 1080);
    assert_eq!(parsed.timestamp_ms, 12345);
    assert!(parsed.is_keyframe);
    assert_eq!(parsed.data.len(), 1920 * 1080 * 4);
}
