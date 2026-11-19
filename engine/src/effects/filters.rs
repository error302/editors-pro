//! Filter effects - Color adjustments and visual filters
//!
//! Provides a catalog of built-in filters that can be applied to video frames.
//! All pixel-level operations use rayon for parallel processing to achieve
//! real-time preview performance on mobile devices.

use rayon::prelude::*;

use serde::{Deserialize, Serialize};

use super::{Effect, EffectParameter, EffectType};

/// Built-in filter types
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum FilterType {
    Brightness,
    Contrast,
    Saturation,
    Hue,
    Blur,
    Sharpen,
    Grayscale,
    Sepia,
    Invert,
    Vignette,
    Temperature,
}

impl FilterType {
    /// Get the display name for this filter
    pub fn display_name(&self) -> &str {
        match self {
            FilterType::Brightness => "Brightness",
            FilterType::Contrast => "Contrast",
            FilterType::Saturation => "Saturation",
            FilterType::Hue => "Hue",
            FilterType::Blur => "Blur",
            FilterType::Sharpen => "Sharpen",
            FilterType::Grayscale => "Grayscale",
            FilterType::Sepia => "Sepia",
            FilterType::Invert => "Invert",
            FilterType::Vignette => "Vignette",
            FilterType::Temperature => "Temperature",
        }
    }

    /// Get an icon identifier for UI rendering
    pub fn icon(&self) -> &str {
        match self {
            FilterType::Brightness => "brightness",
            FilterType::Contrast => "contrast",
            FilterType::Saturation => "saturation",
            FilterType::Hue => "hue",
            FilterType::Blur => "blur",
            FilterType::Sharpen => "sharpen",
            FilterType::Grayscale => "grayscale",
            FilterType::Sepia => "sepia",
            FilterType::Invert => "invert",
            FilterType::Vignette => "vignette",
            FilterType::Temperature => "temperature",
        }
    }

    /// Create an Effect instance for this filter type
    pub fn to_effect(&self) -> Effect {
        let params = self.default_parameters();
        Effect {
            id: uuid::Uuid::new_v4().to_string(),
            name: self.display_name().to_string(),
            effect_type: EffectType::Filter,
            enabled: true,
            order: 0,
            parameters: params,
        }
    }

    /// Get the default parameters for this filter
    pub fn default_parameters(&self) -> Vec<EffectParameter> {
        match self {
            FilterType::Brightness => vec![
                EffectParameter::new("brightness", "Brightness", 0.0, -1.0, 1.0, 0.01),
            ],
            FilterType::Contrast => vec![
                EffectParameter::new("contrast", "Contrast", 0.0, -1.0, 1.0, 0.01),
            ],
            FilterType::Saturation => vec![
                EffectParameter::new("saturation", "Saturation", 1.0, 0.0, 3.0, 0.01),
            ],
            FilterType::Hue => vec![
                EffectParameter::new("hue", "Hue Shift", 0.0, -180.0, 180.0, 1.0),
            ],
            FilterType::Blur => vec![
                EffectParameter::new("blur", "Blur Radius", 0.0, 0.0, 20.0, 0.5),
            ],
            FilterType::Sharpen => vec![
                EffectParameter::new("sharpen", "Sharpness", 0.0, 0.0, 2.0, 0.05),
            ],
            FilterType::Grayscale => vec![
                EffectParameter::new("grayscale", "Intensity", 1.0, 0.0, 1.0, 0.01),
            ],
            FilterType::Sepia => vec![
                EffectParameter::new("sepia", "Intensity", 1.0, 0.0, 1.0, 0.01),
            ],
            FilterType::Invert => vec![],
            FilterType::Vignette => vec![
                EffectParameter::new("vignette", "Intensity", 0.5, 0.0, 1.0, 0.01),
                EffectParameter::new("vignette_radius", "Radius", 0.5, 0.0, 1.0, 0.01),
            ],
            FilterType::Temperature => vec![
                EffectParameter::new("temperature", "Temperature", 0.0, -1.0, 1.0, 0.01),
            ],
        }
    }

    /// Get all available filter types
    pub fn all_filters() -> Vec<FilterType> {
        vec![
            FilterType::Brightness,
            FilterType::Contrast,
            FilterType::Saturation,
            FilterType::Hue,
            FilterType::Blur,
            FilterType::Sharpen,
            FilterType::Grayscale,
            FilterType::Sepia,
            FilterType::Invert,
            FilterType::Vignette,
            FilterType::Temperature,
        ]
    }

