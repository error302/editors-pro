//! Proxy generator using FFmpeg
//!
//! Generates lower-resolution copies of video files for smooth editing.
//! Uses FFmpeg for re-encoding at the target proxy resolution.

use std::path::Path;

use super::{ProxyMetadata, ProxyQuality};

/// Generate a proxy for the given video file.
///
/// Steps:
/// 1. Open the source video with FFmpeg
/// 2. Scale down to target resolution (maintaining aspect ratio)
/// 3. Encode with H.264 at moderate bitrate (suitable for preview)
/// 4. Save to cache directory
/// 5. Return metadata
///
/// # Arguments
/// * `source_path` - Path to the source video file
/// * `asset_id` - Unique identifier for the asset
/// * `quality` - Target proxy quality level
/// * `cache_dir` - Directory to store the proxy file
///
/// # Errors
/// Returns an error string if:
/// - The source file doesn't exist or can't be opened
/// - FFmpeg fails to initialize or encode
/// - The cache directory can't be created
#[cfg(feature = "ffmpeg")]
pub fn generate_proxy(
    source_path: &str,
    asset_id: &str,
    quality: ProxyQuality,
    cache_dir: &str,
) -> Result<ProxyMetadata, String> {
    if quality == ProxyQuality::Off {
        return Err("Proxy generation is disabled (quality is Off)".to_string());
    }

    if !Path::new(source_path).exists() {
        return Err(format!("Source file not found: {}", source_path));
    }

    // Ensure cache directory exists
    let proxy_dir = Path::new(cache_dir).join("proxies");
    std::fs::create_dir_all(&proxy_dir)
        .map_err(|e| format!("Failed to create proxy cache directory: {}", e))?;

    let proxy_filename = format!("{}_proxy.mp4", sanitize_filename(asset_id));
    let proxy_path = proxy_dir.join(&proxy_filename);
    let proxy_path_str = proxy_path.to_string_lossy().to_string();

    // Get source video info using FFmpeg
    let (original_width, original_height) = get_video_dimensions(source_path)?;

    // Calculate proxy dimensions maintaining aspect ratio
    let (proxy_width, proxy_height) =
        calculate_proxy_dimensions(original_width, original_height, quality);

    // Use FFmpeg CLI for transcoding (via command invocation for reliability)
    let bitrate = proxy_bitrate(quality);
    let output = transcode_with_ffmpeg(
        source_path,
        &proxy_path_str,
        proxy_width,
        proxy_height,
        bitrate,
    )?;

    // Get the file size
    let file_size = std::fs::metadata(&proxy_path).map(|m| m.len()).unwrap_or(0);

    let generated_at = chrono::Utc::now().timestamp();

    Ok(ProxyMetadata {
        original_asset_id: asset_id.to_string(),
        original_path: source_path.to_string(),
        proxy_path: proxy_path_str,
        quality,
        original_width,
        original_height,
        proxy_width,
        proxy_height,
        generated_at,
        file_size_bytes: file_size,
    })
}

/// Get video dimensions using FFmpeg.
#[cfg(feature = "ffmpeg")]
fn get_video_dimensions(source_path: &str) -> Result<(u32, u32), String> {
    use ffmpeg_next as ffmpeg;

    ffmpeg::init().map_err(|e| format!("FFmpeg init failed: {}", e))?;

    let input = ffmpeg::format::input(source_path)
        .map_err(|e| format!("Failed to open source video: {}", e))?;

    let video_stream = input
        .streams()
        .best(ffmpeg::media::Type::Video)
        .ok_or("No video stream found in source file")?;

    let codec_context = ffmpeg::codec::context::Context::from_parameters(video_stream.parameters())
        .map_err(|e| format!("Failed to read video parameters: {}", e))?;
    let decoder = codec_context
        .decoder()
        .video()
        .map_err(|e| format!("Failed to open video decoder: {}", e))?;
    let width = decoder.width();
    let height = decoder.height();

    if width == 0 || height == 0 {
        return Err("Invalid video dimensions (0x0)".to_string());
    }

    Ok((width, height))
}

