//! Clip model - A segment of media on a track
//!
//! A clip represents a portion of a media asset placed on the timeline.
//! It tracks the position, duration, trim points, speed curve, effects,
//! keyframe animations, and custom properties.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::effects::{Effect, Transition};
use super::keyframe::{ClipKeyframes, InterpolatedValues, Keyframe, KeyframeTrack};
use super::speed_curve::{EasingType, SpeedCurve};

/// A clip on the timeline representing a segment of media
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Clip {
    /// Unique clip identifier
    pub id: String,
    /// Reference to the media asset this clip uses
    pub asset_id: String,
    /// Position on the timeline in milliseconds
    pub start_ms: u64,
    /// Duration of the clip on the timeline in milliseconds
    pub duration_ms: u64,
    /// Trim from the start of the source media in milliseconds
    pub trim_start_ms: u64,
    /// Trim from the end of the source media in milliseconds
    pub trim_end_ms: u64,
    /// Whether the clip is muted
    pub muted: bool,
    /// Clip volume level (0.0 to 2.0, 1.0 = normal)
    pub volume: f32,
    /// Speed curve for variable playback speed (replaces flat speed: f32)
    pub speed_curve: SpeedCurve,
    /// Opacity level (0.0 = transparent, 1.0 = fully opaque)
    pub opacity: f32,
    /// Visual effects applied to this clip (ordered pipeline)
    pub effects: Vec<Effect>,
    /// Transition applied at the start of this clip (in-point)
    pub transition_in: Option<Transition>,
    /// Transition applied at the end of this clip (out-point)
    pub transition_out: Option<Transition>,
    /// Keyframe animation tracks for this clip
    pub keyframes: ClipKeyframes,
    /// Custom properties for text content, etc.
    pub properties: HashMap<String, serde_json::Value>,
}

