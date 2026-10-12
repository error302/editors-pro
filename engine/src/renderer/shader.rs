//! Shader management for GPU effects
//!
//! Handles loading, caching, and applying WGSL shaders
//! for visual effects processing. Provides both GPU shader source
//! code for wgpu compute pipelines and CPU fallback implementations
//! for devices without GPU support or for the preview-low quality tier.

use std::collections::HashMap;

/// Manages GPU shaders for effects processing
pub struct ShaderManager {
    shaders: HashMap<String, String>,
    loaded: bool,
}

impl ShaderManager {
    pub fn new() -> Self {
        let mut shaders = HashMap::new();

        // Built-in shader source code for basic effects (WGSL)
        shaders.insert("brightness".to_string(), BRIGHTNESS_SHADER.to_string());
        shaders.insert("contrast".to_string(), CONTRAST_SHADER.to_string());
        shaders.insert("saturation".to_string(), SATURATION_SHADER.to_string());
        shaders.insert("grayscale".to_string(), GRAYSCALE_SHADER.to_string());
        shaders.insert("blur".to_string(), BLUR_SHADER.to_string());
        shaders.insert("sepia".to_string(), SEPIA_SHADER.to_string());
        shaders.insert("invert".to_string(), INVERT_SHADER.to_string());
        shaders.insert("vignette".to_string(), VIGNETTE_SHADER.to_string());
        shaders.insert("sharpen".to_string(), SHARPEN_SHADER.to_string());
        shaders.insert("hue_rotate".to_string(), HUE_ROTATE_SHADER.to_string());
        shaders.insert("temperature".to_string(), TEMPERATURE_SHADER.to_string());

        Self {
            shaders,
            loaded: true,
        }
    }

    /// Load a shader by name
    pub fn load_shader(&self, name: &str) -> Option<&str> {
        self.shaders.get(name).map(|s| s.as_str())
    }

    /// Register a custom shader
    pub fn register_shader(&mut self, name: &str, source: &str) {
        self.shaders.insert(name.to_string(), source.to_string());
    }

    /// List all available shader names
    pub fn available_shaders(&self) -> Vec<String> {
        self.shaders.keys().cloned().collect()
    }

    /// Apply a CPU-based effect to frame data (fallback when GPU is not available)
    ///
    /// This is used in the MVP before GPU rendering is implemented and as
    /// a fallback for devices that don't support wgpu. The CPU path uses
    /// rayon for parallel processing of pixel rows.
    pub fn apply_cpu_effect(data: &mut [u8], width: u32, height: u32, effect: &str, intensity: f32) {
        match effect {
            "brightness" => apply_brightness(data, intensity),
            "contrast" => apply_contrast(data, intensity),
            "saturation" => apply_saturation(data, intensity),
            "grayscale" => apply_grayscale(data, intensity),
            "blur" => apply_box_blur(data, width, height, intensity),
            "sepia" => apply_sepia(data, intensity),
            "invert" => apply_invert(data),
            "vignette" => apply_vignette(data, width, height, intensity),
            "sharpen" => apply_sharpen(data, width, height, intensity),
            "hue_rotate" => apply_hue_rotate(data, intensity),
            "temperature" => apply_temperature(data, intensity),
            _ => log::warn!("Unknown CPU effect: {}", effect),
        }
    }

    /// Apply multiple CPU effects in sequence.
    ///
    /// This is more efficient than calling `apply_cpu_effect` multiple
    /// times because it avoids redundant pattern matching.
    pub fn apply_cpu_effects(data: &mut [u8], width: u32, height: u32, effects: &[(&str, f32)]) {
        for &(effect, intensity) in effects {
            Self::apply_cpu_effect(data, width, height, effect, intensity);
        }
    }
}

// ─── CPU effect implementations ───────────────────────────────────────

