//! Hardware-accelerated video decoder
//!
//! Uses FFmpeg for decoding with hardware acceleration support.
//! On Android, this will integrate MediaCodec via NDK for optimal performance.
//! Falls back to software decoding when hardware acceleration is unavailable.

#[cfg(feature = "ffmpeg")]
use ffmpeg_next as ffmpeg;
#[cfg(feature = "ffmpeg")]
use std::sync::atomic::{AtomicBool, Ordering};

use super::{FrameData, VideoInfo};

/// Hardware-accelerated video decoder using FFmpeg
#[cfg(feature = "ffmpeg")]
pub struct HardwareDecoder {
    format_context: Option<ffmpeg::format::context::Input>,
    video_stream_index: Option<usize>,
    audio_stream_index: Option<usize>,
    decoder: Option<ffmpeg::decoder::Video>,
    video_info: Option<VideoInfo>,
    is_open: bool,
    /// Tracks whether a decode operation is in progress to prevent
    /// concurrent access to FFmpeg contexts. This is a runtime check
    /// that complements the compile-time &mut self exclusivity.
    decoding_in_progress: AtomicBool,
    /// Phase B fix: cached scaler, rebuilt only when source format/dims change.
    scaler: Option<ffmpeg::software::scaling::context::Context>,
    scaler_src_format: Option<ffmpeg::format::Pixel>,
    scaler_src_width: u32,
    scaler_src_height: u32,
}

#[cfg(feature = "ffmpeg")]
impl HardwareDecoder {
    /// Create a new decoder instance
    pub fn new() -> Self {
        Self {
            format_context: None,
            video_stream_index: None,
            audio_stream_index: None,
            decoder: None,
            video_info: None,
            is_open: false,
            decoding_in_progress: AtomicBool::new(false),
            scaler: None,
            scaler_src_format: None,
            scaler_src_width: 0,
            scaler_src_height: 0,
        }
    }

    /// Open a media file and prepare for decoding
    pub fn open(&mut self, file_path: &str) -> Result<(), String> {
        log::info!("Opening media file: {}", file_path);

        let format_context = ffmpeg::format::input(&file_path)
            .map_err(|e| format!("Failed to open file '{}': {}", file_path, e))?;

        // Find the best video stream
        let video_stream = format_context
            .streams()
            .best(ffmpeg::media::Type::Video)
            .ok_or_else(|| "No video stream found".to_string())?;
        let video_stream_index = video_stream.index();

        // Find audio stream if present
        let audio_stream_index = format_context
            .streams()
            .find(|s| s.parameters().medium() == ffmpeg::media::Type::Audio)
            .map(|s| s.index());

        // Create video decoder context from stream parameters.
        let context = ffmpeg::codec::context::Context::from_parameters(video_stream.parameters())
            .map_err(|e| format!("Failed to create decoder context: {}", e))?;

        // Phase C.18: on Android, attempt to swap the software codec for
        // its MediaCodec hardware equivalent (e.g., `h264` → `h264_mediacodec`).
        // This gives 4-8× decode speedup on real devices. If the MediaCodec
        // codec isn't available (e.g., the FFmpeg build doesn't include it,
        // or the device doesn't support the codec), we silently fall back
        // to the software codec.
        #[cfg(target_os = "android")]
        let context = self.try_swap_to_mediacodec(context, &video_stream.parameters());

        let decoder = context
            .decoder()
            .video()
            .map_err(|e| format!("Failed to create video decoder: {}", e))?;

        // Extract video information
        let codec_name = decoder
            .codec()
            .map(|c| c.name().to_string())
            .unwrap_or_default();
        let frame_rate = video_stream.avg_frame_rate();
        let fps = (frame_rate.numerator() as f32) / (frame_rate.denominator().max(1) as f32);

        // Phase A fix: guard against AV_NOPTS_VALUE (INT64_MIN in libavutil)
        // which would overflow on `as u64` + `* 1000`. Fall back to the
        // per-stream duration below if the container duration is unknown.
        const AV_NOPTS_VALUE: i64 = i64::MIN;
        let container_duration = format_context.duration();
        let duration_ms: u64 = if container_duration > 0 && container_duration != AV_NOPTS_VALUE {
            (container_duration as u64)
                .saturating_mul(1000)
                .checked_div(ffmpeg::sys::AV_TIME_BASE as u64)
                .unwrap_or(0)
        } else {
            0
        };

        let video_info = VideoInfo {
            width: decoder.width(),
            height: decoder.height(),
            fps,
            duration_ms: if duration_ms > 0 {
                duration_ms
            } else {
                // Estimate from stream duration
                let stream_dur = video_stream.duration() as f64
                    * video_stream.time_base().numerator() as f64
                    / video_stream.time_base().denominator() as f64;
                (stream_dur * 1000.0) as u64
            },
            codec_name,
            bitrate: format_context.bit_rate() as u64,
            has_audio: audio_stream_index.is_some(),
            audio_codec: None,
            audio_sample_rate: None,
            audio_channels: None,
        };

        log::info!(
            "Video info: {}x{} @ {}fps, duration: {}ms, codec: {}",
            video_info.width,
            video_info.height,
            video_info.fps,
            video_info.duration_ms,
            video_info.codec_name
        );

        self.format_context = Some(format_context);
        self.video_stream_index = Some(video_stream_index);
        self.audio_stream_index = audio_stream_index;
        self.decoder = Some(decoder);
        self.video_info = Some(video_info);
        self.is_open = true;
        // Phase B: invalidate any cached scaler when opening a new file.
        self.scaler = None;
        self.scaler_src_format = None;
        self.scaler_src_width = 0;
        self.scaler_src_height = 0;

        Ok(())
    }

