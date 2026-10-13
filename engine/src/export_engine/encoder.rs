//! FFmpeg encoder wrapper for video export
//!
//! Provides a high-level interface for encoding RGBA frames into video files
//! using FFmpeg's libx264/libx265 encoders. Handles output context creation,
//! codec configuration, frame encoding, and proper finalization.
//!
//! ## Architecture
//!
//! The encoder operates in two phases:
//! 1. **Setup**: Create output context, configure codec, write header
//! 2. **Encode**: Feed RGBA frames one-by-one; each is converted to YUV420P and encoded
//!
//! For two-pass encoding, phase 2 runs twice with the first pass discarding output.

#[cfg(feature = "ffmpeg")]
use ffmpeg_next as ffmpeg;

use super::{ExportResult, ExportSettings, ExportStage, VideoCodec};

// ──────────────────────────────────────────────────────────────────
// RGBA → YUV420P conversion
// ──────────────────────────────────────────────────────────────────

/// Convert RGBA pixel data to YUV420P planar format.
///
/// This is the CPU fallback used when the ffmpeg scaler is unavailable.
/// The conversion follows the BT.601 standard (same as libx264 default):
///
/// ```text
/// Y  =  0.257*R + 0.504*G + 0.098*B + 16
/// Cb = -0.148*R - 0.291*G + 0.439*B + 128
/// Cr =  0.439*R - 0.368*G - 0.071*B + 128
/// ```
///
/// Chroma subsampling averages 2×2 pixel blocks for Cb/Cr planes.
pub fn convert_rgba_to_yuv420p(rgba: &[u8], width: u32, height: u32) -> Result<Vec<u8>, String> {
    let w = width as usize;
    let h = height as usize;

    if rgba.len() < w * h * 4 {
        return Err(format!(
            "RGBA data too short: expected {} bytes, got {}",
            w * h * 4,
            rgba.len()
        ));
    }

    let y_size = w * h;
    let uv_size = w * h / 4;
    let mut yuv = Vec::with_capacity(y_size * 3 / 2);
    yuv.resize(y_size + 2 * uv_size, 0u8);

    // Luma plane (Y)
    let y_plane = &mut yuv[..y_size];
    for row in 0..h {
        for col in 0..w {
            let idx = (row * w + col) * 4;
            let r = rgba[idx] as f32;
            let g = rgba[idx + 1] as f32;
            let b = rgba[idx + 2] as f32;

            let y = 0.257 * r + 0.504 * g + 0.098 * b + 16.0;
            y_plane[row * w + col] = y.clamp(0.0, 255.0) as u8;
        }
    }

    // Chroma planes (Cb, Cr) — 2×2 subsampled
    let (_, chroma_data) = yuv.split_at_mut(y_size);
    let (cb_plane, cr_plane) = chroma_data.split_at_mut(uv_size);

    for row in (0..h).step_by(2) {
        for col in (0..w).step_by(2) {
            // Average 2×2 block
            let mut r_sum = 0.0f32;
            let mut g_sum = 0.0f32;
            let mut b_sum = 0.0f32;
            let mut count = 0;

            for dy in 0..2 {
                for dx in 0..2 {
                    let ry = row + dy;
                    let cx = col + dx;
                    if ry < h && cx < w {
                        let idx = (ry * w + cx) * 4;
                        r_sum += rgba[idx] as f32;
                        g_sum += rgba[idx + 1] as f32;
                        b_sum += rgba[idx + 2] as f32;
                        count += 1;
                    }
                }
            }

            if count > 0 {
                r_sum /= count as f32;
                g_sum /= count as f32;
                b_sum /= count as f32;
            }

            let cb = -0.148 * r_sum - 0.291 * g_sum + 0.439 * b_sum + 128.0;
            let cr = 0.439 * r_sum - 0.368 * g_sum - 0.071 * b_sum + 128.0;

            let uv_idx = (row / 2) * (w / 2) + col / 2;
            cb_plane[uv_idx] = cb.clamp(0.0, 255.0) as u8;
            cr_plane[uv_idx] = cr.clamp(0.0, 255.0) as u8;
        }
    }

    Ok(yuv)
}

/// Build an ffmpeg `Video` frame in YUV420P format from planar YUV data.
///
/// The returned frame has the correct line sizes and data pointers set up
/// for the encoder.
#[cfg(feature = "ffmpeg")]
fn build_yuv420p_frame(
    yuv_data: &[u8],
    width: u32,
    height: u32,
    pts: i64,
) -> Result<ffmpeg::frame::Video, String> {
    let w = width as usize;
    let h = height as usize;
    let y_size = w * h;

    // Create an ffmpeg frame
    let mut frame = ffmpeg::frame::Video::new(ffmpeg::format::Pixel::YUV420P, width, height);

    frame.set_pts(Some(pts));

    // Copy Y plane
    let y_src = &yuv_data[..y_size];
    let y_dst = frame.data_mut(0);
    let y_stride = frame.stride(0);
    for row in 0..h {
        let src_start = row * w;
        let src_end = src_start + w;
        let dst_start = row * y_stride;
        if src_end <= y_size && dst_start + w <= y_dst.len() {
            y_dst[dst_start..dst_start + w].copy_from_slice(&y_src[src_start..src_end]);
        }
    }

    // Copy Cb plane
    let uv_w = w / 2;
    let uv_h = h / 2;
    let uv_size = uv_w * uv_h;
    let cb_src = &yuv_data[y_size..y_size + uv_size];
    let cb_dst = frame.data_mut(1);
    let cb_stride = frame.stride(1);
    for row in 0..uv_h {
        let src_start = row * uv_w;
        let src_end = src_start + uv_w;
        let dst_start = row * cb_stride;
        if src_end <= uv_size && dst_start + uv_w <= cb_dst.len() {
            cb_dst[dst_start..dst_start + uv_w].copy_from_slice(&cb_src[src_start..src_end]);
        }
    }

    // Copy Cr plane
    let cr_src = &yuv_data[y_size + uv_size..];
    let cr_dst = frame.data_mut(2);
    let cr_stride = frame.stride(2);
    for row in 0..uv_h {
        let src_start = row * uv_w;
        let src_end = src_start + uv_w;
        let dst_start = row * cr_stride;
        if src_end <= cr_src.len() && dst_start + uv_w <= cr_dst.len() {
            cr_dst[dst_start..dst_start + uv_w].copy_from_slice(&cr_src[src_start..src_end]);
        }
    }

    Ok(frame)
}

// ──────────────────────────────────────────────────────────────────
// Encoder
// ──────────────────────────────────────────────────────────────────

