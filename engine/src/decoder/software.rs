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
    /// Preserve lookahead when selecting the frame active at a timestamp.
    pending_frame: Option<FrameData>,
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
            pending_frame: None,
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
            audio_codec: audio_stream.as_ref().and_then(|s| {
                let ctx = ffmpeg::codec::context::Context::from_parameters(s.parameters()).ok()?;
                Some(ctx.decoder().audio().ok()?.codec()?.name().to_string())
            }),
            audio_sample_rate: audio_stream.as_ref().and_then(|s| {
                let ctx = ffmpeg::codec::context::Context::from_parameters(s.parameters()).ok()?;
                Some(ctx.decoder().audio().ok()?.rate())
            }),
            audio_channels: audio_stream.as_ref().and_then(|s| {
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
        self.pending_frame = None;
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
        // Input::seek uses stream -1 and therefore AV_TIME_BASE microseconds.
        let target = time_ms.saturating_mul(1000).min(i64::MAX as u64) as i64;
        format_context
            .seek(target, ..target)
            .map_err(|e| format!("Seek failed: {}", e))?;

        self.current_position_ms = time_ms;
        self.pending_frame = None;
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
        if let Some(frame) = self.pending_frame.take() {
            self.current_position_ms = frame.timestamp_ms;
            return Ok(Some(frame));
        }
        let video_idx = self.video_stream_index.ok_or("No video stream")?;
        let tb = self
            .format_context
            .as_ref()
            .ok_or("Not open")?
            .stream(video_idx)
            .ok_or("Stream not found")?
            .time_base();
        let mut decoded = ffmpeg::util::frame::Video::empty();
        let mut scaled = ffmpeg::util::frame::Video::empty();
        // Always drain available frames before feeding another packet, and
        // send EOF to recover delayed B-frames at the end of a normal GOP.
        loop {
            match self
                .decoder
                .as_mut()
                .ok_or("No decoder")?
                .receive_frame(&mut decoded)
            {
                Ok(()) => break,
                Err(ffmpeg::Error::Eof) => return Ok(None),
                Err(ffmpeg::Error::Other {
                    errno: ffmpeg::sys::EAGAIN,
                }) => {}
                Err(error) => return Err(format!("Receive frame error: {}", error)),
            }
            let packet = self
                .format_context
                .as_mut()
                .ok_or("Not open")?
                .packets()
                .find(|(stream, _)| stream.index() == video_idx)
                .map(|(_, packet)| packet);
            let decoder = self.decoder.as_mut().ok_or("No decoder")?;
            match packet {
                Some(packet) => decoder
                    .send_packet(&packet)
                    .map_err(|e| format!("Send packet error: {}", e))?,
                None => decoder
                    .send_eof()
                    .map_err(|e| format!("Drain decoder error: {}", e))?,
            }
        }
        let pts = decoded
            .timestamp()
            .or(decoded.pts())
            .ok_or("Decoded frame has no timestamp")?;
        let pts_ms = (pts * tb.numerator() as i64 * 1000) / tb.denominator().max(1) as i64;
        self.scaler_for_current_decoder()?
            .run(&decoded, &mut scaled)
            .map_err(|e| format!("Scale error: {}", e))?;
        self.current_position_ms = pts_ms.max(0) as u64;
        let mut frame = FrameData::with_pool(scaled.width(), scaled.height());
        frame.truncate_to_frame_size();
        let row_bytes = scaled.width() as usize * 4;
        for row in 0..scaled.height() as usize {
            let source = row * scaled.stride(0);
            let destination = row * row_bytes;
            frame.data[destination..destination + row_bytes]
                .copy_from_slice(&scaled.data(0)[source..source + row_bytes]);
        }
        frame.timestamp_ms = self.current_position_ms;
        frame.is_keyframe = decoded.is_key();
        Ok(Some(frame))
    }

    /// Decode a frame at a specific timestamp
    pub fn decode_frame_at(&mut self, time_ms: u64) -> Result<FrameData, String> {
        self.seek_to(time_ms)?;

        let mut selected: Option<FrameData> = None;
        while let Some(frame) = self.decode_next_frame()? {
            if frame.timestamp_ms > time_ms {
                if let Some(previous) = selected {
                    self.pending_frame = Some(frame);
                    self.current_position_ms = previous.timestamp_ms;
                    return Ok(previous);
                }
                return Ok(frame);
            }
            if frame.timestamp_ms == time_ms {
                return Ok(frame);
            }
            selected = Some(frame);
        }
        selected.ok_or_else(|| format!("No frame found at {}ms", time_ms))
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
        self.pending_frame = None;
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
