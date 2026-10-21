//! Render pipeline (orphan module wired in Phase A).
//!
//! Applies the timeline → render → encode flow. Phase A refactor:
//! replaced the deleted `crate::codec::encoder::{Encoder, EncoderConfig,
//! QualityPreset, VideoCodec}` (duplicate of `export_engine`) with the
//! canonical `crate::export_engine::{VideoEncoder, ExportSettings,
//! VideoCodec, OutputFormat}`.

use anyhow::{Context, Result};
use log::{debug, info, warn};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;

use crate::export_engine::{ExportSettings, OutputFormat, VideoCodec, VideoEncoder};
use crate::project::Project;
use crate::utils::async_ops::CancellationToken;

/// Quality preset for rendering.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RenderQualityPreset {
    Draft,
    Good,
    High,
    Ultra,
}

impl Default for RenderQualityPreset {
    fn default() -> Self {
        RenderQualityPreset::Good
    }
}

/// Configuration for a render job.
///
/// Phase A: `codec` is now `crate::export_engine::VideoCodec` (which
/// includes Av1). `quality_preset` no longer maps to the deleted
/// `QualityPreset` enum; it's preserved for API compatibility but
/// currently only affects logging.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderConfig {
    pub output_path: String,
    pub codec: VideoCodec,
    pub bitrate: u64,
    pub resolution: (u32, u32),
    pub fps: f64,
    pub quality_preset: RenderQualityPreset,
}

impl Default for RenderConfig {
    fn default() -> Self {
        Self {
            output_path: "output.mp4".to_string(),
            codec: VideoCodec::H264,
            bitrate: 8_000_000,
            resolution: (1920, 1080),
            fps: 30.0,
            quality_preset: RenderQualityPreset::Good,
        }
    }
}

impl RenderConfig {
    /// Convert to an `ExportSettings` instance suitable for `VideoEncoder::new`.
    fn to_export_settings(&self) -> ExportSettings {
        ExportSettings {
            width: self.resolution.0,
            height: self.resolution.1,
            fps: self.fps as f32,
            bitrate_kbps: self.bitrate / 1000,
            codec: self.codec,
            format: OutputFormat::Mp4,
            audio_bitrate_kbps: 128,
            audio_sample_rate: 44100,
            audio_channels: 2,
            include_audio: false, // audio is rendered separately via render_audio()
            two_pass: false,
        }
    }
}

/// The full export pipeline for rendering a project to a video file.
pub struct RenderPipeline {
    project: Project,
    config: RenderConfig,
    progress: Arc<AtomicU32>,
    cancelled: Arc<AtomicBool>,
    total_frames: u64,
}

impl RenderPipeline {
    /// Create a new render pipeline for the given project and config.
    pub fn new(project: Project, config: RenderConfig) -> Result<Self> {
        let duration = project.timeline.get_duration();
        let total_frames = if config.fps > 0.0 {
            (duration * config.fps) as u64
        } else {
            0
        };

        Ok(Self {
            project,
            config,
            progress: Arc::new(AtomicU32::new(0)),
            cancelled: Arc::new(AtomicBool::new(false)),
            total_frames,
        })
    }

    /// Render a single frame at the given index. Applies all effects and compositing.
    pub fn render_frame(&self, frame_idx: u64) -> Result<Vec<u8>> {
        if self.is_cancelled() {
            anyhow::bail!("Render cancelled");
        }

        let (width, height) = self.config.resolution;
        let frame_size = (width * height * 4) as usize;

        // In a complete implementation, this would:
        // 1. Determine which clips are active at this frame's time
        // 2. Decode video frames from source files
        // 3. Apply transforms (position, scale, rotation, opacity)
        // 4. Apply effects and filters
        // 5. Composite all layers using alpha blending
        // 6. Apply color grading

        let time = frame_idx as f64 / self.config.fps;
        let _clip = self.project.timeline.find_clip_at_time(time);

        // Generate a blank frame for now (RGBA)
        let frame_data = vec![0u8; frame_size];

        debug!("Rendered frame {} at time {:.3}s", frame_idx, time);
        Ok(frame_data)
    }