    /// Apply this filter to RGBA frame data using rayon for parallelism
    ///
    /// `data` is mutable RGBA pixel data, `width` and `height` describe
    /// the frame dimensions. Parameters are taken from the `params` slice.
    pub fn apply_to_frame(&self, data: &mut [u8], width: u32, height: u32, params: &[EffectParameter]) {
        match self {
            FilterType::Brightness => {
                let brightness = param_value(params, "brightness", 0.0);
                apply_brightness(data, brightness);
            }
            FilterType::Contrast => {
                let contrast = param_value(params, "contrast", 0.0);
                apply_contrast(data, contrast);
            }
            FilterType::Saturation => {
                let saturation = param_value(params, "saturation", 1.0);
                apply_saturation(data, saturation);
            }
            FilterType::Hue => {
                let hue_shift = param_value(params, "hue", 0.0);
                apply_hue(data, hue_shift);
            }
            FilterType::Blur => {
                let radius = param_value(params, "blur", 0.0);
                if radius > 0.0 {
                    apply_box_blur(data, width, height, radius);
                }
            }
            FilterType::Sharpen => {
                let amount = param_value(params, "sharpen", 0.0);
                if amount > 0.0 {
                    apply_sharpen(data, width, height, amount);
                }
            }
            FilterType::Grayscale => {
                let intensity = param_value(params, "grayscale", 1.0);
                apply_grayscale(data, intensity);
            }
            FilterType::Sepia => {
                let intensity = param_value(params, "sepia", 1.0);
                apply_sepia(data, intensity);
            }
            FilterType::Invert => {
                apply_invert(data);
            }
            FilterType::Vignette => {
                let intensity = param_value(params, "vignette", 0.5);
                let radius = param_value(params, "vignette_radius", 0.5);
                apply_vignette(data, width, height, intensity, radius);
            }
            FilterType::Temperature => {
                let temperature = param_value(params, "temperature", 0.0);
                apply_temperature(data, temperature);
            }
        }
    }
}

/// Helper to extract a parameter value from the params slice
fn param_value(params: &[EffectParameter], name: &str, default: f32) -> f32 {
    params.iter().find(|p| p.name == name).map(|p| p.value).unwrap_or(default)
}

// ─── Rayon-parallel filter implementations ──────────────────────────

/// Apply brightness adjustment using rayon for parallel pixel processing.
///
/// `intensity` ranges from -1.0 (fully dark) to +1.0 (fully bright).
fn apply_brightness(data: &mut [u8], intensity: f32) {
    let adjustment = (intensity * 255.0) as i16;
    data.par_chunks_exact_mut(4).for_each(|pixel| {
        pixel[0] = (pixel[0] as i16 + adjustment).clamp(0, 255) as u8;
        pixel[1] = (pixel[1] as i16 + adjustment).clamp(0, 255) as u8;
        pixel[2] = (pixel[2] as i16 + adjustment).clamp(0, 255) as u8;
        // Alpha stays unchanged
    });
}

/// Apply contrast adjustment using rayon for parallel pixel processing.
///
/// `intensity` ranges from -1.0 (low contrast) to +1.0 (high contrast).
fn apply_contrast(data: &mut [u8], intensity: f32) {
    let factor = (1.0 + intensity).max(0.0);
    data.par_chunks_exact_mut(4).for_each(|pixel| {
        pixel[0] = (((pixel[0] as f32 - 128.0) * factor) + 128.0).clamp(0.0, 255.0) as u8;
        pixel[1] = (((pixel[1] as f32 - 128.0) * factor) + 128.0).clamp(0.0, 255.0) as u8;
        pixel[2] = (((pixel[2] as f32 - 128.0) * factor) + 128.0).clamp(0.0, 255.0) as u8;
    });
}

/// Apply saturation adjustment using rayon for parallel pixel processing.
///
/// `intensity` of 0.0 = grayscale, 1.0 = normal, >1.0 = oversaturated.
fn apply_saturation(data: &mut [u8], intensity: f32) {
    data.par_chunks_exact_mut(4).for_each(|pixel| {
        let r = pixel[0] as f32;
        let g = pixel[1] as f32;
        let b = pixel[2] as f32;
        let gray = 0.299 * r + 0.587 * g + 0.114 * b;

        pixel[0] = (gray + (r - gray) * intensity).clamp(0.0, 255.0) as u8;
        pixel[1] = (gray + (g - gray) * intensity).clamp(0.0, 255.0) as u8;
        pixel[2] = (gray + (b - gray) * intensity).clamp(0.0, 255.0) as u8;
    });
}

