//! Renderer module - Composites timeline tracks into displayable frames
//!
//! The renderer takes a timeline state and a timestamp, then composites
//! all visible tracks (video, text, effects) into a single frame for display.
//! Clip effects are applied per-clip before compositing. Keyframe animations
//! (position, scale, rotation, opacity) are applied via affine transforms.
//!
//! Effects use a canonical ordered CPU path so preview and export share
//! parameter semantics. GPU availability alone does not establish parity.

pub mod gpu;
pub mod shader;
pub mod shaders;

#[cfg(test)]
mod shader_bench;

use crate::decoder::FrameData;
use crate::effects::EffectsPipeline;
use crate::effects::text_rasterizer::TextRasterizer;
use crate::effects::text_render::TextOverlay;
use crate::renderer::gpu::GpuRenderer;
use crate::timeline::keyframe::InterpolatedValues;
use crate::timeline::Timeline;
use crate::timeline::track::TrackType;

/// Preview renderer for real-time frame composition
pub struct PreviewRenderer {
    width: u32,
    height: u32,
    text_rasterizer: TextRasterizer,
    gpu_renderer: GpuRenderer,
    /// Whether to attempt GPU-accelerated effects processing.
    /// Set to true after successful GPU init, false otherwise.
    gpu_available: bool,
}

impl PreviewRenderer {
    /// Create a new preview renderer at the specified resolution.
    ///
    /// GPU acceleration is lazily initialized on the first frame render.
    /// If GPU init fails, it silently falls back to CPU rendering.
    pub fn new(width: u32, height: u32) -> Self {
        Self {
            width,
            height,
            text_rasterizer: TextRasterizer::new(),
            gpu_renderer: GpuRenderer::new(),
            gpu_available: false,
        }
    }

    pub fn set_canvas_size(&mut self, width: u32, height: u32) {
        self.width = width.max(1);
        self.height = height.max(1);
    }

    /// Attempt to initialize the GPU renderer.
    ///
    /// Call this once during engine startup. If it fails, the renderer
    /// will use CPU-only effects processing. This method is non-blocking
    /// and safe to call from any thread.
    pub async fn init_gpu(&mut self) {
        self.gpu_renderer.init_or_fallback().await;
        self.gpu_available = self.gpu_renderer.is_available();
        if self.gpu_available {
            log::info!("Preview renderer: GPU acceleration ENABLED");
        } else {
            log::info!("Preview renderer: using CPU-only effects");
        }
    }

    /// Compose a single frame from the timeline at the given timestamp.
    ///
    /// This method:
    /// 1. Takes the decoded video frame (or a blank frame)
    /// 2. Applies per-clip effects through the canonical ordered CPU pipeline
    /// 3. Applies keyframe transforms (position, scale, rotation, opacity)
    /// 4. Applies opacity blending for non-opaque clips
    /// 5. Renders text overlays from text tracks
    pub fn compose_frame(
        &mut self,
        timeline: &Timeline,
        time_ms: u64,
        video_frame: Option<FrameData>,
    ) -> FrameData {
        let layers = video_frame.and_then(|frame| {
            timeline.tracks.iter()
                .filter(|track| track.visible && track.track_type == TrackType::Video)
                .flat_map(|track| &track.clips)
                .find(|clip| clip.contains_time(time_ms))
                .map(|clip| vec![(clip.id.clone(), frame)])
        }).unwrap_or_default();
        self.compose_video_layers(timeline, time_ms, layers)
    }

    /// Layers arrive in bottom-to-top track order. Each clip is processed
    /// independently before straight-alpha composition onto the project canvas.
    pub fn compose_video_layers(
        &mut self, timeline: &Timeline, time_ms: u64,
        layers: Vec<(String, FrameData)>,
    ) -> FrameData {
        let mut frame = FrameData::blank(self.width, self.height);
        frame.timestamp_ms = time_ms;
        for pixel in frame.data.chunks_exact_mut(4) { pixel[3] = 255; }
        for (clip_id, mut source) in layers {
            let Some(clip) = timeline.tracks.iter()
                .filter(|track| track.visible && track.track_type == TrackType::Video)
                .flat_map(|track| &track.clips)
                .find(|clip| clip.id == clip_id && clip.contains_time(time_ms)) else { continue; };
            self.apply_effects(&mut source, &clip.effects);
            let mut layer = self.fit_to_canvas(&source);
            if clip.has_keyframes() {
                layer = apply_clip_transform(&layer, &clip.interpolate_at(time_ms), self.width, self.height);
            }
            let opacity = clip.opacity.clamp(0.0, 1.0);
            for (destination, pixel) in frame.data.chunks_exact_mut(4).zip(layer.data.chunks_exact(4)) {
                let alpha = pixel[3] as f32 / 255.0 * opacity;
                for channel in 0..3 {
                    destination[channel] = (pixel[channel] as f32 * alpha
                        + destination[channel] as f32 * (1.0 - alpha)).round().clamp(0.0, 255.0) as u8;
                }
                destination[3] = 255;
            }
        }

        // Render text overlays from text tracks
        let text_tracks = timeline.tracks_of_type(TrackType::Text);
        for track in text_tracks {
            if !track.visible {
                continue;
            }
            for clip in &track.clips {
                if !clip.contains_time(time_ms) {
                    continue;
                }

                let progress = if clip.duration_ms > 0 {
                    (time_ms - clip.start_ms) as f32 / clip.duration_ms as f32
                } else {
                    0.0
                };

                let mut overlay = TextOverlay::from_properties(&clip.properties);
                overlay.color.opacity = clip.opacity.clamp(0.0, 1.0);
                self.text_rasterizer.render_text(
                    &overlay,
                    &mut frame.data,
                    frame.width,
                    frame.height,
                    progress,
                    clip.duration_ms,
                );
            }
        }

        frame
    }