/// FFmpeg-based video encoder that writes H.264/H.265/VP9 to MP4/WebM/MOV.
///
/// Usage:
/// ```rust
/// let mut encoder = VideoEncoder::new(&settings)?;
/// encoder.open(output_path)?;
///
/// for each_frame {
///     encoder.encode_rgba_frame(rgba_data, pts)?;
/// }
///
/// let result = encoder.finish()?;
/// ```
#[cfg(feature = "ffmpeg")]
pub struct VideoEncoder {
    settings: ExportSettings,
    output_context: Option<ffmpeg::format::context::Output>,
    output_path: Option<String>,
    encoder: Option<ffmpeg::encoder::Video>,
    stream_index: Option<usize>,
    frame_count: u64,
    start_time: std::time::Instant,
}

#[cfg(feature = "ffmpeg")]
impl VideoEncoder {
    /// Create a new encoder with the given export settings.
    pub fn new(settings: &ExportSettings) -> Result<Self, String> {
        // Validate settings
        if settings.width == 0 || settings.height == 0 {
            return Err("Width and height must be non-zero".to_string());
        }
        if settings.width % 2 != 0 || settings.height % 2 != 0 {
            return Err(format!(
                "Dimensions must be even (got {}x{})",
                settings.width, settings.height
            ));
        }
        if settings.fps <= 0.0 {
            return Err("FPS must be positive".to_string());
        }
        if settings.bitrate_kbps == 0 {
            return Err("Bitrate must be non-zero".to_string());
        }

        Ok(Self {
            settings: settings.clone(),
            output_context: None,
            output_path: None,
            encoder: None,
            stream_index: None,
            frame_count: 0,
            start_time: std::time::Instant::now(),
        })
    }

    /// Open the output file and configure the codec.
    ///
    /// After calling this, the encoder is ready to receive frames.
    pub fn open(&mut self, output_path: &str) -> Result<(), String> {
        log::info!(
            "Opening encoder: {}x{} @ {}fps, {}kbps, codec={:?}",
            self.settings.width,
            self.settings.height,
            self.settings.fps,
            self.settings.bitrate_kbps,
            self.settings.codec
        );

        // 1. Create output format context
        let mut octx = ffmpeg::format::output(&output_path).map_err(|e| {
            format!(
                "Failed to create output context for '{}': {}",
                output_path, e
            )
        })?;

        // 2. Find the encoder codec
        let codec_name = self.settings.codec.ffmpeg_codec_name();
        let codec = ffmpeg::encoder::find_by_name(codec_name)
            .ok_or_else(|| format!("Codec '{}' not found in FFmpeg", codec_name))?;

        // 3. Add a video stream
        let mut stream = octx
            .add_stream(codec)
            .map_err(|e| format!("Failed to add stream: {}", e))?;
        let stream_idx = stream.index();

        // 4. Configure the encoder
        let mut encoder = ffmpeg::codec::context::Context::new_with_codec(codec)
            .encoder()
            .video()
            .map_err(|e| format!("Failed to create video encoder: {}", e))?;

        encoder.set_width(self.settings.width);
        encoder.set_height(self.settings.height);
        encoder.set_frame_rate(Some(ffmpeg::Rational::new(self.settings.fps as i32, 1)));
        encoder.set_bit_rate(self.settings.bitrate_kbps as usize * 1000);
        encoder.set_format(ffmpeg::format::Pixel::YUV420P);

        // Set time_base to match frame rate (standard practice)
        let time_base = ffmpeg::Rational::new(1, self.settings.fps as i32);
        encoder.set_time_base(time_base);
        stream.set_time_base(time_base);

        // Codec-specific options
        match self.settings.codec {
            VideoCodec::H264 => {
                #[cfg(target_os = "android")]
                encoder
                    .open()
                    .map_err(|e| format!("Failed to open Android H.264 encoder: {}", e))?;

                #[cfg(not(target_os = "android"))]
                {
                    let mut opts = ffmpeg::Dictionary::new();
                    let _ = opts.set("preset", "medium");
                    let _ = opts.set("crf", "23");
                    encoder
                        .open_with(opts)
                        .map_err(|e| format!("Failed to open H.264 encoder: {}", e))?;
                }
            }
            VideoCodec::H265 => {
                #[cfg(target_os = "android")]
                encoder
                    .open()
                    .map_err(|e| format!("Failed to open Android H.265 encoder: {}", e))?;

                #[cfg(not(target_os = "android"))]
                {
                    let mut opts = ffmpeg::Dictionary::new();
                    let _ = opts.set("preset", "medium");
                    let _ = opts.set("crf", "28");
                    encoder
                        .open_with(opts)
                        .map_err(|e| format!("Failed to open H.265 encoder: {}", e))?;
                }
            }
            _ => {
                encoder
                    .open()
                    .map_err(|e| format!("Failed to open encoder: {}", e))?;
            }
        }

        // 5. Set stream parameters from encoder
        stream.set_parameters(&encoder);

        // 6. Write header
        octx.write_header()
            .map_err(|e| format!("Failed to write header: {}", e))?;

        log::info!("Encoder opened successfully: {}", output_path);

        self.output_context = Some(octx);
        self.output_path = Some(output_path.to_string());
        self.encoder = Some(encoder);
        self.stream_index = Some(stream_idx);
        self.start_time = std::time::Instant::now();
        self.frame_count = 0;

        Ok(())
    }

    /// Open the output file with both video and audio streams.
    ///
    /// Returns a `MuxedEncoder` that can encode both video and audio.
    /// This is the recommended way to export with audio support.
    /// Consumes the `VideoEncoder` (which must not already be opened).
    pub fn open_with_audio(self, output_path: &str) -> Result<MuxedEncoder, String> {
        if self.output_context.is_some() {
            return Err(
                "VideoEncoder is already opened; cannot convert to MuxedEncoder".to_string(),
            );
        }
        let mut muxed = MuxedEncoder::new(&self.settings)?;
        muxed.open(output_path)?;
        Ok(muxed)
    }

    /// Encode a single RGBA frame and write it to the output.
    ///
    /// The `pts` (presentation timestamp) should be the frame number,
    /// starting from 0. The encoder's time_base will convert this to
    /// the correct timestamp.
    pub fn encode_rgba_frame(&mut self, rgba_data: &[u8], pts: i64) -> Result<(), String> {
        let stream_index = self.stream_index.ok_or("Output stream not configured")?;
        let octx = self.output_context.as_mut().ok_or("Encoder not opened")?;
        let encoder = self.encoder.as_mut().ok_or("Encoder not configured")?;

        // Convert RGBA → YUV420P
        let yuv_data =
            convert_rgba_to_yuv420p(rgba_data, self.settings.width, self.settings.height)?;

        // Build ffmpeg frame
        let frame = build_yuv420p_frame(&yuv_data, self.settings.width, self.settings.height, pts)?;

        // Send frame to encoder
        encoder
            .send_frame(&frame)
            .map_err(|e| format!("Send frame error: {}", e))?;

        // Receive and write encoded packets
        Self::receive_and_write_packets(stream_index, octx, encoder)?;

        self.frame_count += 1;
        Ok(())
    }

