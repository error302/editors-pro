//! Software video decoder fallback
//!
//! Pure FFmpeg-based software decoder for environments where
//! hardware acceleration is not available or not needed.

#[cfg(feature = "ffmpeg")]
use ffmpeg_next as ffmpeg;

use super::{FrameData, VideoInfo};

/// Software-only video decoder using FFmpeg
#[cfg(feature = "ffmpeg")]
pub struct SoftwareDecoder {
    format_context: Option<ffmpeg::format::context::Input>,
    video_stream_index: Option<usize>,
    decoder: Option<ffmpeg::decoder::Video>,
    video_info: Option<VideoInfo>,
    is_open: bool,
    current_position_ms: u64,
    /// Phase B fix: cache the FFmpeg scaler so we don't recreate it on
    /// every `decode_next_frame()` call. Recreating a scaler per frame
    /// at 30fps = 30 scaler constructions/sec, which is wasteful.
    /// The scaler is invalidated when the input format/dimensions change.
    scaler: Option<ffmpeg::software::scaling::context::Context>,
    /// Cached input format used to detect when the scaler must be rebuilt.
    scaler_src_format: Option<ffmpeg::format::Pixel>,
    scaler_src_width: u32,
    scaler_src_height: u32,
}

#[cfg(feature = "ffmpeg")]
impl SoftwareDecoder {
    pub fn new() -> Self {
        Self {
            format_context: None,
            video_stream_index: None,
            decoder: None,
            video_info: None,
            is_open: false,
            current_position_ms: 0,
            scaler: None,
            scaler_src_format: None,
            scaler_src_width: 0,
            scaler_src_height: 0,
        }
    }

    /// Open a media file for software decoding
    pub fn open(&mut self, file_path: &str) -> Result<(), String> {
        log::info!("Software decoder opening: {}", file_path);

        let format_context = ffmpeg::format::input(&file_path)
            .map_err(|e| format!("Failed to open '{}': {}", file_path, e))?;

        let video_stream = format_context
            .streams()
            .best(ffmpeg::media::Type::Video)
            .ok_or("No video stream found")?;
        let video_idx = video_stream.index();

        let context = ffmpeg::codec::context::Context::from_parameters(video_stream.parameters())
            .map_err(|e| format!("Decoder context error: {}", e))?;

        let decoder = context
            .decoder()
            .video()
            .map_err(|e| format!("Video decoder error: {}", e))?;

        let frame_rate = video_stream.avg_frame_rate();
        let fps = frame_rate.numerator() as f32 / frame_rate.denominator().max(1) as f32;

        // Phase A fix: guard against AV_NOPTS_VALUE (defined as INT64_MIN in
        // libavutil) which would overflow when cast to u64 and multiplied by
        // 1000. We compare against the literal value to avoid depending on
        // whether `ffmpeg::sys::AV_NOPTS_VALUE` is exposed as a `i64` const
        // vs. a `u64` const across ffmpeg-sys-next versions.
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

        let audio_stream = format_context
            .streams()
            .find(|s| s.parameters().medium() == ffmpeg::media::Type::Audio);

        let video_info = VideoInfo {
            width: decoder.width(),
            height: decoder.height(),
            fps,
            duration_ms: if duration_ms > 0 {
                duration_ms
            } else {
                let dur = video_stream.duration() as f64
                    * video_stream.time_base().numerator() as f64
                    / video_stream.time_base().denominator().max(1) as f64;
                (dur * 1000.0) as u64
            },
            codec_name: decoder
                .codec()
                .map(|c| c.name().to_string())
                .unwrap_or_default(),
            bitrate: format_context.bit_rate() as u64,
            has_audio: audio_stream.is_some(),
            audio_codec: audio_stream.and_then(|s| {
                let ctx = ffmpeg::codec::context::Context::from_parameters(s.parameters()).ok()?;
                Some(ctx.decoder().audio().ok()?.codec()?.name().to_string())
            }),
            audio_sample_rate: audio_stream.and_then(|s| {
                let ctx = ffmpeg::codec::context::Context::from_parameters(s.parameters()).ok()?;
                Some(ctx.decoder().audio().ok()?.rate())
            }),
            audio_channels: audio_stream.and_then(|s| {
                let ctx = ffmpeg::codec::context::Context::from_parameters(s.parameters()).ok()?;
                Some(ctx.decoder().audio().ok()?.channels() as u32)
            }),
        };

        log::info!(
            "Software decoder: {}x{} @ {}fps, {}ms, codec: {}",
            video_info.width,
            video_info.height,
            video_info.fps,
            video_info.duration_ms,
            video_info.codec_name
        );

        self.format_context = Some(format_context);
        self.video_stream_index = Some(video_idx);
        self.decoder = Some(decoder);
        self.video_info = Some(video_info);
        self.is_open = true;
        // Invalidate any cached scaler from a previously-opened file.
        self.scaler = None;
        self.scaler_src_format = None;
        self.scaler_src_width = 0;
        self.scaler_src_height = 0;

        Ok(())
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
            .map_err(|e| format!("Scaler error: {}", e))?;
            self.scaler = Some(new_scaler);
            self.scaler_src_format = Some(src_format);
            self.scaler_src_width = src_width;
            self.scaler_src_height = src_height;
        }

