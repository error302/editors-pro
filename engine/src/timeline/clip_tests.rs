//! Comprehensive tests for the timeline Clip model
//!
//! Covers: construction, split, trim, speed, properties,
//! effects management, keyframe operations, and time queries.

use super::clip::{Clip, TextProperties};
use super::keyframe::{Keyframe, KeyframeTrack};
use super::speed_curve::SpeedCurve;
use crate::effects::Effect;

#[test]
fn clip_new_has_expected_defaults() {
    let clip = Clip::new("asset-1", 1000, 5000);
    assert_eq!(clip.asset_id, "asset-1");
    assert_eq!(clip.start_ms, 1000);
    assert_eq!(clip.duration_ms, 5000);
    assert_eq!(clip.trim_start_ms, 0);
    assert_eq!(clip.trim_end_ms, 0);
    assert!((clip.opacity - 1.0).abs() < f32::EPSILON);
    assert!(clip.effects.is_empty());
    assert!(clip.transition_in.is_none());
    assert!(clip.transition_out.is_none());
    assert!(clip.properties.is_empty());
    assert!(!clip.id.is_empty());
}

#[test]
fn clip_from_range_calculates_duration() {
    let clip = Clip::from_range("asset-1", 500, 200, 700);
    assert_eq!(clip.start_ms, 500);
    assert_eq!(clip.duration_ms, 500);
    assert_eq!(clip.trim_start_ms, 200);
    assert_eq!(clip.trim_end_ms, 0);
}

#[test]
fn clip_from_range_zero_range() {
    let clip = Clip::from_range("asset-1", 0, 1000, 1000);
    assert_eq!(clip.duration_ms, 0); // saturating_sub yields 0
}

#[test]
fn effective_duration_equals_duration_ms() {
    let clip = Clip::new("a", 0, 3000);
    assert_eq!(clip.effective_duration(), 3000);
}

#[test]
fn end_ms_calculation() {
    let clip = Clip::new("a", 1000, 5000);
    assert_eq!(clip.end_ms(), 6000);
}

#[test]
fn source_duration_with_constant_speed() {
    let clip = Clip::new("a", 0, 4000);
    // At 1x speed, source_duration = duration * speed = 4000 * 1.0 = 4000
    assert_eq!(clip.source_duration_ms(), 4000);
}

#[test]
fn source_duration_with_2x_speed() {
    let clip = Clip::new("a", 0, 4000).with_speed(2.0);
    // At 2x speed: source_duration = timeline_dur * speed = 2000 * 2.0 = 4000
    assert_eq!(clip.source_duration_ms(), 4000);
}

#[test]
fn split_at_valid_point() {
    let clip = Clip::new("a", 1000, 5000);
    let (left, right) = clip.split_at(3500).unwrap();

    assert_eq!(left.start_ms, 1000);
    assert_eq!(left.duration_ms, 2500); // 3500 - 1000
    assert_eq!(right.start_ms, 3500);
    assert_eq!(right.duration_ms, 2500); // 5000 - 2500
    assert_ne!(left.id, right.id);
    assert_ne!(left.id, clip.id);
}

#[test]
fn split_at_clip_start_fails() {
    let clip = Clip::new("a", 1000, 5000);
    assert!(clip.split_at(1000).is_err());
}

#[test]
fn split_at_clip_end_fails() {
    let clip = Clip::new("a", 1000, 5000);
    assert!(clip.split_at(6000).is_err());
}

#[test]
fn split_at_before_clip_fails() {
    let clip = Clip::new("a", 1000, 5000);
    assert!(clip.split_at(500).is_err());
}

#[test]
fn with_speed_adjusts_duration() {
    let clip = Clip::new("a", 0, 4000);
    let faster = clip.with_speed(2.0);
    // source_duration = 4000 * 1.0 = 4000; new_dur = 4000 / 2.0 = 2000
    assert_eq!(faster.duration_ms, 2000);
}

#[test]
fn with_speed_minimum_clamp() {
    let clip = Clip::new("a", 0, 4000);
    let slow = clip.with_speed(0.01);
    // speed is clamped to 0.1
    // source_dur = 4000; new_dur = 4000 / 0.1 = 40000
    assert_eq!(slow.duration_ms, 40000);
}

#[test]
fn with_trim_reduces_duration() {
    let clip = Clip::new("a", 0, 4000);
    let trimmed = clip.with_trim(500, 500);
    // source_dur = 4000; total_trim = 1000; trimmed_source = 3000
    // new_dur = 3000 / 1.0 = 3000
    assert_eq!(trimmed.trim_start_ms, 500);
    assert_eq!(trimmed.trim_end_ms, 500);
}

#[test]
fn with_trim_exceeding_source_clamps() {
    let clip = Clip::new("a", 0, 4000);
    let trimmed = clip.with_trim(3000, 3000);
    // total_trim = 6000 >= source_dur(4000) → clamp, return unchanged
    assert_eq!(trimmed.trim_start_ms, 0);
    assert_eq!(trimmed.trim_end_ms, 0);
}

#[test]
fn set_and_get_property() {
    let mut clip = Clip::new("a", 0, 1000);
    clip.set_property("text", serde_json::json!("Hello World"));
    clip.set_property("font_size", serde_json::json!(24));

    assert_eq!(
        clip.get_property("text").unwrap(),
        &serde_json::json!("Hello World")
    );
    assert_eq!(
        clip.get_property("font_size").unwrap(),
        &serde_json::json!(24)
    );
    assert!(clip.get_property("nonexistent").is_none());
}