    fn fit_to_canvas(&self, source: &FrameData) -> FrameData {
        let mut canvas = FrameData::blank(self.width, self.height);
        if source.width == 0 || source.height == 0 { return canvas; }
        let scale = (self.width as f64 / source.width as f64)
            .min(self.height as f64 / source.height as f64);
        let width = ((source.width as f64 * scale).round() as u32).clamp(1, self.width);
        let height = ((source.height as f64 * scale).round() as u32).clamp(1, self.height);
        let resized = self.resize_frame(source, width, height);
        let left = (self.width - width) / 2;
        let top = (self.height - height) / 2;
        let row_bytes = width as usize * 4;
        for row in 0..height {
            let destination = (((top + row) * self.width + left) * 4) as usize;
            let source_offset = row as usize * row_bytes;
            canvas.data[destination..destination + row_bytes]
                .copy_from_slice(&resized.data[source_offset..source_offset + row_bytes]);
        }
        canvas
    }

    /// Apply the same ordered effect chain used by export.
    fn apply_effects(&mut self, frame: &mut FrameData, effects: &[crate::effects::Effect]) {
        // One canonical ordered implementation for preview and export. GPU
        // descriptors currently disagree with native parameter names and units.
        let pipeline = EffectsPipeline::new(effects.to_vec());
        pipeline.apply(&mut frame.data, frame.width, frame.height);
    }

    /// Apply effects from a clip's effect chain to frame data.
    pub fn apply_clip_effects(&self, frame: &mut FrameData, effects: &[crate::effects::Effect]) {
        if effects.is_empty() { return; }
        let pipeline = EffectsPipeline::new(effects.to_vec());
        pipeline.apply(&mut frame.data, frame.width, frame.height);
    }

    /// Resize a frame to the target dimensions using bilinear interpolation.
    pub fn resize_frame(&self, frame: &FrameData, target_width: u32, target_height: u32) -> FrameData {
        if frame.width == target_width && frame.height == target_height {
            return frame.clone();
        }

        let mut data = vec![0u8; (target_width * target_height * 4) as usize];
        let x_ratio = frame.width as f32 / target_width as f32;
        let y_ratio = frame.height as f32 / target_height as f32;

        // Bilinear interpolation for better quality during export
        for y in 0..target_height {
            for x in 0..target_width {
                let src_x = x as f32 * x_ratio;
                let src_y = y as f32 * y_ratio;

                let x0 = src_x.floor() as u32;
                let y0 = src_y.floor() as u32;
                let x1 = (x0 + 1).min(frame.width - 1);
                let y1 = (y0 + 1).min(frame.height - 1);

                let fx = src_x - x0 as f32;
                let fy = src_y - y0 as f32;

                let dst_idx = ((y * target_width + x) * 4) as usize;

                for ch in 0..4 {
                    let v00 = frame.data[((y0 * frame.width + x0) * 4 + ch as u32) as usize] as f32;
                    let v10 = frame.data[((y0 * frame.width + x1) * 4 + ch as u32) as usize] as f32;
                    let v01 = frame.data[((y1 * frame.width + x0) * 4 + ch as u32) as usize] as f32;
                    let v11 = frame.data[((y1 * frame.width + x1) * 4 + ch as u32) as usize] as f32;

                    let top = v00 * (1.0 - fx) + v10 * fx;
                    let bottom = v01 * (1.0 - fx) + v11 * fx;
                    let value = top * (1.0 - fy) + bottom * fy;

                    data[dst_idx + ch as usize] = value.clamp(0.0, 255.0) as u8;
                }
            }
        }

        FrameData {
            width: target_width,
            height: target_height,
            data,
            timestamp_ms: frame.timestamp_ms,
            is_keyframe: frame.is_keyframe,
            pooled: false,
        }
    }

    /// Check if GPU acceleration is currently active.
    pub fn is_gpu_accelerated(&self) -> bool {
        self.gpu_available
    }

    /// Get the name of the GPU adapter, if available.
    pub fn gpu_adapter_name(&self) -> Option<String> {
        self.gpu_renderer.adapter_name()
    }

    /// Get the name of the GPU backend (e.g., "Vulkan", "Metal"), if available.
    pub fn gpu_backend_name(&self) -> Option<String> {
        self.gpu_renderer.backend_name()
    }

