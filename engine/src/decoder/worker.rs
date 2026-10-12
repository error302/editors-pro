//! Dedicated decode thread with channel-based request/response (Phase C.13).
//!
//! ## Why this exists
//!
//! Previously, `EditorsProEngine::get_frame` ran FFmpeg decode on the
//! calling thread — typically the Flutter UI thread via the FFI dispatcher.
//! At 30 FPS preview, that's 30 sequential FFI calls per second, each
//! blocking on FFmpeg's `decode_frame_at` (which itself does disk I/O,
//! packet demuxing, and H.264 entropy decoding).
//!
//! This module moves decode to a dedicated worker thread. The Flutter
//! side sends a `DecodeRequest` via a `crossbeam_channel::Sender`, and
//! receives a `DecodeResponse` on a oneshot channel. The worker thread
//! owns the `HardwareDecoder` exclusively, eliminating the need for
//! `unsafe impl Send` on FFmpeg contexts (the decoder never leaves the
//! thread that opened it).
//!
//! ## Architecture
//!
//! ```text
//! Flutter UI thread                  Decode worker thread
//! ─────────────────────              ─────────────────────
//!  get_frame(t)         ──req──►     loop {
//!    await oneshot.rx()                  req = rx.recv()
//!    ──────────────────                  match req {
//!    ◄──resp──                            Open(path) => decoder.open(path)
//!                                         Seek(t)    => decoder.decode_frame_at(t)
//!                                         Close      => decoder.close()
//!                                       }
//!                                       tx.send(resp)
//!                                     }
//! ```
//!
//! ## Future: push-based streaming (Phase C.14)
//!
//! The current design is still request-response. Phase C.14 will extend
//! this to push-based streaming, where the worker proactively decodes
//! the next N frames and pushes them via a `flutter_rust_bridge::StreamSink`
//! so the Flutter side can render them without round-trips.

use std::sync::Arc;
use std::thread;

use crossbeam_channel::{bounded, Receiver, Sender};
use once_cell::sync::Lazy;

use crate::decoder::{FrameData, VideoInfo};
use crate::decoder::hardware::HardwareDecoder;

/// A request from the Flutter side to the decode worker.
pub enum DecodeRequest {
    /// Open a media file for decoding. Closes any previously-opened file.
    Open {
        file_path: String,
        /// Oneshot channel for the response.
        response: crossbeam_channel::Sender<DecodeResponse>,
    },
    /// Decode a single frame at the given timestamp (ms).
    Seek {
        time_ms: u64,
        response: crossbeam_channel::Sender<DecodeResponse>,
    },
    /// Close the currently-opened file.
    Close {
        response: crossbeam_channel::Sender<DecodeResponse>,
    },
    /// Get the VideoInfo for the currently-opened file.
    GetInfo {
        response: crossbeam_channel::Sender<DecodeResponse>,
    },
    /// Shut down the worker thread. After this, no more requests can be sent.
    Shutdown,
}

/// A response from the decode worker.
#[derive(Debug)]
pub enum DecodeResponse {
    /// Operation succeeded with no data.
    Ok,
    /// Operation succeeded with a frame.
    Frame(Option<FrameData>),
    /// Operation succeeded with video info.
    Info(Option<VideoInfo>),
    /// Operation failed.
    Error(String),
}

/// Handle to the decode worker.
///
/// Cloning is cheap (just an `Arc` and a `Sender`). The worker thread
/// runs until `Shutdown` is sent or all handles are dropped.
#[derive(Clone)]
pub struct DecodeWorker {
    tx: Sender<DecodeRequest>,
    _handle: Arc<WorkerHandle>,
}

struct WorkerHandle {
    /// JoinHandle for the worker thread. Joined on drop.
    join: Option<thread::JoinHandle<()>>,
}

impl Drop for WorkerHandle {
    fn drop(&mut self) {
        // Try to send a shutdown signal. If the channel is already closed
        // (because someone else sent Shutdown), that's fine — the worker
        // will exit anyway.
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }
}

impl DecodeWorker {
    /// Spawn a new decode worker thread.
    ///
    /// The thread runs until `shutdown()` is called or the sender side
    /// of the channel is dropped.
    pub fn spawn() -> Self {
        // Bounded channel of 1: the worker processes one request at a
        // time, and we don't want requests piling up if the Flutter
        // side is sending them faster than FFmpeg can decode. The
        // Flutter side will block on `request()` until the worker is
        // ready, which is the desired backpressure behavior.
        let (tx, rx) = bounded::<DecodeRequest>(1);

        let join = thread::Builder::new()
            .name("editors-pro-decode".to_string())
            .spawn(move || {
                Self::worker_loop(rx);
            })
            .expect("failed to spawn decode worker thread");

        Self {
            tx,
            _handle: Arc::new(WorkerHandle {
                join: Some(join),
            }),
        }
    }

    /// The worker thread's main loop. Owns the `HardwareDecoder` for
    /// its entire lifetime — no `Send` needed because the decoder never
    /// leaves this thread.
    fn worker_loop(rx: Receiver<DecodeRequest>) {
        let mut decoder = HardwareDecoder::new();
        log::info!("Decode worker thread started");

        while let Ok(req) = rx.recv() {
            match req {
                DecodeRequest::Open { file_path, response } => {
                    let result = decoder.open(&file_path).map(|_| DecodeResponse::Ok);
                    let resp = match result {
                        Ok(r) => r,
                        Err(e) => DecodeResponse::Error(e),
                    };
                    let _ = response.send(resp);
                }
                DecodeRequest::Seek { time_ms, response } => {
                    let result = decoder.decode_frame_at(time_ms);
                    let resp = match result {
                        Ok(frame) => DecodeResponse::Frame(Some(frame)),
                        Err(e) => DecodeResponse::Error(e),
                    };
                    let _ = response.send(resp);
                }
                DecodeRequest::Close { response } => {
                    decoder.close();
                    let _ = response.send(DecodeResponse::Ok);
                }
                DecodeRequest::GetInfo { response } => {
                    let info = decoder.get_video_info().cloned();
                    let _ = response.send(DecodeResponse::Info(info));
                }
                DecodeRequest::Shutdown => {
                    log::info!("Decode worker received Shutdown signal");
                    decoder.close();
                    break;
                }
            }
        }

        log::info!("Decode worker thread exiting");
    }