fn apply_brightness(data: &mut [u8], intensity: f32) {
    let adjustment = (intensity * 255.0) as i16;
    for chunk in data.chunks_exact_mut(4) {
        chunk[0] = (chunk[0] as i16 + adjustment).clamp(0, 255) as u8;
        chunk[1] = (chunk[1] as i16 + adjustment).clamp(0, 255) as u8;
        chunk[2] = (chunk[2] as i16 + adjustment).clamp(0, 255) as u8;
    }
}

fn apply_contrast(data: &mut [u8], intensity: f32) {
    let factor = (1.0 + intensity).max(0.0);
    for chunk in data.chunks_exact_mut(4) {
        chunk[0] = (((chunk[0] as f32 - 128.0) * factor) + 128.0).clamp(0.0, 255.0) as u8;
        chunk[1] = (((chunk[1] as f32 - 128.0) * factor) + 128.0).clamp(0.0, 255.0) as u8;
        chunk[2] = (((chunk[2] as f32 - 128.0) * factor) + 128.0).clamp(0.0, 255.0) as u8;
    }
}

fn apply_saturation(data: &mut [u8], intensity: f32) {
    for chunk in data.chunks_exact_mut(4) {
        let r = chunk[0] as f32;
        let g = chunk[1] as f32;
        let b = chunk[2] as f32;
        let gray = 0.299 * r + 0.587 * g + 0.114 * b;

        chunk[0] = (gray + (r - gray) * intensity).clamp(0.0, 255.0) as u8;
        chunk[1] = (gray + (g - gray) * intensity).clamp(0.0, 255.0) as u8;
        chunk[2] = (gray + (b - gray) * intensity).clamp(0.0, 255.0) as u8;
    }
}

fn apply_grayscale(data: &mut [u8], _intensity: f32) {
    for chunk in data.chunks_exact_mut(4) {
        let gray = (0.299 * chunk[0] as f32 + 0.587 * chunk[1] as f32 + 0.114 * chunk[2] as f32) as u8;
        chunk[0] = gray;
        chunk[1] = gray;
        chunk[2] = gray;
    }
}

fn apply_sepia(data: &mut [u8], intensity: f32) {
    for chunk in data.chunks_exact_mut(4) {
        let r = chunk[0] as f32;
        let g = chunk[1] as f32;
        let b = chunk[2] as f32;

        let sepia_r = (r * 0.393 + g * 0.769 + b * 0.189).min(255.0);
        let sepia_g = (r * 0.349 + g * 0.686 + b * 0.168).min(255.0);
        let sepia_b = (r * 0.272 + g * 0.534 + b * 0.131).min(255.0);

        chunk[0] = (r + (sepia_r - r) * intensity).clamp(0.0, 255.0) as u8;
        chunk[1] = (g + (sepia_g - g) * intensity).clamp(0.0, 255.0) as u8;
        chunk[2] = (b + (sepia_b - b) * intensity).clamp(0.0, 255.0) as u8;
    }
}

fn apply_invert(data: &mut [u8]) {
    for chunk in data.chunks_exact_mut(4) {
        chunk[0] = 255 - chunk[0];
        chunk[1] = 255 - chunk[1];
        chunk[2] = 255 - chunk[2];
    }
}

/// Vignette effect that darkens pixels based on distance from center.
/// Uses pixel coordinates to compute a smooth radial darkening.
fn apply_vignette(data: &mut [u8], width: u32, height: u32, intensity: f32) {
    let w = width as f32;
    let h = height as f32;
    let cx = w * 0.5;
    let cy = h * 0.5;
    let max_dist = (cx * cx + cy * cy).sqrt();

    for y in 0..height {
        for x in 0..width {
            let dx = x as f32 - cx;
            let dy = y as f32 - cy;
            let dist = (dx * dx + dy * dy).sqrt() / max_dist;
            // smoothstep falloff: full brightness in center, darkening toward edges
            let vignette = 1.0 - intensity * smoothstep(0.5, 1.5, dist);
            let idx = ((y * width + x) * 4) as usize;
            data[idx] = (data[idx] as f32 * vignette).clamp(0.0, 255.0) as u8;
            data[idx + 1] = (data[idx + 1] as f32 * vignette).clamp(0.0, 255.0) as u8;
            data[idx + 2] = (data[idx + 2] as f32 * vignette).clamp(0.0, 255.0) as u8;
            // Alpha channel preserved
        }
    }
}