/// Apply hue rotation using rayon for parallel pixel processing.
///
/// Converts each pixel to HSL, shifts the hue, then converts back.
/// `shift` is in degrees (-180 to +180).
fn apply_hue(data: &mut [u8], shift: f32) {
    if shift == 0.0 { return; }

    data.par_chunks_exact_mut(4).for_each(|pixel| {
        let r = pixel[0] as f32 / 255.0;
        let g = pixel[1] as f32 / 255.0;
        let b = pixel[2] as f32 / 255.0;

        let max = r.max(g).max(b);
        let min = r.min(g).min(b);
        let delta = max - min;

        // Lightness
        let l = (max + min) / 2.0;

        if delta == 0.0 {
            // No hue to shift (achromatic)
            return;
        }

        // Saturation
        let s = if l > 0.5 {
            delta / (2.0 - max - min)
        } else {
            delta / (max + min)
        };

        // Hue
        let h = if (max - r).abs() < f32::EPSILON {
            60.0 * (((g - b) / delta) % 6.0)
        } else if (max - g).abs() < f32::EPSILON {
            60.0 * (((b - r) / delta) + 2.0)
        } else {
            60.0 * (((r - g) / delta) + 4.0)
        };

        let new_h = ((h + shift) % 360.0 + 360.0) % 360.0;

        // Convert HSL back to RGB
        let c = (1.0 - (2.0 * l - 1.0).abs()) * s;
        let x = c * (1.0 - ((new_h / 60.0) % 2.0 - 1.0).abs());
        let m = l - c / 2.0;

        let (r1, g1, b1) = if new_h < 60.0 {
            (c, x, 0.0)
        } else if new_h < 120.0 {
            (x, c, 0.0)
        } else if new_h < 180.0 {
            (0.0, c, x)
        } else if new_h < 240.0 {
            (0.0, x, c)
        } else if new_h < 300.0 {
            (x, 0.0, c)
        } else {
            (c, 0.0, x)
        };

        pixel[0] = ((r1 + m) * 255.0).clamp(0.0, 255.0) as u8;
        pixel[1] = ((g1 + m) * 255.0).clamp(0.0, 255.0) as u8;
        pixel[2] = ((b1 + m) * 255.0).clamp(0.0, 255.0) as u8;
    });
}

/// Apply box blur using a two-pass separable filter with rayon.
///
/// `radius` controls the blur kernel size (0.0 = no blur, 20.0 = max).
/// Uses a horizontal + vertical pass for O(n) per pixel instead of O(n²).
fn apply_box_blur(data: &mut [u8], width: u32, height: u32, radius: f32) {
    // A centered box kernel must have an odd width. Fractional radii used
    // to produce an even kernel, moving highlights down and right.
    let kernel_size = radius.ceil() as usize * 2 + 1;
    if kernel_size < 2 { return; }
    // Fractional radii weight the two outside samples equally, retaining
    // the half-step strength control without introducing a spatial shift.
    let weights: Vec<f32> = (0..kernel_size)
        .map(|k| (radius + 1.0 - k.abs_diff(kernel_size / 2) as f32).clamp(0.0, 1.0))
        .collect();

    let w = width as usize;
    let h = height as usize;

    // Create a working buffer for the intermediate result
    let mut temp = vec![0u8; data.len()];

    // Horizontal pass: read from `data`, write to `temp`
    let half = kernel_size / 2;
    for y in 0..h {
        for x in 0..w {
            let mut r_sum = 0.0;
            let mut g_sum = 0.0;
            let mut b_sum = 0.0;
            let mut count = 0.0;

            for (k, &weight) in weights.iter().enumerate() {
                let nx = x as isize + k as isize - half as isize;
                if nx >= 0 && nx < w as isize {
                    let idx = (y * w + nx as usize) * 4;
                    r_sum += data[idx] as f32 * weight;
                    g_sum += data[idx + 1] as f32 * weight;
                    b_sum += data[idx + 2] as f32 * weight;
                    count += weight;
                }
            }

            let out_idx = (y * w + x) * 4;
            temp[out_idx] = (r_sum / count) as u8;
            temp[out_idx + 1] = (g_sum / count) as u8;
            temp[out_idx + 2] = (b_sum / count) as u8;
            temp[out_idx + 3] = data[out_idx + 3];
        }
    }

    // Vertical pass: read from `temp`, write to `data`
    for y in 0..h {
        for x in 0..w {
            let mut r_sum = 0.0;
            let mut g_sum = 0.0;
            let mut b_sum = 0.0;
            let mut count = 0.0;

            for (k, &weight) in weights.iter().enumerate() {
                let ny = y as isize + k as isize - half as isize;
                if ny >= 0 && ny < h as isize {
                    let idx = (ny as usize * w + x) * 4;
                    r_sum += temp[idx] as f32 * weight;
                    g_sum += temp[idx + 1] as f32 * weight;
                    b_sum += temp[idx + 2] as f32 * weight;
                    count += weight;
                }
            }

            let out_idx = (y * w + x) * 4;
            data[out_idx] = (r_sum / count) as u8;
            data[out_idx + 1] = (g_sum / count) as u8;
            data[out_idx + 2] = (b_sum / count) as u8;
            // Alpha unchanged
        }
    }
}