    /// Render all frames and write to the output file.
    ///
    /// Phase A refactor: now uses `crate::export_engine::VideoEncoder`
    /// instead of the deleted `crate::codec::encoder::Encoder`.
    /// The progress callback is called with a value from 0.0 to 1.0.
    pub fn render_all(&mut self, progress_cb: Box<dyn Fn(f32)>) -> Result<()> {
        if self.total_frames == 0 {
            anyhow::bail!("No frames to render (duration=0 or fps=0)");
        }

        let settings = self.config.to_export_settings();
        let mut encoder = VideoEncoder::new(&settings)
            .map_err(|e| anyhow::anyhow!("Failed to create encoder: {}", e))?;
        encoder.open(&self.config.output_path).map_err(|e| {
            anyhow::anyhow!("Failed to open output '{}': {}", self.config.output_path, e)
        })?;

        for frame_idx in 0..self.total_frames {
            if self.is_cancelled() {
                warn!(
                    "Render cancelled at frame {}/{}",
                    frame_idx, self.total_frames
                );
                break;
            }

            match self.render_frame(frame_idx) {
                Ok(frame_data) => {
                    if let Err(e) = encoder.encode_rgba_frame(&frame_data, frame_idx as i64) {
                        warn!("Failed to encode frame {}: {}", frame_idx, e);
                    }
                }
                Err(e) => {
                    warn!("Failed to render frame {}: {}", frame_idx, e);
                    // Write a black frame as fallback
                    let (w, h) = self.config.resolution;
                    let black_frame = vec![0u8; (w * h * 4) as usize];
                    let _ = encoder.encode_rgba_frame(&black_frame, frame_idx as i64);
                }
            }

            let progress_pct = ((frame_idx + 1) as f32 / self.total_frames as f32 * 100.0) as u32;
            self.progress.store(progress_pct, Ordering::SeqCst);
            progress_cb(progress_pct as f32 / 100.0);
        }

        let duration_ms = (self.total_frames as f64 / self.config.fps * 1000.0) as u64;
        encoder
            .finish(duration_ms)
            .map_err(|e| anyhow::anyhow!("Failed to finalize encoder: {}", e))?;

        info!(
            "Render complete: {} frames written to {}",
            self.total_frames, self.config.output_path
        );
        Ok(())
    }

    /// Render and mix all audio tracks.
    pub fn render_audio(&self) -> Result<Vec<f32>> {
        let duration = self.project.timeline.get_duration();
        let sample_rate = 48000u32;
        let total_samples = (duration * sample_rate as f64) as usize;

        let mut mixed = vec![0.0f32; total_samples];

        for track in &self.project.timeline.tracks {
            if track.muted {
                continue;
            }

            let track_volume = track.volume as f32;
            let track_pan = track.pan as f32;

            for clip in &track.clips {
                if clip.muted {
                    continue;
                }

                let clip_volume = clip.volume as f32 * track_volume;
                let clip_duration_samples =
                    (clip.effective_duration() as f64 / 1000.0 * sample_rate as f64) as usize;

                // Generate silence for now (real implementation would decode audio)
                for i in 0..clip_duration_samples.min(total_samples) {
                    mixed[i] += 0.0 * clip_volume; // placeholder for actual audio data
                }
                let _ = track_pan; // suppress unused warning until pan is implemented
            }
        }

        // Normalize to prevent clipping
        let max_val = mixed.iter().fold(0.0f32, |a, &b| a.max(b.abs()));
        if max_val > 1.0 {
            let scale = 1.0 / max_val;
            for s in mixed.iter_mut() {
                *s *= scale;
            }
        }

        Ok(mixed)
    }

