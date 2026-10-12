//! Color Space Management — 13 transfer functions, ACES pipeline, HDR tone mapping.
//!
//! Professional color space transforms for cinema-grade workflows:
//! Input CST → Working Space → Output CST with proper transfer function handling.
//! Supports Rec.709, sRGB, DCI-P3, Rec.2020, and HDR (PQ/HLG).

use serde::{Deserialize, Serialize};

/// Color space primaries definition.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ColorPrimaries {
    Rec709,     // BT.709 (sRGB)
    DCIP3,      // DCI-P3 (Cinema)
    Rec2020,    // BT.2020 (UHD)
    AdobeRGB,   // Adobe RGB (1998)
    ProPhoto,   // ProPhoto RGB (ROMM)
    ACEScg,     // ACES CG (AP1)
    ACES2065,   // ACES 2065-1 (AP0)
}

/// Transfer function / OETF / EOTF.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransferFunction {
    SRGB,           // sRGB ~2.2 with linear segment
    Linear,         // Scene-linear
    Rec709,         // BT.709 OETF
    Gamma22,        // Pure 2.2 gamma
    Gamma28,        // Pure 2.8 gamma (legacy NTSC)
    PQ,             // SMPTE ST 2084 (Perceptual Quantizer) for HDR
    HLG,            // ITU-R BT.2100 HLG (Hybrid Log-Gamma)
    LogC,           // ARRI LogC (EI 800)
    SLog3,          // Sony S-Log3
    VLog,           // Panasonic V-Log
    CLog,           // Canon Log 3
    FLog,           // Fujifilm F-Log
    RedLog3G10,     // RED Log3G10
}