/// Apply sharpening using an unsharp mask approach.
///
/// `amount` ranges from 0.0 (no sharpening) to 2.0 (maximum sharpness).
/// The algorithm subtracts a blurred version from the original, then
/// adds back the difference scaled by the amount.
fn apply_sharpen(data: &mut [u8], width: u32, height: u32, amount: f32) {
    let w = width as usize;
    let h = height as usize;

    // Create a blurred copy (3x3 box blur)
    let original = data.to_vec();
    let mut blurred = vec![0u8; data.len()];

    for y in 0..h {
        for x in 0..w {
            let mut r_sum = 0u32;
            let mut g_sum = 0u32;
            let mut b_sum = 0u32;
            let mut count = 0u32;

            for dy in -1i32..=1 {
                for dx in -1i32..=1 {
                    let nx = (x as i32 + dx).clamp(0, w as i32 - 1) as usize;
                    let ny = (y as i32 + dy).clamp(0, h as i32 - 1) as usize;
                    let idx = (ny * w + nx) * 4;
                    r_sum += original[idx] as u32;
                    g_sum += original[idx + 1] as u32;
                    b_sum += original[idx + 2] as u32;
                    count += 1;
                }
            }

            let out_idx = (y * w + x) * 4;
            blurred[out_idx] = (r_sum / count) as u8;
            blurred[out_idx + 1] = (g_sum / count) as u8;
            blurred[out_idx + 2] = (b_sum / count) as u8;
            blurred[out_idx + 3] = original[out_idx + 3];
        }
    }

    // Apply unsharp mask: result = original + amount * (original - blurred)
    data.par_chunks_exact_mut(4).enumerate().for_each(|(i, pixel)| {
        let idx = i * 4;
        let orig_r = original[idx] as f32;
        let orig_g = original[idx + 1] as f32;
        let orig_b = original[idx + 2] as f32;
        let blur_r = blurred[idx] as f32;
        let blur_g = blurred[idx + 1] as f32;
        let blur_b = blurred[idx + 2] as f32;

        pixel[0] = (orig_r + amount * (orig_r - blur_r)).clamp(0.0, 255.0) as u8;
        pixel[1] = (orig_g + amount * (orig_g - blur_g)).clamp(0.0, 255.0) as u8;
        pixel[2] = (orig_b + amount * (orig_b - blur_b)).clamp(0.0, 255.0) as u8;
    });
}

/// Apply grayscale using rayon for parallel pixel processing.
///
/// `intensity` controls the blend between original and grayscale (1.0 = full grayscale).
fn apply_grayscale(data: &mut [u8], intensity: f32) {
    data.par_chunks_exact_mut(4).for_each(|pixel| {
        let gray = (0.299 * pixel[0] as f32 + 0.587 * pixel[1] as f32 + 0.114 * pixel[2] as f32) as u8;
        pixel[0] = (pixel[0] as f32 + (gray as f32 - pixel[0] as f32) * intensity) as u8;
        pixel[1] = (pixel[1] as f32 + (gray as f32 - pixel[1] as f32) * intensity) as u8;
        pixel[2] = (pixel[2] as f32 + (gray as f32 - pixel[2] as f32) * intensity) as u8;
    });
}

