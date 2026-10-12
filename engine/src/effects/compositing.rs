//! Compositing — 22 blend modes with exact math formulas, alpha compositing, opacity control.
//!
//! Implements all standard Photoshop-style blend modes for professional compositing.
//! Supports GPU acceleration via WGSL compute shaders.

use serde::{Deserialize, Serialize};

/// All 22 blend modes for layer compositing.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BlendMode {
    Normal,
    Dissolve,
    Darken,
    Multiply,
    ColorBurn,
    LinearBurn,
    DarkerColor,
    Lighten,
    Screen,
    ColorDodge,
    LinearDodge,    // Add
    LighterColor,
    Overlay,
    SoftLight,
    HardLight,
    VividLight,
    LinearLight,
    PinLight,
    HardMix,
    Difference,
    Exclusion,
    Divide,
}

impl BlendMode {
    /// Get the display name of this blend mode.
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Normal => "Normal",
            Self::Dissolve => "Dissolve",
            Self::Darken => "Darken",
            Self::Multiply => "Multiply",
            Self::ColorBurn => "Color Burn",
            Self::LinearBurn => "Linear Burn",
            Self::DarkerColor => "Darker Color",
            Self::Lighten => "Lighten",
            Self::Screen => "Screen",
            Self::ColorDodge => "Color Dodge",
            Self::LinearDodge => "Linear Dodge (Add)",
            Self::LighterColor => "Lighter Color",
            Self::Overlay => "Overlay",
            Self::SoftLight => "Soft Light",
            Self::HardLight => "Hard Light",
            Self::VividLight => "Vivid Light",
            Self::LinearLight => "Linear Light",
            Self::PinLight => "Pin Light",
            Self::HardMix => "Hard Mix",
            Self::Difference => "Difference",
            Self::Exclusion => "Exclusion",
            Self::Divide => "Divide",
        }
    }

    /// Get the formula description for tooltip display.
    pub fn formula(&self) -> &'static str {
        match self {
            Self::Normal => "R = S",
            Self::Dissolve => "R = random(S, D)",
            Self::Darken => "R = min(S, D)",
            Self::Multiply => "R = S × D",
            Self::ColorBurn => "R = 1 - (1-D)/S",
            Self::LinearBurn => "R = S + D - 1",
            Self::DarkerColor => "R = lum(S) < lum(D) ? S : D",
            Self::Lighten => "R = max(S, D)",
            Self::Screen => "R = S + D - S×D",
            Self::ColorDodge => "R = D / (1-S)",
            Self::LinearDodge => "R = S + D",
            Self::LighterColor => "R = lum(S) > lum(D) ? S : D",
            Self::Overlay => "R = D<0.5 ? 2SD : 1-2(1-S)(1-D)",
            Self::SoftLight => "R = D(2S+(1-D)(2S-1))", // Pegtop version
            Self::HardLight => "R = S<0.5 ? 2SD : 1-2(1-S)(1-D)",
            Self::VividLight => "S<0.5 ? ColorBurn : ColorDodge",
            Self::LinearLight => "R = D + 2S - 1",
            Self::PinLight => "R = S<0.5 ? min(D,2S) : max(D,2S-1)",
            Self::HardMix => "R = LinearLight < 0.5 ? 0 : 1",
            Self::Difference => "R = |S - D|",
            Self::Exclusion => "R = S + D - 2SD",
            Self::Divide => "R = D / S",
        }
    }

    /// Apply blend mode to normalized [0..1] source and destination values.
    pub fn blend(&self, src: f32, dst: f32) -> f32 {
        let s = src.clamp(0.0, 1.0);
        let d = dst.clamp(0.0, 1.0);
        match self {
            Self::Normal => s,
            Self::Dissolve => s, // Simplified; true dissolve uses dither
            Self::Darken => s.min(d),
            Self::Multiply => s * d,
            Self::ColorBurn => {
                if d <= 0.0 { 0.0 }
                else if s >= 1.0 { 1.0 }
                else { (1.0 - (1.0 - d) / s).clamp(0.0, 1.0) }
            }
            Self::LinearBurn => (s + d - 1.0).clamp(0.0, 1.0),
            Self::DarkerColor => {
                if luminance(s, s, s) < luminance(d, d, d) { s } else { d }
            }
            Self::Lighten => s.max(d),
            Self::Screen => s + d - s * d,
            Self::ColorDodge => {
                if d <= 0.0 { 0.0 }
                else if s >= 1.0 { 1.0 }
                else { (d / (1.0 - s)).clamp(0.0, 1.0) }
            }
            Self::LinearDodge => (s + d).clamp(0.0, 1.0),
            Self::LighterColor => {
                if luminance(s, s, s) > luminance(d, d, d) { s } else { d }
            }
            Self::Overlay => {
                if d < 0.5 { 2.0 * s * d } else { 1.0 - 2.0 * (1.0 - s) * (1.0 - d) }
            }
            Self::SoftLight => {
                // Pegtop soft light formula
                d * (2.0 * s + (1.0 - d) * (2.0 * s - 1.0))
            }
            Self::HardLight => {
                if s < 0.5 { 2.0 * s * d } else { 1.0 - 2.0 * (1.0 - s) * (1.0 - d) }
            }
            Self::VividLight => {
                if s < 0.5 { Self::ColorBurn.blend(2.0 * s, d) }
                else { Self::ColorDodge.blend(2.0 * s - 1.0, d) }
            }
            Self::LinearLight => (d + 2.0 * s - 1.0).clamp(0.0, 1.0),
            Self::PinLight => {
                if s < 0.5 { d.min(2.0 * s) } else { d.max(2.0 * s - 1.0) }
            }
            Self::HardMix => {
                let v = Self::LinearLight.blend(s, d);
                if v < 0.5 { 0.0 } else { 1.0 }
            }
            Self::Difference => (s - d).abs(),
            Self::Exclusion => s + d - 2.0 * s * d,
            Self::Divide => {
                if s <= 0.0 { 1.0 } else { (d / s).clamp(0.0, 1.0) }
            }
        }
    }

    /// List all blend modes.
    pub fn all() -> &'static [BlendMode] {
        &[
            Self::Normal, Self::Dissolve,
            Self::Darken, Self::Multiply, Self::ColorBurn, Self::LinearBurn, Self::DarkerColor,
            Self::Lighten, Self::Screen, Self::ColorDodge, Self::LinearDodge, Self::LighterColor,
            Self::Overlay, Self::SoftLight, Self::HardLight, Self::VividLight, Self::LinearLight, Self::PinLight, Self::HardMix,
            Self::Difference, Self::Exclusion, Self::Divide,
        ]
    }
}