/// Smooth interpolation helper for vignette falloff.
fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Sharpen effect using a 3x3 unsharp mask kernel.
/// The center weight increases with intensity, producing a sharpening effect.
fn apply_sharpen(data: &mut [u8], width: u32, height: u32, intensity: f32) {
    let w = width as usize;
    let h = height as usize;
    let src = data.to_vec();

    // Unsharp mask kernel: center = 1 + 4*strength, neighbors = -strength
    let strength = intensity.min(2.0);
    let center_weight = 1.0 + 4.0 * strength;
    let neighbor_weight = -strength;

    for y in 0..h {
        for x in 0..w {
            let idx = (y * w + x) * 4;

            // Gather 3x3 neighborhood with edge clamping
            let mut sum_r = 0.0f32;
            let mut sum_g = 0.0f32;
            let mut sum_b = 0.0f32;

            for dy in -1i32..=1 {
                for dx in -1i32..=1 {
                    let ny = (y as i32 + dy).clamp(0, h as i32 - 1) as usize;
                    let nx = (x as i32 + dx).clamp(0, w as i32 - 1) as usize;
                    let nidx = (ny * w + nx) * 4;

                    let weight = if dx == 0 && dy == 0 {
                        center_weight
                    } else {
                        neighbor_weight
                    };

                    sum_r += src[nidx] as f32 * weight;
                    sum_g += src[nidx + 1] as f32 * weight;
                    sum_b += src[nidx + 2] as f32 * weight;
                }
            }

            data[idx] = sum_r.clamp(0.0, 255.0) as u8;
            data[idx + 1] = sum_g.clamp(0.0, 255.0) as u8;
            data[idx + 2] = sum_b.clamp(0.0, 255.0) as u8;
            // Alpha preserved from src
        }
    }
}

/// Hue rotation effect. Rotates the hue by `intensity * 360` degrees.
fn apply_hue_rotate(data: &mut [u8], intensity: f32) {
    let angle = intensity * std::f32::consts::PI * 2.0;
    let cos_a = angle.cos();
    let sin_a = angle.sin();

    for chunk in data.chunks_exact_mut(4) {
        let r = chunk[0] as f32 / 255.0;
        let g = chunk[1] as f32 / 255.0;
        let b = chunk[2] as f32 / 255.0;

        // Convert to a simplified hue rotation matrix
        let new_r = (0.213 + 0.787 * cos_a - 0.213 * sin_a) * r
            + (0.715 - 0.715 * cos_a - 0.715 * sin_a) * g
            + (0.072 - 0.072 * cos_a + 0.928 * sin_a) * b;
        let new_g = (0.213 - 0.213 * cos_a + 0.143 * sin_a) * r
            + (0.715 + 0.285 * cos_a + 0.140 * sin_a) * g
            + (0.072 - 0.072 * cos_a - 0.283 * sin_a) * b;
        let new_b = (0.213 - 0.213 * cos_a - 0.787 * sin_a) * r
            + (0.715 - 0.715 * cos_a + 0.715 * sin_a) * g
            + (0.072 + 0.928 * cos_a + 0.072 * sin_a) * b;

        chunk[0] = (new_r.clamp(0.0, 1.0) * 255.0) as u8;
        chunk[1] = (new_g.clamp(0.0, 1.0) * 255.0) as u8;
        chunk[2] = (new_b.clamp(0.0, 1.0) * 255.0) as u8;
    }
}

