//! Film Grain — 17 film stock presets, VHS degradation, halation effect.
//!
//! Professional film grain simulation with realistic presets for classic film stocks,
//! adjustable grain intensity/size/color profile, VHS tape degradation, and halation glow.

use serde::{Deserialize, Serialize};

/// Film stock preset.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FilmStock {
    KodakPortra400,
    KodakPortra800,
    KodakEktar100,
    KodakTriX400,
    KodakTMax3200,
    FujiVelvia50,
    FujiPro400H,
    FujiSuperia400,
    IlfordHP5,
    IlfordDelta3200,
    CineStill800T,
    KodakVision3_500T,
    KodakVision3_250D,
    Fomapan400,
    Lomography800,
    Polaroid600,
    Kodachrome64,
}

impl FilmStock {
    pub fn all() -> &'static [FilmStock] {
        &[
            Self::KodakPortra400, Self::KodakPortra800, Self::KodakEktar100,
            Self::KodakTriX400, Self::KodakTMax3200,
            Self::FujiVelvia50, Self::FujiPro400H, Self::FujiSuperia400,
            Self::IlfordHP5, Self::IlfordDelta3200,
            Self::CineStill800T, Self::KodakVision3_500T, Self::KodakVision3_250D,
            Self::Fomapan400, Self::Lomography800, Self::Polaroid600, Self::Kodachrome64,
        ]
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            Self::KodakPortra400 => "Kodak Portra 400",
            Self::KodakPortra800 => "Kodak Portra 800",
            Self::KodakEktar100 => "Kodak Ektar 100",
            Self::KodakTriX400 => "Kodak Tri-X 400",
            Self::KodakTMax3200 => "Kodak T-Max 3200",
            Self::FujiVelvia50 => "Fuji Velvia 50",
            Self::FujiPro400H => "Fuji Pro 400H",
            Self::FujiSuperia400 => "Fuji Superia 400",
            Self::IlfordHP5 => "Ilford HP5+",
            Self::IlfordDelta3200 => "Ilford Delta 3200",
            Self::CineStill800T => "CineStill 800T",
            Self::KodakVision3_500T => "Kodak Vision3 500T",
            Self::KodakVision3_250D => "Kodak Vision3 250D",
            Self::Fomapan400 => "Fomapan 400",
            Self::Lomography800 => "Lomography 800",
            Self::Polaroid600 => "Polaroid 600",
            Self::Kodachrome64 => "Kodachrome 64",
        }
    }

    /// Get the grain parameters for this stock.
    pub fn grain_params(&self) -> GrainParams {
        match self {
            Self::KodakPortra400 => GrainParams { intensity: 0.12, size: 1.2, color_grain: true, red_weight: 0.8, green_weight: 0.9, blue_weight: 1.0, softness: 0.5 },
            Self::KodakPortra800 => GrainParams { intensity: 0.20, size: 1.5, color_grain: true, red_weight: 0.85, green_weight: 0.9, blue_weight: 1.0, softness: 0.6 },
            Self::KodakEktar100 => GrainParams { intensity: 0.06, size: 0.8, color_grain: true, red_weight: 1.0, green_weight: 0.9, blue_weight: 0.8, softness: 0.3 },
            Self::KodakTriX400 => GrainParams { intensity: 0.30, size: 1.8, color_grain: false, red_weight: 1.0, green_weight: 1.0, blue_weight: 1.0, softness: 0.4 },
            Self::KodakTMax3200 => GrainParams { intensity: 0.45, size: 2.5, color_grain: false, red_weight: 1.0, green_weight: 1.0, blue_weight: 1.0, softness: 0.5 },
            Self::FujiVelvia50 => GrainParams { intensity: 0.04, size: 0.7, color_grain: true, red_weight: 1.0, green_weight: 0.95, blue_weight: 0.85, softness: 0.2 },
            Self::FujiPro400H => GrainParams { intensity: 0.14, size: 1.3, color_grain: true, red_weight: 0.9, green_weight: 0.95, blue_weight: 1.0, softness: 0.5 },
            Self::FujiSuperia400 => GrainParams { intensity: 0.18, size: 1.4, color_grain: true, red_weight: 0.95, green_weight: 0.9, blue_weight: 1.1, softness: 0.55 },
            Self::IlfordHP5 => GrainParams { intensity: 0.28, size: 1.7, color_grain: false, red_weight: 1.0, green_weight: 1.0, blue_weight: 1.0, softness: 0.4 },
            Self::IlfordDelta3200 => GrainParams { intensity: 0.40, size: 2.2, color_grain: false, red_weight: 1.0, green_weight: 1.0, blue_weight: 1.0, softness: 0.45 },
            Self::CineStill800T => GrainParams { intensity: 0.22, size: 1.6, color_grain: true, red_weight: 1.0, green_weight: 0.85, blue_weight: 0.75, softness: 0.55 },
            Self::KodakVision3_500T => GrainParams { intensity: 0.15, size: 1.3, color_grain: true, red_weight: 0.9, green_weight: 0.9, blue_weight: 1.0, softness: 0.5 },
            Self::KodakVision3_250D => GrainParams { intensity: 0.10, size: 1.1, color_grain: true, red_weight: 0.95, green_weight: 0.95, blue_weight: 1.0, softness: 0.45 },
            Self::Fomapan400 => GrainParams { intensity: 0.25, size: 1.9, color_grain: false, red_weight: 1.0, green_weight: 1.0, blue_weight: 1.0, softness: 0.35 },
            Self::Lomography800 => GrainParams { intensity: 0.35, size: 2.0, color_grain: true, red_weight: 1.2, green_weight: 0.8, blue_weight: 0.9, softness: 0.6 },
            Self::Polaroid600 => GrainParams { intensity: 0.20, size: 1.5, color_grain: true, red_weight: 1.1, green_weight: 0.85, blue_weight: 0.8, softness: 0.65 },
            Self::Kodachrome64 => GrainParams { intensity: 0.08, size: 0.9, color_grain: true, red_weight: 1.0, green_weight: 0.88, blue_weight: 0.82, softness: 0.3 },
        }
    }
}

