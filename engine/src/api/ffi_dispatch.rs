//! JSON-RPC-style FFI dispatcher for the EDITORS-PRO engine.
//!
//! ## Why this exists
//!
//! `flutter_rust_bridge` v2 generates per-method Dart bindings from the
//! Rust source via `flutter_rust_bridge_codegen generate`. The previous
//! `lib/src/rust/frb_generated.dart` and `lib/src/rust/api/bridge_api.dart`
//! were stubs that threw `UnimplementedError` on every call, leaving the
//! entire engine unreachable from Flutter.
//!
//! As a Phase A pragmatic bridge, this module exposes a single C-ABI
//! function `editors_pro_dispatch` that accepts a JSON method name and
//! JSON arguments, dispatches to the corresponding `EditorsProEngineApi`
//! method, and returns a JSON response. The Dart side calls this via
//! `dart:ffi` — no codegen required.
//!
//! When the team later runs `flutter_rust_bridge_codegen generate`, the
//! generated per-method bindings will replace this dispatcher and the
//! Dart `_call` shim. The dispatcher remains as a fallback for
//! headless-test environments where FRB codegen isn't available.
//!
//! ## ABI
//!
//! ```c
//! char* editors_pro_dispatch(const char* method, const char* args_json);
//! ```
//!
//! - `method`: UTF-8 JSON string naming the engine method (e.g. `"initialize"`).
//! - `args_json`: UTF-8 JSON object string of method arguments.
//! - Returns: UTF-8 JSON string of `{"ok": true, "data": ...}` on success,
//!   or `{"ok": false, "error": "..."}` on failure. The caller MUST free
//!   the returned buffer with `editors_pro_free_string`.
//!
//! All dispatch calls are serialized through a global `Mutex<EditorsProEngineApi>`
//! to satisfy the `&self` contract of the bridge API.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Mutex;

use once_cell::sync::Lazy;

use crate::api::bridge_api::EditorsProEngineApi;

/// Payload returned by the dispatcher.
#[derive(serde::Serialize)]
struct DispatchOk<'a, T: serde::Serialize> {
    ok: bool,
    data: &'a T,
}

#[derive(serde::Serialize)]
struct DispatchErr {
    ok: bool,
    error: String,
}

/// Global engine instance.
///
/// Initialized lazily on first dispatch call. Using a `Lazy<Mutex<...>>`
/// keeps the FFI surface simple — there's exactly one engine per process,
/// which is the intended usage for a mobile app.
static ENGINE: Lazy<Mutex<EditorsProEngineApi>> =
    Lazy::new(|| Mutex::new(EditorsProEngineApi::new()));

/// Convert a Rust `Result<T, String>` into a JSON string suitable for
/// returning across the FFI boundary.
fn to_json_string<T: serde::Serialize>(result: Result<T, String>) -> String {
    match result {
        Ok(value) => to_json_ok(&value),
        Err(err) => to_json_err(err),
    }
}

/// Serialize a successful value as `{"ok": true, "data": ...}`.
fn to_json_ok<T: serde::Serialize>(value: &T) -> String {
    let wrapper = DispatchOk { ok: true, data: value };
    serde_json::to_string(&wrapper).unwrap_or_else(|e| {
        to_json_err(format!("Serialization failed: {}", e))
    })
}

