//! Export engine - Video export pipeline
//!
//! Handles rendering the timeline and encoding the final video output
//! with configurable resolution, bitrate, codec, and format settings.
//!
//! ## Phase 3 Implementation
//!
//! The export pipeline now supports real FFmpeg encoding with:
//! - Frame-by-frame rendering from the timeline
//! - RGBA → YUV420P color conversion
//! - H.264/H.265/VP9/AV1 encoding via FFmpeg
//! - Progress reporting via callback
//! - Storage space validation
//! - Audio passthrough (stream copy from source)
//!
//! ## Phase 8 Implementation
//!
//! Hardware-accelerated encoding using Android MediaCodec:
//! - Automatic detection of hardware encoder capabilities
//! - 3-5x speedup on devices with hardware H.264/H.265 encoders
//! - Transparent fallback to software (libx264/libx265) when HW unavailable
//! - Drop-in `HardwareEncoder` replacement for `VideoEncoder` in the export pipeline

pub mod encoder;
pub mod hardware_encoder;
pub mod batch;

#[cfg(test)]
mod tests;

use serde::{Deserialize, Serialize};

pub use encoder::{
    convert_f32_to_s16, convert_rgba_to_yuv420p, estimate_remaining, check_storage_space,
    AudioEncoder, MuxedEncoder, VideoEncoder,
};

pub use hardware_encoder::{
    HardwareEncoder, HardwareEncoderType, HardwareEncoderCapabilities,
};

/// Export configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportSettings {
    pub width: u32,
    pub height: u32,
    pub fps: f32,
    pub bitrate_kbps: u64,
    pub codec: VideoCodec,
    pub format: OutputFormat,
    pub audio_bitrate_kbps: u32,
    pub audio_sample_rate: u32,
    pub audio_channels: u32,
    pub include_audio: bool,
    pub two_pass: bool,
}

impl ExportSettings {
    /// 720p export preset
    pub fn hd_720p() -> Self {
        Self {
            width: 1280,
            height: 720,
            fps: 30.0,
            bitrate_kbps: 5000,
            codec: VideoCodec::H264,
            format: OutputFormat::Mp4,
            audio_bitrate_kbps: 128,
            audio_sample_rate: 44100,
            audio_channels: 2,
            include_audio: true,
            two_pass: false,
        }
    }

    /// 1080p export preset
    pub fn full_hd_1080p() -> Self {
        Self {
            width: 1920,
            height: 1080,
            fps: 30.0,
            bitrate_kbps: 10000,
            codec: VideoCodec::H264,
            format: OutputFormat::Mp4,
            audio_bitrate_kbps: 192,
            audio_sample_rate: 44100,
            audio_channels: 2,
            include_audio: true,
            two_pass: false,
        }
    }

    /// 4K export preset
    pub fn ultra_hd_4k() -> Self {
        Self {
            width: 3840,
            height: 2160,
            fps: 30.0,
            bitrate_kbps: 40000,
            codec: VideoCodec::H265,
            format: OutputFormat::Mp4,
            audio_bitrate_kbps: 256,
            audio_sample_rate: 48000,
            audio_channels: 2,
            include_audio: true,
            two_pass: true,
        }
    }

    /// TikTok/Reels vertical format
    pub fn social_vertical() -> Self {
        Self {
            width: 1080,
            height: 1920,
            fps: 30.0,
            bitrate_kbps: 8000,
            codec: VideoCodec::H264,
            format: OutputFormat::Mp4,
            audio_bitrate_kbps: 128,
            audio_sample_rate: 44100,
            audio_channels: 2,
            include_audio: true,
            two_pass: false,
        }
    }

    /// Instagram square format
    pub fn social_square() -> Self {
        Self {
            width: 1080,
            height: 1080,
            fps: 30.0,
            bitrate_kbps: 6000,
            codec: VideoCodec::H264,
            format: OutputFormat::Mp4,
            audio_bitrate_kbps: 128,
            audio_sample_rate: 44100,
            audio_channels: 2,
            include_audio: true,
            two_pass: false,
        }
    }