/// Calculate proxy dimensions maintaining the source aspect ratio.
///
/// Ensures both dimensions are even (required by H.264 encoding).
fn calculate_proxy_dimensions(
    source_width: u32,
    source_height: u32,
    quality: ProxyQuality,
) -> (u32, u32) {
    let target_width = quality.target_width();
    let target_height = quality.target_height();

    // Only downscale, never upscale
    if source_width <= target_width && source_height <= target_height {
        return (make_even(source_width), make_even(source_height));
    }

    let aspect_ratio = source_width as f32 / source_height as f32;

    let (proxy_width, proxy_height) = if aspect_ratio >= 1.0 {
        // Landscape: fit to target width
        let w = target_width;
        let h = (w as f32 / aspect_ratio).round() as u32;
        (w, h)
    } else {
        // Portrait: fit to target height
        let h = target_height;
        let w = (h as f32 * aspect_ratio).round() as u32;
        (w, h)
    };

    (make_even(proxy_width), make_even(proxy_height))
}

/// Ensure a dimension is even (required by H.264).
fn make_even(n: u32) -> u32 {
    if n % 2 == 0 {
        n
    } else {
        n - 1
    }
}

/// Get the target bitrate for a proxy quality level (in kbps).
fn proxy_bitrate(quality: ProxyQuality) -> u64 {
    match quality {
        ProxyQuality::P360 => 800,
        ProxyQuality::P480 => 1500,
        ProxyQuality::P720 => 2500,
        ProxyQuality::Off => 0,
    }
}