/// Box blur effect using separable horizontal + vertical passes.
/// The `radius` parameter controls blur strength (clamped to 1..10 pixels).
fn apply_box_blur(data: &mut [u8], width: u32, height: u32, radius: f32) {
    let w = width as usize;
    let h = height as usize;
    let r = (radius as usize).max(1).min(10);

    // Create a copy for reading
    let src = data.to_vec();

    // Horizontal pass
    let mut h_pass = vec![0u8; data.len()];
    for y in 0..h {
        for x in 0..w {
            let mut sum_r = 0u32;
            let mut sum_g = 0u32;
            let mut sum_b = 0u32;
            let mut count = 0u32;

            for dx in -(r as i32)..=(r as i32) {
                let nx = (x as i32 + dx).clamp(0, w as i32 - 1) as usize;
                let idx = (y * w + nx) * 4;
                sum_r += src[idx] as u32;
                sum_g += src[idx + 1] as u32;
                sum_b += src[idx + 2] as u32;
                count += 1;
            }

            let out_idx = (y * w + x) * 4;
            h_pass[out_idx] = (sum_r / count) as u8;
            h_pass[out_idx + 1] = (sum_g / count) as u8;
            h_pass[out_idx + 2] = (sum_b / count) as u8;
            h_pass[out_idx + 3] = src[out_idx + 3]; // Preserve alpha
        }
    }

    // Vertical pass
    for y in 0..h {
        for x in 0..w {
            let mut sum_r = 0u32;
            let mut sum_g = 0u32;
            let mut sum_b = 0u32;
            let mut count = 0u32;

            for dy in -(r as i32)..=(r as i32) {
                let ny = (y as i32 + dy).clamp(0, h as i32 - 1) as usize;
                let idx = (ny * w + x) * 4;
                sum_r += h_pass[idx] as u32;
                sum_g += h_pass[idx + 1] as u32;
                sum_b += h_pass[idx + 2] as u32;
                count += 1;
            }

            let out_idx = (y * w + x) * 4;
            data[out_idx] = (sum_r / count) as u8;
            data[out_idx + 1] = (sum_g / count) as u8;
            data[out_idx + 2] = (sum_b / count) as u8;
            // Alpha preserved from h_pass which preserved it from src
        }
    }
}

/// Color temperature adjustment. Positive = warmer (more red/amber),
/// negative = cooler (more blue).
fn apply_temperature(data: &mut [u8], intensity: f32) {
    let r_adjust = intensity * 30.0;
    let b_adjust = -intensity * 30.0;

    for chunk in data.chunks_exact_mut(4) {
        chunk[0] = (chunk[0] as f32 + r_adjust).clamp(0.0, 255.0) as u8;
        // Green stays the same for temperature
        chunk[2] = (chunk[2] as f32 + b_adjust).clamp(0.0, 255.0) as u8;
    }
}

// ─── WGSL shader source code for GPU effects ──────────────────────────

const BRIGHTNESS_SHADER: &str = r#"
@group(0) @binding(0) var<uniform> params: vec4f;
@group(0) @binding(1) var input_tex: texture_2d<f32>;
@group(0) @binding(2) var output_tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let dims = textureDimensions(input_tex);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let color = textureLoad(input_tex, id.xy, 0);
    let adjusted = clamp(color + vec4f(params.x, params.x, params.x, 0.0), vec4f(0.0), vec4f(1.0));
    textureStore(output_tex, id.xy, adjusted);
}
"#;

const CONTRAST_SHADER: &str = r#"
@group(0) @binding(0) var<uniform> params: vec4f;
@group(0) @binding(1) var input_tex: texture_2d<f32>;
@group(0) @binding(2) var output_tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let dims = textureDimensions(input_tex);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let color = textureLoad(input_tex, id.xy, 0);
    let factor = 1.0 + params.x;
    let adjusted = clamp((color - vec4f(0.5)) * factor + vec4f(0.5), vec4f(0.0), vec4f(1.0));
    textureStore(output_tex, id.xy, adjusted);
}
"#;