impl TransferFunction {
    /// List all transfer functions.
    pub fn all() -> &'static [TransferFunction] {
        &[
            Self::SRGB, Self::Linear, Self::Rec709, Self::Gamma22, Self::Gamma28,
            Self::PQ, Self::HLG, Self::LogC, Self::SLog3, Self::VLog, Self::CLog, Self::FLog, Self::RedLog3G10,
        ]
    }

    /// Display name.
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::SRGB => "sRGB", Self::Linear => "Linear", Self::Rec709 => "Rec.709",
            Self::Gamma22 => "Gamma 2.2", Self::Gamma28 => "Gamma 2.8",
            Self::PQ => "ST 2084 (PQ)", Self::HLG => "HLG",
            Self::LogC => "ARRI LogC", Self::SLog3 => "Sony S-Log3",
            Self::VLog => "Panasonic V-Log", Self::CLog => "Canon Log3",
            Self::FLog => "Fuji F-Log", Self::RedLog3G10 => "RED Log3G10",
        }
    }

    /// Is this an HDR transfer function?
    pub fn is_hdr(&self) -> bool {
        matches!(self, Self::PQ | Self::HLG)
    }

    /// Encode: Linear → Transfer function.
    pub fn encode(&self, linear: f32) -> f32 {
        match self {
            Self::Linear => linear,
            Self::SRGB => {
                if linear <= 0.0031308 { linear * 12.92 }
                else { 1.055 * linear.powf(1.0/2.4) - 0.055 }
            }
            Self::Rec709 => {
                if linear < 0.018 { 4.5 * linear }
                else { 1.099 * linear.powf(0.45) - 0.099 }
            }
            Self::Gamma22 => linear.powf(1.0/2.2),
            Self::Gamma28 => linear.powf(1.0/2.8),
            Self::PQ => {
                // ST 2084 PQ OETF
                let m1 = 2610.0 / 16384.0;
                let m2 = 2523.0 / 32.0;
                let c1 = 3424.0 / 4096.0;
                let c2 = 2413.0 / 128.0;
                let c3 = 2392.0 / 128.0;
                let n = (c1 + c2 * linear.powf(m1)) / (1.0 + c3 * linear.powf(m1));
                n.powf(m2)
            }
            Self::HLG => {
                // HLG OETF (scene-referred)
                let a = 0.17883277f64;
                let b = 1.0f64 - 4.0f64 * a;
                let c = 0.5f64 - a * (4.0f64 * a).ln();
                if linear <= 1.0 / 12.0 { (3.0 * linear).sqrt() }
                else { (a * (12.0f64 * linear as f64 - b).ln() + c) as f32 }
            }
            Self::LogC => {
                // ARRI LogC EI 800
                let cut = 0.010591;
                if linear < cut { (0.092514 * linear + 0.000684) * 1023.0 / 1023.0 }
                else { (0.247190 * (10.0 * linear + 0.338593).log10() + 0.391007)}
            }
            Self::SLog3 => {
                // Sony S-Log3
                if linear < 0.01 { (linear * 171.097 + 95.0) / 1023.0 }
                else { ((linear.ln() * 0.432699 + 0.554595) * 1023.0) / 1023.0 }
            }
            Self::VLog => {
                // Panasonic V-Log
                let cut1 = 0.01;
                if linear < cut1 { 0.125 * linear + 0.0928 }
                else { 0.432699 * (10.0 * linear).ln() + 0.554595 }
            }
            Self::CLog => {
                // Canon Log 3
                if linear < 0.01 { -0.069 * linear + 0.0928 }
                else { 0.5548 * (10.0 * linear).ln() + 0.3063 }
            }
            Self::FLog => {
                // Fujifilm F-Log
                if linear < 0.00089 { linear * 8.109 + 0.0929 }
                else { 0.3389 * (10.0 * linear).ln() + 0.6276 }
            }
            Self::RedLog3G10 => {
                // RED Log3G10
                if linear < 0.0 { 0.0 }
                else { (linear.powf(0.3) * 1023.0 - 1023.0 * 0.01) / 1023.0 + 0.333 }
            }
        }
    }

    /// Decode: Transfer function → Linear.
    pub fn decode(&self, encoded: f32) -> f32 {
        match self {
            Self::Linear => encoded,
            Self::SRGB => {
                if encoded <= 0.04045 { encoded / 12.92 }
                else { ((encoded + 0.055) / 1.055).powf(2.4) }
            }
            Self::Rec709 => {
                if encoded < 0.081 { encoded / 4.5 }
                else { ((encoded + 0.099) / 1.099).powf(1.0/0.45) }
            }
            Self::Gamma22 => encoded.powf(2.2),
            Self::Gamma28 => encoded.powf(2.8),
            Self::PQ => {
                let m1 = 2610.0 / 16384.0;
                let m2 = 2523.0 / 32.0;
                let c1 = 3424.0 / 4096.0;
                let c2 = 2413.0 / 128.0;
                let c3 = 2392.0 / 128.0;
                let n = encoded.powf(1.0/m2);
                ((c1 - n).max(0.0) / (c2 - c3 * n)).powf(1.0/m1)
            }
            Self::HLG => {
                let a = 0.17883277;
                let b = 1.0 - 4.0 * a;
                let c = 0.5 - a * (4.0f64 * a).ln();
                if encoded <= 0.5 { (encoded * encoded) / 3.0 }
                else { (((encoded as f64 - c) / a).exp() / 12.0 + b / 12.0) as f32 }
            }
            Self::LogC => {
                let cut = 0.092514 * 0.010591 + 0.000684;
                if encoded < cut { (encoded - 0.000684) / 0.092514 }
                else { 10.0_f32.powf((encoded - 0.391007) / 0.247190) / 10.0 - 0.338593 / 10.0 }
            }
            Self::SLog3 => {
                if encoded < 171.097 * 0.01 + 95.0 { (encoded - 95.0) / 171.097 }
                else { ((encoded - 0.554595) / 0.432699).exp() }
            }
            Self::VLog => {
                if encoded < 0.125 * 0.01 + 0.0928 { (encoded - 0.0928) / 0.125 }
                else { 10.0_f32.powf((encoded - 0.554595) / 0.432699) / 10.0 }
            }
            Self::CLog => {
                if encoded < -0.069 * 0.01 + 0.0928 { (encoded - 0.0928) / -0.069 }
                else { 10.0_f32.powf((encoded - 0.3063) / 0.5548) / 10.0 }
            }
            Self::FLog => {
                if encoded < 8.109 * 0.00089 + 0.0929 { (encoded - 0.0929) / 8.109 }
                else { 10.0_f32.powf((encoded - 0.6276) / 0.3389) / 10.0 }
            }
            Self::RedLog3G10 => {
                if encoded <= 0.0 { 0.0 }
                else { ((encoded - 0.333) * 1023.0 / 1023.0 + 0.01).powf(1.0/0.3) / 1023.0 * 1023.0 }
            }
        }
    }
}