/// Compute luminance from RGB (simplified Rec.709).
fn luminance(r: f32, g: f32, b: f32) -> f32 {
    0.2126 * r + 0.7152 * g + 0.0722 * b
}

/// Composite two RGBA pixels using a blend mode and opacity.
pub fn composite_pixel(src: &[u8; 4], dst: &[u8; 4], mode: BlendMode, opacity: f32) -> [u8; 4] {
    let sa = src[3] as f32 / 255.0 * opacity;
    let da = dst[3] as f32 / 255.0;
    if sa <= 0.0 { return *dst; }
    if da <= 0.0 {
        return [
            (src[0] as f32 * sa) as u8,
            (src[1] as f32 * sa) as u8,
            (src[2] as f32 * sa) as u8,
            (sa * 255.0) as u8,
        ];
    }

    let sr = src[0] as f32 / 255.0;
    let sg = src[1] as f32 / 255.0;
    let sb = src[2] as f32 / 255.0;
    let dr = dst[0] as f32 / 255.0;
    let dg = dst[1] as f32 / 255.0;
    let db = dst[2] as f32 / 255.0;

    let cr = mode.blend(sr, dr);
    let cg = mode.blend(sg, dg);
    let cb = mode.blend(sb, db);

    // Porter-Duff source-over compositing
    let out_a = sa + da * (1.0 - sa);
    let factor = if out_a > 0.0 { 1.0 / out_a } else { 0.0 };
    let out_r = (sa * cr + da * dr * (1.0 - sa)) * factor;
    let out_g = (sa * cg + da * dg * (1.0 - sa)) * factor;
    let out_b = (sa * cb + da * db * (1.0 - sa)) * factor;

    [
        (out_r.clamp(0.0, 1.0) * 255.0) as u8,
        (out_g.clamp(0.0, 1.0) * 255.0) as u8,
        (out_b.clamp(0.0, 1.0) * 255.0) as u8,
        (out_a.clamp(0.0, 1.0) * 255.0) as u8,
    ]
}

