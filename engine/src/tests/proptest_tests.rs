//! Property-based tests using proptest
//!
//! These tests verify invariants hold for arbitrary inputs, catching
//! edge cases that hand-written tests might miss.

use proptest::prelude::*;

use crate::decoder::{FrameData, VideoInfo};
use crate::timeline::clip::Clip;
use crate::timeline::track::{Track, TrackType};
use crate::utils::math::{hsv_to_rgb, rgb_to_hsv};

// ─── Color Roundtrip: RGB → HSV → RGB ───────────────────────

proptest! {
    #[test]
    fn rgb_hsv_roundtrip(
        r in 0u8..=255,
        g in 0u8..=255,
        b in 0u8..=255,
    ) {
        let (h, s, l) = rgb_to_hsv(r as f64 / 255.0, g as f64 / 255.0, b as f64 / 255.0);
        let (r2, g2, b2) = hsv_to_rgb(h, s, l);
        let (r2, g2, b2) = ((r2 * 255.0).round() as u8, (g2 * 255.0).round() as u8, (b2 * 255.0).round() as u8);
        // Allow 1-unit tolerance due to floating point
        assert!(
            (r as i16 - r2 as i16).abs() <= 1 &&
            (g as i16 - g2 as i16).abs() <= 1 &&
            (b as i16 - b2 as i16).abs() <= 1,
            "Roundtrip failed: ({}, {}, {}) → ({:.1}, {:.2}, {:.2}) → ({}, {}, {})",
            r, g, b, h, s, l, r2, g2, b2
        );
    }
}

// ─── Clip Split Invariants ───────────────────────────────────

proptest! {
    #[test]
    fn clip_split_durations_sum_to_original(
        start_ms in 0u64..10000u64,
        duration_ms in 100u64..60000u64,
        split_offset in 1u64..100u64,
    ) {
        let clip = Clip::new("asset-1", start_ms, duration_ms);
        let split_point = start_ms + (split_offset % duration_ms).max(1).min(duration_ms - 1);

        if let Ok((left, right)) = clip.split_at(split_point) {
            assert_eq!(left.duration_ms + right.duration_ms, duration_ms);
            assert_eq!(left.start_ms, start_ms);
            assert_eq!(right.start_ms, split_point);
            assert_ne!(left.id, right.id);
            assert_ne!(left.id, clip.id);
            assert_ne!(right.id, clip.id);
        }
    }
}

// ─── Track Volume Clamp Invariant ────────────────────────────

proptest! {
    #[test]
    fn track_volume_always_clamped(
        volume in -100.0f32..=100.0f32,
    ) {
        let mut track = Track::new("V1".into(), TrackType::Video, 0);
        track.set_volume(volume);
        assert!(track.volume >= 0.0 && track.volume <= 2.0);
    }
}

// ─── VideoInfo Serialization Invariant ───────────────────────

proptest! {
    #[test]
    fn video_info_serde_roundtrip(
        width in 1u32..=7680u32,
        height in 1u32..=4320u32,
        fps in 1.0f32..=240.0f32,
        duration_ms in 0u64..=3600000u64,
        bitrate in 0u64..=100000000u64,
        has_audio in any::<bool>(),
    ) {
        let info = VideoInfo {
            width,
            height,
            fps,
            duration_ms,
            codec_name: "h264".to_string(),
            bitrate,
            has_audio,
            audio_codec: None,
            audio_sample_rate: None,
            audio_channels: None,
        };

        let json = serde_json::to_string(&info).unwrap();
        let parsed: VideoInfo = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed.width, width);
        assert_eq!(parsed.height, height);
        assert!((parsed.fps - fps).abs() < 0.01);
        assert_eq!(parsed.duration_ms, duration_ms);
        assert_eq!(parsed.bitrate, bitrate);
        assert_eq!(parsed.has_audio, has_audio);
    }
}

// ─── FrameData Blank Size Invariant ──────────────────────────

proptest! {
    #[test]
    fn frame_data_blank_size_matches_dimensions(
        width in 1u32..=1920u32,
        height in 1u32..=1080u32,
    ) {
        let frame = FrameData::blank(width, height);
        assert_eq!(frame.data.len(), (width * height * 4) as usize);
        assert_eq!(frame.pixel_count(), width * height);
        assert_eq!(frame.data_size(), (width * height * 4) as usize);
    }
}