    /// Encode a single frame that is already in YUV420P format.
    pub fn encode_yuv420p_frame(&mut self, yuv_data: &[u8], pts: i64) -> Result<(), String> {
        let stream_index = self.stream_index.ok_or("Output stream not configured")?;
        let octx = self.output_context.as_mut().ok_or("Encoder not opened")?;
        let encoder = self.encoder.as_mut().ok_or("Encoder not configured")?;

        let frame = build_yuv420p_frame(yuv_data, self.settings.width, self.settings.height, pts)?;

        encoder
            .send_frame(&frame)
            .map_err(|e| format!("Send frame error: {}", e))?;

        Self::receive_and_write_packets(stream_index, octx, encoder)?;

        self.frame_count += 1;
        Ok(())
    }

    /// Flush the encoder and write the trailer, returning the export result.
    ///
    /// After calling this, the encoder is consumed and cannot be reused.
    pub fn finish(mut self, duration_ms: u64) -> Result<ExportResult, String> {
        let output_path = self
            .output_path
            .clone()
            .ok_or("Output path not configured")?;
        let stream_index = self.stream_index.ok_or("Output stream not configured")?;
        let octx = self.output_context.as_mut().ok_or("Encoder not opened")?;

        // Flush the encoder
        if let Some(encoder) = self.encoder.as_mut() {
            // Send EOF to flush
            let _ = encoder.send_eof();
            Self::receive_and_write_packets(stream_index, octx, encoder)?;
        }

        // Write trailer
        octx.write_trailer()
            .map_err(|e| format!("Failed to write trailer: {}", e))?;

        // Get output file size
        let file_size = std::fs::metadata(&output_path)
            .map(|m| m.len())
            .unwrap_or(0);

        let elapsed = self.start_time.elapsed();
        log::info!(
            "Export complete: {} frames, {}ms → {}bytes, took {:.1}s",
            self.frame_count,
            duration_ms,
            file_size,
            elapsed.as_secs_f64()
        );

        Ok(ExportResult {
            success: true,
            output_path,
            file_size_bytes: file_size,
            duration_ms,
            error_message: None,
        })
    }

    /// Cancel the export and clean up the output file.
    pub fn cancel(self) {
        if let Some(octx) = self.output_context {
            let path = self.output_path.unwrap_or_default();
            // Close the context first
            drop(octx);
            // Delete the partial file
            let _ = std::fs::remove_file(&path);
            log::info!("Export cancelled, partial file removed: {}", path);
        }
    }

    /// Get the number of frames encoded so far.
    pub fn frame_count(&self) -> u64 {
        self.frame_count
    }

    /// Get the elapsed time since the encoder was opened.
    pub fn elapsed(&self) -> std::time::Duration {
        self.start_time.elapsed()
    }

    /// Receive encoded packets from the encoder and write them to the output.
    fn receive_and_write_packets(
        stream_index: usize,
        octx: &mut ffmpeg::format::context::Output,
        encoder: &mut ffmpeg::encoder::Video,
    ) -> Result<(), String> {
        let output_time_base = octx
            .stream(stream_index)
            .ok_or("Output video stream not found")?
            .time_base();
        let encoder_time_base = encoder.time_base();
        let mut packet = ffmpeg::Packet::new();
        while encoder.receive_packet(&mut packet).is_ok() {
            packet.set_stream(stream_index);
            packet.rescale_ts(encoder_time_base, output_time_base);
            packet
                .write_interleaved(octx)
                .map_err(|e| format!("Write packet error: {}", e))?;
        }
        Ok(())
    }
}

/// Estimate the remaining time for an export based on progress.
///
/// Returns the estimated seconds remaining, or 0 if not enough data.
pub fn estimate_remaining(
    current_frame: u64,
    total_frames: u64,
    start_time: std::time::Instant,
) -> u64 {
    if current_frame == 0 || total_frames == 0 {
        return 0;
    }

    let elapsed = start_time.elapsed().as_secs_f64();
    let frames_per_sec = current_frame as f64 / elapsed;
    let remaining_frames = total_frames.saturating_sub(current_frame);

    (remaining_frames as f64 / frames_per_sec).ceil() as u64
}

/// Check available storage space at the given path.
///
/// Returns `Ok(())` if there's enough space (at least 500MB free),
/// or an error message describing the issue.
pub fn check_storage_space(output_path: &str, estimated_size_bytes: u64) -> Result<(), String> {
    // Get the parent directory of the output path
    let path = std::path::Path::new(output_path);
    let dir = path.parent().unwrap_or(std::path::Path::new("/"));

    // Try to get filesystem stats
    // On Android, this will work for app-specific directories
    let available = fs_available_space(dir);

    // Require at least 100MB + estimated size
    let required = estimated_size_bytes + 100 * 1024 * 1024;

    if available < required {
        let available_mb = available / (1024 * 1024);
        let required_mb = required / (1024 * 1024);
        return Err(format!(
            "Insufficient storage: {:.0}MB available, {:.0}MB required",
            available_mb, required_mb
        ));
    }

    Ok(())
}

/// Get available disk space for a directory (in bytes).
///
/// Returns 0 if the information cannot be determined.
fn fs_available_space(path: &std::path::Path) -> u64 {
    // On Unix (Android is Linux), use statvfs
    #[cfg(unix)]
    {
        use std::ffi::CString;
        use std::mem::MaybeUninit;
        use std::os::unix::ffi::OsStrExt;

        let c_path = match CString::new(path.as_os_str().as_bytes()) {
            Ok(p) => p,
            Err(_) => return 0,
        };

        unsafe {
            let mut stat: MaybeUninit<libc::statvfs> = MaybeUninit::uninit();
            if libc::statvfs(c_path.as_ptr(), stat.as_mut_ptr()) == 0 {
                let stat = stat.assume_init();
                return stat.f_bsize as u64 * stat.f_bavail;
            }
        }
    }

    // Fallback: assume plenty of space
    #[cfg(not(unix))]
    {
        let _ = path;
    }

    0
}