    /// Get a preset by name. Returns None for unknown preset names.
    pub fn preset_by_name(name: &str) -> Option<Self> {
        match name {
            "720p" => Some(Self::hd_720p()),
            "1080p" => Some(Self::full_hd_1080p()),
            "4K" => Some(Self::ultra_hd_4k()),
            "Social Vertical" | "social_vertical" => Some(Self::social_vertical()),
            "Social Square" | "social_square" => Some(Self::social_square()),
            _ => None,
        }
    }

    /// Get the estimated file size in bytes for a given duration.
    pub fn estimated_file_size(&self, duration_ms: u64) -> u64 {
        let duration_secs = duration_ms as f64 / 1000.0;
        let video_bytes = (self.bitrate_kbps as f64 * 1000.0 / 8.0) * duration_secs;
        let audio_bytes = (self.audio_bitrate_kbps as f64 * 1000.0 / 8.0) * duration_secs;
        // Add 5% overhead for container format
        ((video_bytes + audio_bytes) * 1.05) as u64
    }
}

/// Video codec options
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum VideoCodec {
    H264,
    H265,
    Vp9,
    Av1,
}

impl VideoCodec {
    pub fn ffmpeg_codec_name(&self) -> &str {
        #[cfg(target_os = "android")]
        {
            match self {
                VideoCodec::H264 => "h264_mediacodec",
                VideoCodec::H265 => "hevc_mediacodec",
                VideoCodec::Vp9 => "vp9_mediacodec",
                VideoCodec::Av1 => "av1_mediacodec",
            }
        }

        #[cfg(not(target_os = "android"))]
        {
            match self {
                VideoCodec::H264 => "libx264",
                VideoCodec::H265 => "libx265",
                VideoCodec::Vp9 => "libvpx-vp9",
                VideoCodec::Av1 => "libaom-av1",
            }
        }
    }

    pub fn display_name(&self) -> &str {
        match self {
            VideoCodec::H264 => "H.264 (AVC)",
            VideoCodec::H265 => "H.265 (HEVC)",
            VideoCodec::Vp9 => "VP9",
            VideoCodec::Av1 => "AV1",
        }
    }

    /// Parse a codec from a display name or identifier string.
    pub fn from_str_lossy(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "h264" | "h.264" | "avc" | "libx264" => Some(VideoCodec::H264),
            "h265" | "h.265" | "hevc" | "libx265" => Some(VideoCodec::H265),
            "vp9" | "libvpx-vp9" => Some(VideoCodec::Vp9),
            "av1" | "libaom-av1" => Some(VideoCodec::Av1),
            _ => None,
        }
    }
}

/// Output container format
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum OutputFormat {
    Mp4,
    WebM,
    Mov,
    Avi,
    Gif,
}

impl OutputFormat {
    pub fn ffmpeg_format_name(&self) -> &str {
        match self {
            OutputFormat::Mp4 => "mp4",
            OutputFormat::WebM => "webm",
            OutputFormat::Mov => "mov",
            OutputFormat::Avi => "avi",
            OutputFormat::Gif => "gif",
        }
    }

    pub fn file_extension(&self) -> &str {
        match self {
            OutputFormat::Mp4 => ".mp4",
            OutputFormat::WebM => ".webm",
            OutputFormat::Mov => ".mov",
            OutputFormat::Avi => ".avi",
            OutputFormat::Gif => ".gif",
        }
    }

    /// Parse a format from a display name or identifier string.
    pub fn from_str_lossy(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "mp4" => Some(OutputFormat::Mp4),
            "webm" => Some(OutputFormat::WebM),
            "mov" => Some(OutputFormat::Mov),
            "avi" => Some(OutputFormat::Avi),
            "gif" => Some(OutputFormat::Gif),
            _ => None,
        }
    }
}

/// Progress report during export
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportProgress {
    /// Percentage complete (0.0 to 1.0)
    pub progress: f32,
    /// Current frame being processed
    pub current_frame: u64,
    /// Total frames to process
    pub total_frames: u64,
    /// Estimated time remaining in seconds
    pub estimated_seconds_remaining: u64,
    /// Current processing stage
    pub stage: ExportStage,
}