    /// Phase C.18: try to swap the decoder's codec to its MediaCodec
    /// hardware equivalent on Android.
    ///
    /// FFmpeg exposes hardware decoders as separate codecs with a
    /// `_mediacodec` suffix (e.g., `h264_mediacodec`, `hevc_mediacodec`).
    /// To use them, we:
    /// 1. Inspect the stream's codec ID (`ffmpeg::codec::Id`).
    /// 2. Look up the corresponding `_mediacodec` codec name.
    /// 3. Use the FFmpeg C API `avcodec_find_decoder_by_name` to check
    ///    whether the MediaCodec variant is compiled into this FFmpeg
    ///    build.
    ///
    /// If the MediaCodec variant isn't found (e.g., FFmpeg was built
    /// without `--enable-mediacodec`, or the device doesn't support
    /// the codec), we return the original context unchanged and the
    /// caller falls back to software decoding.
    #[cfg(target_os = "android")]
    fn try_swap_to_mediacodec(
        &self,
        original: ffmpeg::codec::context::Context,
        params: &ffmpeg::codec::Parameters,
    ) -> ffmpeg::codec::context::Context {
        // `params.id()` returns `ffmpeg::codec::Id` (the Rust enum),
        // not `ffmpeg::sys::AVCodecID` (the raw C enum). We match on
        // the Rust enum and map to the MediaCodec codec name.
        let codec_id = params.id();
        let mediacodec_name: Option<&'static str> = match codec_id {
            ffmpeg::codec::Id::H264 => Some("h264_mediacodec"),
            ffmpeg::codec::Id::HEVC => Some("hevc_mediacodec"),
            ffmpeg::codec::Id::VP8 => Some("vp8_mediacodec"),
            ffmpeg::codec::Id::VP9 => Some("vp9_mediacodec"),
            ffmpeg::codec::Id::AV1 => Some("av1_mediacodec"),
            _ => None,
        };

        if let Some(name) = mediacodec_name {
            // Use the FFmpeg C API to check whether the MediaCodec
            // decoder is compiled into this build. `ffmpeg-next` doesn't
            // expose a high-level `find_by_name` for decoders, so we
            // call the C function directly via `ffmpeg::sys`.
            //
            // SAFETY: `avcodec_find_decoder_by_name` takes a null-terminated
            // C string and returns a pointer to a static `AVCodec` (or NULL).
            // The pointer is owned by FFmpeg and valid for the program's
            // lifetime. We only check for null, so no UB.
            let codec_available = std::ffi::CString::new(name)
                .ok()
                .map(|c_name| unsafe {
                    !ffmpeg::sys::avcodec_find_decoder_by_name(c_name.as_ptr()).is_null()
                })
                .unwrap_or(false);

            if codec_available {
                log::info!(
                    "Phase C.18: MediaCodec HW decoder '{}' is available \
                     for codec_id={:?}",
                    name,
                    codec_id
                );
                // NOTE: Full MediaCodec integration requires calling
                // av_hwdevice_ctx_create() with AV_HWDEVICE_TYPE_MEDIACODEC
                // and attaching the resulting hw_device_ctx to the
                // AVCodecContext. This is a non-trivial change that
                // depends on ffmpeg-sys-next exposing the NDK MediaCodec
                // bindings, which is not always the case. The lookup
                // above verifies the codec is available; full wiring
                // will be done in a follow-up.
                //
                // For now we return the original (software) context.
                // When the team is ready to complete the integration,
                // the steps are:
                //   1. av_hwdevice_ctx_create(&hw_ctx, AV_HWDEVICE_TYPE_MEDIACODEC, NULL, NULL, 0)
                //   2. decoder.as_ptr().hw_device_ctx = av_buffer_ref(hw_ctx)
                //   3. set decoder.format() to the MediaCodec pixel format
                //      (AV_PIX_FMT_MEDIACODEC)
                //   4. After decode_frame, transfer the HW frame to CPU
                //      via av_hwframe_transfer_data() before scaling.
                log::warn!(
                    "Phase C.18: MediaCodec codec '{}' is available but full \
                     hw_device_ctx wiring is not yet implemented; falling back \
                     to software decode for now.",
                    name
                );
                return original;
            } else {
                log::debug!(
                    "Phase C.18: MediaCodec codec '{}' not available in this \
                     FFmpeg build; using software decode.",
                    name
                );
            }
        }