/// Transcode a video file using FFmpeg's Rust bindings.
///
/// Re-encodes the source video at the specified resolution and bitrate
/// using the ultrafast H.264 preset for maximum encoding speed.
#[cfg(feature = "ffmpeg")]
fn transcode_with_ffmpeg(
    source_path: &str,
    output_path: &str,
    width: u32,
    height: u32,
    bitrate_kbps: u64,
) -> Result<(), String> {
    use ffmpeg_next as ffmpeg;

    ffmpeg::init().map_err(|e| format!("FFmpeg init failed: {}", e))?;

    // Open input
    let mut input =
        ffmpeg::format::input(source_path).map_err(|e| format!("Failed to open input: {}", e))?;

    let (video_stream_index, frame_rate, mut decoder) = {
        let input_video_stream = input
            .streams()
            .best(ffmpeg::media::Type::Video)
            .ok_or("No video stream found")?;
        let frame_rate = input_video_stream.avg_frame_rate();
        let video_stream_index = input_video_stream.index();
        let codec_context =
            ffmpeg::codec::context::Context::from_parameters(input_video_stream.parameters())
                .map_err(|e| format!("Failed to read input video parameters: {}", e))?;
        let decoder = codec_context
            .decoder()
            .video()
            .map_err(|e| format!("Failed to create decoder: {}", e))?;
        (video_stream_index, frame_rate, decoder)
    };

    // Create output context
    let mut output = ffmpeg::format::output(output_path)
        .map_err(|e| format!("Failed to create output: {}", e))?;

    // Find the H.264 encoder
    let codec =
        ffmpeg::encoder::find(ffmpeg_next::codec::Id::H264).ok_or("H.264 encoder not found")?;

    // Create output video stream
    let mut output_video_stream = output
        .add_stream(codec)
        .map_err(|e| format!("Failed to add output stream: {}", e))?;

    // Configure the encoder
    let mut encoder_ctx = ffmpeg::codec::context::Context::new_with_codec(codec)
        .encoder()
        .video()
        .map_err(|e| format!("Failed to create video encoder: {}", e))?;

    encoder_ctx.set_width(width);
    encoder_ctx.set_height(height);
    encoder_ctx.set_bit_rate((bitrate_kbps * 1000) as usize);
    let frame_rate = if frame_rate.numerator() > 0 && frame_rate.denominator() > 0 {
        frame_rate
    } else {
        ffmpeg::Rational::new(30, 1)
    };
    let encoder_time_base = ffmpeg::Rational::new(frame_rate.denominator(), frame_rate.numerator());
    encoder_ctx.set_frame_rate(Some(frame_rate));
    encoder_ctx.set_time_base(encoder_time_base);
    encoder_ctx.set_format(ffmpeg_next::format::Pixel::YUV420P);

    // Apply preset via codec options
    let mut codec_opts = ffmpeg::Dictionary::new();
    codec_opts.set("preset", "ultrafast");
    codec_opts.set("crf", "23");

    // Open the encoder
    let encoder = encoder_ctx
        .open_with(codec_opts)
        .map_err(|e| format!("Failed to open encoder: {}", e))?;

    output_video_stream.set_time_base(encoder_time_base);
    output_video_stream.set_parameters(&encoder);

    // Write output header
    output
        .write_header()
        .map_err(|e| format!("Failed to write header: {}", e))?;

    // Create decoder for input
    // Create scaler to resize frames
    let mut scaler = ffmpeg::software::scaling::context::Context::get(
        decoder.format(),
        decoder.width(),
        decoder.height(),
        ffmpeg_next::format::Pixel::Yuv420p,
        width,
        height,
        ffmpeg::software::scaling::Flags::BILINEAR,
    )
    .map_err(|e| format!("Failed to create scaler: {}", e))?;

    // Process frames
    let mut frame_index: i64 = 0;
    let mut receive_and_send = |decoder: &mut ffmpeg::decoder::Video,
                                scaler: &mut ffmpeg::software::scaling::Context::Context,
                                encoder: &mut ffmpeg::encoder::Video,
                                output: &mut ffmpeg::format::context::Output|
     -> Result<(), String> {
        let mut decoded = ffmpeg::util::frame::Video::empty();
        while decoder.receive_frame(&mut decoded).is_ok() {
            let mut scaled = ffmpeg::util::frame::Video::empty();
            scaler
                .run(&decoded, &mut scaled)
                .map_err(|e| format!("Scaling failed: {}", e))?;
            scaled.set_pts(Some(frame_index));
            frame_index += 1;
            encoder
                .send_frame(&scaled)
                .map_err(|e| format!("Send frame failed: {}", e))?;

            let mut encoded = ffmpeg::Packet::empty();
            while encoder.receive_packet(&mut encoded).is_ok() {
                encoded.set_stream(0);
                encoded.rescale_ts(decoder.time_base(), output.stream(0).unwrap().time_base());
                encoded
                    .write_interleaved(output)
                    .map_err(|e| format!("Write packet failed: {}", e))?;
            }
        }
        Ok(())
    };

    // Send packets to decoder
    for (stream, packet) in input.packets() {
        if stream.index() == video_stream_index {
            decoder
                .send_packet(&packet)
                .map_err(|e| format!("Send packet failed: {}", e))?;
            receive_and_send(&mut decoder, &mut scaler, &mut encoder, &mut output)?;
        }
    }

    // Flush decoder
    decoder
        .send_eof()
        .map_err(|e| format!("Send EOF failed: {}", e))?;
    receive_and_send(&mut decoder, &mut scaler, &mut encoder, &mut output)?;

    // Flush encoder
    encoder
        .send_eof()
        .map_err(|e| format!("Encoder EOF failed: {}", e))?;
    let mut encoded = ffmpeg::Packet::empty();
    while encoder.receive_packet(&mut encoded).is_ok() {
        encoded.set_stream(0);
        encoded.rescale_ts(decoder.time_base(), output.stream(0).unwrap().time_base());
        encoded
            .write_interleaved(&mut output)
            .map_err(|e| format!("Write packet failed: {}", e))?;
    }

    // Write trailer
    output
        .write_trailer()
        .map_err(|e| format!("Failed to write trailer: {}", e))?;

    Ok(())
}

/// Delete a proxy file and its metadata.
///
/// Removes the proxy file from disk. Returns an error if the file
/// exists but cannot be deleted.
pub fn delete_proxy(proxy_path: &str) -> Result<(), String> {
    let path = Path::new(proxy_path);
    if path.exists() {
        std::fs::remove_file(path).map_err(|e| format!("Failed to delete proxy file: {}", e))?;
        log::info!("Deleted proxy file: {}", proxy_path);
    } else {
        log::warn!("Proxy file not found for deletion: {}", proxy_path);
    }
    Ok(())
}

/// Get the total size of all proxy files in the cache directory.
///
/// Scans the `proxies/` subdirectory of `cache_dir` and sums
/// the file sizes of all `.mp4` files.
pub fn get_total_proxy_cache_size(cache_dir: &str) -> Result<u64, String> {
    let proxy_dir = Path::new(cache_dir).join("proxies");
    if !proxy_dir.exists() {
        return Ok(0);
    }

    let mut total_size: u64 = 0;
    let entries = std::fs::read_dir(&proxy_dir)
        .map_err(|e| format!("Failed to read proxy directory: {}", e))?;

    for entry in entries {
        let entry = entry.map_err(|e| format!("Failed to read directory entry: {}", e))?;
        if let Ok(metadata) = entry.metadata() {
            if metadata.is_file() {
                total_size += metadata.len();
            }
        }
    }

    Ok(total_size)
}