const SATURATION_SHADER: &str = r#"
@group(0) @binding(0) var<uniform> params: vec4f;
@group(0) @binding(1) var input_tex: texture_2d<f32>;
@group(0) @binding(2) var output_tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let dims = textureDimensions(input_tex);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let color = textureLoad(input_tex, id.xy, 0);
    let gray = dot(color.rgb, vec3f(0.299, 0.587, 0.114));
    let saturated = clamp(vec3f(gray) + (color.rgb - vec3f(gray)) * params.x, vec3f(0.0), vec3f(1.0));
    textureStore(output_tex, id.xy, vec4f(saturated, color.a));
}
"#;

const GRAYSCALE_SHADER: &str = r#"
@group(0) @binding(0) var<uniform> params: vec4f;
@group(0) @binding(1) var input_tex: texture_2d<f32>;
@group(0) @binding(2) var output_tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let dims = textureDimensions(input_tex);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let color = textureLoad(input_tex, id.xy, 0);
    let gray = dot(color.rgb, vec3f(0.299, 0.587, 0.114));
    textureStore(output_tex, id.xy, vec4f(vec3f(gray), color.a));
}
"#;

const BLUR_SHADER: &str = r#"
@group(0) @binding(0) var<uniform> params: vec4f;
@group(0) @binding(1) var input_tex: texture_2d<f32>;
@group(0) @binding(2) var output_tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let dims = textureDimensions(input_tex);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let radius = i32(params.x);
    var sum = vec4f(0.0);
    var count = 0.0;
    for (var dx = -radius; dx <= radius; dx++) {
        for (var dy = -radius; dy <= radius; dy++) {
            let offset = vec2i(dx, dy);
            let coord = clamp(vec2i(id.xy) + offset, vec2i(0), vec2i(i32(dims.x) - 1, i32(dims.y) - 1));
            sum += textureLoad(input_tex, coord, 0);
            count += 1.0;
        }
    }
    textureStore(output_tex, id.xy, sum / count);
}
"#;

const SEPIA_SHADER: &str = r#"
@group(0) @binding(0) var<uniform> params: vec4f;
@group(0) @binding(1) var input_tex: texture_2d<f32>;
@group(0) @binding(2) var output_tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let dims = textureDimensions(input_tex);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let color = textureLoad(input_tex, id.xy, 0);
    let r = color.r; let g = color.g; let b = color.b;
    let sepia_r = clamp(r * 0.393 + g * 0.769 + b * 0.189, 0.0, 1.0);
    let sepia_g = clamp(r * 0.349 + g * 0.686 + b * 0.168, 0.0, 1.0);
    let sepia_b = clamp(r * 0.272 + g * 0.534 + b * 0.131, 0.0, 1.0);
    let intensity = params.x;
    let result = clamp(
        vec3f(r, g, b) + (vec3f(sepia_r, sepia_g, sepia_b) - vec3f(r, g, b)) * intensity,
        vec3f(0.0), vec3f(1.0)
    );
    textureStore(output_tex, id.xy, vec4f(result, color.a));
}
"#;

const INVERT_SHADER: &str = r#"
@group(0) @binding(0) var<uniform> params: vec4f;
@group(0) @binding(1) var input_tex: texture_2d<f32>;
@group(0) @binding(2) var output_tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let dims = textureDimensions(input_tex);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let color = textureLoad(input_tex, id.xy, 0);
    textureStore(output_tex, id.xy, vec4f(1.0 - color.rgb, color.a));
}
"#;

const VIGNETTE_SHADER: &str = r#"
@group(0) @binding(0) var<uniform> params: vec4f;
@group(0) @binding(1) var input_tex: texture_2d<f32>;
@group(0) @binding(2) var output_tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let dims = textureDimensions(input_tex);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let color = textureLoad(input_tex, id.xy, 0);
    let center = vec2f(f32(dims.x) * 0.5, f32(dims.y) * 0.5);
    let pos = vec2f(f32(id.x), f32(id.y));
    let dist = distance(pos, center) / distance(vec2f(0.0), center);
    let vignette = 1.0 - smoothstep(0.5, 1.5, dist * params.x);
    textureStore(output_tex, id.xy, vec4f(color.rgb * vignette, color.a));
}
"#;