impl Clip {
    /// Create a new clip from a media asset
    pub fn new(asset_id: &str, start_ms: u64, duration_ms: u64) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            asset_id: asset_id.to_string(),
            start_ms,
            duration_ms,
            trim_start_ms: 0,
            trim_end_ms: 0,
            muted: false,
            volume: 1.0,
            speed_curve: SpeedCurve::constant(1.0),
            opacity: 1.0,
            effects: Vec::new(),
            transition_in: None,
            transition_out: None,
            keyframes: ClipKeyframes::new(),
            properties: HashMap::new(),
        }
    }

    /// Create a clip from a specific portion of a media asset
    pub fn from_range(asset_id: &str, start_ms: u64, source_start_ms: u64, source_end_ms: u64) -> Self {
        let duration = source_end_ms.saturating_sub(source_start_ms);
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            asset_id: asset_id.to_string(),
            start_ms,
            duration_ms: duration,
            trim_start_ms: source_start_ms,
            trim_end_ms: 0,
            muted: false,
            volume: 1.0,
            speed_curve: SpeedCurve::constant(1.0),
            opacity: 1.0,
            effects: Vec::new(),
            transition_in: None,
            transition_out: None,
            keyframes: ClipKeyframes::new(),
            properties: HashMap::new(),
        }
    }

    /// Get the effective speed at a given time (convenience accessor)
    ///
    /// For simple constant-speed clips, this returns the same value as
    /// `speed_curve.average_speed()`.
    pub fn speed(&self) -> f32 {
        self.speed_curve.average_speed()
    }

    /// Get the speed at a specific point in the clip
    pub fn speed_at(&self, relative_time_ms: u64) -> f32 {
        self.speed_curve.evaluate_speed_at(relative_time_ms)
    }

    /// Calculate the effective duration considering speed
    /// When speed is 2x, a 10s source plays in 5s on the timeline
    pub fn effective_duration(&self) -> u64 {
        // The duration_ms already reflects the timeline duration
        // which accounts for speed changes
        self.duration_ms
    }

    /// Get the source media duration (before speed adjustment)
    pub fn source_duration_ms(&self) -> u64 {
        let avg_speed = self.speed_curve.average_speed();
        if avg_speed > 0.0 {
            (self.duration_ms as f32 * avg_speed) as u64
        } else {
            self.duration_ms
        }
    }

    /// Get the end position of this clip on the timeline
    pub fn end_ms(&self) -> u64 {
        self.start_ms + self.effective_duration()
    }

    /// Split this clip at the given timeline timestamp
    /// Returns two new clips if the split point is valid
    pub fn split_at(&self, time_ms: u64) -> Result<(Clip, Clip), String> {
        if time_ms <= self.start_ms {
            return Err("Split point is at or before clip start".to_string());
        }
        if time_ms >= self.end_ms() {
            return Err("Split point is at or after clip end".to_string());
        }

        let left_duration = time_ms - self.start_ms;
        let right_duration = self.effective_duration() - left_duration;

        // Left clip: same start, shorter duration
        let mut left = self.clone();
        left.id = uuid::Uuid::new_v4().to_string();
        left.duration_ms = left_duration;

        // Right clip: starts at split point, rest of duration
        let mut right = self.clone();
        right.id = uuid::Uuid::new_v4().to_string();
        right.start_ms = time_ms;
        right.duration_ms = right_duration;
        // The right clip's trim_start advances by the left portion's source duration
        right.trim_start_ms = self.trim_start_ms + left_duration;

        Ok((left, right))
    }

    /// Create a copy of this clip with a different constant speed
    pub fn with_speed(&self, speed: f32) -> Self {
        let mut new_clip = self.clone();
        let clamped_speed = speed.max(0.1); // Minimum 0.1x speed
        new_clip.speed_curve = SpeedCurve::constant(clamped_speed);
        // Adjust timeline duration based on speed ratio
        let source_dur = self.source_duration_ms();
        new_clip.duration_ms = (source_dur as f32 / clamped_speed) as u64;
        new_clip
    }

    /// Set the speed curve for this clip
    pub fn set_speed_curve(&mut self, curve: SpeedCurve) {
        self.speed_curve = curve;
    }

    /// Create a copy with different trim points
    pub fn with_trim(&self, trim_start_ms: u64, trim_end_ms: u64) -> Self {
        let mut new_clip = self.clone();
        let original_source = self.source_duration_ms();

        // Validate trim doesn't exceed source length
        let total_trim = trim_start_ms + trim_end_ms;
        if total_trim >= original_source {
            log::warn!("Trim exceeds source duration, clamping");
            return new_clip;
        }

        new_clip.trim_start_ms = trim_start_ms;
        new_clip.trim_end_ms = trim_end_ms;

        // Recalculate timeline duration based on trimmed source and speed
        let trimmed_source = original_source - total_trim;
        let avg_speed = new_clip.speed_curve.average_speed();
        if avg_speed > 0.0 {
            new_clip.duration_ms = (trimmed_source as f32 / avg_speed) as u64;
        }

        new_clip
    }

    /// Set a custom property on this clip
    pub fn set_property(&mut self, key: &str, value: serde_json::Value) {
        self.properties.insert(key.to_string(), value);
    }

    /// Get a custom property from this clip
    pub fn get_property(&self, key: &str) -> Option<&serde_json::Value> {
        self.properties.get(key)
    }

    /// Add an effect to this clip's pipeline
    pub fn add_effect(&mut self, effect: Effect) {
        let order = effect.order;
        self.effects.push(effect);
        self.effects.sort_by_key(|e| e.order);
    }

    /// Remove an effect from this clip by ID
    pub fn remove_effect(&mut self, effect_id: &str) -> Option<Effect> {
        if let Some(pos) = self.effects.iter().position(|e| e.id == effect_id) {
            Some(self.effects.remove(pos))
        } else {
            None
        }
    }

    /// Update a parameter of a specific effect on this clip
    pub fn set_effect_parameter(&mut self, effect_id: &str, param_name: &str, value: f32) -> Result<(), String> {
        let effect = self.effects.iter_mut()
            .find(|e| e.id == effect_id)
            .ok_or_else(|| format!("Effect {} not found on clip {}", effect_id, self.id))?;
        let param = effect.parameters.iter_mut()
            .find(|p| p.name == param_name)
            .ok_or_else(|| format!("Parameter {} not found on effect {}", param_name, effect_id))?;
        param.set_value(value);
        Ok(())
    }

    /// Get all enabled effects in order
    pub fn enabled_effects(&self) -> Vec<&Effect> {
        self.effects.iter().filter(|e| e.enabled).collect()
    }

    /// Set the transition at the clip's in-point
    pub fn set_transition_in(&mut self, transition: Transition) {
        self.transition_in = Some(transition);
    }

    /// Set the transition at the clip's out-point
    pub fn set_transition_out(&mut self, transition: Transition) {
        self.transition_out = Some(transition);
    }

    /// Check if a given timestamp is within this clip's range
    pub fn contains_time(&self, time_ms: u64) -> bool {
        time_ms >= self.start_ms && time_ms < self.end_ms()
    }

    /// Get the relative position within the clip for a given timeline time
    /// Returns 0.0 at clip start, 1.0 at clip end
    pub fn progress_at(&self, time_ms: u64) -> f32 {
        if self.effective_duration() == 0 {
            return 0.0;
        }
        let relative = time_ms.saturating_sub(self.start_ms) as f32;
        (relative / self.effective_duration() as f32).clamp(0.0, 1.0)
    }

    // ─── Keyframe Operations ──────────────────────────────────────────

    /// Add a keyframe to a property track
    pub fn add_keyframe(&mut self, property: &str, keyframe: Keyframe) -> Result<(), String> {
        let track = self.keyframes.track_for(property)
            .ok_or_else(|| format!("Unknown keyframe property: {}", property))?;
        track.add_keyframe(keyframe);
        Ok(())
    }

    /// Remove a keyframe by ID from a property track
    pub fn remove_keyframe(&mut self, property: &str, keyframe_id: &str) -> Result<bool, String> {
        let track = self.keyframes.track_for(property)
            .ok_or_else(|| format!("Unknown keyframe property: {}", property))?;
        Ok(track.remove_keyframe(keyframe_id))
    }

    /// Update a keyframe's value and/or easing
    pub fn update_keyframe(
        &mut self,
        property: &str,
        keyframe_id: &str,
        value: Option<f32>,
        easing: Option<EasingType>,
    ) -> Result<bool, String> {
        let track = self.keyframes.track_for(property)
            .ok_or_else(|| format!("Unknown keyframe property: {}", property))?;
        Ok(track.update_keyframe(keyframe_id, value, easing))
    }

    /// Interpolate all keyframe properties at a given time
    ///
    /// Returns `InterpolatedValues` with position, scale, rotation, and opacity.
    /// If no keyframes exist for a property, the default value is returned.
    pub fn interpolate_at(&self, time_ms: u64) -> InterpolatedValues {
        self.keyframes.interpolate_all(time_ms)
    }

    /// Check if this clip has any keyframe animations
    pub fn has_keyframes(&self) -> bool {
        self.keyframes.has_any_keyframes()
    }

    /// Get a reference to a keyframe track by property name
    pub fn keyframe_track(&self, property: &str) -> Option<&KeyframeTrack> {
        self.keyframes.track_for_ref(property)
    }
}

/// Clip-specific properties for text overlays
/// Re-uses types from the effects::text_render module to avoid duplication
pub use crate::effects::text_render::{TextAnchor, TextAnimation, SlideDirection};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextProperties {
    pub content: String,
    pub font_family: String,
    pub font_size: f32,
    pub color: String,
    pub background_color: Option<String>,
    pub position_x: f32,
    pub position_y: f32,
    pub anchor: TextAnchor,
    pub animation: TextAnimation,
}

impl TextProperties {
    pub fn default_text(content: &str) -> Self {
        Self {
            content: content.to_string(),
            font_family: "sans-serif".to_string(),
            font_size: 48.0,
            color: "#FFFFFF".to_string(),
            background_color: None,
            position_x: 0.5,
            position_y: 0.9,
            anchor: TextAnchor::BottomCenter,
            animation: TextAnimation::None,
        }
    }
}