    /// Get the list of effects that have GPU shader pipelines.
    pub fn gpu_accelerated_effects(&self) -> Vec<&str> {
        self.gpu_renderer.gpu_accelerated_effects()
    }

    /// Enable or disable GPU acceleration at runtime.
    ///
    /// When `enabled` is `false`, the renderer will use CPU-only effects
    /// even if a GPU is available. This is useful for debugging.
    pub fn set_gpu_enabled(&mut self, enabled: bool) {
        if !enabled {
            self.gpu_available = false;
        } else {
            // Only re-enable if the GPU was actually initialized
            self.gpu_available = self.gpu_renderer.is_available();
        }
    }

    /// Get the rendering resolution.
    pub fn resolution(&self) -> (u32, u32) {
        (self.width, self.height)
    }
}

/// Apply affine transforms (translation, scaling, rotation) to a frame
/// based on keyframe-interpolated values.
///
/// This creates a new frame with the transforms applied. The transform
/// pipeline is:
/// 1. Scale the frame by the scale factor
/// 2. Rotate the frame by the rotation angle (degrees)
/// 3. Translate (offset) the frame by position_x and position_y pixels
/// 4. Apply opacity from the interpolated values
///
/// The output frame has the same dimensions as the input. Pixels that
/// are transformed outside the frame boundary are clipped.
fn apply_clip_transform(
    frame: &FrameData,
    values: &InterpolatedValues,
    _output_width: u32,
    _output_height: u32,
) -> FrameData {
    let w = frame.width as usize;
    let h = frame.height as usize;
    let mut output = vec![0u8; w * h * 4];

    // Convert rotation from degrees to radians
    let angle_rad = values.rotation.to_radians();
    let cos_a = angle_rad.cos();
    let sin_a = angle_rad.sin();

    // Scale factor
    let scale = values.scale;
    if scale <= 0.0 {
        // Fully scaled down — nothing visible
        return FrameData {
            width: frame.width,
            height: frame.height,
            data: output,
            timestamp_ms: frame.timestamp_ms,
            is_keyframe: frame.is_keyframe,
            pooled: false,
        };
    }

    // Center of the frame
    let cx = w as f32 / 2.0;
    let cy = h as f32 / 2.0;

    // Translation offsets (in pixels)
    let tx = values.position_x;
    let ty = values.position_y;

    // Opacity multiplier
    let opacity = values.opacity.clamp(0.0, 1.0);

    // Inverse transform: for each output pixel, find the source pixel
    let inv_scale = 1.0 / scale;

    for dst_y in 0..h {
        for dst_x in 0..w {
            // Translate destination pixel to center-origin
            let dx = dst_x as f32 - cx - tx;
            let dy = dst_y as f32 - cy - ty;

            // Inverse rotate
            let rot_x = dx * cos_a + dy * sin_a;
            let rot_y = -dx * sin_a + dy * cos_a;

            // Inverse scale
            let src_x = rot_x * inv_scale + cx;
            let src_y = rot_y * inv_scale + cy;

            // Nearest-neighbor sampling for speed
            let sx = src_x.round() as isize;
            let sy = src_y.round() as isize;

            let dst_idx = (dst_y * w + dst_x) * 4;

            if sx >= 0 && sx < w as isize && sy >= 0 && sy < h as isize {
                let src_idx = (sy as usize * w + sx as usize) * 4;
                output[dst_idx] = frame.data[src_idx];
                output[dst_idx + 1] = frame.data[src_idx + 1];
                output[dst_idx + 2] = frame.data[src_idx + 2];
                output[dst_idx + 3] = (frame.data[src_idx + 3] as f32 * opacity) as u8;
            }
            // else: leave as 0 (transparent black)
        }
    }

    FrameData {
        width: frame.width,
        height: frame.height,
        data: output,
        timestamp_ms: frame.timestamp_ms,
        is_keyframe: frame.is_keyframe,
        pooled: false,
    }
}

/// Render quality settings for preview vs export
#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize)]
pub enum RenderQuality {
    /// Low quality for smooth preview on weak devices
    PreviewLow,
    /// Medium quality for standard preview
    PreviewMedium,
    /// High quality for final export
    ExportHigh,
    /// Maximum quality for 4K export
    ExportUltra,
}

impl RenderQuality {
    /// Get the resolution scale factor for this quality level
    pub fn scale_factor(&self) -> f32 {
        match self {
            RenderQuality::PreviewLow => 0.25,
            RenderQuality::PreviewMedium => 0.5,
            RenderQuality::ExportHigh => 1.0,
            RenderQuality::ExportUltra => 1.0,
        }
    }

    /// Whether GPU effects should be used at this quality level.
    pub fn use_gpu(&self) -> bool {
        match self {
            RenderQuality::PreviewLow => false, // CPU is fast enough for small frames
            RenderQuality::PreviewMedium => true,
            RenderQuality::ExportHigh => true,
            RenderQuality::ExportUltra => true,
        }
    }
}