// ──────────────────────────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn video_codecs_use_encoders_available_for_target() {
        #[cfg(target_os = "android")]
        let expected = [
            "h264_mediacodec",
            "hevc_mediacodec",
            "vp9_mediacodec",
            "av1_mediacodec",
        ];

        #[cfg(not(target_os = "android"))]
        let expected = ["libx264", "libx265", "libvpx-vp9", "libaom-av1"];

        let codecs = [
            VideoCodec::H264,
            VideoCodec::H265,
            VideoCodec::Vp9,
            VideoCodec::Av1,
        ];
        for (codec, expected_name) in codecs.into_iter().zip(expected) {
            assert_eq!(codec.ffmpeg_codec_name(), expected_name);
        }
    }

    /// Test RGBA → YUV420P conversion produces the expected buffer size
    #[test]
    fn test_rgba_to_yuv420p_size() {
        let width = 64u32;
        let height = 64u32;
        let rgba = vec![128u8; (width * height * 4) as usize];

        let yuv = convert_rgba_to_yuv420p(&rgba, width, height).unwrap();

        let expected_size = (width * height * 3 / 2) as usize;
        assert_eq!(yuv.len(), expected_size, "YUV420P size should be W*H*3/2");
    }

    /// Test that black RGBA pixels produce the expected YUV values
    #[test]
    fn test_rgba_to_yuv420p_black() {
        let width = 4u32;
        let height = 4u32;
        // RGBA black (0,0,0,255)
        let rgba: Vec<u8> = (0..width * height)
            .flat_map(|_| [0u8, 0u8, 0u8, 255u8])
            .collect();

        let yuv = convert_rgba_to_yuv420p(&rgba, width, height).unwrap();

        let y_size = (width * height) as usize;
        // Y for black should be 16 (BT.601 limited range)
        assert_eq!(yuv[0], 16, "Y for black should be 16 (limited range)");
        // Cb for black should be 128
        assert_eq!(yuv[y_size], 128, "Cb for black should be 128");
    }

    /// Test that white RGBA pixels produce the expected Y values
    #[test]
    fn test_rgba_to_yuv420p_white() {
        let width = 4u32;
        let height = 4u32;
        // RGBA white (255,255,255,255)
        let rgba: Vec<u8> = (0..width * height)
            .flat_map(|_| [255u8, 255u8, 255u8, 255u8])
            .collect();

        let yuv = convert_rgba_to_yuv420p(&rgba, width, height).unwrap();

        // Y for white should be 235 (BT.601 limited range)
        assert_eq!(yuv[0], 235, "Y for white should be 235 (limited range)");
    }

    /// Test that even-dimension requirement is enforced
    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_odd_dimensions_rejected() {
        let result = VideoEncoder::new(&ExportSettings {
            width: 191,
            height: 108,
            fps: 30.0,
            bitrate_kbps: 5000,
            codec: VideoCodec::H264,
            format: super::super::OutputFormat::Mp4,
            audio_bitrate_kbps: 128,
            audio_sample_rate: 44100,
            audio_channels: 2,
            include_audio: true,
            two_pass: false,
        });
        assert!(result.is_err(), "Odd dimensions should be rejected");
    }

    /// Test that zero dimensions are rejected
    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_zero_dimensions_rejected() {
        let result = VideoEncoder::new(&ExportSettings {
            width: 0,
            height: 1080,
            fps: 30.0,
            bitrate_kbps: 5000,
            codec: VideoCodec::H264,
            format: super::super::OutputFormat::Mp4,
            audio_bitrate_kbps: 128,
            audio_sample_rate: 44100,
            audio_channels: 2,
            include_audio: true,
            two_pass: false,
        });
        assert!(result.is_err(), "Zero width should be rejected");
    }

    /// Test estimate_remaining returns sensible values
    #[test]
    fn test_estimate_remaining() {
        let start = std::time::Instant::now() - std::time::Duration::from_secs(10);
        // 100 frames encoded in 10 seconds = 10 fps
        // 900 frames remaining → ~90 seconds
        let remaining = estimate_remaining(100, 1000, start);
        assert!(
            remaining > 80 && remaining < 100,
            "Expected ~90s, got {}",
            remaining
        );
    }

    /// Test estimate_remaining with zero frames returns 0
    #[test]
    fn test_estimate_remaining_zero_frames() {
        let start = std::time::Instant::now();
        assert_eq!(estimate_remaining(0, 1000, start), 0);
    }

    /// Test f32 → s16 conversion
    #[test]
    fn test_convert_f32_to_s16() {
        let samples = vec![-1.0f32, -0.5, 0.0, 0.5, 1.0];
        let s16 = convert_f32_to_s16(&samples);
        assert_eq!(s16[0], -32767, "f32 -1.0 → s16 -32767");
        assert_eq!(s16[2], 0, "f32 0.0 → s16 0");
        assert!(s16[4] > 32000, "f32 1.0 → s16 ~32767 (got {})", s16[4]);
    }

    /// Test f32 → s16 clamping
    #[test]
    fn test_convert_f32_to_s16_clamp() {
        let samples = vec![-2.0f32, 2.0];
        let s16 = convert_f32_to_s16(&samples);
        assert_eq!(s16[0], -32767, "f32 -2.0 clamped → s16 -32767");
        assert_eq!(s16[1], 32767, "f32 2.0 clamped → s16 32767");
    }

    /// Test AudioEncoder rejects invalid parameters
    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_audio_encoder_rejects_zero_sample_rate() {
        let result = AudioEncoder::new(0, 2, 128);
        assert!(result.is_err(), "Zero sample rate should be rejected");
    }

    /// Test AudioEncoder rejects zero channels
    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_audio_encoder_rejects_zero_channels() {
        let result = AudioEncoder::new(44100, 0, 128);
        assert!(result.is_err(), "Zero channels should be rejected");
    }

    /// Test AudioEncoder rejects zero bitrate
    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_audio_encoder_rejects_zero_bitrate() {
        let result = AudioEncoder::new(44100, 2, 0);
        assert!(result.is_err(), "Zero bitrate should be rejected");
    }

    /// Test AudioEncoder accepts valid parameters
    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_audio_encoder_accepts_valid_params() {
        let result = AudioEncoder::new(48000, 2, 192);
        assert!(result.is_ok(), "Valid params should be accepted");
        let enc = result.unwrap();
        assert_eq!(enc.sample_rate, 48000);
        assert_eq!(enc.channels, 2);
        assert_eq!(enc.bitrate_kbps, 192);
        assert_eq!(enc.frame_size, 1024);
    }

    /// Test MuxedEncoder rejects invalid video dimensions
    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_muxed_encoder_rejects_odd_dimensions() {
        let result = MuxedEncoder::new(&ExportSettings {
            width: 191,
            height: 108,
            fps: 30.0,
            bitrate_kbps: 5000,
            codec: VideoCodec::H264,
            format: super::super::OutputFormat::Mp4,
            audio_bitrate_kbps: 128,
            audio_sample_rate: 44100,
            audio_channels: 2,
            include_audio: true,
            two_pass: false,
        });
        assert!(result.is_err(), "Odd dimensions should be rejected");
    }
}

// ──────────────────────────────────────────────────────────────────
// Audio sample format conversion
// ──────────────────────────────────────────────────────────────────