        Ok(self.scaler.as_mut().expect("scaler was just initialized"))
    }

    /// Seek to a specific timestamp in milliseconds
    pub fn seek_to(&mut self, time_ms: u64) -> Result<(), String> {
        let format_context = self.format_context.as_mut().ok_or("Not open")?;
        let video_idx = self.video_stream_index.ok_or("No video stream")?;
        let stream = format_context.stream(video_idx).ok_or("Stream not found")?;
        let tb = stream.time_base();

        let target =
            (time_ms as i64 * tb.denominator() as i64) / (1000 * tb.numerator().max(1) as i64);
        format_context
            .seek(target, ..target + 500)
            .map_err(|e| format!("Seek failed: {}", e))?;

        self.current_position_ms = time_ms;
        // Flush the decoder after seeking
        if let Some(decoder) = &mut self.decoder {
            decoder.flush();
        }

        Ok(())
    }

    /// Decode the next available frame
    pub fn decode_next_frame(&mut self) -> Result<Option<FrameData>, String> {
        if !self.is_open {
            return Err("Decoder not open".to_string());
        }

        let format_context = self.format_context.as_mut().ok_or("Not open")?;
        let video_idx = self.video_stream_index.ok_or("No video stream")?;
        let stream = format_context.stream(video_idx).ok_or("Stream not found")?;
        let tb = stream.time_base();

        let mut decoded = ffmpeg::util::frame::Video::empty();
        let mut scaled = ffmpeg::util::frame::Video::empty();

        for (s, packet) in format_context.packets() {
            if s.index() != video_idx {
                continue;
            }

            let decoder = self.decoder.as_mut().ok_or("No decoder")?;
            decoder
                .send_packet(&packet)
                .map_err(|e| format!("Send packet error: {}", e))?;

            while decoder.receive_frame(&mut decoded).is_ok() {
                let pts_ms = (decoded.pts().unwrap_or(0) as i64 * tb.numerator() as i64 * 1000)
                    / tb.denominator().max(1) as i64;

                // Phase B: use cached scaler instead of recreating per frame.
                let scaler = self.scaler_for_current_decoder()?;
                scaler
                    .run(&decoded, &mut scaled)
                    .map_err(|e| format!("Scale error: {}", e))?;

                self.current_position_ms = pts_ms as u64;

                // Phase C.15: allocate the output buffer from the global
                // FRAME_BUFFER_POOL so the same 8 MB Vec is recycled
                // across frames instead of being allocated and freed
                // 30 times per second.
                let frame_width = scaled.width();
                let frame_height = scaled.height();
                let mut frame = FrameData::with_pool(frame_width, frame_height);
                frame.truncate_to_frame_size();
                let src_bytes = scaled.data(0);
                let dst_bytes = &mut frame.data;
                if dst_bytes.len() >= src_bytes.len() {
                    dst_bytes[..src_bytes.len()].copy_from_slice(src_bytes);
                }
                frame.timestamp_ms = pts_ms as u64;
                frame.is_keyframe = decoded.is_key();

                return Ok(Some(frame));
            }
        }

        Ok(None)
    }

    /// Decode a frame at a specific timestamp
    pub fn decode_frame_at(&mut self, time_ms: u64) -> Result<FrameData, String> {
        self.seek_to(time_ms)?;

        // Decode frames until we reach the target
        let mut attempts = 0;
        const MAX_ATTEMPTS: u32 = 30;

        while attempts < MAX_ATTEMPTS {
            match self.decode_next_frame()? {
                Some(frame) => {
                    // Accept frame if it's close enough to the target time
                    if frame.timestamp_ms >= time_ms.saturating_sub(50) {
                        return Ok(frame);
                    }
                }
                None => break,
            }
            attempts += 1;
        }

        Err(format!(
            "No frame found at {}ms after {} attempts",
            time_ms, attempts
        ))
    }

    /// Get the current position in milliseconds
    pub fn current_position(&self) -> u64 {
        self.current_position_ms
    }

    /// Get video info
    pub fn get_video_info(&self) -> Option<&VideoInfo> {
        self.video_info.as_ref()
    }

    /// Close the decoder
    pub fn close(&mut self) {
        self.format_context = None;
        self.video_stream_index = None;
        self.decoder = None;
        self.video_info = None;
        self.is_open = false;
        // Phase B: drop cached scaler along with the decoder.
        self.scaler = None;
        self.scaler_src_format = None;
        self.scaler_src_width = 0;
        self.scaler_src_height = 0;
        log::info!("Software decoder closed");
    }
}

#[cfg(feature = "ffmpeg")]
impl Drop for SoftwareDecoder {
    fn drop(&mut self) {
        if self.is_open {
            self.close();
        }
    }
}

// SAFETY: Same rationale as HardwareDecoder - FFmpeg contexts are not
// thread-safe. Send allows moving between threads, but Sync is intentionally
// omitted to prevent shared concurrent access.
#[cfg(feature = "ffmpeg")]
unsafe impl Send for SoftwareDecoder {}

// ─── Stub implementation when FFmpeg is not available ──────────────────────────

#[cfg(not(feature = "ffmpeg"))]
pub struct SoftwareDecoder;

#[cfg(not(feature = "ffmpeg"))]
impl SoftwareDecoder {
    pub fn new() -> Self {
        Self
    }

    pub fn open(&mut self, _file_path: &str) -> Result<(), String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn seek_to(&mut self, _time_ms: u64) -> Result<(), String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn decode_next_frame(&mut self) -> Result<Option<FrameData>, String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn decode_frame_at(&mut self, _time_ms: u64) -> Result<FrameData, String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn current_position(&self) -> u64 {
        0
    }

    pub fn get_video_info(&self) -> Option<&VideoInfo> {
        None
    }

    pub fn close(&mut self) {}
}
