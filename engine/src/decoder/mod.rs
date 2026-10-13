//! Video/Audio decoder module
//!
//! Handles decoding media files using FFmpeg with hardware acceleration
//! support (MediaCodec on Android) and software fallback.

pub mod hardware;
pub mod software;
pub mod still_image;
pub mod worker;

#[cfg(test)]
mod tests;

use once_cell::sync::Lazy;

use crate::system::buffer_pool::{BufferPool, BufferPoolConfig, PooledBuffer};

/// Information about a video file
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct VideoInfo {
    pub width: u32,
    pub height: u32,
    pub fps: f32,
    pub duration_ms: u64,
    pub codec_name: String,
    pub bitrate: u64,
    pub has_audio: bool,
    pub audio_codec: Option<String>,
    pub audio_sample_rate: Option<u32>,
    pub audio_channels: Option<u32>,
}

/// Global frame buffer pool (Phase C.15).
///
/// A single process-wide pool that recycles `Vec<u8>` allocations for
/// decoded RGBA frames. The hot path for 1080p playback allocates 8 MB
/// per frame (1920×1080×4 bytes) at 30 fps = 240 MB/s of allocations.
/// Without a pool this triggers frequent malloc/free syscalls and
/// fragments the heap; with the pool, the same buffer is reused across
/// frames once the steady-state working set is reached.
///
/// The pool is bounded per size class (default 8 buffers per class) so
/// it never grows unbounded. Under memory pressure the engine calls
/// `release_all()` to drop every pooled buffer.
pub static FRAME_BUFFER_POOL: Lazy<BufferPool> = Lazy::new(|| {
    BufferPool::with_config(BufferPoolConfig {
        max_per_class: 8,
        prewarm: true,
    })
});

/// A decoded frame with RGBA pixel data
///
/// Phase C.15: `data` can optionally be backed by the global
/// [`FRAME_BUFFER_POOL`]. Use [`FrameData::with_pool`] to allocate
/// from the pool, and [`FrameData::return_to_pool`] to return the
/// buffer when the frame is no longer needed. Frames constructed via
/// [`FrameData::blank`] or by deserialization use a plain `Vec<u8>`
/// and are not pooled.
#[derive(Debug, Clone)]
pub struct FrameData {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>, // RGBA format, 4 bytes per pixel
    pub timestamp_ms: u64,
    pub is_keyframe: bool,
    /// Whether `data` was allocated from the pool and should be
    /// returned on drop. Set by `with_pool`, cleared by `into_data`
    /// or any operation that takes ownership of the `Vec`.
    pub pooled: bool,
}

impl FrameData {
    /// Create a blank black frame.
    ///
    /// Uses a plain `Vec<u8>` (not pooled). Suitable for test fixtures
    /// and one-off placeholders. For decode hot paths, use
    /// [`FrameData::with_pool`] instead.
    pub fn blank(width: u32, height: u32) -> Self {
        let size = (width * height * 4) as usize;
        Self {
            width,
            height,
            data: vec![0u8; size],
            timestamp_ms: 0,
            is_keyframe: true,
            pooled: false,
        }
    }

    /// Phase C.15: allocate a frame from the global buffer pool.
    ///
    /// The returned `FrameData` has `data.len()` >= `width * height * 4`
    /// (the pool rounds up to the nearest size class). Callers should
    /// use [`FrameData::truncate_to_size`] to shrink the `Vec` to the
    /// exact frame size before passing it to consumers that expect
    /// tightly-sized buffers.
    ///
    /// When this `FrameData` is dropped, the buffer is automatically
    /// returned to the pool (see `Drop` impl).
    pub fn with_pool(width: u32, height: u32) -> Self {
        let size = (width * height * 4) as usize;
        let pooled_buf: PooledBuffer = FRAME_BUFFER_POOL.allocate(size);
        // We take ownership of the underlying Vec so we can store it
        // in FrameData. The pool's `Drop` would normally return the
        // buffer; by calling `into_vec()` we prevent that and instead
        // mark `pooled: true` so FrameData's own Drop returns it.
        let data = pooled_buf.into_vec();
        Self {
            width,
            height,
            data,
            timestamp_ms: 0,
            is_keyframe: false,
            pooled: true,
        }
    }

    /// Phase C.15: shrink the data buffer to exactly `width * height * 4`
    /// bytes. Useful after `with_pool` rounds up to a size class.
    ///
    /// This is a no-op if the buffer is already the right size.
    pub fn truncate_to_frame_size(&mut self) {
        let expected = (self.width * self.height * 4) as usize;
        if self.data.len() != expected {
            self.data.resize(expected, 0);
        }
    }

    /// Phase C.15: take ownership of the underlying `Vec<u8>`.
    ///
    /// The buffer will NOT be returned to the pool when this `FrameData`
    /// is dropped. Use this when transferring the bytes to a consumer
    /// that doesn't know about the pool (e.g., serializing across FFI).
    pub fn into_data(mut self) -> Vec<u8> {
        self.pooled = false;
        std::mem::take(&mut self.data)
    }

    /// Phase C.15: explicitly return the buffer to the pool, if pooled.
    ///
    /// After this call, `data` is empty and `pooled` is false. Safe to
    /// call on non-pooled frames (no-op).
    pub fn return_to_pool(&mut self) {
        if self.pooled {
            let data = std::mem::take(&mut self.data);
            FRAME_BUFFER_POOL.handle().return_vec(data);
            self.pooled = false;
        }
    }

    /// Get the total number of pixels
    pub fn pixel_count(&self) -> u32 {
        self.width * self.height
    }

    /// Get the data size in bytes (width * height * 4)
    pub fn data_size(&self) -> usize {
        (self.width * self.height * 4) as usize
    }
}

impl Drop for FrameData {
    fn drop(&mut self) {
        // Phase C.15: if the buffer was allocated from the pool and the
        // caller didn't take ownership via `into_data` or `return_to_pool`,
        // return it to the pool now. This closes the recycle loop so the
        // same 8 MB buffer is reused for the next frame decode.
        //
        // We swallow any panic from the pool's lock (e.g., if the mutex
        // is poisoned) — dropping a frame should never crash the engine.
        if self.pooled {
            let data = std::mem::take(&mut self.data);
            // Don't let a poisoned pool panic propagate out of Drop.
            let _ = std::panic::catch_unwind(|| {
                FRAME_BUFFER_POOL.handle().return_vec(data);
            });
            self.pooled = false;
        }
    }
}

/// Audio sample data
#[derive(Debug, Clone)]
pub struct AudioData {
    pub samples: Vec<f32>, // Interleaved stereo samples
    pub sample_rate: u32,
    pub channels: u32,
    pub timestamp_ms: u64,
    pub duration_ms: u64,
}