/// Convert f32 interleaved audio samples to s16 (signed 16-bit) PCM format.
///
/// Each f32 sample in the range `[-1.0, 1.0]` is mapped to `[-32767, 32767]`.
/// Values outside `[-1.0, 1.0]` are clamped before conversion.
///
/// This is useful for interfacing with FFmpeg encoders or audio APIs
/// that expect integer PCM data.
pub fn convert_f32_to_s16(samples: &[f32]) -> Vec<i16> {
    samples
        .iter()
        .map(|&s| {
            let clamped = s.clamp(-1.0, 1.0);
            (clamped * 32767.0) as i16
        })
        .collect()
}

// ──────────────────────────────────────────────────────────────────
// AudioEncoder
// ──────────────────────────────────────────────────────────────────

/// FFmpeg-based AAC audio encoder that writes audio to an output context.
///
/// Works in conjunction with a [`MuxedEncoder`] which owns the shared
/// output context. The audio encoder manages its own stream, frame
/// buffering, and PTS tracking.
///
/// ## Audio pipeline
///
/// 1. Receive f32 interleaved PCM samples (stereo: `L R L R …`)
/// 2. Buffer samples until a full AAC frame (1024 samples/channel) is available
/// 3. Convert f32 interleaved → FLTP planar for the encoder
/// 4. Encode and write packets via `write_interleaved()`
///
/// ## PTS calculation
///
/// The audio stream uses a time base of `1/sample_rate`. For a frame
/// starting at sample index `N` (per channel), the PTS is simply `N`.
#[cfg(feature = "ffmpeg")]
pub struct AudioEncoder {
    encoder: Option<ffmpeg::encoder::Audio>,
    stream_index: Option<usize>,
    sample_rate: u32,
    channels: u32,
    bitrate_kbps: u32,
    time_base: ffmpeg::Rational,
    next_pts: i64,
    /// Buffer for partial audio frames (f32 interleaved).
    sample_buffer: Vec<f32>,
    /// Number of samples per channel per AAC frame (typically 1024).
    frame_size: usize,
}

#[cfg(feature = "ffmpeg")]
impl AudioEncoder {
    /// Create a new audio encoder with the specified parameters.
    ///
    /// The encoder is not yet connected to an output context; call
    /// [`add_stream()`](Self::add_stream) to attach it.
    pub fn new(sample_rate: u32, channels: u32, bitrate_kbps: u32) -> Result<Self, String> {
        if sample_rate == 0 {
            return Err("Sample rate must be non-zero".to_string());
        }
        if channels == 0 {
            return Err("Channels must be non-zero".to_string());
        }
        if bitrate_kbps == 0 {
            return Err("Audio bitrate must be non-zero".to_string());
        }

        Ok(Self {
            encoder: None,
            stream_index: None,
            sample_rate,
            channels,
            bitrate_kbps,
            time_base: ffmpeg::Rational::new(1, sample_rate as i32),
            next_pts: 0,
            sample_buffer: Vec::new(),
            frame_size: 1024, // AAC standard frame size
        })
    }

    /// Add an audio stream to the output context and configure the AAC encoder.
    ///
    /// This must be called **before** `write_header()` on the output context.
    /// After this call the encoder is ready to receive samples via
    /// [`encode_samples()`](Self::encode_samples).
    pub fn add_stream(&mut self, octx: &mut ffmpeg::format::context::Output) -> Result<(), String> {
        log::info!(
            "Opening audio encoder: {}Hz, {}ch, {}kbps, codec=aac",
            self.sample_rate,
            self.channels,
            self.bitrate_kbps,
        );

        // Find the AAC encoder
        let codec = ffmpeg::encoder::find_by_name("aac")
            .ok_or_else(|| "AAC encoder not found in FFmpeg".to_string())?;

        // Add audio stream
        let mut stream = octx
            .add_stream(codec)
            .map_err(|e| format!("Failed to add audio stream: {}", e))?;
        let stream_idx = stream.index();

        // Configure the audio encoder
        let mut encoder = ffmpeg::codec::context::Context::new_with_codec(codec)
            .encoder()
            .audio()
            .map_err(|e| format!("Failed to create audio encoder: {}", e))?;

        encoder.set_rate(self.sample_rate as i32);
        encoder.set_bit_rate(self.bitrate_kbps as usize * 1000);
        encoder.set_time_base(self.time_base);
        stream.set_time_base(self.time_base);

        // Set channel layout based on channel count
        let channel_layout = match self.channels {
            1 => ffmpeg::channel_layout::ChannelLayout::MONO,
            2 => ffmpeg::channel_layout::ChannelLayout::STEREO,
            _ => {
                return Err(format!(
                    "Unsupported channel count: {} (supported: 1, 2)",
                    self.channels
                ))
            }
        };
        encoder.set_channel_layout(channel_layout);

        // AAC encoder requires FLTP (float, planar) sample format
        encoder.set_format(ffmpeg::format::Sample::F32(
            ffmpeg::format::sample::Type::Planar,
        ));

        // Open the encoder
        encoder
            .open()
            .map_err(|e| format!("Failed to open AAC encoder: {}", e))?;

        // Update frame size from encoder (AAC is typically 1024)
        self.frame_size = if encoder.frame_size() > 0 {
            encoder.frame_size() as usize
        } else {
            1024
        };

        // Set stream parameters from encoder
        stream.set_parameters(&encoder);

        log::info!(
            "Audio encoder opened: stream={}, frame_size={}",
            stream_idx,
            self.frame_size,
        );

        self.encoder = Some(encoder);
        self.stream_index = Some(stream_idx);

        Ok(())
    }

    /// Encode f32 interleaved audio samples and write packets to the output.
    ///
    /// Samples are buffered internally until a full AAC frame is available.
    /// Partial frames are held until more data arrives or [`flush()`](Self::flush)
    /// is called.
    ///
    /// For stereo audio, the input layout is `L₀ R₀ L₁ R₁ …`.
    pub fn encode_samples(
        &mut self,
        octx: &mut ffmpeg::format::context::Output,
        samples: &[f32],
    ) -> Result<(), String> {
        let stream_index = self.stream_index.ok_or("Audio stream not configured")?;
        let encoder = self
            .encoder
            .as_mut()
            .ok_or("Audio encoder not configured")?;

        // Append new samples to buffer
        self.sample_buffer.extend_from_slice(samples);

        // Encode full frames from the buffer
        let samples_per_frame = self.frame_size * self.channels as usize;

        while self.sample_buffer.len() >= samples_per_frame {
            let frame_data: Vec<f32> = self.sample_buffer.drain(..samples_per_frame).collect();
            let frame = self.build_audio_frame(&frame_data)?;

            encoder
                .send_frame(&frame)
                .map_err(|e| format!("Audio send frame error: {}", e))?;

            Self::receive_and_write_packets(stream_index, octx, encoder)?;

            self.next_pts += self.frame_size as i64;
        }

        Ok(())
    }