impl ExportProgress {
    /// Create a progress report for the preparing stage.
    pub fn preparing() -> Self {
        Self {
            progress: 0.0,
            current_frame: 0,
            total_frames: 0,
            estimated_seconds_remaining: 0,
            stage: ExportStage::Preparing,
        }
    }

    /// Create a progress report for the encoding stage.
    pub fn encoding(current_frame: u64, total_frames: u64, start_time: std::time::Instant) -> Self {
        let progress = if total_frames > 0 {
            current_frame as f32 / total_frames as f32
        } else {
            0.0
        };

        Self {
            progress,
            current_frame,
            total_frames,
            estimated_seconds_remaining: estimate_remaining(current_frame, total_frames, start_time),
            stage: ExportStage::Encoding,
        }
    }

    /// Create a progress report for the finalizing stage.
    pub fn finalizing() -> Self {
        Self {
            progress: 0.95,
            current_frame: 0,
            total_frames: 0,
            estimated_seconds_remaining: 5,
            stage: ExportStage::Finalizing,
        }
    }

    /// Create a progress report for the completed stage.
    pub fn complete() -> Self {
        Self {
            progress: 1.0,
            current_frame: 0,
            total_frames: 0,
            estimated_seconds_remaining: 0,
            stage: ExportStage::Complete,
        }
    }

    /// Create a progress report for an error stage.
    pub fn error(message: &str) -> Self {
        Self {
            progress: 0.0,
            current_frame: 0,
            total_frames: 0,
            estimated_seconds_remaining: 0,
            stage: ExportStage::Error(message.to_string()),
        }
    }
}

/// Stages of the export process
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ExportStage {
    Preparing,
    Rendering,
    Encoding,
    Finalizing,
    Complete,
    Error(String),
}

impl ExportStage {
    /// Get a human-readable name for the stage.
    pub fn display_name(&self) -> &str {
        match self {
            ExportStage::Preparing => "Preparing",
            ExportStage::Rendering => "Rendering",
            ExportStage::Encoding => "Encoding",
            ExportStage::Finalizing => "Finalizing",
            ExportStage::Complete => "Complete",
            ExportStage::Error(_) => "Error",
        }
    }
}

/// Export result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportResult {
    pub success: bool,
    pub output_path: String,
    pub file_size_bytes: u64,
    pub duration_ms: u64,
    pub error_message: Option<String>,
}

impl ExportResult {
    /// Create an error result.
    pub fn error(message: &str, output_path: &str) -> Self {
        Self {
            success: false,
            output_path: output_path.to_string(),
            file_size_bytes: 0,
            duration_ms: 0,
            error_message: Some(message.to_string()),
        }
    }

    /// Get the file size in a human-readable format.
    pub fn file_size_human(&self) -> String {
        let bytes = self.file_size_bytes as f64;
        if bytes < 1024.0 {
            format!("{} B", bytes as u64)
        } else if bytes < 1024.0 * 1024.0 {
            format!("{:.1} KB", bytes / 1024.0)
        } else if bytes < 1024.0 * 1024.0 * 1024.0 {
            format!("{:.1} MB", bytes / (1024.0 * 1024.0))
        } else {
            format!("{:.2} GB", bytes / (1024.0 * 1024.0 * 1024.0))
        }
    }
}

/// The export pipeline orchestrates the rendering and encoding process
pub struct ExportPipeline {
    settings: ExportSettings,
}

impl ExportPipeline {
    pub fn new(settings: ExportSettings) -> Self {
        Self { settings }
    }

    /// Get the export settings
    pub fn settings(&self) -> &ExportSettings {
        &self.settings
    }

    /// Calculate the total number of frames for the given duration
    pub fn total_frames(&self, duration_ms: u64) -> u64 {
        (duration_ms as f64 * self.settings.fps as f64 / 1000.0).ceil() as u64
    }

    /// Calculate the frame number for a given timestamp
    pub fn frame_at_time(&self, time_ms: u64) -> u64 {
        (time_ms as f64 * self.settings.fps as f64 / 1000.0) as u64
    }

    /// Calculate the timestamp for a given frame number
    pub fn time_at_frame(&self, frame: u64) -> u64 {
        (frame as f64 * 1000.0 / self.settings.fps as f64) as u64
    }
}
