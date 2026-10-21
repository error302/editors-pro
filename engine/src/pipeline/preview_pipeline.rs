use anyhow::{Context, Result};
use log::debug;
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use crate::project::Project;

/// Preview quality level.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PreviewQuality {
    Full,
    Half,
    Quarter,
    Eighth,
}

impl Default for PreviewQuality {
    fn default() -> Self {
        PreviewQuality::Half
    }
}

/// Configuration for the preview pipeline.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreviewConfig {
    pub max_resolution: (u32, u32),
    pub target_fps: f64,
    pub quality: PreviewQuality,
}

impl Default for PreviewConfig {
    fn default() -> Self {
        Self {
            max_resolution: (960, 540),
            target_fps: 24.0,
            quality: PreviewQuality::Half,
        }
    }
}

/// Real-time preview pipeline with adaptive quality.
pub struct PreviewPipeline {
    project: Project,
    config: PreviewConfig,
    current_time: Arc<AtomicU64>,
    current_frame: Arc<AtomicU64>,
    playback_speed: Arc<AtomicU64>,
    adaptive_quality_enabled: bool,
    current_quality: PreviewQuality,
}

impl PreviewPipeline {
    /// Create a new preview pipeline.
    pub fn new(project: Project, config: PreviewConfig) -> Result<Self> {
        Ok(Self {
            project,
            config: config.clone(),
            current_time: Arc::new(AtomicU64::new(0.0f64.to_bits())),
            current_frame: Arc::new(AtomicU64::new(0)),
            playback_speed: Arc::new(AtomicU64::new(1.0f64.to_bits())),
            adaptive_quality_enabled: true,
            current_quality: config.quality,
        })
    }

    /// Render a preview frame at the given time.
    pub fn render_preview_frame(&self, time: f64) -> Result<Vec<u8>> {
        let (width, height) = self.effective_resolution();
        let frame_size = (width * height * 4) as usize;

        // In a complete implementation, this would:
        // 1. Determine active clips at this time
        // 2. Decode necessary frames (possibly from proxy files)
        // 3. Apply transforms and effects at preview quality
        // 4. Composite all layers
        // 5. Apply preview-grade color correction

        let _clip = self.project.timeline.find_clip_at_time(time);

        // Return a blank frame
        let frame_data = vec![0u8; frame_size];

        self.current_time.store(time.to_bits(), Ordering::SeqCst);
        if self.config.target_fps > 0.0 {
            self.current_frame
                .store((time * self.config.target_fps) as u64, Ordering::SeqCst);
        }

        debug!("Preview frame at {:.3}s ({}x{})", time, width, height);
        Ok(frame_data)
    }

    /// Seek to a specific time.
    pub fn seek(&self, time: f64) -> Result<()> {
        let duration = self.project.timeline.get_duration();
        let clamped_time = time.clamp(0.0, duration);
        self.current_time
            .store(clamped_time.to_bits(), Ordering::SeqCst);
        if self.config.target_fps > 0.0 {
            self.current_frame.store(
                (clamped_time * self.config.target_fps) as u64,
                Ordering::SeqCst,
            );
        }
        debug!("Seeked to {:.3}s", clamped_time);
        Ok(())
    }

    /// Set the playback speed (1.0 = normal, 2.0 = double speed, etc.).
    pub fn set_playback_speed(&self, speed: f32) {
        self.playback_speed
            .store((speed as f64).to_bits(), Ordering::SeqCst);
        debug!("Playback speed set to {:.2}x", speed);
    }

    /// Enable or disable adaptive quality.
    pub fn enable_adaptive_quality(&mut self, enabled: bool) {
        self.adaptive_quality_enabled = enabled;
        if !enabled {
            self.current_quality = self.config.quality;
        }
        debug!("Adaptive quality: {}", enabled);
    }

    /// Get the current frame number.
    pub fn get_current_frame(&self) -> u64 {
        self.current_frame.load(Ordering::SeqCst)
    }

    /// Get the current playback time.
    pub fn get_current_time(&self) -> f64 {
        f64::from_bits(self.current_time.load(Ordering::SeqCst))
    }

    /// Get the playback speed.
    pub fn get_playback_speed(&self) -> f64 {
        f64::from_bits(self.playback_speed.load(Ordering::SeqCst))
    }

    /// Calculate the effective resolution based on quality setting.
    fn effective_resolution(&self) -> (u32, u32) {
        let (max_w, max_h) = self.config.max_resolution;
        let quality = if self.adaptive_quality_enabled {
            self.current_quality
        } else {
            self.config.quality
        };

        let divisor = match quality {
            PreviewQuality::Full => 1,
            PreviewQuality::Half => 2,
            PreviewQuality::Quarter => 4,
            PreviewQuality::Eighth => 8,
        };

        ((max_w / divisor).max(16), (max_h / divisor).max(16))
    }