    /// Flush any remaining buffered samples and the encoder.
    ///
    /// Call this before writing the trailer. Pads the final partial
    /// frame with silence if needed.
    pub fn flush(&mut self, octx: &mut ffmpeg::format::context::Output) -> Result<(), String> {
        let stream_index = self.stream_index.ok_or("Audio stream not configured")?;
        let encoder = self
            .encoder
            .as_mut()
            .ok_or("Audio encoder not configured")?;

        // Encode any remaining partial frame (padded with silence)
        let samples_per_frame = self.frame_size * self.channels as usize;
        if !self.sample_buffer.is_empty() {
            let mut padded = self.sample_buffer.clone();
            padded.resize(samples_per_frame, 0.0f32);
            self.sample_buffer.clear();

            let frame = self.build_audio_frame(&padded)?;
            encoder
                .send_frame(&frame)
                .map_err(|e| format!("Audio send frame error during flush: {}", e))?;

            Self::receive_and_write_packets(stream_index, octx, encoder)?;
        }

        // Send EOF to flush the encoder
        let _ = encoder.send_eof();
        Self::receive_and_write_packets(stream_index, octx, encoder)?;

        Ok(())
    }

    /// Get the stream index for this audio encoder.
    pub fn stream_index(&self) -> Option<usize> {
        self.stream_index
    }

    /// Get the configured sample rate.
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    /// Get the configured channel count.
    pub fn channels(&self) -> u32 {
        self.channels
    }

    /// Get the configured bitrate in kbps.
    pub fn bitrate_kbps(&self) -> u32 {
        self.bitrate_kbps
    }

    /// Get the number of samples buffered but not yet encoded.
    pub fn buffered_sample_count(&self) -> usize {
        self.sample_buffer.len()
    }

    /// Build an FLTP planar audio frame from f32 interleaved samples.
    ///
    /// Converts `[L₀, R₀, L₁, R₁, …]` → `plane₀ = [L₀, L₁, …]`,
    /// `plane₁ = [R₀, R₁, …]`.
    fn build_audio_frame(&self, interleaved: &[f32]) -> Result<ffmpeg::frame::Audio, String> {
        let channel_layout = match self.channels {
            1 => ffmpeg::channel_layout::ChannelLayout::MONO,
            2 => ffmpeg::channel_layout::ChannelLayout::STEREO,
            _ => return Err(format!("Unsupported channel count: {}", self.channels)),
        };

        let mut frame = ffmpeg::frame::Audio::new(
            ffmpeg::format::Sample::F32(ffmpeg::format::sample::Type::Planar),
            self.frame_size,
            channel_layout,
        );

        frame.set_pts(Some(self.next_pts));

        // Deinterleave: [L0, R0, L1, R1, ...] → plane 0 [L0, L1, ...], plane 1 [R0, R1, ...]
        let channels = self.channels as usize;
        for ch in 0..channels {
            let dst = frame.data_mut(ch);
            let plane: Vec<f32> = (0..self.frame_size)
                .map(|i| {
                    let idx = i * channels + ch;
                    if idx < interleaved.len() {
                        interleaved[idx]
                    } else {
                        0.0
                    }
                })
                .collect();

            let src_bytes = unsafe {
                std::slice::from_raw_parts(
                    plane.as_ptr() as *const u8,
                    plane.len() * std::mem::size_of::<f32>(),
                )
            };

            let copy_len = src_bytes.len().min(dst.len());
            dst[..copy_len].copy_from_slice(&src_bytes[..copy_len]);
        }

        Ok(frame)
    }

    /// Receive encoded audio packets and write them interleaved to the output.
    fn receive_and_write_packets(
        stream_index: usize,
        octx: &mut ffmpeg::format::context::Output,
        encoder: &mut ffmpeg::encoder::Audio,
    ) -> Result<(), String> {
        let output_time_base = octx
            .stream(stream_index)
            .ok_or("Output audio stream not found")?
            .time_base();
        let encoder_time_base = encoder.time_base();
        let mut packet = ffmpeg::Packet::new();
        while encoder.receive_packet(&mut packet).is_ok() {
            packet.set_stream(stream_index);
            packet.rescale_ts(encoder_time_base, output_time_base);
            packet
                .write_interleaved(octx)
                .map_err(|e| format!("Audio write packet error: {}", e))?;
        }
        Ok(())
    }
}

// ──────────────────────────────────────────────────────────────────
// MuxedEncoder
// ──────────────────────────────────────────────────────────────────

/// Combined video + audio encoder that muxes both streams into a single output file.
///
/// This is the recommended way to export video with audio. It manages
/// both a video encoder (H.264/H.265/VP9) and an audio encoder (AAC)
/// in the same FFmpeg output context, properly interleaving packets
/// for correct playback.
///
/// ## Usage
///
/// ```rust
/// let mut encoder = MuxedEncoder::new(&settings)?;
/// encoder.open(output_path)?;
///
/// // Encode video frames
/// encoder.encode_video_frame(rgba_data, pts)?;
///
/// // Encode audio samples (f32 interleaved)
/// encoder.encode_audio_samples(&audio_samples)?;
///
/// let result = encoder.finish(duration_ms)?;
/// ```
///
/// ## PTS synchronization
///
/// Video PTS uses time base `1/fps` (PTS = frame number).
/// Audio PTS uses time base `1/sample_rate` (PTS = sample index per channel).
/// Both are automatically rescaled by FFmpeg's muxer when writing interleaved
/// packets, ensuring correct A/V sync.
#[cfg(feature = "ffmpeg")]
pub struct MuxedEncoder {
    settings: ExportSettings,
    output_context: Option<ffmpeg::format::context::Output>,
    output_path: Option<String>,
    video_encoder: Option<ffmpeg::encoder::Video>,
    video_stream_index: Option<usize>,
    audio_encoder: AudioEncoder,
    frame_count: u64,
    start_time: std::time::Instant,
}

#[cfg(feature = "ffmpeg")]
impl MuxedEncoder {
    /// Create a new muxed encoder with the given export settings.
    ///
    /// If `settings.include_audio` is true, an AAC audio stream will be
    /// added when [`open()`](Self::open) is called.
    pub fn new(settings: &ExportSettings) -> Result<Self, String> {
        // Validate video settings
        if settings.width == 0 || settings.height == 0 {
            return Err("Width and height must be non-zero".to_string());
        }
        if settings.width % 2 != 0 || settings.height % 2 != 0 {
            return Err(format!(
                "Dimensions must be even (got {}x{})",
                settings.width, settings.height
            ));
        }
        if settings.fps <= 0.0 {
            return Err("FPS must be positive".to_string());
        }
        if settings.bitrate_kbps == 0 {
            return Err("Video bitrate must be non-zero".to_string());
        }

        // Create audio encoder (always created; only activated if include_audio is true)
        let audio_encoder = if settings.include_audio {
            AudioEncoder::new(
                settings.audio_sample_rate,
                settings.audio_channels,
                settings.audio_bitrate_kbps,
            )?
        } else {
            // Create a placeholder that won't be used
            AudioEncoder::new(44100, 2, 128)?
        };

        Ok(Self {
            settings: settings.clone(),
            output_context: None,
            output_path: None,
            video_encoder: None,
            video_stream_index: None,
            audio_encoder,
            frame_count: 0,
            start_time: std::time::Instant::now(),
        })
    }