/// Clear all proxy files from the cache directory.
///
/// Deletes all files in the `proxies/` subdirectory of `cache_dir`.
/// Returns the total bytes freed.
pub fn clear_proxy_cache(cache_dir: &str) -> Result<u64, String> {
    let proxy_dir = Path::new(cache_dir).join("proxies");
    if !proxy_dir.exists() {
        return Ok(0);
    }

    let mut bytes_freed: u64 = 0;
    let entries = std::fs::read_dir(&proxy_dir)
        .map_err(|e| format!("Failed to read proxy directory: {}", e))?;

    for entry in entries {
        let entry = entry.map_err(|e| format!("Failed to read directory entry: {}", e))?;
        if let Ok(metadata) = entry.metadata() {
            if metadata.is_file() {
                bytes_freed += metadata.len();
                std::fs::remove_file(entry.path())
                    .map_err(|e| format!("Failed to delete proxy file: {}", e))?;
            }
        }
    }

    log::info!("Cleared proxy cache: {} bytes freed", bytes_freed);
    Ok(bytes_freed)
}

/// Sanitize a filename by replacing non-alphanumeric characters.
fn sanitize_filename(s: &str) -> String {
    s.chars()
        .map(|c| {
            if c.is_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect()
}

// ─── Stub implementation when FFmpeg is not available ──────────────────────────

#[cfg(not(feature = "ffmpeg"))]
pub fn generate_proxy(
    _source_path: &str,
    _asset_id: &str,
    _quality: ProxyQuality,
    _cache_dir: &str,
) -> Result<ProxyMetadata, String> {
    Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculate_proxy_dimensions_landscape() {
        // 4K landscape → 480p
        let (w, h) = calculate_proxy_dimensions(3840, 2160, ProxyQuality::P480);
        assert_eq!(w, 854);
        assert!(h > 0 && h <= 480);
        assert_eq!(w % 2, 0, "Width should be even");
        assert_eq!(h % 2, 0, "Height should be even");
    }

    #[test]
    fn test_calculate_proxy_dimensions_portrait() {
        // Portrait video → 480p
        let (w, h) = calculate_proxy_dimensions(1080, 1920, ProxyQuality::P480);
        assert!(w > 0 && w <= 854);
        assert_eq!(h, 480);
        assert_eq!(w % 2, 0, "Width should be even");
        assert_eq!(h % 2, 0, "Height should be even");
    }

    #[test]
    fn test_calculate_proxy_dimensions_no_upscale() {
        // Already small video → should not upscale
        let (w, h) = calculate_proxy_dimensions(640, 480, ProxyQuality::P480);
        assert_eq!(w, 640);
        assert_eq!(h, 480);
    }

    #[test]
    fn test_make_even() {
        assert_eq!(make_even(100), 100);
        assert_eq!(make_even(101), 100);
        assert_eq!(make_even(1), 0);
        assert_eq!(make_even(2), 2);
    }

    #[test]
    fn test_proxy_bitrate() {
        assert_eq!(proxy_bitrate(ProxyQuality::P360), 800);
        assert_eq!(proxy_bitrate(ProxyQuality::P480), 1500);
        assert_eq!(proxy_bitrate(ProxyQuality::P720), 2500);
        assert_eq!(proxy_bitrate(ProxyQuality::Off), 0);
    }

    #[test]
    fn test_sanitize_filename() {
        assert_eq!(sanitize_filename("abc-123"), "abc-123");
        assert_eq!(sanitize_filename("a/b\\c"), "a_b_c");
        assert_eq!(sanitize_filename("test.file"), "test_file");
    }

    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_generate_proxy_off_returns_error() {
        let result = generate_proxy("/fake.mp4", "id", ProxyQuality::Off, "/cache");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("disabled"));
    }

    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_generate_proxy_missing_file() {
        let result = generate_proxy("/nonexistent.mp4", "id", ProxyQuality::P480, "/cache");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not found"));
    }
}