/// Grain parameters.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct GrainParams {
    pub intensity: f32,      // 0..1
    pub size: f32,           // Grain particle size factor
    pub color_grain: bool,   // Color vs luminance grain
    pub red_weight: f32,
    pub green_weight: f32,
    pub blue_weight: f32,
    pub softness: f32,       // 0 = sharp, 1 = soft
}

impl Default for GrainParams {
    fn default() -> Self { Self { intensity: 0.1, size: 1.0, color_grain: true, red_weight: 1.0, green_weight: 1.0, blue_weight: 1.0, softness: 0.5 } }
}

/// VHS degradation parameters.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VHSParams {
    pub enabled: bool,
    pub tracking_noise: f32,   // 0..1 horizontal displacement
    pub color_bleed: f32,      // 0..1 chroma offset
    pub scanlines: f32,        // 0..1 line darkness
    pub tape_hiss: f32,        // 0..1 noise intensity
    pub frame_roll: f32,       // 0..1 vertical jitter
    pub sharpness_loss: f32,   // 0..1 blur amount
}

impl Default for VHSParams {
    fn default() -> Self {
        Self { enabled: false, tracking_noise: 0.3, color_bleed: 0.2, scanlines: 0.15, tape_hiss: 0.1, frame_roll: 0.05, sharpness_loss: 0.3 }
    }
}

/// Halation parameters (light bloom around highlights).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HalationParams {
    pub enabled: bool,
    pub threshold: f32,    // Luminance threshold for bloom
    pub intensity: f32,    // Bloom strength
    pub radius: f32,       // Bloom spread in pixels
    pub color_r: f32,      // Bloom tint (typically reddish)
    pub color_g: f32,
    pub color_b: f32,
}

impl Default for HalationParams {
    fn default() -> Self {
        Self { enabled: false, threshold: 0.8, intensity: 0.3, radius: 10.0, color_r: 1.0, color_g: 0.6, color_b: 0.4 }
    }
}

/// Complete grain configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GrainConfig {
    pub enabled: bool,
    pub preset: Option<FilmStock>,
    pub params: GrainParams,
    pub vhs: VHSParams,
    pub halation: HalationParams,
    pub temporal_blend: f32, // 0 = static grain, 1 = full temporal variation
}

impl Default for GrainConfig {
    fn default() -> Self {
        Self { enabled: false, preset: None, params: GrainParams::default(), vhs: VHSParams::default(), halation: HalationParams::default(), temporal_blend: 0.8 }
    }
}

/// Simple pseudo-random number generator for grain.
fn hash_pixel(x: u32, y: u32, frame: u32) -> f32 {
    let mut h = x.wrapping_mul(374761393).wrapping_add(y.wrapping_mul(668265263)).wrapping_add(frame.wrapping_mul(1274126177));
    h = (h ^ (h >> 13)).wrapping_mul(1274126177);
    h = h ^ (h >> 16);
    (h as f32 / u32::MAX as f32) * 2.0 - 1.0 // -1..1
}