    /// Open the output file and configure both video and audio encoders.
    ///
    /// Sets up the output context, adds video and (optionally) audio streams,
    /// configures codecs, and writes the file header.
    pub fn open(&mut self, output_path: &str) -> Result<(), String> {
        log::info!(
            "Opening muxed encoder: {}x{} @ {}fps, {}kbps, codec={:?}, audio={}ch@{}Hz/{}kbps",
            self.settings.width,
            self.settings.height,
            self.settings.fps,
            self.settings.bitrate_kbps,
            self.settings.codec,
            self.settings.audio_channels,
            self.settings.audio_sample_rate,
            self.settings.audio_bitrate_kbps,
        );

        // 1. Create output format context
        let mut octx = ffmpeg::format::output(&output_path).map_err(|e| {
            format!(
                "Failed to create output context for '{}': {}",
                output_path, e
            )
        })?;

        // 2. Add video stream
        let codec_name = self.settings.codec.ffmpeg_codec_name();
        let video_codec = ffmpeg::encoder::find_by_name(codec_name)
            .ok_or_else(|| format!("Video codec '{}' not found in FFmpeg", codec_name))?;

        let mut video_stream = octx
            .add_stream(video_codec)
            .map_err(|e| format!("Failed to add video stream: {}", e))?;
        let video_stream_idx = video_stream.index();

        let mut video_encoder = ffmpeg::codec::context::Context::new_with_codec(video_codec)
            .encoder()
            .video()
            .map_err(|e| format!("Failed to create video encoder: {}", e))?;

        video_encoder.set_width(self.settings.width);
        video_encoder.set_height(self.settings.height);
        video_encoder.set_frame_rate(Some(ffmpeg::Rational::new(self.settings.fps as i32, 1)));
        video_encoder.set_bit_rate(self.settings.bitrate_kbps as usize * 1000);
        video_encoder.set_format(ffmpeg::format::Pixel::YUV420P);
        let video_time_base = ffmpeg::Rational::new(1, self.settings.fps as i32);
        video_encoder.set_time_base(video_time_base);
        video_stream.set_time_base(video_time_base);

        // Codec-specific options for video
        match self.settings.codec {
            VideoCodec::H264 => {
                #[cfg(target_os = "android")]
                video_encoder
                    .open()
                    .map_err(|e| format!("Failed to open Android H.264 encoder: {}", e))?;

                #[cfg(not(target_os = "android"))]
                {
                    let mut opts = ffmpeg::Dictionary::new();
                    let _ = opts.set("preset", "medium");
                    let _ = opts.set("crf", "23");
                    video_encoder
                        .open_with(opts)
                        .map_err(|e| format!("Failed to open H.264 encoder: {}", e))?;
                }
            }
            VideoCodec::H265 => {
                #[cfg(target_os = "android")]
                video_encoder
                    .open()
                    .map_err(|e| format!("Failed to open Android H.265 encoder: {}", e))?;

                #[cfg(not(target_os = "android"))]
                {
                    let mut opts = ffmpeg::Dictionary::new();
                    let _ = opts.set("preset", "medium");
                    let _ = opts.set("crf", "28");
                    video_encoder
                        .open_with(opts)
                        .map_err(|e| format!("Failed to open H.265 encoder: {}", e))?;
                }
            }
            _ => {
                video_encoder
                    .open()
                    .map_err(|e| format!("Failed to open video encoder: {}", e))?;
            }
        }

        video_stream.set_parameters(&video_encoder);

        // 3. Add audio stream (if enabled)
        if self.settings.include_audio {
            self.audio_encoder.add_stream(&mut octx)?;
        }

        // 4. Write header
        octx.write_header()
            .map_err(|e| format!("Failed to write header: {}", e))?;

        log::info!("Muxed encoder opened successfully: {}", output_path);

        self.output_context = Some(octx);
        self.output_path = Some(output_path.to_string());
        self.video_encoder = Some(video_encoder);
        self.video_stream_index = Some(video_stream_idx);
        self.start_time = std::time::Instant::now();
        self.frame_count = 0;

        Ok(())
    }

    /// Encode a single RGBA video frame and write it to the output.
    ///
    /// The `pts` (presentation timestamp) should be the frame number,
    /// starting from 0. Packets are written interleaved so that video
    /// and audio stay in sync in the output container.
    pub fn encode_video_frame(&mut self, rgba_data: &[u8], pts: i64) -> Result<(), String> {
        let stream_index = self
            .video_stream_index
            .ok_or("Video stream not configured")?;
        let octx = self
            .output_context
            .as_mut()
            .ok_or("Muxed encoder not opened")?;
        let video_encoder = self
            .video_encoder
            .as_mut()
            .ok_or("Video encoder not configured")?;

        // Convert RGBA → YUV420P
        let yuv_data =
            convert_rgba_to_yuv420p(rgba_data, self.settings.width, self.settings.height)?;

        // Build ffmpeg frame
        let frame = build_yuv420p_frame(&yuv_data, self.settings.width, self.settings.height, pts)?;

        // Send frame to encoder
        video_encoder
            .send_frame(&frame)
            .map_err(|e| format!("Video send frame error: {}", e))?;

        // Receive and write encoded packets (interleaved with audio)
        let output_time_base = octx
            .stream(stream_index)
            .ok_or("Output video stream not found")?
            .time_base();
        let encoder_time_base = video_encoder.time_base();
        let mut packet = ffmpeg::Packet::new();
        while video_encoder.receive_packet(&mut packet).is_ok() {
            packet.set_stream(stream_index);
            packet.rescale_ts(encoder_time_base, output_time_base);
            packet
                .write_interleaved(octx)
                .map_err(|e| format!("Video write packet error: {}", e))?;
        }

        self.frame_count += 1;
        Ok(())
    }

    /// Encode a single YUV420P video frame and write it to the output.
    pub fn encode_yuv420p_video_frame(&mut self, yuv_data: &[u8], pts: i64) -> Result<(), String> {
        let stream_index = self
            .video_stream_index
            .ok_or("Video stream not configured")?;
        let octx = self
            .output_context
            .as_mut()
            .ok_or("Muxed encoder not opened")?;
        let video_encoder = self
            .video_encoder
            .as_mut()
            .ok_or("Video encoder not configured")?;

        let frame = build_yuv420p_frame(yuv_data, self.settings.width, self.settings.height, pts)?;

        video_encoder
            .send_frame(&frame)
            .map_err(|e| format!("Video send frame error: {}", e))?;

        let output_time_base = octx
            .stream(stream_index)
            .ok_or("Output video stream not found")?
            .time_base();
        let encoder_time_base = video_encoder.time_base();
        let mut packet = ffmpeg::Packet::new();
        while video_encoder.receive_packet(&mut packet).is_ok() {
            packet.set_stream(stream_index);
            packet.rescale_ts(encoder_time_base, output_time_base);
            packet
                .write_interleaved(octx)
                .map_err(|e| format!("Video write packet error: {}", e))?;
        }

        self.frame_count += 1;
        Ok(())
    }