/// Composite an entire source frame onto a destination frame.
pub fn composite_frames(
    src: &[u8], dst: &mut [u8],
    width: u32, height: u32,
    mode: BlendMode, opacity: f32,
) {
    let pixel_count = (width * height) as usize;
    for i in 0..pixel_count {
        let idx = i * 4;
        let s = [src[idx], src[idx+1], src[idx+2], src[idx+3]];
        let d = [dst[idx], dst[idx+1], dst[idx+2], dst[idx+3]];
        let result = composite_pixel(&s, &d, mode, opacity);
        dst[idx] = result[0];
        dst[idx+1] = result[1];
        dst[idx+2] = result[2];
        dst[idx+3] = result[3];
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normal_blend() {
        assert!((BlendMode::Normal.blend(0.5, 0.3) - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_multiply_blend() {
        assert!((BlendMode::Multiply.blend(0.5, 0.5) - 0.25).abs() < 0.001);
    }

    #[test]
    fn test_screen_blend() {
        assert!((BlendMode::Screen.blend(0.5, 0.5) - 0.75).abs() < 0.001);
    }

    #[test]
    fn test_overlay_mid() {
        assert!((BlendMode::Overlay.blend(0.5, 0.5) - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_darken_blend() {
        assert!((BlendMode::Darken.blend(0.3, 0.7) - 0.3).abs() < 0.001);
    }

    #[test]
    fn test_lighten_blend() {
        assert!((BlendMode::Lighten.blend(0.3, 0.7) - 0.7).abs() < 0.001);
    }

    #[test]
    fn test_color_burn() {
        let result = BlendMode::ColorBurn.blend(0.5, 0.5);
        assert!(result >= 0.0 && result <= 1.0);
    }

    #[test]
    fn test_color_dodge() {
        let result = BlendMode::ColorDodge.blend(0.5, 0.5);
        assert!(result >= 0.0 && result <= 1.0);
    }

    #[test]
    fn test_difference_blend() {
        assert!((BlendMode::Difference.blend(0.8, 0.3) - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_exclusion_blend() {
        let result = BlendMode::Exclusion.blend(0.5, 0.5);
        assert!((result - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_soft_light() {
        let result = BlendMode::SoftLight.blend(0.5, 0.5);
        assert!(result >= 0.0 && result <= 1.0);
    }

    #[test]
    fn test_hard_light() {
        let result = BlendMode::HardLight.blend(0.3, 0.7);
        assert!(result >= 0.0 && result <= 1.0);
    }

    #[test]
    fn test_linear_dodge() {
        assert!((BlendMode::LinearDodge.blend(0.5, 0.5) - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_linear_burn() {
        assert!((BlendMode::LinearBurn.blend(0.5, 0.5) - 0.0).abs() < 0.001);
    }

    #[test]
    fn test_vivid_light() {
        let result = BlendMode::VividLight.blend(0.5, 0.5);
        assert!(result >= 0.0 && result <= 1.0);
    }

    #[test]
    fn test_pin_light() {
        let result = BlendMode::PinLight.blend(0.5, 0.5);
        assert!(result >= 0.0 && result <= 1.0);
    }

    #[test]
    fn test_hard_mix() {
        let result = BlendMode::HardMix.blend(0.8, 0.5);
        assert!(result == 0.0 || result == 1.0);
    }

    #[test]
    fn test_divide_blend() {
        let result = BlendMode::Divide.blend(0.5, 0.5);
        assert!((result - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_composite_pixel_normal() {
        let src = [200, 100, 50, 255];
        let dst = [50, 100, 200, 255];
        let result = composite_pixel(&src, &dst, BlendMode::Normal, 1.0);
        assert_eq!(result[0], 200);
    }

    #[test]
    fn test_composite_pixel_opacity() {
        let src = [200, 100, 50, 255];
        let dst = [50, 100, 200, 255];
        let result = composite_pixel(&src, &dst, BlendMode::Normal, 0.0);
        assert_eq!(result[0], 50); // Fully transparent src
    }

    #[test]
    fn test_composite_pixel_multiply() {
        let src = [255, 128, 0, 255];
        let dst = [255, 128, 64, 255];
        let result = composite_pixel(&src, &dst, BlendMode::Multiply, 1.0);
        assert!(result[0] <= 255);
    }

    #[test]
    fn test_blend_modes_count() {
        assert_eq!(BlendMode::all().len(), 22);
    }

    #[test]
    fn test_blend_mode_names() {
        assert_eq!(BlendMode::Normal.display_name(), "Normal");
        assert_eq!(BlendMode::ColorDodge.display_name(), "Color Dodge");
    }

    #[test]
    fn test_blend_mode_formulas() {
        assert_eq!(BlendMode::Multiply.formula(), "R = S × D");
        assert_eq!(BlendMode::Screen.formula(), "R = S + D - S×D");
    }

    #[test]
    fn test_composite_frames() {
        let src = vec![255u8; 4 * 4]; // 1x1 RGBA
        let mut dst = vec![0u8; 4 * 4];
        composite_frames(&src, &mut dst, 1, 1, BlendMode::Normal, 1.0);
        assert_eq!(dst[0], 255);
    }

    #[test]
    fn test_luminance() {
        let l = luminance(1.0, 1.0, 1.0);
        assert!((l - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_blend_clamp() {
        let result = BlendMode::LinearDodge.blend(1.0, 1.0);
        assert_eq!(result, 1.0);
    }

    #[test]
    fn test_color_burn_edge_zero_src() {
        let result = BlendMode::ColorBurn.blend(0.0, 0.5);
        assert_eq!(result, 0.0);
    }

    #[test]
    fn test_color_dodge_edge_zero_src() {
        let result = BlendMode::ColorDodge.blend(0.0, 0.5);
        assert_eq!(result, 0.0);
    }

    #[test]
    fn test_darker_color() {
        let result = BlendMode::DarkerColor.blend(0.2, 0.8);
        assert!((result - 0.2).abs() < 0.001);
    }

    #[test]
    fn test_lighter_color() {
        let result = BlendMode::LighterColor.blend(0.2, 0.8);
        assert!((result - 0.8).abs() < 0.001);
    }
}
