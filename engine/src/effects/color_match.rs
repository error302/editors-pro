//! Color match — histogram-based matching between two frames.
//!
//! ## Status
//!
//! This module provides histogram-based shot matching: it computes the
//! CDF (cumulative distribution function) of the reference frame and the
//! target frame, then maps the target's pixels through the CDF difference
//! to match the reference's distribution.
//!
//! ## video: debt markers
//!
//! - Histogram-based match only, upgrade to per-channel with masking if selective match is needed
//! - Global match (whole frame), upgrade to qualifier-based match for skin-tone-only matching
//! - No white balance detection, upgrade to gray-world or learning-based WB detection
//! - 8-bit precision, upgrade to 10-bit if banding appears after match

use serde::{Deserialize, Serialize};

/// Color match result — the per-channel LUT (256 entries per channel)
/// that maps the source frame's pixels to match the reference frame.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ColorMatchLut {
    /// 768 bytes: 3 channels * 256 entries. `lut[ch * 256 + input_val] → output_val`.
    pub lut: Vec<u8>,
}

impl ColorMatchLut {
    pub fn new() -> Self {
        Self { lut: vec![0u8; 768] }
    }

    pub fn get(&self, ch: usize, val: u8) -> u8 {
        self.lut[ch * 256 + val as usize]
    }

    pub fn set(&mut self, ch: usize, val: u8, new_val: u8) {
        self.lut[ch * 256 + val as usize] = new_val;
    }
}

/// Compute a color-match LUT from a source frame and a reference frame.
///
/// Both frames must have the same dimensions.
pub fn compute_match_lut(
    source: &[u8],
    reference: &[u8],
    width: usize,
    height: usize,
) -> ColorMatchLut {
    debug_assert_eq!(source.len(), width * height * 4);
    debug_assert_eq!(reference.len(), width * height * 4);

    let mut lut_obj = ColorMatchLut::new();

    for ch in 0..3 {
        // Compute source histogram and CDF
        let mut src_hist = [0u32; 256];
        let mut ref_hist = [0u32; 256];
        for i in (0..source.len()).step_by(4) {
            src_hist[source[i + ch] as usize] += 1;
        }
        for i in (0..reference.len()).step_by(4) {
            ref_hist[reference[i + ch] as usize] += 1;
        }

        // CDFs
        let mut src_cdf = [0.0f64; 256];
        let mut ref_cdf = [0.0f64; 256];
        let src_total = (width * height) as f64;
        let ref_total = (width * height) as f64;
        let mut src_sum = 0u32;
        let mut ref_sum = 0u32;
        for i in 0..256 {
            src_sum += src_hist[i];
            ref_sum += ref_hist[i];
            src_cdf[i] = src_sum as f64 / src_total;
            ref_cdf[i] = ref_sum as f64 / ref_total;
        }

        // Build the LUT: for each input value, find the value whose CDF
        // in the reference matches the source's CDF.
        for i in 0..256 {
            let target_cdf = src_cdf[i];
            // Binary search for the value in ref_cdf that matches
            let mut lo = 0;
            let mut hi = 255;
            while lo < hi {
                let mid = (lo + hi) / 2;
                if ref_cdf[mid] < target_cdf {
                    lo = mid + 1;
                } else {
                    hi = mid;
                }
            }
            lut_obj.set(ch, i as u8, lo as u8);
        }
    }

    lut_obj
}

/// Apply a color-match LUT to a frame (in-place).
pub fn apply_match_lut(pixels: &mut [u8], lut: &ColorMatchLut) {
    for px in pixels.chunks_exact_mut(4) {
        px[0] = lut.get(0, px[0]);
        px[1] = lut.get(1, px[1]);
        px[2] = lut.get(2, px[2]);
        // alpha unchanged
    }
}

/// Convenience: match `target` to `reference` in one call.
pub fn match_frames(
    target: &mut [u8],
    reference: &[u8],
    width: usize,
    height: usize,
) {
    let lut = compute_match_lut(target, reference, width, height);
    apply_match_lut(target, &lut);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid_frame(width: usize, height: usize, r: u8, g: u8, b: u8) -> Vec<u8> {
        let mut v = Vec::with_capacity(width * height * 4);
        for _ in 0..(width * height) {
            v.push(r); v.push(g); v.push(b); v.push(255);
        }
        v
    }

    #[test]
    fn match_lut_identity_for_identical_frames() {
        let src = solid_frame(16, 16, 100, 150, 200);
        let lut = compute_match_lut(&src, &src, 16, 16);
        // Identical frames → identity LUT (or close to it)
        for ch in 0..3 {
            for i in 0..256 {
                // The LUT maps i to itself (or very close)
                let mapped = lut.get(ch, i as u8);
                assert!((mapped as i32 - i as i32).abs() <= 1,
                    "channel {} index {} mapped to {}, expected ~{}", ch, i, mapped, i);
            }
        }
    }

    #[test]
    fn match_frames_brightens_dark_to_bright() {
        let mut target = solid_frame(16, 16, 50, 50, 50);
        let reference = solid_frame(16, 16, 200, 200, 200);
        match_frames(&mut target, &reference, 16, 16);
        // After matching, the target's pixels should be brighter (closer to 200)
        assert!(target[0] > 100, "expected brightened target, got {}", target[0]);
    }
}