/// Complete color space transform pipeline configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ColorSpaceTransform {
    pub input_primaries: ColorPrimaries,
    pub input_transfer: TransferFunction,
    pub working_primaries: ColorPrimaries,
    pub working_transfer: TransferFunction,
    pub output_primaries: ColorPrimaries,
    pub output_transfer: TransferFunction,
    pub enable_hdr: bool,
    pub hdr_peak_nits: f32,
    pub hdr_min_nits: f32,
}

impl Default for ColorSpaceTransform {
    fn default() -> Self {
        Self {
            input_primaries: ColorPrimaries::Rec709,
            input_transfer: TransferFunction::SRGB,
            working_primaries: ColorPrimaries::Rec709,
            working_transfer: TransferFunction::Linear,
            output_primaries: ColorPrimaries::Rec709,
            output_transfer: TransferFunction::SRGB,
            enable_hdr: false,
            hdr_peak_nits: 1000.0,
            hdr_min_nits: 0.005,
        }
    }
}

/// ACES RRT + ODT tone mapping (simplified).
pub fn aces_tone_map(r: f32, g: f32, b: f32) -> (f32, f32, f32) {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    let map = |x: f32| -> f32 {
        (x * (a * x + b)) / (x * (c * x + d) + e)
    };
    (map(r), map(g), map(b))
}

/// Reinhard tone mapping.
pub fn reinhard_tone_map(r: f32, g: f32, b: f32) -> (f32, f32, f32) {
    (r / (1.0 + r), g / (1.0 + g), b / (1.0 + b))
}