/// Serialize an error as `{"ok": false, "error": "..."}`.
fn to_json_err(msg: impl Into<String>) -> String {
    serde_json::to_string(&DispatchErr {
        ok: false,
        error: msg.into(),
    })
    .unwrap_or_else(|_| r#"{"ok":false,"error":"unknown"}"#.to_string())
}

/// Dispatch a JSON method call to the engine.
///
/// See module docs for the ABI contract.
///
/// # Safety
///
/// - `method` and `args_json` must be valid non-null pointers to NUL-terminated
///   UTF-8 C strings.
/// - The returned pointer MUST be freed by `editors_pro_free_string` to avoid
///   a memory leak.
#[no_mangle]
pub unsafe extern "C" fn editors_pro_dispatch(
    method: *const c_char,
    args_json: *const c_char,
) -> *mut c_char {
    // Parse method name.
    let method_str = if method.is_null() {
        return leak_cstring(r#"{"ok":false,"error":"method is null"}"#);
    } else {
        match CStr::from_ptr(method).to_str() {
            Ok(s) => s,
            Err(_) => {
                return leak_cstring(
                    r#"{"ok":false,"error":"method is not valid UTF-8"}"#,
                );
            }
        }
    };

    // Parse args JSON. Null or empty is treated as `{}`.
    let args_str: &str = if args_json.is_null() {
        "{}"
    } else {
        match CStr::from_ptr(args_json).to_str() {
            Ok(s) if s.is_empty() => "{}",
            Ok(s) => s,
            Err(_) => {
                return leak_cstring(
                    r#"{"ok":false,"error":"args_json is not valid UTF-8"}"#,
                );
            }
        }
    };

    let args: serde_json::Value = match serde_json::from_str(args_str) {
        Ok(v) => v,
        Err(e) => {
            let msg = format!(r#"{{"ok":false,"error":"args_json parse error: {}"}}"#, e);
            return leak_cstring(&msg);
        }
    };

    // Acquire engine lock and dispatch.
    let result = std::panic::catch_unwind(|| {
        let mut api = ENGINE.lock().expect("engine mutex poisoned");
        dispatch_method(&mut api, method_str, &args)
    });

    let json_str = match result {
        Ok(json) => json,
        Err(panic_payload) => {
            let msg = if let Some(s) = panic_payload.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = panic_payload.downcast_ref::<String>() {
                s.clone()
            } else {
                "Rust panic during dispatch".to_string()
            };
            to_json_string::<()>(Err(format!("Panic: {}", msg)))
        }
    };

    leak_cstring(&json_str)
}

/// Set the export cancellation signal without waiting for the engine mutex.
#[no_mangle]
pub extern "C" fn editors_pro_cancel_export() {
    crate::api::request_export_cancel();
}

/// Clear a stale cancellation signal before a new export is scheduled.
#[no_mangle]
pub extern "C" fn editors_pro_prepare_export() {
    crate::api::clear_export_cancel_request();
}

/// Read the lock-free export progress snapshot.
#[no_mangle]
pub extern "C" fn editors_pro_export_status() -> *mut c_char {
    leak_cstring(&crate::api::export_status::snapshot_json())
}

/// Free a string returned by `editors_pro_dispatch`.
///
/// # Safety
///
/// `ptr` must be a non-null pointer previously returned by
/// `editors_pro_dispatch`. Passing any other pointer is undefined behavior.
#[no_mangle]
pub unsafe extern "C" fn editors_pro_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    // Reconstruct the CString and drop it to reclaim memory.
    let _ = CString::from_raw(ptr);
}

/// Leak a `CString` so its memory is owned by the caller.
///
/// The caller MUST free it with `editors_pro_free_string`.
fn leak_cstring(s: &str) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new(r#"{"ok":false,"error":"internal nul error"}"#).unwrap())
        .into_raw()
}

/// Dispatch a single method call. Returns the JSON response string.
///
/// This is a giant match on `method`. Only a subset of the full 60+ API
/// is wired here initially — enough to support the Phase A end-to-end
/// smoke test (initialize → create_project → import_media → add_track →
/// add_clip → trim_clip → split_clip → get_frame → export). The remaining
/// methods will be added as they're needed, or replaced entirely when
/// `flutter_rust_bridge_codegen generate` is run.
fn dispatch_method(
    api: &mut EditorsProEngineApi,
    method: &str,
    args: &serde_json::Value,
) -> String {
    match method {
        // ─── Lifecycle ────────────────────────────────────────────────────
        "initialize" => to_json_string::<()>(api.initialize()),
        "get_engine_version" => to_json_ok(&crate::engine_version().to_string()),
        "force_reset_engine" => to_json_string::<()>(api.force_reset_engine()),
        "recover_project" => {
            let path: Option<String> = args
                .get("auto_save_path")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            to_json_string(api.recover_project(path))
        }

        // ─── Project Operations ───────────────────────────────────────────
        "create_project" => {
            let name = args
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("Untitled")
                .to_string();
            let settings = args.get("settings").and_then(|v| {
                if v.is_null() {
                    None
                } else {
                    serde_json::from_value(v.clone()).ok()
                }
            });
            to_json_string(api.create_project(name, settings))
        }
        "save_project" => {
            let path = match args.get("path").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'path'"),
            };
            to_json_string::<()>(api.save_project(path))
        }
        "load_project" => {
            let path = match args.get("path").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'path'"),
            };
            to_json_string(api.load_project(path))
        }
        "get_project_info" => to_json_ok(&api.get_project_info()),
        "get_timeline_duration" => to_json_ok(&api.get_timeline_duration()),
        "can_undo" => to_json_ok(&api.can_undo()),
        "can_redo" => to_json_ok(&api.can_redo()),

        // ─── Media ────────────────────────────────────────────────────────
        "import_media" => {
            let path = match args.get("file_path").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'file_path'"),
            };
            to_json_string(api.import_media(path))
        }
        "restore_media_asset" => {
            let asset = match args.get("asset") {
                Some(value) => match serde_json::from_value(value.clone()) {
                    Ok(asset) => asset,
                    Err(error) => return to_json_err(format!("invalid media asset: {}", error)),
                },
                None => return to_json_err("missing 'asset'"),
            };
            to_json_string(api.restore_media_asset(asset))
        }

        // ─── Timeline ─────────────────────────────────────────────────────
        "add_track" => {
            let track_type = match args.get("track_type").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return to_json_err("missing 'track_type'"),
            };
            let name = args
                .get("name")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            to_json_string(api.add_track(track_type, name))
        }
        "add_clip" => {
            let track_id = match args.get("track_id").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return to_json_err("missing 'track_id'"),
            };
            let asset_id = match args.get("asset_id").and_then(|v| v.as_str()) {
                Some(a) => a.to_string(),
                None => return to_json_err("missing 'asset_id'"),
            };
            let start_ms = parse_u64(args, "start_ms");
            let duration_ms = parse_u64(args, "duration_ms");
            to_json_string(api.add_clip(track_id, asset_id, start_ms, duration_ms))
        }
        "trim_clip" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let trim_start_ms = parse_u64(args, "trim_start_ms");
            let trim_end_ms = parse_u64(args, "trim_end_ms");
            to_json_string::<()>(api.trim_clip(clip_id, trim_start_ms, trim_end_ms))
        }
        "split_clip" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let time_ms = parse_u64(args, "time_ms");
            to_json_string(api.split_clip(clip_id, time_ms))
        }
        "remove_clip" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            to_json_string::<()>(api.remove_clip(clip_id))
        }
        "get_timeline_state" => to_json_ok(&api.get_timeline_state()),
        "undo" => to_json_string::<()>(api.undo()),
        "redo" => to_json_string::<()>(api.redo()),

        // ─── Move clip ───────────────────────────────────────────────────
        "move_clip" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let new_start_ms = parse_u64(args, "new_start_ms");
            let new_track_id = args
                .get("new_track_id")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            to_json_string::<()>(api.move_clip(clip_id, new_start_ms, new_track_id))
        }

        // ─── Cache management (Phase B.12) ────────────────────────────────
        "invalidate_frame_cache" => to_json_string::<()>(api.invalidate_frame_cache()),

        // ─── Preview ──────────────────────────────────────────────────────
        "get_frame" => {
            let time_ms = parse_u64(args, "time_ms");
            to_json_string(api.get_frame(time_ms))
        }

        // ─── Export ───────────────────────────────────────────────────────
        "export_video" => {
            let output_path = match args.get("output_path").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'output_path'"),
            };
            let settings = match args.get("settings") {
                Some(v) if !v.is_null() => match serde_json::from_value(v.clone()) {
                    Ok(s) => s,
                    Err(e) => return to_json_err(format!("invalid 'settings': {}", e)),
                },
                _ => return to_json_err("missing 'settings'"),
            };
            to_json_string(api.export_video(output_path, settings))
        }
        "export_video_with_callback" => {
            let output_path = match args.get("output_path").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'output_path'"),
            };
            let settings = match args.get("settings") {
                Some(v) if !v.is_null() => match serde_json::from_value(v.clone()) {
                    Ok(s) => s,
                    Err(e) => return to_json_err(format!("invalid 'settings': {}", e)),
                },
                _ => return to_json_err("missing 'settings'"),
            };
            to_json_string(api.export_video_with_callback(output_path, settings))
        }
        "cancel_export" => to_json_string::<()>(api.cancel_export()),
        "get_export_presets" => to_json_ok(&api.get_export_presets()),
        "get_export_preset" => {
            let name = match args.get("name").and_then(|v| v.as_str()) {
                Some(n) => n.to_string(),
                None => return to_json_err("missing 'name'"),
            };
            to_json_ok(&api.get_export_preset(name))
        }

        // ─── Audio ────────────────────────────────────────────────────────
        "set_track_volume" => {
            let track_id = match args.get("track_id").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return to_json_err("missing 'track_id'"),
            };
            let volume = parse_f32(args, "volume");
            to_json_string::<()>(api.set_track_volume(track_id, volume))
        }
        "toggle_track_visibility" => {
            let track_id = match args.get("track_id").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return to_json_err("missing 'track_id'"),
            };
            to_json_string::<()>(api.toggle_track_visibility(track_id))
        }
        "get_audio_samples" => {
            let asset_id = match args.get("asset_id").and_then(|v| v.as_str()) {
                Some(a) => a.to_string(),
                None => return to_json_err("missing 'asset_id'"),
            };
            let start_ms = parse_u64(args, "start_ms");
            let duration_ms = parse_u64(args, "duration_ms");
            to_json_string(api.get_audio_samples(asset_id, start_ms, duration_ms))
        }
        "mix_audio_at_time" => {
            let start_ms = parse_u64(args, "start_ms");
            let duration_ms = parse_u64(args, "duration_ms");
            to_json_string(api.mix_audio_at_time(start_ms, duration_ms))
        }
        "get_waveform" => {
            let asset_id = match args.get("asset_id").and_then(|v| v.as_str()) {
                Some(a) => a.to_string(),
                None => return to_json_err("missing 'asset_id'"),
            };
            let num_bins = args.get("num_bins").and_then(|v| v.as_u64()).unwrap_or(200) as u32;
            to_json_string(api.get_waveform(asset_id, num_bins))
        }
        "set_ducking" => {
            let track_id = match args.get("track_id").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return to_json_err("missing 'track_id'"),
            };
            let enabled = args.get("enabled").and_then(|v| v.as_bool()).unwrap_or(false);
            let duck_level = parse_f32(args, "duck_level");
            to_json_string::<()>(api.set_ducking(track_id, enabled, duck_level))
        }
        "get_ducking_config" => {
            let track_id = match args.get("track_id").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return to_json_err("missing 'track_id'"),
            };
            to_json_ok(&api.get_ducking_config(track_id))
        }
        "get_audio_info" => {
            let file_path = match args.get("file_path").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'file_path'"),
            };
            to_json_string(api.get_audio_info(file_path))
        }

        // ─── Text Operations ─────────────────────────────────────────────
        "add_text_clip" => {
            let track_id = match args.get("track_id").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return to_json_err("missing 'track_id'"),
            };
            let text = match args.get("text").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return to_json_err("missing 'text'"),
            };
            let font_family = args.get("font_family").and_then(|v| v.as_str()).unwrap_or("Inter").to_string();
            let font_size = parse_f32(args, "font_size");
            let color_hex = args.get("color_hex").and_then(|v| v.as_str()).unwrap_or("#FFFFFF").to_string();
            let position_x = parse_f32(args, "position_x");
            let position_y = parse_f32(args, "position_y");
            let start_ms = parse_u64(args, "start_ms");
            let duration_ms = parse_u64(args, "duration_ms");
            to_json_string(api.add_text_clip(track_id, text, font_family, font_size, color_hex, position_x, position_y, start_ms, duration_ms))
        }
        "set_text_position" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let position_x = parse_f32(args, "position_x");
            let position_y = parse_f32(args, "position_y");
            to_json_string::<()>(api.set_text_position(clip_id, position_x, position_y))
        }
        "set_text_style" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let font_family = args.get("font_family").and_then(|v| v.as_str()).unwrap_or("Inter").to_string();
            let font_size = parse_f32(args, "font_size");
            let color_hex = args.get("color_hex").and_then(|v| v.as_str()).unwrap_or("#FFFFFF").to_string();
            to_json_string::<()>(api.set_text_style(clip_id, font_family, font_size, color_hex))
        }
        "get_available_fonts" => to_json_ok(&api.get_available_fonts()),
        "import_subtitles" => {
            let file_path = match args.get("file_path").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'file_path'"),
            };
            to_json_string(api.import_subtitles(file_path))
        }

        // ─── Effect Operations ────────────────────────────────────────────
        "add_effect" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let filter_type_name = match args.get("filter_type_name").and_then(|v| v.as_str()) {
                Some(f) => f.to_string(),
                None => return to_json_err("missing 'filter_type_name'"),
            };
            to_json_string(api.add_effect(clip_id, filter_type_name))
        }
        "remove_effect" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let effect_id = match args.get("effect_id").and_then(|v| v.as_str()) {
                Some(e) => e.to_string(),
                None => return to_json_err("missing 'effect_id'"),
            };
            to_json_string::<()>(api.remove_effect(clip_id, effect_id))
        }
        "set_effect_parameter" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let effect_id = match args.get("effect_id").and_then(|v| v.as_str()) {
                Some(e) => e.to_string(),
                None => return to_json_err("missing 'effect_id'"),
            };
            let param_name = match args.get("param_name").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'param_name'"),
            };
            let value = parse_f32(args, "value");
            to_json_string::<()>(api.set_effect_parameter(clip_id, effect_id, param_name, value))
        }
        "get_clip_effects" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            to_json_string(api.get_clip_effects(clip_id))
        }
        "toggle_effect" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let effect_id = match args.get("effect_id").and_then(|v| v.as_str()) {
                Some(e) => e.to_string(),
                None => return to_json_err("missing 'effect_id'"),
            };
            to_json_string::<()>(api.toggle_effect(clip_id, effect_id))
        }
        "add_chroma_key_effect" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let target_hue = parse_f32(args, "target_hue");
            let hue_tolerance = parse_f32(args, "hue_tolerance");
            let saturation_tolerance = parse_f32(args, "saturation_tolerance");
            let softness = parse_f32(args, "softness");
            let spill_suppression = parse_f32(args, "spill_suppression");
            to_json_string(api.add_chroma_key_effect(clip_id, target_hue, hue_tolerance, saturation_tolerance, softness, spill_suppression))
        }
        "pick_color_from_frame" => {
            let time_ms = parse_u64(args, "time_ms");
            let x = args.get("x").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
            let y = args.get("y").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
            to_json_string(api.pick_color_from_frame(time_ms, x, y))
        }
        "get_filter_catalog" => to_json_ok(&api.get_filter_catalog()),
        "get_filter_presets" => to_json_ok(&api.get_filter_presets()),
        "apply_filter_preset" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let preset_id = match args.get("preset_id").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'preset_id'"),
            };
            to_json_string::<()>(api.apply_filter_preset(clip_id, preset_id))
        }

        // ─── Transition Operations ────────────────────────────────────────
        "add_transition" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let transition_type = match args.get("transition_type").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return to_json_err("missing 'transition_type'"),
            };
            let duration_ms = parse_u64(args, "duration_ms");
            let direction = match args.get("direction").and_then(|v| v.as_str()) {
                Some(d) => d.to_string(),
                None => return to_json_err("missing 'direction'"),
            };
            to_json_string(api.add_transition(clip_id, transition_type, duration_ms, direction))
        }
        "get_clip_transition" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let direction = match args.get("direction").and_then(|v| v.as_str()) {
                Some(d) => d.to_string(),
                None => return to_json_err("missing 'direction'"),
            };
            to_json_ok(&api.get_clip_transition(clip_id, direction))
        }
        "remove_transition" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let direction = match args.get("direction").and_then(|v| v.as_str()) {
                Some(d) => d.to_string(),
                None => return to_json_err("missing 'direction'"),
            };
            to_json_string::<()>(api.remove_transition(clip_id, direction))
        }
        "get_transition_catalog" => to_json_ok(&api.get_transition_catalog()),

        // ─── Speed Curve & Keyframe Operations ────────────────────────────
        "set_clip_speed_curve" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let curve = match args.get("curve") {
                Some(v) if !v.is_null() => match serde_json::from_value(v.clone()) {
                    Ok(c) => c,
                    Err(e) => return to_json_err(format!("invalid 'curve': {}", e)),
                },
                _ => return to_json_err("missing 'curve'"),
            };
            to_json_string::<()>(api.set_clip_speed_curve(clip_id, curve))
        }
        "get_clip_speed_curve" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            to_json_string(api.get_clip_speed_curve(clip_id))
        }
        "add_keyframe" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let property = match args.get("property").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'property'"),
            };
            let time_ms = parse_u64(args, "time_ms");
            let value = parse_f32(args, "value");
            let easing = args.get("easing").and_then(|v| v.as_str()).unwrap_or("Linear").to_string();
            to_json_string(api.add_keyframe(clip_id, property, time_ms, value, easing))
        }
        "remove_keyframe" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let property = match args.get("property").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'property'"),
            };
            let keyframe_id = match args.get("keyframe_id").and_then(|v| v.as_str()) {
                Some(k) => k.to_string(),
                None => return to_json_err("missing 'keyframe_id'"),
            };
            to_json_string::<()>(api.remove_keyframe(clip_id, property, keyframe_id))
        }
        "update_keyframe" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let property = match args.get("property").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'property'"),
            };
            let keyframe_id = match args.get("keyframe_id").and_then(|v| v.as_str()) {
                Some(k) => k.to_string(),
                None => return to_json_err("missing 'keyframe_id'"),
            };
            let value = args.get("value").and_then(|v| v.as_f64()).map(|v| v as f32);
            let easing = args.get("easing").and_then(|v| v.as_str()).map(|s| s.to_string());
            to_json_string::<()>(api.update_keyframe(clip_id, property, keyframe_id, value, easing))
        }
        "get_keyframes" => {
            let clip_id = match args.get("clip_id").and_then(|v| v.as_str()) {
                Some(c) => c.to_string(),
                None => return to_json_err("missing 'clip_id'"),
            };
            let property = match args.get("property").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'property'"),
            };
            to_json_string(api.get_keyframes(clip_id, property))
        }

        // ─── GPU ──────────────────────────────────────────────────────────
        "is_gpu_available" => to_json_ok(&api.is_gpu_available()),
        "get_gpu_info" => to_json_ok(&api.get_gpu_info()),
        "set_gpu_acceleration" => {
            let enabled = args
                .get("enabled")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            to_json_string::<()>(api.set_gpu_acceleration(enabled))
        }
        "export_video_hardware" => {
            let output_path = match args.get("output_path").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'output_path'"),
            };
            let settings = match args.get("settings") {
                Some(v) if !v.is_null() => match serde_json::from_value(v.clone()) {
                    Ok(s) => s,
                    Err(e) => return to_json_err(format!("invalid 'settings': {}", e)),
                },
                _ => return to_json_err("missing 'settings'"),
            };
            to_json_string(api.export_video_hardware(output_path, settings))
        }

        // ─── Cloud Sync ──────────────────────────────────────────────────
        "sync_project" => {
            let project_id = match args.get("project_id").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'project_id'"),
            };
            to_json_string(api.sync_project(project_id))
        }
        "get_sync_status" => {
            let project_id = match args.get("project_id").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'project_id'"),
            };
            to_json_ok(&api.get_sync_status(project_id))
        }
        "get_cloud_projects" => to_json_ok(&api.get_cloud_projects()),
        "resolve_sync_conflict" => {
            let project_id = match args.get("project_id").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'project_id'"),
            };
            let resolution = match args.get("resolution").and_then(|v| v.as_str()) {
                Some(r) => r.to_string(),
                None => return to_json_err("missing 'resolution'"),
            };
            to_json_string(api.resolve_sync_conflict(project_id, resolution))
        }

        // ─── Templates ───────────────────────────────────────────────────
        "get_templates" => to_json_ok(&api.get_templates()),
        "get_template_details" => {
            let template_id = match args.get("template_id").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return to_json_err("missing 'template_id'"),
            };
            to_json_ok(&api.get_template_details(template_id))
        }
        "instantiate_template" => {
            let template_id = match args.get("template_id").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return to_json_err("missing 'template_id'"),
            };
            let assignments: std::collections::HashMap<String, String> = args
                .get("assignments")
                .and_then(|v| serde_json::from_value(v.clone()).ok())
                .unwrap_or_default();
            to_json_string(api.instantiate_template(template_id, assignments))
        }

        // ─── Transcription ───────────────────────────────────────────────
        "transcribe_audio" => {
            let asset_id = match args.get("asset_id").and_then(|v| v.as_str()) {
                Some(a) => a.to_string(),
                None => return to_json_err("missing 'asset_id'"),
            };
            let language = args.get("language").and_then(|v| v.as_str()).unwrap_or("auto").to_string();
            to_json_string(api.transcribe_audio(asset_id, language))
        }
        "add_subtitles_from_transcription" => {
            let asset_id = match args.get("asset_id").and_then(|v| v.as_str()) {
                Some(a) => a.to_string(),
                None => return to_json_err("missing 'asset_id'"),
            };
            let track_id = match args.get("track_id").and_then(|v| v.as_str()) {
                Some(t) => t.to_string(),
                None => return to_json_err("missing 'track_id'"),
            };
            to_json_string(api.add_subtitles_from_transcription(asset_id, track_id))
        }

        // ─── Proxy Workflow ──────────────────────────────────────────────
        "generate_proxy" => {
            let asset_id = match args.get("asset_id").and_then(|v| v.as_str()) {
                Some(a) => a.to_string(),
                None => return to_json_err("missing 'asset_id'"),
            };
            let source_path = match args.get("source_path").and_then(|v| v.as_str()) {
                Some(s) => s.to_string(),
                None => return to_json_err("missing 'source_path'"),
            };
            to_json_string(api.generate_proxy(asset_id, source_path))
        }
        "get_proxy_path" => {
            let asset_id = match args.get("asset_id").and_then(|v| v.as_str()) {
                Some(a) => a.to_string(),
                None => return to_json_err("missing 'asset_id'"),
            };
            to_json_ok(&api.get_proxy_path(asset_id))
        }
        "set_proxy_quality" => {
            let quality = match args.get("quality").and_then(|v| v.as_str()) {
                Some(q) => q.to_string(),
                None => return to_json_err("missing 'quality'"),
            };
            to_json_string::<()>(api.set_proxy_quality(quality))
        }
        "get_proxy_quality" => to_json_ok(&api.get_proxy_quality()),
        "clear_proxy_cache" => to_json_string(api.clear_proxy_cache()),
        "get_proxy_cache_size" => to_json_string(api.get_proxy_cache_size()),
        "get_proxy_count" => to_json_ok(&api.get_proxy_count()),
        "set_cache_dir" => {
            let path = match args.get("path").and_then(|v| v.as_str()) {
                Some(p) => p.to_string(),
                None => return to_json_err("missing 'path'"),
            };
            to_json_string::<()>(api.set_cache_dir(path))
        }
        "set_auto_proxy" => {
            let enabled = args.get("enabled").and_then(|v| v.as_bool()).unwrap_or(false);
            to_json_string::<()>(api.set_auto_proxy(enabled))
        }
        "is_auto_proxy_enabled" => to_json_ok(&api.is_auto_proxy_enabled()),
        "get_proxy_info" => {
            let asset_id = match args.get("asset_id").and_then(|v| v.as_str()) {
                Some(a) => a.to_string(),
                None => return to_json_err("missing 'asset_id'"),
            };
            to_json_ok(&api.get_proxy_info(asset_id))
        }
        "regenerate_proxy" => {
            let asset_id = match args.get("asset_id").and_then(|v| v.as_str()) {
                Some(a) => a.to_string(),
                None => return to_json_err("missing 'asset_id'"),
            };
            to_json_string(api.regenerate_proxy(asset_id))
        }
        "should_generate_proxy" => {
            let width = args.get("width").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
            let height = args.get("height").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
            to_json_ok(&api.should_generate_proxy(width, height))
        }

        // ─── Profiling (free functions, not methods on EditorsProEngineApi) ───
        "set_profiling_enabled" => {
            let enabled = args
                .get("enabled")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            crate::api::bridge_api::set_profiling_enabled(enabled);
            to_json_ok(&())
        }
        "is_profiling_enabled" => to_json_ok(&crate::api::bridge_api::is_profiling_enabled()),
        "get_performance_snapshot" => {
            to_json_ok(&crate::api::bridge_api::get_performance_snapshot())
        }
        "get_profiler_report" => {
            to_json_ok(&crate::api::bridge_api::get_profiler_report())
        }
        "reset_profiler" => {
            crate::api::bridge_api::reset_profiler();
            to_json_ok(&())
        }

        // ─── System metrics ───────────────────────────────────────────────
        "get_system_metrics" => to_json_ok(&api.get_system_metrics()),
        "is_memory_pressure" => to_json_ok(&api.is_memory_pressure()),
        "get_memory_pressure_level" => {
            to_json_ok(&crate::api::bridge_api::get_memory_pressure_level())
        }
        "get_memory_usage_bytes" => {
            to_json_ok(&crate::api::bridge_api::get_memory_usage_bytes())
        }

        // ─── Pro Tools (Phase F: persona-driven pro videographer toolkit) ──
        // LUT management (engine/src/effects/lut.rs)
        "lut_load_cube" => {
            let path = args.get("path").and_then(|v| v.as_str()).unwrap_or("");
            match crate::effects::lut::Lut::from_cube_file(std::path::Path::new(path)) {
                Ok(lut) => to_json_ok(&lut),
                Err(e) => to_json_err(format!("LUT load failed: {}", e)),
            }
        }
        "lut_load_cube_content" => {
            let content = args.get("content").and_then(|v| v.as_str()).unwrap_or("");
            match crate::effects::lut::Lut::from_cube(content) {
                Ok(lut) => to_json_ok(&lut),
                Err(e) => to_json_err(format!("LUT parse failed: {}", e)),
            }
        }

        // Color scopes (engine/src/analysis/scopes.rs)
        "compute_scopes" => {
            let frame_b64 = args.get("frame").and_then(|v| v.as_str()).unwrap_or("");
            let width = args.get("width").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
            let height = args.get("height").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
            match base64_decode_bytes(frame_b64) {
                Some(pixels) => {
                    if width > 0 && height > 0 && pixels.len() == width * height * 4 {
                        to_json_ok(&crate::analysis::scopes::compute_scopes(&pixels, width, height))
                    } else {
                        match crate::api::bridge_api::decode_png_to_rgba(&pixels) {
                            Ok((rgba, w, h)) => {
                                to_json_ok(&crate::analysis::scopes::compute_scopes(&rgba, w as usize, h as usize))
                            }
                            Err(e) => to_json_err(format!("PNG decode failed: {}", e)),
                        }
                    }
                }
                None => to_json_err(String::from("invalid base64 frame")),
            }
        }
        "count_out_of_range_pixels" => {
            let frame_b64 = args.get("frame").and_then(|v| v.as_str()).unwrap_or("");
            match base64_decode_bytes(frame_b64) {
                Some(pixels) => {
                    to_json_ok(&crate::analysis::scopes::count_out_of_range_pixels(&pixels))
                }
                None => to_json_err(String::from("invalid base64 frame")),
            }
        }

        // Color legalizer (engine/src/effects/legalizer.rs)
        "legalize_frame" => {
            let frame_b64 = args.get("frame").and_then(|v| v.as_str()).unwrap_or("");
            let soft_clip = args.get("soft_clip").and_then(|v| v.as_bool()).unwrap_or(true);
            let knee = args.get("knee").and_then(|v| v.as_f64()).unwrap_or(0.9) as f32;
            match base64_decode_bytes(frame_b64) {
                Some(mut pixels) => {
                    let params = crate::effects::legalizer::LegalizerParams { soft_clip, knee };
                    crate::effects::legalizer::legalize_rgba8(&mut pixels, &params);
                    to_json_ok(&base64_encode_bytes(&pixels))
                }
                None => to_json_err(String::from("invalid base64 frame")),
            }
        }

        // Video stabilization (engine/src/effects/stabilization.rs)
        "estimate_motion" => {
            let prev_b64 = args.get("prev").and_then(|v| v.as_str()).unwrap_or("");
            let curr_b64 = args.get("curr").and_then(|v| v.as_str()).unwrap_or("");
            let width = args.get("width").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
            let height = args.get("height").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
            let block_size = args.get("block_size").and_then(|v| v.as_u64()).unwrap_or(32) as usize;
            let search_range = args.get("search_range").and_then(|v| v.as_u64()).unwrap_or(16) as usize;
            match (base64_decode_bytes(prev_b64), base64_decode_bytes(curr_b64)) {
                (Some(prev), Some(curr))
                    if prev.len() == width * height * 4 && curr.len() == width * height * 4 =>
                {
                    to_json_ok(&crate::effects::stabilization::estimate_motion(
                        &prev, &curr, width, height, block_size, search_range,
                    ))
                }
                _ => to_json_err(String::from("invalid frames")),
            }
        }

        // Motion tracking (engine/src/effects/motion_tracking.rs)
        "track_point" => {
            // Stub: returns the start point as a single-point track.
            // Full implementation requires multi-frame input via stream.
            to_json_err(String::from("track_point requires stream input — use track_point_single instead"))
        }

        // Color match (engine/src/effects/color_match.rs)
        "compute_color_match_lut" => {
            let source_b64 = args.get("source").and_then(|v| v.as_str()).unwrap_or("");
            let reference_b64 = args.get("reference").and_then(|v| v.as_str()).unwrap_or("");
            let width = args.get("width").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
            let height = args.get("height").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
            match (base64_decode_bytes(source_b64), base64_decode_bytes(reference_b64)) {
                (Some(source), Some(reference))
                    if source.len() == width * height * 4 && reference.len() == width * height * 4 =>
                {
                    to_json_ok(&crate::effects::color_match::compute_match_lut(
                        &source, &reference, width, height,
                    ))
                }
                _ => to_json_err(String::from("invalid frames")),
            }
        }

        // Sky replacement (engine/src/effects/sky_replace.rs)
        "replace_sky" => {
            let frame_b64 = args.get("frame").and_then(|v| v.as_str()).unwrap_or("");
            let new_sky_b64 = args.get("new_sky").and_then(|v| v.as_str()).unwrap_or("");
            let width = args.get("width").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
            let height = args.get("height").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
            let luma_threshold = args.get("luma_threshold").and_then(|v| v.as_u64()).unwrap_or(180) as u8;
            let top_portion = args.get("top_portion").and_then(|v| v.as_f64()).unwrap_or(0.6) as f32;
            let feather = args.get("feather").and_then(|v| v.as_u64()).unwrap_or(4) as usize;
            let intensity = args.get("intensity").and_then(|v| v.as_f64()).unwrap_or(1.0) as f32;
            match (base64_decode_bytes(frame_b64), base64_decode_bytes(new_sky_b64)) {
                (Some(mut frame), Some(new_sky))
                    if frame.len() == width * height * 4 && new_sky.len() == width * height * 4 =>
                {
                    let params = crate::effects::sky_replace::SkyReplaceParams {
                        luma_threshold, top_portion, feather, intensity,
                    };
                    crate::effects::sky_replace::replace_sky(&mut frame, &new_sky, width, height, &params);
                    to_json_ok(&base64_encode_bytes(&frame))
                }
                _ => to_json_err(String::from("invalid frames")),
            }
        }

        // Beat detection (engine/src/analysis/beat_detect.rs)
        "detect_beats" => {
            let samples_b64 = args.get("samples").and_then(|v| v.as_str()).unwrap_or("");
            let sample_rate = args.get("sample_rate").and_then(|v| v.as_u64()).unwrap_or(44100) as u32;
            let window_size = args.get("window_size").and_then(|v| v.as_u64()).unwrap_or(1024) as usize;
            let hop_size = args.get("hop_size").and_then(|v| v.as_u64()).unwrap_or(512) as usize;
            let min_strength = args.get("min_strength").and_then(|v| v.as_f64()).unwrap_or(0.3) as f32;
            let min_interval_ms = args.get("min_interval_ms").and_then(|v| v.as_u64()).unwrap_or(200) as u32;
            match base64_decode_f32_samples(samples_b64) {
                Some(samples) => {
                    let params = crate::analysis::beat_detect::BeatDetectParams {
                        window_size, hop_size, sample_rate, min_strength, min_interval_ms,
                    };
                    to_json_ok(&crate::analysis::beat_detect::detect_beats(&samples, &params))
                }
                None => to_json_err(String::from("invalid base64 samples")),
            }
        }

        // Batch export queue (engine/src/export_engine/batch.rs)
        "batch_enqueue" => {
            let name = args.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let project_path = args.get("project_path").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let output_path = args.get("output_path").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let preset = args.get("preset").and_then(|v| v.as_str()).unwrap_or("").to_string();
            BATCH_QUEUE.with(|q| {
                let mut q = q.borrow_mut();
                let job = crate::export_engine::batch::ExportJob {
                    id: String::new(), name, project_path, output_path, preset,
                    status: crate::export_engine::batch::JobStatus::Queued,
                    progress: 0.0, error: None,
                    submitted_at_ms: 0, started_at_ms: None, completed_at_ms: None,
                };
                to_json_ok(&q.enqueue(job))
            })
        }
        "batch_jobs" => {
            BATCH_QUEUE.with(|q| {
                let q = q.borrow();
                to_json_ok(&q.jobs())
            })
        }
        "batch_cancel" => {
            let job_id = args.get("job_id").and_then(|v| v.as_str()).unwrap_or("");
            BATCH_QUEUE.with(|q| {
                let mut q = q.borrow_mut();
                q.cancel(job_id);
                to_json_ok(&true)
            })
        }
        "batch_clear_finished" => {
            BATCH_QUEUE.with(|q| {
                let mut q = q.borrow_mut();
                q.clear_finished();
                to_json_ok(&true)
            })
        }

        // Format interop (engine/src/project/interop.rs)
        "export_interop" => {
            // Args: { "timeline": <InteropTimeline JSON>, "format": "edl"|"fcpxml"|"otio" }
            let timeline_json = match args.get("timeline") {
                Some(t) => t,
                None => return to_json_err(String::from("missing 'timeline' arg")),
            };
            let timeline: crate::project::interop::InteropTimeline =
                match serde_json::from_value(timeline_json.clone()) {
                    Ok(t) => t,
                    Err(e) => return to_json_err(format!("timeline parse error: {}", e)),
                };
            let format_str = args.get("format").and_then(|v| v.as_str()).unwrap_or("edl");
            let format = match format_str {
                "edl" => crate::project::interop::InteropFormat::Edl,
                "fcpxml" => crate::project::interop::InteropFormat::Fcpxml,
                "otio" => crate::project::interop::InteropFormat::OpenTimelineIO,
                _ => return to_json_err(format!("unknown format: {}", format_str)),
            };
            to_json_ok(&crate::project::interop::export(&timeline, format))
        }

        // Advanced trim (engine/src/timeline/advanced_trim.rs)
        // Validation only — actual trim is performed by existing timeline methods
        // (split_clip, trim_clip, move_clip) composed per the trim mode.
        "validate_advanced_trim" => {
            let params_json = match args.get("params") {
                Some(p) => p,
                None => return to_json_err(String::from("missing 'params' arg")),
            };
            let params: crate::timeline::advanced_trim::AdvancedTrimParams =
                match serde_json::from_value(params_json.clone()) {
                    Ok(p) => p,
                    Err(e) => return to_json_err(format!("params parse error: {}", e)),
                };
            // For validation we need clip state from the caller — pass as separate args
            let clip_duration_ms = args.get("clip_duration_ms").and_then(|v| v.as_u64()).unwrap_or(0);
            let clip_in = args.get("clip_in_ms").and_then(|v| v.as_i64()).unwrap_or(0);
            let clip_out = args.get("clip_out_ms").and_then(|v| v.as_i64()).unwrap_or(0);
            let clip_start = args.get("clip_start_ms").and_then(|v| v.as_i64()).unwrap_or(0);
            let adj_duration = args.get("adj_duration_ms").and_then(|v| v.as_u64());
            let adj_in = args.get("adj_in_ms").and_then(|v| v.as_i64());
            let adj_out = args.get("adj_out_ms").and_then(|v| v.as_i64());
            let adj_start = args.get("adj_start_ms").and_then(|v| v.as_i64());

            match crate::timeline::advanced_trim::validate_trim(
                &params, clip_duration_ms, clip_in, clip_out, clip_start,
                adj_duration, adj_in, adj_out, adj_start,
            ) {
                Ok(()) => to_json_ok(&true),
                Err(e) => to_json_err(e),
            }
        }

        // ─── Phase F.3: Engine-wired pro tools (apply LUT, EQ, markers,
        //                 loudness) — finishes the F.2 stubbed integrations ──

        // Apply a previously-loaded LUT to a frame.
        // Args: { "lut_json": <Lut JSON>, "frame_b64": "...", "width": N, "height": N, "intensity": 0.0..1.0 }
        // Returns: base64-encoded RGBA8 frame with LUT applied.
        "apply_lut_to_frame" => {
            let lut_json = match args.get("lut_json") {
                Some(v) => v,
                None => return to_json_err(String::from("missing 'lut_json' arg")),
            };
            let lut: crate::effects::lut::Lut = match serde_json::from_value(lut_json.clone()) {
                Ok(l) => l,
                Err(e) => return to_json_err(format!("lut parse error: {}", e)),
            };
            let frame_b64 = args.get("frame").and_then(|v| v.as_str()).unwrap_or("");
            let width = args.get("width").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
            let height = args.get("height").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
            let intensity = args.get("intensity").and_then(|v| v.as_f64()).unwrap_or(1.0) as f32;
            match base64_decode_bytes(frame_b64) {
                Some(mut pixels) if pixels.len() == width * height * 4 => {
                    lut.apply_rgba8(&mut pixels, width, height, intensity);
                    to_json_ok(&base64_encode_bytes(&pixels))
                }
                Some(_) => to_json_err(String::from("frame size mismatch")),
                None => to_json_err(String::from("invalid base64 frame")),
            }
        }

        // Apply an EQ chain (HPF + 8 peaking bands + LPF) to f32 PCM samples.
        // Args: { "settings": <EqSettings JSON>, "samples_b64": "...", "sample_rate": 44100 }
        // Returns: base64-encoded f32 PCM samples (LE bytes).
        "apply_eq_to_samples" => {
            let settings_json = match args.get("settings") {
                Some(v) => v,
                None => return to_json_err(String::from("missing 'settings' arg")),
            };
            let settings: crate::audio::effects::EqSettings = match serde_json::from_value(settings_json.clone()) {
                Ok(s) => s,
                Err(e) => return to_json_err(format!("settings parse error: {}", e)),
            };
            let samples_b64 = args.get("samples").and_then(|v| v.as_str()).unwrap_or("");
            let sample_rate = args.get("sample_rate").and_then(|v| v.as_u64()).unwrap_or(44100) as u32;
            match base64_decode_f32_samples(samples_b64) {
                Some(samples) => {
                    let result = crate::audio::effects::apply_eq_chain(&samples, sample_rate, &settings);
                    to_json_ok(&base64_encode_f32_samples(&result))
                }
                None => to_json_err(String::from("invalid base64 samples")),
            }
        }

        // ─── Markers CRUD (engine/src/effects/markers.rs via EditorsProEngine) ──

        "markers_add" => {
            let name = args.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let position_ms = args.get("position_ms").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let color_str = args.get("color").and_then(|v| v.as_str()).unwrap_or("blue");
            let type_str = args.get("marker_type").and_then(|v| v.as_str()).unwrap_or("standard");
            let comment = args.get("comment").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let color = parse_marker_color(color_str);
            let marker_type = parse_marker_type(type_str);
            match api.add_marker(name, position_ms, color, marker_type, comment) {
                Ok(m) => to_json_ok(&serde_json::to_value(&m).unwrap_or_default()),
                Err(e) => to_json_err(e),
            }
        }
        "markers_get" => {
            match api.get_markers() {
                Ok(markers) => to_json_ok(&serde_json::to_value(&markers).unwrap_or_default()),
                Err(e) => to_json_err(e),
            }
        }
        "markers_remove" => {
            let id = args.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            match api.remove_marker(id) {
                Ok(Some(m)) => to_json_ok(&serde_json::to_value(&m).unwrap_or_default()),
                Ok(None) => to_json_err(String::from("marker not found")),
                Err(e) => to_json_err(e),
            }
        }

        // ─── Loudness analysis (engine/src/analysis/loudness.rs) ──────────

        // Analyze loudness of arbitrary f32 PCM samples.
        // Args: { "samples_b64": "...", "sample_rate": 44100, "channels": 2 }
        // Returns: { integrated_lufs, short_term_lufs, momentary_lufs, rms_db, peak_db, true_peak_dbtp }
        "analyze_loudness" => {
            let samples_b64 = args.get("samples").and_then(|v| v.as_str()).unwrap_or("");
            let sample_rate = args.get("sample_rate").and_then(|v| v.as_u64()).unwrap_or(44100) as u32;
            let channels = args.get("channels").and_then(|v| v.as_u64()).unwrap_or(2) as u32;
            match base64_decode_f32_samples(samples_b64) {
                Some(samples) => {
                    match api.analyze_loudness(samples, sample_rate, channels) {
                        Ok(result) => to_json_ok(&serde_json::to_value(&result).unwrap_or_default()),
                        Err(e) => to_json_err(e),
                    }
                }
                None => to_json_err(String::from("invalid base64 samples")),
            }
        }

        // Get the last computed loudness reading (null if no audio analyzed).
        // Polled by the Flutter Audio Meter Bridge.
        "get_current_loudness" => {
            match api.get_current_loudness() {
                Ok(Some(result)) => to_json_ok(&serde_json::to_value(&result).unwrap_or_default()),
                Ok(None) => to_json_ok(&serde_json::Value::Null),
                Err(e) => to_json_err(e),
            }
        }

        // ─── Phase F.4: Per-track mixer state (pan, solo) ────────────────

        "set_track_pan" => {
            let track_id = args.get("track_id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let pan = args.get("pan").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
            to_json_string::<()>(api.set_track_pan(track_id, pan))
        }
        "get_track_pan" => {
            let track_id = args.get("track_id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            to_json_string(api.get_track_pan(track_id))
        }
        "set_track_solo" => {
            let track_id = args.get("track_id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let solo = args.get("solo").and_then(|v| v.as_bool()).unwrap_or(false);
            to_json_string::<()>(api.set_track_solo(track_id, solo))
        }
        "get_track_solo" => {
            let track_id = args.get("track_id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            to_json_string(api.get_track_solo(track_id))
        }

        // ─── Phase F.4: Per-track EQ settings ────────────────────────────

        "set_track_eq_settings" => {
            let track_id = args.get("track_id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let settings_json = match args.get("settings") {
                Some(v) => v,
                None => return to_json_err(String::from("missing 'settings' arg")),
            };
            let settings: crate::audio::effects::EqSettings = match serde_json::from_value(settings_json.clone()) {
                Ok(s) => s,
                Err(e) => return to_json_err(format!("settings parse error: {}", e)),
            };
            to_json_string::<()>(api.set_track_eq_settings(track_id, settings))
        }
        "get_track_eq_settings" => {
            let track_id = args.get("track_id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            match api.get_track_eq_settings(track_id) {
                Ok(Some(s)) => to_json_ok(&serde_json::to_value(&s).unwrap_or_default()),
                Ok(None) => to_json_ok(&serde_json::Value::Null),
                Err(e) => to_json_err(e),
            }
        }

        // ─── Phase F.4: Audio cache write-back ───────────────────────────

        "set_audio_samples" => {
            let asset_id = args.get("asset_id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let samples_b64 = args.get("samples").and_then(|v| v.as_str()).unwrap_or("");
            let sample_rate = args.get("sample_rate").and_then(|v| v.as_u64()).unwrap_or(44100) as u32;
            let channels = args.get("channels").and_then(|v| v.as_u64()).unwrap_or(2) as u32;
            match base64_decode_f32_samples(samples_b64) {
                Some(samples) => {
                    to_json_string::<()>(api.set_audio_samples(asset_id, samples, sample_rate, channels))
                }
                None => to_json_err(String::from("invalid base64 samples")),
            }
        }

        // ─── Phase F.5: Active LUT (applied in get_frame) ──────────────────

        "set_active_lut" => {
            let lut_json = match args.get("lut_json") {
                Some(v) => v,
                None => return to_json_err(String::from("missing 'lut_json' arg")),
            };
            let lut: crate::effects::lut::Lut = match serde_json::from_value(lut_json.clone()) {
                Ok(l) => l,
                Err(e) => return to_json_err(format!("lut parse error: {}", e)),
            };
            let intensity = args.get("intensity").and_then(|v| v.as_f64()).unwrap_or(1.0) as f32;
            to_json_string::<()>(api.set_active_lut(lut, intensity))
        }
        "clear_active_lut" => {
            to_json_string::<()>(api.clear_active_lut())
        }

        // ─── Stream-based methods (Phase C.14) ─────────────────────────────
        // `stream_frames` and `export_video_streaming` are NOT exposed via
        // the FFI dispatcher because they require StreamSink which cannot
        // be passed across a plain C FFI boundary. Use polling fallbacks:
        // get_frame / export_video_with_callback.

        // ─── Catch-all ────────────────────────────────────────────────────
        _ => to_json_err(format!("unknown method: {}", method)),
    }
}

/// Parse a u64 from a JSON value, accepting both `u64` and numeric strings
/// (since Dart's `BigInt` is serialized as a string for values > 2^53).
fn parse_u64(args: &serde_json::Value, key: &str) -> u64 {
    args.get(key)
        .and_then(|v| {
            v.as_u64()
                .or_else(|| v.as_str().and_then(|s| s.parse::<u64>().ok()))
        })
        .unwrap_or(0)
}

/// Parse an f32 from a JSON value, accepting both numbers and numeric strings.
fn parse_f32(args: &serde_json::Value, key: &str) -> f32 {
    args.get(key)
        .and_then(|v| {
            v.as_f64()
                .map(|f| f as f32)
                .or_else(|| v.as_str().and_then(|s| s.parse::<f32>().ok()))
        })
        .unwrap_or(0.0)
}

// ─── Pro Tools helpers (Phase F) ───────────────────────────────────────────

/// Thread-local batch export queue. One queue per dispatch thread; the
/// typical case is a single thread, so this is functionally a global queue.
///
/// video: thread-local queue, upgrade to global queue with cross-thread sync if export is driven from a worker thread
thread_local! {
    static BATCH_QUEUE: std::cell::RefCell<crate::export_engine::batch::BatchExportQueue> =
        std::cell::RefCell::new(crate::export_engine::batch::BatchExportQueue::new());
}

/// Decode a base64 string to bytes. Returns None on failure.
fn base64_decode_bytes(s: &str) -> Option<Vec<u8>> {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.decode(s).ok()
}

/// Encode bytes to a base64 string.
fn base64_encode_bytes(bytes: &[u8]) -> String {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

/// Decode a base64 string to f32 samples (little-endian f32 bytes).
fn base64_decode_f32_samples(s: &str) -> Option<Vec<f32>> {
    let bytes = base64_decode_bytes(s)?;
    if bytes.len() % 4 != 0 {
        return None;
    }
    Some(
        bytes
            .chunks_exact(4)
            .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
            .collect(),
    )
}

/// Encode f32 samples to a base64 string (little-endian bytes).
fn base64_encode_f32_samples(samples: &[f32]) -> String {
    let bytes: Vec<u8> = samples.iter().flat_map(|s| s.to_le_bytes()).collect();
    base64_encode_bytes(&bytes)
}

/// Parse a marker color string into the engine enum. Falls back to Blue.
fn parse_marker_color(s: &str) -> crate::effects::markers::MarkerColor {
    use crate::effects::markers::MarkerColor;
    match s.to_lowercase().as_str() {
        "red" => MarkerColor::Red,
        "orange" => MarkerColor::Orange,
        "yellow" => MarkerColor::Yellow,
        "green" => MarkerColor::Green,
        "blue" => MarkerColor::Blue,
        "purple" => MarkerColor::Purple,
        "pink" => MarkerColor::Pink,
        "gray" | "grey" => MarkerColor::Gray,
        _ => MarkerColor::Blue,
    }
}

/// Parse a marker type string into the engine enum. Falls back to Standard.
fn parse_marker_type(s: &str) -> crate::effects::markers::MarkerType {
    use crate::effects::markers::MarkerType;
    match s.to_lowercase().as_str() {
        "standard" => MarkerType::Standard,
        "chapter" => MarkerType::Chapter,
        "comment" => MarkerType::Comment,
        "todo" => MarkerType::Todo,
        "error" => MarkerType::Error,
        "musicbeat" | "music_beat" | "beat" => MarkerType::MusicBeat,
        "custom" => MarkerType::Custom,
        _ => MarkerType::Standard,
    }
}

// ─── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_to_json_string_ok() {
        let s = to_json_string(Ok(42u64));
        assert!(s.contains(r#""ok":true"#));
        assert!(s.contains("42"));
    }

    #[test]
    fn test_to_json_string_err() {
        let s = to_json_string::<u64>(Err("boom".to_string()));
        assert!(s.contains(r#""ok":false"#));
        assert!(s.contains("boom"));
    }

    #[test]
    fn test_parse_u64_from_number() {
        let args = serde_json::json!({"start_ms": 12345});
        assert_eq!(parse_u64(&args, "start_ms"), 12345);
    }

    #[test]
    fn test_parse_u64_from_string() {
        // BigInt-serialized values come through as strings.
        let args = serde_json::json!({"start_ms": "12345"});
        assert_eq!(parse_u64(&args, "start_ms"), 12345);
    }

    #[test]
    fn test_parse_u64_missing_key() {
        let args = serde_json::json!({});
        assert_eq!(parse_u64(&args, "start_ms"), 0);
    }

    /// End-to-end smoke test: dispatch the `initialize` method through the
    /// FFI boundary and verify we get a JSON-serialized success response.
    /// This exercises the global Mutex<EditorsProEngineApi> as well as the
    /// JSON serialization path.
    #[test]
    fn test_dispatch_initialize() {
        let method = CString::new("initialize").unwrap();
        let args = CString::new("{}").unwrap();
        let raw = unsafe {
            editors_pro_dispatch(method.as_ptr(), args.as_ptr())
        };
        assert!(!raw.is_null());
        let s = unsafe { CStr::from_ptr(raw) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editors_pro_free_string(raw) };
        assert!(s.contains(r#""ok":true"#), "got: {}", s);
    }

    /// End-to-end smoke test: dispatch an unknown method and verify we get
    /// a graceful error rather than a panic.
    #[test]
    fn test_dispatch_unknown_method() {
        let method = CString::new("definitely_not_a_real_method").unwrap();
        let args = CString::new("{}").unwrap();
        let raw = unsafe {
            editors_pro_dispatch(method.as_ptr(), args.as_ptr())
        };
        assert!(!raw.is_null());
        let s = unsafe { CStr::from_ptr(raw) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editors_pro_free_string(raw) };
        assert!(s.contains(r#""ok":false"#), "got: {}", s);
        assert!(s.contains("unknown method"), "got: {}", s);
    }

    /// Verify that dispatching to `get_engine_version` returns a string
    /// matching the crate version.
    #[test]
    fn test_dispatch_get_engine_version() {
        let method = CString::new("get_engine_version").unwrap();
        let args = CString::new("{}").unwrap();
        let raw = unsafe {
            editors_pro_dispatch(method.as_ptr(), args.as_ptr())
        };
        assert!(!raw.is_null());
        let s = unsafe { CStr::from_ptr(raw) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editors_pro_free_string(raw) };
        assert!(s.contains(r#""ok":true"#), "got: {}", s);
        assert!(
            s.contains(env!("CARGO_PKG_VERSION")),
            "expected version {}, got: {}",
            env!("CARGO_PKG_VERSION"),
            s
        );
    }
}