/// Apply sepia tone using rayon for parallel pixel processing.
///
/// `intensity` controls the blend between original and sepia (1.0 = full sepia).
fn apply_sepia(data: &mut [u8], intensity: f32) {
    data.par_chunks_exact_mut(4).for_each(|pixel| {
        let r = pixel[0] as f32;
        let g = pixel[1] as f32;
        let b = pixel[2] as f32;

        let sepia_r = (r * 0.393 + g * 0.769 + b * 0.189).min(255.0);
        let sepia_g = (r * 0.349 + g * 0.686 + b * 0.168).min(255.0);
        let sepia_b = (r * 0.272 + g * 0.534 + b * 0.131).min(255.0);

        pixel[0] = (r + (sepia_r - r) * intensity).clamp(0.0, 255.0) as u8;
        pixel[1] = (g + (sepia_g - g) * intensity).clamp(0.0, 255.0) as u8;
        pixel[2] = (b + (sepia_b - b) * intensity).clamp(0.0, 255.0) as u8;
    });
}

/// Apply color inversion using rayon for parallel pixel processing.
fn apply_invert(data: &mut [u8]) {
    data.par_chunks_exact_mut(4).for_each(|pixel| {
        pixel[0] = 255 - pixel[0];
        pixel[1] = 255 - pixel[1];
        pixel[2] = 255 - pixel[2];
    });
}

/// Apply vignette effect — darkens edges of the frame.
///
/// `intensity` controls how dark the edges become (0.0 = no darkening, 1.0 = fully black).
/// `radius` controls the size of the unaffected center (0.0 = tiny center, 1.0 = no vignette).
fn apply_vignette(data: &mut [u8], width: u32, height: u32, intensity: f32, radius: f32) {
    // Pixel coordinates span 0..width-1, not 0..width. Keep opposite
    // corners equidistant from the optical center on even and odd frames.
    let cx = width.saturating_sub(1) as f32 / 2.0;
    let cy = height.saturating_sub(1) as f32 / 2.0;
    let max_dist = (cx * cx + cy * cy).sqrt();
    let inner_radius = max_dist * radius;
    let outer_radius = max_dist;

    data.par_chunks_exact_mut(4).enumerate().for_each(|(pixel_idx, pixel)| {
        let x = (pixel_idx % (width as usize)) as f32;
        let y = (pixel_idx / (width as usize)) as f32;

        let dx = x - cx;
        let dy = y - cy;
        let dist = (dx * dx + dy * dy).sqrt();

        let factor = if dist <= inner_radius {
            1.0
        } else if dist >= outer_radius {
            1.0 - intensity
        } else {
            let t = (dist - inner_radius) / (outer_radius - inner_radius);
            1.0 - intensity * t
        };

        pixel[0] = (pixel[0] as f32 * factor).clamp(0.0, 255.0) as u8;
        pixel[1] = (pixel[1] as f32 * factor).clamp(0.0, 255.0) as u8;
        pixel[2] = (pixel[2] as f32 * factor).clamp(0.0, 255.0) as u8;
    });
}

/// Apply color temperature shift using rayon for parallel pixel processing.
///
/// Positive values add warm (orange/red) tones; negative values add cool (blue) tones.
/// Range: -1.0 (cool) to +1.0 (warm).
fn apply_temperature(data: &mut [u8], temperature: f32) {
    let r_adj = temperature * 30.0;
    let b_adj = -temperature * 30.0;

    data.par_chunks_exact_mut(4).for_each(|pixel| {
        pixel[0] = (pixel[0] as f32 + r_adj).clamp(0.0, 255.0) as u8;
        pixel[2] = (pixel[2] as f32 + b_adj).clamp(0.0, 255.0) as u8;
        // Green channel stays unchanged for natural temperature shifts
    });
}

/// Preset filter combinations for quick application
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilterPreset {
    pub id: String,
    pub name: String,
    pub description: String,
    pub filters: Vec<FilterType>,
    pub parameter_overrides: Vec<(String, f32)>,
}