/// Apply film grain to an RGBA frame.
pub fn apply_grain(frame: &mut [u8], width: u32, height: u32, config: &GrainConfig, frame_num: u32) {
    if !config.enabled { return; }

    let params = &config.params;

    for y in 0..height {
        for x in 0..width {
            let idx = ((y * width + x) * 4) as usize;
            let noise = hash_pixel(x, y, frame_num) * params.intensity;

            if params.color_grain {
                let nr = noise * params.red_weight;
                let ng = noise * params.green_weight;
                let nb = noise * params.blue_weight;
                frame[idx] = (frame[idx] as f32 + nr * 255.0).clamp(0.0, 255.0) as u8;
                frame[idx+1] = (frame[idx+1] as f32 + ng * 255.0).clamp(0.0, 255.0) as u8;
                frame[idx+2] = (frame[idx+2] as f32 + nb * 255.0).clamp(0.0, 255.0) as u8;
            } else {
                let lum_noise = noise * 255.0;
                frame[idx] = (frame[idx] as f32 + lum_noise).clamp(0.0, 255.0) as u8;
                frame[idx+1] = (frame[idx+1] as f32 + lum_noise).clamp(0.0, 255.0) as u8;
                frame[idx+2] = (frame[idx+2] as f32 + lum_noise).clamp(0.0, 255.0) as u8;
            }
        }
    }

    // Apply VHS effects
    if config.vhs.enabled {
        apply_vhs(frame, width, height, &config.vhs, frame_num);
    }

    // Apply halation
    if config.halation.enabled {
        apply_halation(frame, width, height, &config.halation);
    }
}

/// Apply VHS degradation effects.
fn apply_vhs(frame: &mut [u8], width: u32, height: u32, params: &VHSParams, frame_num: u32) {
    let mut output = frame.to_vec();

    for y in 0..height {
        // Tracking noise: horizontal shift per scanline
        let shift = (hash_pixel(0, y, frame_num) * params.tracking_noise * 10.0) as i32;

        for x in 0..width {
            let idx = ((y * width + x) * 4) as usize;
            let src_x = (x as i32 + shift).clamp(0, width as i32 - 1) as u32;
            let src_idx = ((y * width + src_x) * 4) as usize;

            // Tracking displacement
            output[idx] = frame[src_idx];
            output[idx+1] = frame[src_idx+1];
            output[idx+2] = frame[src_idx+2];

            // Scanlines
            if y % 2 == 0 {
                let dim = 1.0 - params.scanlines * 0.5;
                output[idx] = (output[idx] as f32 * dim) as u8;
                output[idx+1] = (output[idx+1] as f32 * dim) as u8;
                output[idx+2] = (output[idx+2] as f32 * dim) as u8;
            }

            // Color bleed: offset red channel
            let bleed_x = (x as i32 + (params.color_bleed * 3.0) as i32).clamp(0, width as i32 - 1) as u32;
            let bleed_idx = ((y * width + bleed_x) * 4) as usize;
            output[idx] = frame[bleed_idx]; // Red from shifted position
        }
    }

    frame.copy_from_slice(&output);
}