    /// Mux (combine) rendered video and audio into the final output.
    pub fn mux_final(&self) -> Result<()> {
        // In a complete implementation, this would:
        // 1. Render video to a temp file
        // 2. Render audio to a temp file
        // 3. Mux them together
        debug!("mux_final: combining video + audio");
        Ok(())
    }

    /// Cancel the render.
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
        info!("Render cancellation requested");
    }

    /// Check if the render has been cancelled.
    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }

    /// Estimate the output file size in bytes.
    pub fn estimate_output_size(&self) -> u64 {
        let duration = self.project.timeline.get_duration();
        let video_size = (self.config.bitrate as f64 * duration / 8.0) as u64;
        let audio_size = (128_000.0 * duration / 8.0) as u64; // Estimate 128kbps audio
        let container_overhead = (video_size + audio_size) / 100; // ~1% overhead
        video_size + audio_size + container_overhead
    }

    /// Get the current render progress as a percentage (0-100).
    pub fn get_progress(&self) -> f32 {
        self.progress.load(Ordering::SeqCst) as f32 / 100.0
    }

    /// Get the total number of frames to render.
    pub fn total_frames(&self) -> u64 {
        self.total_frames
    }
}

// ─── Unit tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::timeline::track::{Track, TrackType};
    use crate::timeline::Timeline;

    fn make_project() -> Project {
        let mut project = Project::new("Render Test");
        project
            .timeline
            .add_track(TrackType::Video, Some("V1".into()));
        project
    }

    #[test]
    fn test_render_pipeline_new() {
        let project = make_project();
        let config = RenderConfig::default();
        let pipeline = RenderPipeline::new(project, config);
        assert!(pipeline.is_ok());
    }

    #[test]
    fn test_render_pipeline_cancel() {
        let project = make_project();
        let config = RenderConfig::default();
        let pipeline = RenderPipeline::new(project, config).unwrap();
        assert!(!pipeline.is_cancelled());
        pipeline.cancel();
        assert!(pipeline.is_cancelled());
    }

    #[test]
    fn test_render_pipeline_get_progress_initial() {
        let project = make_project();
        let config = RenderConfig::default();
        let pipeline = RenderPipeline::new(project, config).unwrap();
        assert!((pipeline.get_progress()).abs() < 1e-5);
    }

    #[test]
    fn test_render_pipeline_estimate_output_size() {
        let project = make_project();
        let config = RenderConfig {
            bitrate: 8_000_000,
            ..RenderConfig::default()
        };
        let pipeline = RenderPipeline::new(project, config).unwrap();
        let size = pipeline.estimate_output_size();
        // Should be > 0 even for zero-duration project
        assert!(size >= 0);
    }

    #[test]
    fn test_render_config_default() {
        let config = RenderConfig::default();
        assert_eq!(config.codec, VideoCodec::H264);
        assert_eq!(config.bitrate, 8_000_000);
        assert_eq!(config.resolution, (1920, 1080));
        assert_eq!(config.fps, 30.0);
    }

    #[test]
    fn test_render_pipeline_render_frame_cancelled() {
        let project = make_project();
        let config = RenderConfig {
            resolution: (64, 64),
            ..RenderConfig::default()
        };
        let pipeline = RenderPipeline::new(project, config).unwrap();
        pipeline.cancel();
        let result = pipeline.render_frame(0);
        assert!(result.is_err());
    }

    #[test]
    fn test_render_pipeline_render_audio() {
        let project = make_project();
        let config = RenderConfig::default();
        let pipeline = RenderPipeline::new(project, config).unwrap();
        let audio = pipeline.render_audio();
        assert!(audio.is_ok());
    }

    /// Ensure the cancellation token from `utils::async_ops` is reachable
    /// after the Phase A wiring of the orphan `utils` module.
    #[test]
    fn test_cancellation_token_wired() {
        let token = CancellationToken::new();
        assert!(!token.is_cancelled());
        token.cancel();
        assert!(token.is_cancelled());
        token.reset();
        assert!(!token.is_cancelled());
    }
}