impl FilterPreset {
    /// Restrained recipes using the same implemented filters as manual adjustments.
    pub fn built_in_presets() -> Vec<FilterPreset> {
        use FilterType::*;
        let recipe = |id: &str, name: &str, description: &str, filters, values: Vec<(&str, f32)>| FilterPreset {
            id: id.into(), name: name.into(), description: description.into(), filters,
            parameter_overrides: values.into_iter().map(|(key, value)| (key.into(), value)).collect(),
        };
        vec![
            recipe("clean", "Clean", "Subtle brightness, contrast and color", vec![Brightness, Contrast, Saturation],
                vec![("brightness", 0.012), ("contrast", 0.04), ("saturation", 1.04)]),
            recipe("cinematic", "Cinematic", "Muted color, gentle warmth and contrast", vec![Temperature, Saturation, Contrast],
                vec![("temperature", 0.10), ("saturation", 0.88), ("contrast", 0.10)]),
            recipe("vintage", "Vintage", "Soft contrast with a light sepia tint", vec![Sepia, Contrast, Brightness],
                vec![("sepia", 0.22), ("contrast", -0.07), ("brightness", 0.025)]),
            recipe("dramatic", "Dramatic", "Deeper contrast, richer color and soft dark edges", vec![Contrast, Saturation, Vignette],
                vec![("contrast", 0.20), ("saturation", 1.08), ("vignette", 0.18), ("vignette_radius", 0.65)]),
            recipe("cool", "Cool", "A restrained blue tint with gentle contrast", vec![Temperature, Contrast],
                vec![("temperature", -0.18), ("contrast", 0.05)]),
            recipe("warm", "Warm", "Gentle golden warmth with richer color", vec![Temperature, Saturation],
                vec![("temperature", 0.18), ("saturation", 1.07)]),
            recipe("noir", "Noir", "Black and white with contrast and soft dark edges", vec![Grayscale, Contrast, Vignette],
                vec![("grayscale", 1.0), ("contrast", 0.16), ("vignette", 0.14), ("vignette_radius", 0.65)]),
            recipe("soft_film", "Soft Film", "Lifted shadows, softer contrast and muted color", vec![Contrast, Brightness, Saturation],
                vec![("contrast", -0.12), ("brightness", 0.015), ("saturation", 0.92)]),
        ]
    }

    pub fn to_effects(&self) -> Vec<Effect> {
        self.to_effects_with_intensity(1.0, true).expect("valid full-strength recipe")
    }

    /// Look membership and recipe metadata survive project serialization in the
    /// existing effect ID/parameter contract, including older .epp readers.
    pub fn to_effects_with_intensity(&self, intensity: f32, enabled: bool) -> Result<Vec<Effect>, String> {
        if !intensity.is_finite() || !(0.0..=1.0).contains(&intensity) {
            return Err("Look intensity must be a finite number from 0 to 1".into());
        }
        self.filters.iter().enumerate().map(|(i, filter_type)| {
            let mut effect = filter_type.to_effect();
            effect.id = format!("look:{}:{}", self.id, effect.id);
            effect.enabled = enabled;
            effect.order = i as u32;
            for (name, target) in &self.parameter_overrides {
                if let Some(parameter) = effect.parameters.iter_mut().find(|p| p.name == *name) {
                    let neutral = match name.as_str() {
                        "saturation" => 1.0,
                        "vignette_radius" => *target,
                        _ => 0.0,
                    };
                    parameter.set_value(neutral + (*target - neutral) * intensity);
                }
            }
            effect.parameters.push(EffectParameter::new("__look_intensity", "Look intensity", intensity, 0.0, 1.0, 0.01));
            effect.parameters.push(EffectParameter::new("__look_version", "Recipe version", 1.0, 1.0, 1.0, 1.0));
            Ok(effect)
        }).collect()
    }
}