/// Apply halation (highlight bloom).
fn apply_halation(frame: &mut [u8], width: u32, height: u32, params: &HalationParams) {
    let radius = params.radius as usize;
    let mut bloom = vec![0.0f32; (width * height) as usize];

    // Compute bloom mask from highlights
    for y in 0..height {
        for x in 0..width {
            let idx = ((y * width + x) * 4) as usize;
            let luma = (frame[idx] as f32 * 0.299 + frame[idx+1] as f32 * 0.587 + frame[idx+2] as f32 * 0.114) / 255.0;
            if luma > params.threshold {
                bloom[(y * width + x) as usize] = (luma - params.threshold) / (1.0 - params.threshold + 1e-6);
            }
        }
    }

    // Simple box blur for bloom spread
    let mut blurred = bloom.clone();
    for _ in 0..3 {
        for y in radius..height as usize - radius {
            for x in radius..width as usize - radius {
                let mut sum = 0.0;
                let mut count = 0;
                let r = radius as i32;
                for dy in -r..=r {
                    for dx in -r..=r {
                        let y_idx = (y as i32 + dy) as usize;
                        let x_idx = (x as i32 + dx) as usize;
                        sum += bloom[y_idx * width as usize + x_idx];
                        count += 1;
                    }
                }
                blurred[y * width as usize + x] = sum / count as f32;
            }
        }
        bloom.copy_from_slice(&blurred);
    }

    // Apply bloom
    for y in 0..height {
        for x in 0..width {
            let idx = ((y * width + x) * 4) as usize;
            let b = bloom[(y * width + x) as usize] * params.intensity;
            frame[idx] = (frame[idx] as f32 + b * params.color_r * 255.0).clamp(0.0, 255.0) as u8;
            frame[idx+1] = (frame[idx+1] as f32 + b * params.color_g * 255.0).clamp(0.0, 255.0) as u8;
            frame[idx+2] = (frame[idx+2] as f32 + b * params.color_b * 255.0).clamp(0.0, 255.0) as u8;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_film_stock_count() { assert_eq!(FilmStock::all().len(), 17); }

    #[test]
    fn test_film_stock_names() {
        assert_eq!(FilmStock::KodakPortra400.display_name(), "Kodak Portra 400");
        assert_eq!(FilmStock::KodakTriX400.display_name(), "Kodak Tri-X 400");
    }

    #[test]
    fn test_grain_params_portra() {
        let p = FilmStock::KodakPortra400.grain_params();
        assert!(p.intensity > 0.0);
        assert!(p.color_grain);
    }

    #[test]
    fn test_grain_params_tri_x() {
        let p = FilmStock::KodakTriX400.grain_params();
        assert!(p.intensity > 0.0);
        assert!(!p.color_grain); // B&W stock
    }

    #[test]
    fn test_grain_params_tmax() {
        let p = FilmStock::KodakTMax3200.grain_params();
        assert!(p.intensity > 0.3); // High ISO = more grain
    }

    #[test]
    fn test_grain_config_default() {
        let c = GrainConfig::default();
        assert!(!c.enabled);
        assert!(c.preset.is_none());
    }

    #[test]
    fn test_vhs_params_default() {
        let v = VHSParams::default();
        assert!(!v.enabled);
    }

    #[test]
    fn test_halation_params_default() {
        let h = HalationParams::default();
        assert!(!h.enabled);
        assert!((h.color_r - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_apply_grain_disabled() {
        let mut frame = vec![128u8; 10 * 10 * 4];
        let original = frame.clone();
        let config = GrainConfig::default();
        apply_grain(&mut frame, 10, 10, &config, 0);
        assert_eq!(frame, original);
    }

    #[test]
    fn test_apply_grain_enabled() {
        let mut frame = vec![128u8; 20 * 20 * 4];
        let mut config = GrainConfig::default();
        config.enabled = true;
        config.params.intensity = 0.1;
        apply_grain(&mut frame, 20, 20, &config, 0);
        // Frame should be modified
        assert_ne!(frame, vec![128u8; 20 * 20 * 4]);
    }

    #[test]
    fn test_apply_grain_with_preset() {
        let mut frame = vec![128u8; 20 * 20 * 4];
        let mut config = GrainConfig { enabled: true, preset: Some(FilmStock::KodakPortra400), ..Default::default() };
        config.params = FilmStock::KodakPortra400.grain_params();
        apply_grain(&mut frame, 20, 20, &config, 0);
    }

    #[test]
    fn test_apply_grain_bw() {
        let mut frame = vec![128u8; 20 * 20 * 4];
        let mut config = GrainConfig { enabled: true, preset: Some(FilmStock::KodakTriX400), ..Default::default() };
        config.params = FilmStock::KodakTriX400.grain_params();
        apply_grain(&mut frame, 20, 20, &config, 0);
    }

    #[test]
    fn test_apply_vhs() {
        let mut frame = vec![128u8; 20 * 20 * 4];
        let config = GrainConfig { enabled: true, vhs: VHSParams { enabled: true, ..Default::default() }, ..Default::default() };
        apply_grain(&mut frame, 20, 20, &config, 0);
    }

    #[test]
    fn test_apply_halation() {
        let mut frame = vec![128u8; 20 * 20 * 4];
        let config = GrainConfig { enabled: true, halation: HalationParams { enabled: true, threshold: 0.3, ..Default::default() }, ..Default::default() };
        apply_grain(&mut frame, 20, 20, &config, 0);
    }

    #[test]
    fn test_hash_pixel_range() {
        let v = hash_pixel(100, 200, 0);
        assert!(v >= -1.0 && v <= 1.0);
    }

    #[test]
    fn test_hash_pixel_varies() {
        let v0 = hash_pixel(100, 200, 0);
        let v1 = hash_pixel(100, 200, 1);
        assert_ne!(v0, v1); // Different frames should give different values
    }

    #[test]
    fn test_grain_params_velvia() {
        let p = FilmStock::FujiVelvia50.grain_params();
        assert!(p.intensity < 0.1); // Low ISO = fine grain
    }

    #[test]
    fn test_grain_params_cinestill() {
        let p = FilmStock::CineStill800T.grain_params();
        assert!(p.color_grain);
        assert!(p.blue_weight < 1.0); // Tungsten balance
    }

    #[test]
    fn test_all_stocks_have_params() {
        for stock in FilmStock::all() {
            let p = stock.grain_params();
            assert!(p.intensity > 0.0);
        }
    }
}