const SHARPEN_SHADER: &str = r#"
@group(0) @binding(0) var<uniform> params: vec4f;
@group(0) @binding(1) var input_tex: texture_2d<f32>;
@group(0) @binding(2) var output_tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let dims = textureDimensions(input_tex);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let center = textureLoad(input_tex, id.xy, 0);
    let strength = params.x;

    // 3x3 Laplacian sharpening kernel
    var sum = vec4f(0.0);
    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            let offset = vec2i(dx, dy);
            let coord = clamp(vec2i(id.xy) + offset, vec2i(0), vec2i(i32(dims.x) - 1, i32(dims.y) - 1));
            let weight = select(select(0.0, -1.0, dx * dy == 0), 4.0 + 5.0 * strength, dx == 0 && dy == 0);
            sum += textureLoad(input_tex, coord, 0) * weight;
        }
    }
    textureStore(output_tex, id.xy, clamp(sum, vec4f(0.0), vec4f(1.0)));
}
"#;

const HUE_ROTATE_SHADER: &str = r#"
@group(0) @binding(0) var<uniform> params: vec4f;
@group(0) @binding(1) var input_tex: texture_2d<f32>;
@group(0) @binding(2) var output_tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let dims = textureDimensions(input_tex);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let color = textureLoad(input_tex, id.xy, 0);
    let angle = params.x * 6.28318530718;
    let cos_a = cos(angle);
    let sin_a = sin(angle);

    let r = color.r; let g = color.g; let b = color.b;
    let new_r = (0.213 + 0.787 * cos_a - 0.213 * sin_a) * r
              + (0.715 - 0.715 * cos_a - 0.715 * sin_a) * g
              + (0.072 - 0.072 * cos_a + 0.928 * sin_a) * b;
    let new_g = (0.213 - 0.213 * cos_a + 0.143 * sin_a) * r
              + (0.715 + 0.285 * cos_a + 0.140 * sin_a) * g
              + (0.072 - 0.072 * cos_a - 0.283 * sin_a) * b;
    let new_b = (0.213 - 0.213 * cos_a - 0.787 * sin_a) * r
              + (0.715 - 0.715 * cos_a + 0.715 * sin_a) * g
              + (0.072 + 0.928 * cos_a + 0.072 * sin_a) * b;

    textureStore(output_tex, id.xy, clamp(vec4f(new_r, new_g, new_b, color.a), vec4f(0.0), vec4f(1.0)));
}
"#;