/// Group membership is explicit and never inferred from a filter's display name.
pub fn is_look_effect(effect: &Effect) -> bool {
    effect.id.starts_with("look:")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_white_frame(w: u32, h: u32) -> Vec<u8> {
        vec![255u8; (w * h * 4) as usize]
    }

    fn make_test_frame(w: u32, h: u32) -> Vec<u8> {
        let mut data = Vec::with_capacity((w * h * 4) as usize);
        for y in 0..h {
            for x in 0..w {
                data.push((x * 255 / w) as u8); // R
                data.push((y * 255 / h) as u8); // G
                data.push(128); // B
                data.push(255); // A
            }
        }
        data
    }

    #[test]
    fn test_brightness_positive_on_white_stays_white() {
        let mut data = make_white_frame(100, 100);
        apply_brightness(&mut data, 1.0);
        for chunk in data.chunks_exact(4) {
            assert_eq!(chunk[0], 255);
            assert_eq!(chunk[1], 255);
            assert_eq!(chunk[2], 255);
        }
    }

    #[test]
    fn test_brightness_negative_on_white() {
        let mut data = make_white_frame(100, 100);
        apply_brightness(&mut data, -0.5);
        for chunk in data.chunks_exact(4) {
            assert!(chunk[0] < 255);
            assert!(chunk[1] < 255);
            assert!(chunk[2] < 255);
        }
    }

    #[test]
    fn test_contrast_zero_no_change() {
        let mut data = make_test_frame(100, 100);
        let original = data.clone();
        apply_contrast(&mut data, 0.0);
        // With zero contrast change, factor is 1.0 — values stay the same
        for (a, b) in data.iter().zip(original.iter()) {
            assert_eq!(*a, *b);
        }
    }

    #[test]
    fn test_saturation_zero_produces_grayscale() {
        let mut data = make_test_frame(100, 100);
        apply_saturation(&mut data, 0.0);
        for chunk in data.chunks_exact(4) {
            // Grayscale: R ≈ G ≈ B (luminance-weighted)
            let diff_rg = (chunk[0] as i16 - chunk[1] as i16).abs();
            let diff_gb = (chunk[1] as i16 - chunk[2] as i16).abs();
            assert!(diff_rg <= 2, "R={} G={} diff={}", chunk[0], chunk[1], diff_rg);
            assert!(diff_gb <= 2, "G={} B={} diff={}", chunk[1], chunk[2], diff_gb);
        }
    }

    #[test]
    fn test_invert_on_white() {
        let mut data = make_white_frame(10, 10);
        apply_invert(&mut data);
        for chunk in data.chunks_exact(4) {
            assert_eq!(chunk[0], 0);
            assert_eq!(chunk[1], 0);
            assert_eq!(chunk[2], 0);
        }
    }

    #[test]
    fn test_hue_shift_changes_colors() {
        let mut data = make_test_frame(100, 100);
        let original = data.clone();
        apply_hue(&mut data, 90.0);
        // After a 90-degree hue shift, at least some pixels should change
        let changed = data.iter().zip(original.iter())
            .filter(|(a, b)| a != b)
            .count();
        assert!(changed > 0, "Hue shift should change some pixels");
    }

    #[test]
    fn test_temperature_warm_shifts_red() {
        let mut data = make_test_frame(100, 100);
        let original = data.clone();
        apply_temperature(&mut data, 1.0);
        // Red channel should increase, blue should decrease
        for (new, old) in data.iter().zip(original.iter()).step_by(4) {
            // R channel: new >= old (or clamped at 255)
            assert!(*new >= *old || *old == 255, "Warm temp should increase R");
        }
    }

    #[test]
    fn test_grayscale_full_intensity() {
        let mut data = make_test_frame(100, 100);
        apply_grayscale(&mut data, 1.0);
        for chunk in data.chunks_exact(4) {
            assert_eq!(chunk[0], chunk[1]);
            assert_eq!(chunk[1], chunk[2]);
        }
    }

    #[test]
    fn test_sepia_reduces_blue() {
        let mut data = make_white_frame(100, 100);
        apply_sepia(&mut data, 1.0);
        for chunk in data.chunks_exact(4) {
            // Sepia should reduce blue channel compared to red
            assert!(chunk[2] < chunk[0], "Sepia: B={} should be < R={}", chunk[2], chunk[0]);
        }
    }

    #[test]
    fn test_vignette_darkens_edges() {
        let mut data = make_white_frame(100, 100);
        apply_vignette(&mut data, 100, 100, 1.0, 0.5);
        // Center pixel should remain bright
        let center_idx = (50 * 100 + 50) * 4;
        assert!(data[center_idx] > 200, "Center should remain bright");
        // Corner pixel should be darker
        let corner_idx = 0;
        assert!(data[corner_idx] < 200, "Corner should be darker");
    }

    #[test]
    fn test_filter_type_all_filters_count() {
        assert_eq!(FilterType::all_filters().len(), 11);
    }

    #[test]
    fn test_preset_to_effects() {
        let preset = FilterPreset::built_in_presets().into_iter()
            .find(|p| p.id == "cinematic").unwrap();
        let effects = preset.to_effects();
        assert_eq!(effects.len(), 3);
        assert_eq!(effects[0].order, 0);
        assert_eq!(effects[1].order, 1);
    }
}