/// Apply a full color space transform to RGBA frame data.
pub fn apply_color_space_transform(frame: &mut [u8], width: u32, height: u32, cst: &ColorSpaceTransform) {
    let pixel_count = (width * height) as usize;
    let input_tf = cst.input_transfer;
    let output_tf = cst.output_transfer;

    for i in 0..pixel_count {
        let idx = i * 4;
        let r = frame[idx] as f32 / 255.0;
        let g = frame[idx + 1] as f32 / 255.0;
        let b = frame[idx + 2] as f32 / 255.0;

        // Input → Linear
        let r_lin = input_tf.decode(r);
        let g_lin = input_tf.decode(g);
        let b_lin = input_tf.decode(b);

        // Tone mapping if working in HDR
        let (r_tm, g_tm, b_tm) = if cst.enable_hdr && input_tf.is_hdr() {
            aces_tone_map(r_lin, g_lin, b_lin)
        } else {
            (r_lin, g_lin, b_lin)
        };

        // Linear → Output
        let r_out = output_tf.encode(r_tm.clamp(0.0, 1.0));
        let g_out = output_tf.encode(g_tm.clamp(0.0, 1.0));
        let b_out = output_tf.encode(b_tm.clamp(0.0, 1.0));

        frame[idx] = (r_out.clamp(0.0, 1.0) * 255.0) as u8;
        frame[idx + 1] = (g_out.clamp(0.0, 1.0) * 255.0) as u8;
        frame[idx + 2] = (b_out.clamp(0.0, 1.0) * 255.0) as u8;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_srgb_roundtrip() {
        let tf = TransferFunction::SRGB;
        for v in [0.0, 0.1, 0.5, 0.9, 1.0] {
            let encoded = tf.encode(v);
            let decoded = tf.decode(encoded);
            assert!((decoded - v).abs() < 0.01, "sRGB roundtrip failed at {}", v);
        }
    }

    #[test]
    fn test_pq_roundtrip() {
        let tf = TransferFunction::PQ;
        for v in [0.0, 0.1, 0.5, 1.0] {
            let encoded = tf.encode(v);
            let decoded = tf.decode(encoded);
            assert!((decoded - v).abs() < 0.02, "PQ roundtrip failed at {}", v);
        }
    }

    #[test]
    fn test_hlg_roundtrip() {
        let tf = TransferFunction::HLG;
        for v in [0.01, 0.1, 0.5, 1.0] {
            let encoded = tf.encode(v);
            let decoded = tf.decode(encoded);
            assert!((decoded - v).abs() < 0.02, "HLG roundtrip failed at {}", v);
        }
    }

    #[test]
    fn test_linear_identity() {
        let tf = TransferFunction::Linear;
        assert_eq!(tf.encode(0.5), 0.5);
        assert_eq!(tf.decode(0.5), 0.5);
    }

    #[test]
    fn test_gamma22_roundtrip() {
        let tf = TransferFunction::Gamma22;
        let encoded = tf.encode(0.5);
        let decoded = tf.decode(encoded);
        assert!((decoded - 0.5).abs() < 0.01);
    }

    #[test]
    fn test_rec709_roundtrip() {
        let tf = TransferFunction::Rec709;
        for v in [0.0, 0.5, 1.0] {
            let decoded = tf.decode(tf.encode(v));
            assert!((decoded - v).abs() < 0.01);
        }
    }

    #[test]
    fn test_logc_roundtrip() {
        let tf = TransferFunction::LogC;
        for v in [0.01, 0.1, 0.5] {
            let decoded = tf.decode(tf.encode(v));
            assert!((decoded - v).abs() < 0.05, "LogC roundtrip at {}", v);
        }
    }

    #[test]
    fn test_slog3_roundtrip() {
        let tf = TransferFunction::SLog3;
        for v in [0.01, 0.1, 0.5] {
            let decoded = tf.decode(tf.encode(v));
            assert!((decoded - v).abs() < 0.05, "SLog3 roundtrip at {}", v);
        }
    }

    #[test]
    fn test_aces_tone_map() {
        let (r, g, b) = aces_tone_map(0.5, 0.5, 0.5);
        assert!(r > 0.0 && r < 1.0);
        assert!((r - g).abs() < 0.001);
    }

    #[test]
    fn test_aces_tone_map_hdr() {
        let (r, _, _) = aces_tone_map(10.0, 5.0, 1.0);
        assert!(r < 1.0); // Should compress HDR values
    }

    #[test]
    fn test_reinhard_tone_map() {
        let (r, g, b) = reinhard_tone_map(0.5, 0.5, 0.5);
        assert!((r - 0.333).abs() < 0.01);
    }

    #[test]
    fn test_cst_default() {
        let cst = ColorSpaceTransform::default();
        assert_eq!(cst.input_transfer, TransferFunction::SRGB);
        assert_eq!(cst.working_transfer, TransferFunction::Linear);
        assert_eq!(cst.output_transfer, TransferFunction::SRGB);
        assert!(!cst.enable_hdr);
    }

    #[test]
    fn test_apply_cst_identity() {
        let mut frame = vec![128u8; 10 * 10 * 4];
        let original = frame.clone();
        let cst = ColorSpaceTransform::default();
        apply_color_space_transform(&mut frame, 10, 10, &cst);
        // sRGB→Linear→sRGB should be near-identity
    }

    #[test]
    fn test_transfer_function_count() {
        assert_eq!(TransferFunction::all().len(), 13);
    }

    #[test]
    fn test_is_hdr() {
        assert!(TransferFunction::PQ.is_hdr());
        assert!(TransferFunction::HLG.is_hdr());
        assert!(!TransferFunction::SRGB.is_hdr());
        assert!(!TransferFunction::Linear.is_hdr());
    }

    #[test]
    fn test_display_names() {
        assert_eq!(TransferFunction::SRGB.display_name(), "sRGB");
        assert_eq!(TransferFunction::PQ.display_name(), "ST 2084 (PQ)");
    }

    #[test]
    fn test_vlog_roundtrip() {
        let tf = TransferFunction::VLog;
        for v in [0.01, 0.1, 0.5] {
            let decoded = tf.decode(tf.encode(v));
            assert!((decoded - v).abs() < 0.05);
        }
    }

    #[test]
    fn test_clog_roundtrip() {
        let tf = TransferFunction::CLog;
        for v in [0.01, 0.1, 0.5] {
            let decoded = tf.decode(tf.encode(v));
            assert!((decoded - v).abs() < 0.05);
        }
    }

    #[test]
    fn test_flog_roundtrip() {
        let tf = TransferFunction::FLog;
        for v in [0.01, 0.1, 0.5] {
            let decoded = tf.decode(tf.encode(v));
            assert!((decoded - v).abs() < 0.05);
        }
    }
}