    /// Encode f32 interleaved audio samples and write them to the output.
    ///
    /// If audio is not enabled in the settings, this is a no-op.
    /// For stereo audio, the input layout is `L₀ R₀ L₁ R₁ …`.
    pub fn encode_audio_samples(&mut self, samples: &[f32]) -> Result<(), String> {
        if !self.settings.include_audio {
            return Ok(()); // Audio disabled, silently skip
        }

        let octx = self
            .output_context
            .as_mut()
            .ok_or("Muxed encoder not opened")?;

        self.audio_encoder.encode_samples(octx, samples)
    }

    /// Flush both encoders and write the trailer, returning the export result.
    ///
    /// This consumes the encoder. After calling this, the encoder cannot
    /// be reused.
    pub fn finish(mut self, duration_ms: u64) -> Result<ExportResult, String> {
        let output_path = self
            .output_path
            .clone()
            .ok_or("Output path not configured")?;
        let video_stream_index = self
            .video_stream_index
            .ok_or("Video stream not configured")?;
        let octx = self
            .output_context
            .as_mut()
            .ok_or("Muxed encoder not opened")?;

        // Flush video encoder
        if let Some(video_encoder) = self.video_encoder.as_mut() {
            let _ = video_encoder.send_eof();
            let output_time_base = octx
                .stream(video_stream_index)
                .ok_or("Output video stream not found")?
                .time_base();
            let encoder_time_base = video_encoder.time_base();
            let mut packet = ffmpeg::Packet::new();
            while video_encoder.receive_packet(&mut packet).is_ok() {
                packet.set_stream(video_stream_index);
                packet.rescale_ts(encoder_time_base, output_time_base);
                packet
                    .write_interleaved(octx)
                    .map_err(|e| format!("Video flush write error: {}", e))?;
            }
        }

        // Flush audio encoder
        if self.settings.include_audio {
            self.audio_encoder.flush(octx)?;
        }

        // Write trailer
        octx.write_trailer()
            .map_err(|e| format!("Failed to write trailer: {}", e))?;

        // Get output file size
        let file_size = std::fs::metadata(&output_path)
            .map(|m| m.len())
            .unwrap_or(0);

        let elapsed = self.start_time.elapsed();
        log::info!(
            "Muxed export complete: {} frames, {}ms → {}bytes, took {:.1}s",
            self.frame_count,
            duration_ms,
            file_size,
            elapsed.as_secs_f64()
        );

        Ok(ExportResult {
            success: true,
            output_path,
            file_size_bytes: file_size,
            duration_ms,
            error_message: None,
        })
    }

    /// Cancel the export and clean up the output file.
    pub fn cancel(self) {
        if let Some(octx) = self.output_context {
            let path = self.output_path.unwrap_or_default();
            drop(octx);
            let _ = std::fs::remove_file(&path);
            log::info!("Muxed export cancelled, partial file removed: {}", path);
        }
    }

    /// Get the number of video frames encoded so far.
    pub fn frame_count(&self) -> u64 {
        self.frame_count
    }

    /// Get the elapsed time since the encoder was opened.
    pub fn elapsed(&self) -> std::time::Duration {
        self.start_time.elapsed()
    }

    /// Check if audio encoding is enabled.
    pub fn has_audio(&self) -> bool {
        self.settings.include_audio
    }

    /// Get the audio encoder's buffered sample count.
    ///
    /// Useful for checking how many audio samples are waiting to be
    /// encoded into full AAC frames.
    pub fn audio_buffered_samples(&self) -> usize {
        self.audio_encoder.buffered_sample_count()
    }
}

// ─── Stub implementations when FFmpeg is not available ──────────────────────────

#[cfg(not(feature = "ffmpeg"))]
pub struct VideoEncoder;

#[cfg(not(feature = "ffmpeg"))]
impl VideoEncoder {
    pub fn new(_settings: &ExportSettings) -> Result<Self, String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn open(&mut self, _output_path: &str) -> Result<(), String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn open_with_audio(self, _output_path: &str) -> Result<MuxedEncoder, String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn encode_rgba_frame(&mut self, _rgba_data: &[u8], _pts: i64) -> Result<(), String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn encode_yuv420p_frame(&mut self, _yuv_data: &[u8], _pts: i64) -> Result<(), String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn finish(self, _duration_ms: u64) -> Result<ExportResult, String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn cancel(self) {}

    pub fn frame_count(&self) -> u64 {
        0
    }

    pub fn elapsed(&self) -> std::time::Duration {
        std::time::Duration::ZERO
    }
}

#[cfg(not(feature = "ffmpeg"))]
pub struct AudioEncoder;

#[cfg(not(feature = "ffmpeg"))]
impl AudioEncoder {
    pub fn new(_sample_rate: u32, _channels: u32, _bitrate_kbps: u32) -> Result<Self, String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn stream_index(&self) -> Option<usize> {
        None
    }

    pub fn sample_rate(&self) -> u32 {
        0
    }

    pub fn channels(&self) -> u32 {
        0
    }

    pub fn bitrate_kbps(&self) -> u32 {
        0
    }

    pub fn buffered_sample_count(&self) -> usize {
        0
    }
}

#[cfg(not(feature = "ffmpeg"))]
pub struct MuxedEncoder;

#[cfg(not(feature = "ffmpeg"))]
impl MuxedEncoder {
    pub fn new(_settings: &ExportSettings) -> Result<Self, String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn open(&mut self, _output_path: &str) -> Result<(), String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn encode_video_frame(&mut self, _rgba_data: &[u8], _pts: i64) -> Result<(), String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn encode_yuv420p_video_frame(
        &mut self,
        _yuv_data: &[u8],
        _pts: i64,
    ) -> Result<(), String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn encode_audio_samples(&mut self, _samples: &[f32]) -> Result<(), String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn finish(self, _duration_ms: u64) -> Result<ExportResult, String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn cancel(self) {}

    pub fn frame_count(&self) -> u64 {
        0
    }

    pub fn elapsed(&self) -> std::time::Duration {
        std::time::Duration::ZERO
    }

    pub fn has_audio(&self) -> bool {
        false
    }

    pub fn audio_buffered_samples(&self) -> usize {
        0
    }
}