    /// Adapt quality based on rendering performance.
    /// If frame_time_ms > target_frame_ms, reduce quality.
    pub fn adapt_quality(&mut self, frame_time_ms: f64) {
        if !self.adaptive_quality_enabled {
            return;
        }

        let target_frame_ms = 1000.0 / self.config.target_fps;

        if frame_time_ms > target_frame_ms * 1.5 {
            // Drop quality
            self.current_quality = match self.current_quality {
                PreviewQuality::Full => PreviewQuality::Half,
                PreviewQuality::Half => PreviewQuality::Quarter,
                PreviewQuality::Quarter => PreviewQuality::Eighth,
                PreviewQuality::Eighth => PreviewQuality::Eighth,
            };
            debug!("Quality reduced to {:?}", self.current_quality);
        } else if frame_time_ms < target_frame_ms * 0.5 {
            // Increase quality
            self.current_quality = match self.current_quality {
                PreviewQuality::Full => PreviewQuality::Full,
                PreviewQuality::Half => PreviewQuality::Full,
                PreviewQuality::Quarter => PreviewQuality::Half,
                PreviewQuality::Eighth => PreviewQuality::Quarter,
            };
            debug!("Quality increased to {:?}", self.current_quality);
        }
    }

    /// Get the current quality level.
    pub fn current_quality(&self) -> PreviewQuality {
        self.current_quality
    }
}

// ─── Unit tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::timeline::track::{Track, TrackType};
    use crate::timeline::Timeline;

    fn make_project() -> Project {
        let mut project = Project::new("Preview Test");
        project
            .timeline
            .add_track(TrackType::Video, Some("V1".into()));
        project
    }

    #[test]
    fn test_preview_pipeline_new() {
        let project = make_project();
        let config = PreviewConfig::default();
        let pipeline = PreviewPipeline::new(project, config);
        assert!(pipeline.is_ok());
    }

    #[test]
    fn test_preview_pipeline_render_frame() {
        let project = make_project();
        let config = PreviewConfig::default();
        let pipeline = PreviewPipeline::new(project, config).unwrap();
        let result = pipeline.render_preview_frame(0.0);
        assert!(result.is_ok());
    }

    #[test]
    fn test_preview_pipeline_seek() {
        let project = make_project();
        let config = PreviewConfig::default();
        let pipeline = PreviewPipeline::new(project, config).unwrap();
        pipeline.seek(5.0).unwrap();
        assert!((pipeline.get_current_time() - 5.0).abs() < 1e-9);
    }

    #[test]
    fn test_preview_pipeline_set_speed() {
        let project = make_project();
        let config = PreviewConfig::default();
        let pipeline = PreviewPipeline::new(project, config).unwrap();
        pipeline.set_playback_speed(2.0);
        assert!((pipeline.get_playback_speed() - 2.0).abs() < 1e-9);
    }

    #[test]
    fn test_preview_pipeline_adaptive_quality() {
        let project = make_project();
        let config = PreviewConfig {
            quality: PreviewQuality::Half,
            ..PreviewConfig::default()
        };
        let mut pipeline = PreviewPipeline::new(project, config).unwrap();
        assert_eq!(pipeline.current_quality(), PreviewQuality::Half);
        pipeline.adapt_quality(100.0); // very slow frame
        assert_eq!(pipeline.current_quality(), PreviewQuality::Quarter);
    }

    #[test]
    fn test_preview_pipeline_disable_adaptive() {
        let project = make_project();
        let config = PreviewConfig {
            quality: PreviewQuality::Half,
            ..PreviewConfig::default()
        };
        let mut pipeline = PreviewPipeline::new(project, config).unwrap();
        pipeline.enable_adaptive_quality(false);
        pipeline.adapt_quality(1000.0); // very slow frame, but adaptive disabled
        assert_eq!(pipeline.current_quality(), PreviewQuality::Half);
    }

    #[test]
    fn test_preview_effective_resolution() {
        let project = make_project();
        let config = PreviewConfig {
            max_resolution: (1920, 1080),
            quality: PreviewQuality::Quarter,
            ..PreviewConfig::default()
        };
        let pipeline = PreviewPipeline::new(project, config).unwrap();
        let (w, h) = pipeline.effective_resolution();
        assert_eq!(w, 480);
        assert_eq!(h, 270);
    }
}