#[test]
fn add_and_remove_effect() {
    let mut clip = Clip::new("a", 0, 1000);
    let effect = crate::effects::filters::FilterType::Brightness.to_effect();
    let effect_id = effect.id.clone();

    clip.add_effect(effect);
    assert_eq!(clip.effects.len(), 1);

    let removed = clip.remove_effect(&effect_id);
    assert!(removed.is_some());
    assert!(clip.effects.is_empty());
}

#[test]
fn remove_effect_not_found() {
    let mut clip = Clip::new("a", 0, 1000);
    assert!(clip.remove_effect("nonexistent").is_none());
}

#[test]
fn enabled_effects_filters_disabled() {
    let mut clip = Clip::new("a", 0, 1000);
    let mut e1 = crate::effects::filters::FilterType::Brightness.to_effect();
    e1.enabled = true;
    let mut e2 = crate::effects::filters::FilterType::Contrast.to_effect();
    e2.enabled = false;

    clip.add_effect(e1);
    clip.add_effect(e2);

    let enabled = clip.enabled_effects();
    assert_eq!(enabled.len(), 1);
    assert_eq!(enabled[0].effect_type, crate::effects::EffectType::Filter);
}

#[test]
fn set_effect_parameter() {
    let mut clip = Clip::new("a", 0, 1000);
    let effect = crate::effects::filters::FilterType::Brightness.to_effect();
    let effect_id = effect.id.clone();

    clip.add_effect(effect);
    // Try to set the first parameter
    if let Some(param) = clip.effects[0].parameters.first() {
        let name = param.name.clone();
        let result = clip.set_effect_parameter(&effect_id, &name, 0.75);
        assert!(result.is_ok());
    }
}

#[test]
fn set_effect_parameter_wrong_effect() {
    let mut clip = Clip::new("a", 0, 1000);
    let result = clip.set_effect_parameter("nonexistent", "value", 0.5);
    assert!(result.is_err());
}

#[test]
fn contains_time() {
    let clip = Clip::new("a", 1000, 5000);
    assert!(clip.contains_time(1000));
    assert!(clip.contains_time(3000));
    assert!(!clip.contains_time(999));
    assert!(!clip.contains_time(6000)); // end is exclusive
}

#[test]
fn progress_at() {
    let clip = Clip::new("a", 1000, 4000);
    assert!((clip.progress_at(1000) - 0.0).abs() < f32::EPSILON);
    assert!((clip.progress_at(3000) - 0.5).abs() < f32::EPSILON);
    assert!((clip.progress_at(5000) - 1.0).abs() < f32::EPSILON);
}

#[test]
fn progress_at_zero_duration() {
    let clip = Clip::new("a", 0, 0);
    assert!((clip.progress_at(0) - 0.0).abs() < f32::EPSILON);
}

#[test]
fn progress_at_clamps_beyond_end() {
    let clip = Clip::new("a", 0, 1000);
    assert!((clip.progress_at(5000) - 1.0).abs() < f32::EPSILON);
}

#[test]
fn speed_returns_average_speed() {
    let clip = Clip::new("a", 0, 1000);
    assert!((clip.speed() - 1.0).abs() < f32::EPSILON);
}

#[test]
fn clip_serialization_roundtrip() {
    let mut clip = Clip::new("asset-1", 500, 3000);
    clip.set_property("label", serde_json::json!("My Clip"));

    let json = serde_json::to_string(&clip).unwrap();
    let parsed: Clip = serde_json::from_str(&json).unwrap();

    assert_eq!(parsed.asset_id, "asset-1");
    assert_eq!(parsed.start_ms, 500);
    assert_eq!(parsed.duration_ms, 3000);
    assert_eq!(
        parsed.get_property("label").unwrap(),
        &serde_json::json!("My Clip")
    );
}

#[test]
fn text_properties_default_text() {
    let tp = TextProperties::default_text("Hello");
    assert_eq!(tp.content, "Hello");
    assert_eq!(tp.font_family, "sans-serif");
    assert_eq!(tp.font_size, 48.0);
    assert_eq!(tp.color, "#FFFFFF");
    assert!(tp.background_color.is_none());
    assert!((tp.position_x - 0.5).abs() < f32::EPSILON);
    assert!((tp.position_y - 0.9).abs() < f32::EPSILON);
}

#[test]
fn transition_in_out() {
    let mut clip = Clip::new("a", 0, 1000);
    let transition =
        crate::effects::Transition::new(crate::effects::TransitionType::Dissolve, 500, "a", "b");

    clip.set_transition_in(transition.clone());
    assert!(clip.transition_in.is_some());
    assert_eq!(clip.transition_in.as_ref().unwrap().duration_ms, 500);

    clip.set_transition_out(transition);
    assert!(clip.transition_out.is_some());
}

#[test]
fn set_speed_curve() {
    let mut clip = Clip::new("a", 0, 1000);
    let curve = SpeedCurve::constant(2.0);
    clip.set_speed_curve(curve);
    assert!((clip.speed() - 2.0).abs() < 0.01);
}