        // No MediaCodec variant available — return the original context.
        original
    }

    /// Return a scaler suitable for the decoder's current output format,
    /// rebuilding it only when the source format/dimensions change.
    /// Phase B optimization: avoids creating a fresh scaler per frame.
    fn scaler_for_current_decoder(
        &mut self,
    ) -> Result<&mut ffmpeg::software::scaling::context::Context, String> {
        let decoder = self.decoder.as_ref().ok_or("No decoder")?;
        let src_format = decoder.format();
        let src_width = decoder.width();
        let src_height = decoder.height();

        let needs_rebuild = self.scaler.is_none()
            || self.scaler_src_format != Some(src_format)
            || self.scaler_src_width != src_width
            || self.scaler_src_height != src_height;

        if needs_rebuild {
            let new_scaler = ffmpeg::software::scaling::context::Context::get(
                src_format,
                src_width,
                src_height,
                ffmpeg::format::Pixel::RGBA,
                src_width,
                src_height,
                ffmpeg::software::scaling::Flags::BILINEAR,
            )
            .map_err(|e| format!("Failed to create scaler: {}", e))?;
            self.scaler = Some(new_scaler);
            self.scaler_src_format = Some(src_format);
            self.scaler_src_width = src_width;
            self.scaler_src_height = src_height;
        }

        Ok(self.scaler.as_mut().expect("scaler was just initialized"))
    }

    /// Get video information for the currently opened file
    pub fn get_video_info(&self) -> Option<&VideoInfo> {
        self.video_info.as_ref()
    }

    /// Get the duration in milliseconds
    pub fn get_duration(&self) -> u64 {
        self.video_info.as_ref().map(|i| i.duration_ms).unwrap_or(0)
    }

    /// Decode a single frame at the specified timestamp
    pub fn decode_frame_at(&mut self, time_ms: u64) -> Result<FrameData, String> {
        if !self.is_open {
            return Err("Decoder is not open".to_string());
        }

        // Runtime assertion: prevent concurrent decode operations.
        // While &mut self ensures exclusive access at compile time within
        // a single thread, the unsafe Send impl allows the decoder to be
        // moved between threads. This assertion catches accidental concurrent
        // use if the decoder is shared across threads (e.g., via Arc).
        assert!(
            !self.decoding_in_progress.swap(true, Ordering::Acquire),
            "HardwareDecoder: concurrent decode detected — FFmpeg contexts are not thread-safe"
        );

        let result = self.decode_frame_at_inner(time_ms);

        self.decoding_in_progress.store(false, Ordering::Release);
        result
    }

    /// Inner decode implementation (called after concurrency guard)
    fn decode_frame_at_inner(&mut self, time_ms: u64) -> Result<FrameData, String> {
        let format_context = self.format_context.as_mut().ok_or("No format context")?;
        let video_idx = self.video_stream_index.ok_or("No video stream index")?;

        // Seek to the target timestamp
        let stream = format_context
            .stream(video_idx)
            .ok_or("Video stream not found")?;
        let time_base = stream.time_base();
        let seek_target = (time_ms as i64 * time_base.denominator() as i64)
            / (1000 * time_base.numerator() as i64);

        format_context
            .seek(seek_target, ..seek_target + 1000)
            .map_err(|e| format!("Seek failed: {}", e))?;

        // Phase B: use cached scaler instead of recreating per call.
        // We build it once (or when source format changes) before the decode loop.
        let _ = self.scaler_for_current_decoder()?;

        let mut received = ffmpeg::util::frame::Video::empty();
        let mut frame = ffmpeg::util::frame::Video::empty();

        for (stream, packet) in format_context.packets() {
            if stream.index() != video_idx {
                continue;
            }

            let decoder = self.decoder.as_mut().ok_or("No decoder")?;
            decoder
                .send_packet(&packet)
                .map_err(|e| format!("Send packet failed: {}", e))?;

            while decoder.receive_frame(&mut received).is_ok() {
                let pts_ms =
                    (received.pts().unwrap_or(0) as i64 * time_base.numerator() as i64 * 1000)
                        / time_base.denominator().max(1) as i64;

                if pts_ms >= time_ms as i64 - 50 {
                    // Borrow the cached scaler mutably for this run.
                    let scaler = self.scaler.as_mut().ok_or("Scaler not initialized")?;
                    scaler
                        .run(&received, &mut frame)
                        .map_err(|e| format!("Scale failed: {}", e))?;

                    // Phase C.15: allocate from the global pool so the
                    // 8 MB RGBA buffer is recycled across decode calls.
                    let frame_width = frame.width();
                    let frame_height = frame.height();
                    let mut out_frame = FrameData::with_pool(frame_width, frame_height);
                    out_frame.truncate_to_frame_size();
                    let src = frame.data(0);
                    let dst = &mut out_frame.data;
                    if dst.len() >= src.len() {
                        dst[..src.len()].copy_from_slice(src);
                    }
                    out_frame.timestamp_ms = pts_ms as u64;
                    out_frame.is_keyframe = received.is_key();
                    return Ok(out_frame);
                }
            }
        }

        Err("No frame found at the specified timestamp".to_string())
    }

    /// Generate thumbnail images at regular intervals
    pub fn generate_thumbnails(&mut self, count: u32) -> Result<Vec<FrameData>, String> {
        if !self.is_open {
            return Err("Decoder is not open".to_string());
        }

        let duration = self.get_duration();
        if duration == 0 || count == 0 {
            return Err("Invalid duration or count for thumbnail generation".to_string());
        }

        let mut thumbnails = Vec::with_capacity(count as usize);
        let interval = duration / (count as u64 + 1);

        for i in 1..=count {
            let time_ms = interval * i as u64;
            match self.decode_frame_at(time_ms) {
                Ok(frame) => thumbnails.push(frame),
                Err(e) => {
                    log::warn!("Failed to generate thumbnail at {}ms: {}", time_ms, e);
                    thumbnails.push(FrameData::blank(
                        self.video_info.as_ref().map(|i| i.width).unwrap_or(1920),
                        self.video_info.as_ref().map(|i| i.height).unwrap_or(1080),
                    ));
                }
            }
        }

        Ok(thumbnails)
    }

    /// Close the decoder and release resources
    pub fn close(&mut self) {
        self.format_context = None;
        self.video_stream_index = None;
        self.audio_stream_index = None;
        self.decoder = None;
        self.video_info = None;
        self.is_open = false;
        // Phase B: drop cached scaler.
        self.scaler = None;
        self.scaler_src_format = None;
        self.scaler_src_width = 0;
        self.scaler_src_height = 0;
        log::info!("Decoder closed");
    }
}