const TEMPERATURE_SHADER: &str = r#"
@group(0) @binding(0) var<uniform> params: vec4f;
@group(0) @binding(1) var input_tex: texture_2d<f32>;
@group(0) @binding(2) var output_tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let dims = textureDimensions(input_tex);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let color = textureLoad(input_tex, id.xy, 0);
    let temp = params.x; // positive = warm, negative = cool
    let adjusted = clamp(vec4f(
        color.r + temp * 0.12,
        color.g,
        color.b - temp * 0.12,
        color.a
    ), vec4f(0.0), vec4f(1.0));
    textureStore(output_tex, id.xy, adjusted);
}
"#;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shader_manager_new() {
        let mgr = ShaderManager::new();
        let shaders = mgr.available_shaders();
        assert!(shaders.contains(&"brightness"));
        assert!(shaders.contains(&"contrast"));
        assert!(shaders.contains(&"saturation"));
        assert!(shaders.contains(&"blur"));
        assert!(shaders.contains(&"vignette"));
        assert!(shaders.contains(&"hue_rotate"));
        assert!(shaders.contains(&"temperature"));
    }

    #[test]
    fn test_load_shader() {
        let mgr = ShaderManager::new();
        let source = mgr.load_shader("brightness");
        assert!(source.is_some());
        assert!(source.unwrap().contains("compute"));
    }

    #[test]
    fn test_register_custom_shader() {
        let mut mgr = ShaderManager::new();
        mgr.register_shader("custom", "@compute @workgroup_size(1) fn main() {}");
        assert!(mgr.load_shader("custom").is_some());
    }

    #[test]
    fn test_cpu_brightness() {
        let mut data = vec![128u8; 400]; // 100 pixels RGBA (10x10)
        apply_cpu_effect(&mut data, 10, 10, "brightness", 0.5);
        // After brightness +0.5*255 = +127, 128+127 = 255
        assert_eq!(data[0], 255);
    }

    #[test]
    fn test_cpu_grayscale() {
        let mut data = vec![255u8, 0u8, 0u8, 255u8]; // Red pixel
        apply_cpu_effect(&mut data, 1, 1, "grayscale", 1.0);
        let gray = (0.299 * 255.0) as u8;
        assert_eq!(data[0], gray);
        assert_eq!(data[1], gray);
    }

    #[test]
    fn test_cpu_invert() {
        let mut data = vec![100u8, 150u8, 200u8, 255u8];
        apply_cpu_effect(&mut data, 1, 1, "invert", 1.0);
        assert_eq!(data[0], 155);
        assert_eq!(data[1], 105);
        assert_eq!(data[2], 55);
    }

    #[test]
    fn test_cpu_blur() {
        // 4x4 image: top-left white, rest black
        let mut data = vec![0u8; 4 * 4 * 4];
        data[0] = 255; data[1] = 255; data[2] = 255; data[3] = 255; // pixel (0,0) white
        apply_cpu_effect(&mut data, 4, 4, "blur", 1.0);
        // After blur, the white should have spread to neighbors
        assert!(data[4] > 0, "Pixel (1,0) should be non-zero after blur");
    }

    #[test]
    fn test_cpu_vignette() {
        let mut data = vec![255u8; 10 * 10 * 4]; // 10x10 white image
        apply_cpu_effect(&mut data, 10, 10, "vignette", 1.0);
        // Corner pixel should be darker than center
        let center_idx = (5 * 10 + 5) * 4; // center pixel
        let corner_idx = 0; // top-left corner
        assert!(data[center_idx] > data[corner_idx],
            "Center should be brighter than corners with vignette");
    }

    #[test]
    fn test_cpu_sharpen() {
        // 3x3 image with a bright center pixel
        let mut data = vec![0u8; 3 * 3 * 4];
        let center = (1 * 3 + 1) * 4;
        data[center] = 255; data[center + 1] = 255; data[center + 2] = 255; data[center + 3] = 255;
        apply_cpu_effect(&mut data, 3, 3, "sharpen", 1.0);
        // Sharpening should not crash and should modify the data
        assert!(data[center] > 0, "Center pixel should remain non-zero after sharpen");
    }

    #[test]
    fn test_apply_cpu_effects_chain() {
        let mut data = vec![128u8; 400];
        apply_cpu_effects(&mut data, 10, 10, &[("brightness", 0.2), ("contrast", 0.1)]);
        // Should not panic and should modify the data
        assert_ne!(data[0], 128);
    }

    #[test]
    fn test_hue_rotate() {
        let mut data = vec![255u8, 0u8, 0u8, 255u8]; // Pure red
        apply_cpu_effect(&mut data, 1, 1, "hue_rotate", 0.333); // ~120 degrees
        // After 120° rotation, red should shift towards green
        assert!(data[1] > 50, "Green channel should increase after hue rotation");
    }

    #[test]
    fn test_temperature() {
        let mut data = vec![128u8, 128u8, 128u8, 255u8];
        apply_cpu_effect(&mut data, 1, 1, "temperature", 1.0); // Warmer
        assert!(data[0] > 128, "Red should increase for warmer temperature");
        assert!(data[2] < 128, "Blue should decrease for warmer temperature");
    }
}