    /// Send an `Open` request and wait for the response.
    ///
    /// Blocks the calling thread until the worker has finished opening
    /// the file. Returns `Err` if the worker has shut down.
    pub fn open(&self, file_path: &str) -> Result<(), String> {
        let (resp_tx, resp_rx) = crossbeam_channel::bounded(1);
        self.tx
            .send(DecodeRequest::Open {
                file_path: file_path.to_string(),
                response: resp_tx,
            })
            .map_err(|_| "decode worker channel closed".to_string())?;
        match resp_rx.recv().map_err(|_| "decode worker dropped response".to_string())? {
            DecodeResponse::Ok => Ok(()),
            DecodeResponse::Error(e) => Err(e),
            _ => Err("unexpected response type for Open".to_string()),
        }
    }

    /// Send a `Seek` request and wait for the decoded frame.
    ///
    /// Returns `Ok(None)` if the worker decoded successfully but produced
    /// no frame (e.g., end of stream).
    pub fn seek(&self, time_ms: u64) -> Result<Option<FrameData>, String> {
        let (resp_tx, resp_rx) = crossbeam_channel::bounded(1);
        self.tx
            .send(DecodeRequest::Seek {
                time_ms,
                response: resp_tx,
            })
            .map_err(|_| "decode worker channel closed".to_string())?;
        match resp_rx.recv().map_err(|_| "decode worker dropped response".to_string())? {
            DecodeResponse::Frame(f) => Ok(f),
            DecodeResponse::Error(e) => Err(e),
            _ => Err("unexpected response type for Seek".to_string()),
        }
    }

    /// Send a `Close` request.
    pub fn close(&self) -> Result<(), String> {
        let (resp_tx, resp_rx) = crossbeam_channel::bounded(1);
        self.tx
            .send(DecodeRequest::Close {
                response: resp_tx,
            })
            .map_err(|_| "decode worker channel closed".to_string())?;
        match resp_rx.recv().map_err(|_| "decode worker dropped response".to_string())? {
            DecodeResponse::Ok => Ok(()),
            DecodeResponse::Error(e) => Err(e),
            _ => Err("unexpected response type for Close".to_string()),
        }
    }

    /// Send a `GetInfo` request.
    pub fn get_info(&self) -> Result<Option<VideoInfo>, String> {
        let (resp_tx, resp_rx) = crossbeam_channel::bounded(1);
        self.tx
            .send(DecodeRequest::GetInfo {
                response: resp_tx,
            })
            .map_err(|_| "decode worker channel closed".to_string())?;
        match resp_rx.recv().map_err(|_| "decode worker dropped response".to_string())? {
            DecodeResponse::Info(i) => Ok(i),
            DecodeResponse::Error(e) => Err(e),
            _ => Err("unexpected response type for GetInfo".to_string()),
        }
    }

    /// Shut down the worker thread. After this, no more requests can
    /// be sent on this handle.
    pub fn shutdown(&self) {
        let _ = self.tx.send(DecodeRequest::Shutdown);
    }
}

/// Global decode worker singleton.
///
/// Lazily spawned on first use. The worker runs for the lifetime of
/// the process. Use `DecodeWorker::instance()` to get a handle.
pub static DECODE_WORKER: Lazy<DecodeWorker> = Lazy::new(DecodeWorker::spawn);

impl DecodeWorker {
    /// Get the global decode worker instance.
    pub fn instance() -> &'static DecodeWorker {
        &DECODE_WORKER
    }
}

// ─── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decode_worker_spawn_and_shutdown() {
        let worker = DecodeWorker::spawn();
        // Worker should be alive.
        worker.shutdown();
        // After shutdown, sending a request should fail.
        let result = worker.open("/dev/null");
        assert!(result.is_err(), "expected error after shutdown");
    }

    #[test]
    fn test_decode_worker_open_nonexistent_file() {
        let worker = DecodeWorker::spawn();
        let result = worker.open("/this/path/definitely/does/not/exist.mp4");
        assert!(result.is_err(), "expected error for nonexistent file");
        worker.shutdown();
    }

    #[test]
    fn test_decode_worker_get_info_without_open() {
        let worker = DecodeWorker::spawn();
        let info = worker.get_info();
        // Should succeed but return None (no file opened).
        assert!(info.is_ok(), "get_info failed: {:?}", info);
        assert!(info.unwrap().is_none(), "expected None when no file open");
        worker.shutdown();
    }

    #[test]
    fn test_decode_worker_clone_preserves_handle() {
        let worker = DecodeWorker::spawn();
        let cloned = worker.clone();
        // Both should share the same underlying thread.
        let info1 = cloned.get_info();
        let info2 = worker.get_info();
        assert!(info1.is_ok() && info2.is_ok());
        // Shutting down one affects both (shared Arc).
        cloned.shutdown();
    }

    #[test]
    fn test_global_decode_worker_instance() {
        // Just verify the global is reachable.
        let _worker = DecodeWorker::instance();
        // Don't shut it down — it's process-global.
    }
}