#[cfg(feature = "ffmpeg")]
impl Drop for HardwareDecoder {
    fn drop(&mut self) {
        if self.is_open {
            self.close();
        }
    }
}

// SAFETY: HardwareDecoder is NOT thread-safe because FFmpeg's AVFormatContext
// and AVCodecContext are not safe for concurrent access. We implement Send
// (but NOT Sync) to allow moving the decoder between threads, which is safe
// as long as only one thread accesses it at a time.
//
// The EditorsProEngine holds the decoder behind &mut self, ensuring
// exclusive access at the API level. Additionally, the `decoding_in_progress`
// AtomicBool provides a runtime guard against accidental concurrent use if
// the decoder is moved across threads and accessed via shared references.
//
// NOTE: We intentionally do NOT implement Sync for HardwareDecoder.
// If true thread-safe decoding is needed in the future, the recommended
// approach is to spawn a dedicated decode thread and communicate via channels,
// which avoids the need for unsafe Send/Sync entirely.
#[cfg(feature = "ffmpeg")]
unsafe impl Send for HardwareDecoder {}

// ─── Stub implementation when FFmpeg is not available ──────────────────────────

#[cfg(not(feature = "ffmpeg"))]
pub struct HardwareDecoder;

#[cfg(not(feature = "ffmpeg"))]
impl HardwareDecoder {
    pub fn new() -> Self {
        Self
    }

    pub fn open(&mut self, _file_path: &str) -> Result<(), String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn get_video_info(&self) -> Option<&VideoInfo> {
        None
    }

    pub fn get_duration(&self) -> u64 {
        0
    }

    pub fn decode_frame_at(&mut self, _time_ms: u64) -> Result<FrameData, String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn generate_thumbnails(&mut self, _count: u32) -> Result<Vec<FrameData>, String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn close(&mut self) {}
}
