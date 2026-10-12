//! Command system for undo/redo operations
//!
//! Implements the Command pattern for all timeline mutations,
//! enabling full undo/redo support throughout the editor.

use serde::{Deserialize, Serialize};

use super::clip::Clip;
use super::Timeline;

/// Result of executing a command
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommandResult {
    pub success: bool,
    pub message: String,
    pub affected_clip_ids: Vec<String>,
}

/// A trait for commands that can be executed and undone on a timeline
pub trait Command: std::fmt::Debug + Send {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String>;
    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String>;
    fn description(&self) -> String;
}

/// Command to add a clip to a track
#[derive(Debug, Clone)]
pub struct AddClipCommand {
    pub track_id: String,
    pub clip: Option<Clip>,
    pub clip_id: String,
}

impl AddClipCommand {
    pub fn new(track_id: String, clip: Clip) -> Self {
        let clip_id = clip.id.clone();
        Self {
            track_id,
            clip: Some(clip),
            clip_id,
        }
    }
}

impl Command for AddClipCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let clip = self.clip.take().ok_or("No clip to add")?;
        let clip_id = clip.id.clone();
        timeline.add_clip_to_track(&self.track_id, clip)?;
        Ok(CommandResult {
            success: true,
            message: "Clip added".to_string(),
            affected_clip_ids: vec![clip_id],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        // Remove the clip we added and store it for redo
        self.clip = timeline.remove_clip(&self.clip_id);

        Ok(CommandResult {
            success: true,
            message: "Clip addition undone".to_string(),
            affected_clip_ids: self.clip.as_ref().map(|c| vec![c.id.clone()]).unwrap_or_default(),
        })
    }

    fn description(&self) -> String {
        "Add clip".to_string()
    }
}

/// Command to remove a clip from a track
#[derive(Debug, Clone)]
pub struct RemoveClipCommand {
    pub clip_id: String,
    pub removed_clip: Option<Clip>,
    pub track_id: Option<String>,
}

impl RemoveClipCommand {
    pub fn new(clip_id: String) -> Self {
        Self {
            clip_id,
            removed_clip: None,
            track_id: None,
        }
    }
}

impl Command for RemoveClipCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        // Find which track contains the clip
        let track_id = timeline.tracks.iter()
            .find(|t| t.find_clip(&self.clip_id).is_some())
            .map(|t| t.id.clone())
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        self.track_id = Some(track_id);

        // Remove the clip and store it for undo
        self.removed_clip = timeline.remove_clip(&self.clip_id);

        Ok(CommandResult {
            success: true,
            message: "Clip removed".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let clip = self.removed_clip.take().ok_or("No clip to restore")?;
        let track_id = self.track_id.as_ref().ok_or("No track ID stored")?;
        let clip_id = clip.id.clone();
        timeline.add_clip_to_track(track_id, clip)?;

        Ok(CommandResult {
            success: true,
            message: "Clip removal undone".to_string(),
            affected_clip_ids: vec![clip_id],
        })
    }

    fn description(&self) -> String {
        "Remove clip".to_string()
    }
}

/// Command to trim a clip
#[derive(Debug, Clone)]
pub struct TrimClipCommand {
    pub clip_id: String,
    pub new_trim_start: u64,
    pub new_trim_end: u64,
    pub old_trim_start: Option<u64>,
    pub old_trim_end: Option<u64>,
    pub old_duration_ms: Option<u64>,
}

impl TrimClipCommand {
    pub fn new(clip_id: String, trim_start: u64, trim_end: u64) -> Self {
        Self {
            clip_id,
            new_trim_start: trim_start,
            new_trim_end: trim_end,
            old_trim_start: None,
            old_trim_end: None,
            old_duration_ms: None,
        }
    }
}

impl Command for TrimClipCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        // Store old values for undo
        self.old_trim_start = Some(clip.trim_start_ms);
        self.old_trim_end = Some(clip.trim_end_ms);
        self.old_duration_ms = Some(clip.duration_ms);

        // Apply new trim using the clip's with_trim method which handles duration
        let trimmed = clip.with_trim(self.new_trim_start, self.new_trim_end);
        clip.trim_start_ms = trimmed.trim_start_ms;
        clip.trim_end_ms = trimmed.trim_end_ms;
        clip.duration_ms = trimmed.duration_ms;

        // Recalculate timeline duration
        timeline.recalculate_duration();

        Ok(CommandResult {
            success: true,
            message: "Clip trimmed".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        clip.trim_start_ms = self.old_trim_start.ok_or("No old trim start")?;
        clip.trim_end_ms = self.old_trim_end.ok_or("No old trim end")?;
        clip.duration_ms = self.old_duration_ms.ok_or("No old duration")?;
        timeline.recalculate_duration();

        Ok(CommandResult {
            success: true,
            message: "Trim undone".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn description(&self) -> String {
        "Trim clip".to_string()
    }
}

/// Command to move a clip to a new position on the timeline
#[derive(Debug, Clone)]
pub struct MoveClipCommand {
    pub clip_id: String,
    pub new_start_ms: u64,
    pub old_start_ms: Option<u64>,
    pub new_track_id: Option<String>,
    pub old_track_id: Option<String>,
}

impl MoveClipCommand {
    pub fn new(clip_id: String, new_start_ms: u64, new_track_id: Option<String>) -> Self {
        Self {
            clip_id,
            new_start_ms,
            old_start_ms: None,
            new_track_id,
            old_track_id: None,
        }
    }
}

impl Command for MoveClipCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        // Find the current track
        let current_track_id = timeline.tracks.iter()
            .find(|t| t.find_clip(&self.clip_id).is_some())
            .map(|t| t.id.clone())
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        self.old_track_id = Some(current_track_id.clone());

        let (_, clip) = timeline.find_clip(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        self.old_start_ms = Some(clip.start_ms);

        // If moving to a different track
        let target_track_id = self.new_track_id.as_ref().unwrap_or(&current_track_id);

        if target_track_id != &current_track_id {
            // Remove from current track, add to new track
            let clip_data = timeline.remove_clip(&self.clip_id)
                .ok_or("Failed to remove clip from source track")?;
            let mut moved_clip = clip_data;
            moved_clip.start_ms = self.new_start_ms;
            timeline.add_clip_to_track(target_track_id, moved_clip)?;
        } else {
            // Just update the start position on the same track
            let clip = timeline.find_clip_mut(&self.clip_id)
                .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
            clip.start_ms = self.new_start_ms;
        }

        timeline.recalculate_duration();

        Ok(CommandResult {
            success: true,
            message: "Clip moved".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let old_start = self.old_start_ms.ok_or("No old start position")?;
        let old_track = self.old_track_id.as_ref().ok_or("No old track ID")?;

        let current_track_id = timeline.tracks.iter()
            .find(|t| t.find_clip(&self.clip_id).is_some())
            .map(|t| t.id.clone());

        if let Some(current_track) = current_track_id {
            if &current_track != old_track {
                let clip_data = timeline.remove_clip(&self.clip_id)
                    .ok_or("Failed to remove clip")?;
                let mut moved_clip = clip_data;
                moved_clip.start_ms = old_start;
                timeline.add_clip_to_track(old_track, moved_clip)?;
            } else {
                let clip = timeline.find_clip_mut(&self.clip_id)
                    .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
                clip.start_ms = old_start;
            }
        }

        timeline.recalculate_duration();

        Ok(CommandResult {
            success: true,
            message: "Move undone".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn description(&self) -> String {
        "Move clip".to_string()
    }
}

/// Command to split a clip at a timestamp
#[derive(Debug, Clone)]
pub struct SplitClipCommand {
    pub clip_id: String,
    pub split_time_ms: u64,
    pub left_clip_id: Option<String>,
    pub right_clip_id: Option<String>,
    pub original_clip: Option<Clip>,
    pub original_track_id: Option<String>,
}

impl SplitClipCommand {
    pub fn new(clip_id: String, split_time_ms: u64) -> Self {
        Self {
            clip_id,
            split_time_ms,
            left_clip_id: None,
            right_clip_id: None,
            original_clip: None,
            original_track_id: None,
        }
    }
}

impl Command for SplitClipCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        // Store the original clip and track for undo
        let (track, clip) = timeline.find_clip(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
        self.original_clip = Some(clip.clone());
        self.original_track_id = Some(track.id.clone());

        let (left, right) = timeline.split_clip(&self.clip_id, self.split_time_ms)?;
        self.left_clip_id = Some(left.id.clone());
        self.right_clip_id = Some(right.id.clone());

        Ok(CommandResult {
            success: true,
            message: "Clip split".to_string(),
            affected_clip_ids: vec![left.id, right.id],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        // Remove the split clips
        if let Some(left_id) = &self.left_clip_id {
            timeline.remove_clip(left_id);
        }
        if let Some(right_id) = &self.right_clip_id {
            timeline.remove_clip(right_id);
        }

        // Restore the original clip to the correct track
        let original = self.original_clip.take().ok_or("No original clip stored")?;
        let track_id = self.original_track_id.take()
            .ok_or("No original track ID stored")?;

        timeline.add_clip_to_track(&track_id, original)?;

        Ok(CommandResult {
            success: true,
            message: "Split undone".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn description(&self) -> String {
        "Split clip".to_string()
    }
}

/// Command to set a track's volume level
#[derive(Debug, Clone)]
pub struct SetTrackVolumeCommand {
    pub track_id: String,
    pub new_volume: f32,
    pub old_volume: Option<f32>,
}

impl SetTrackVolumeCommand {
    pub fn new(track_id: String, new_volume: f32) -> Self {
        Self {
            track_id,
            new_volume: new_volume.clamp(0.0, 2.0),
            old_volume: None,
        }
    }
}

impl Command for SetTrackVolumeCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let track = timeline.find_track_mut(&self.track_id)
            .ok_or_else(|| format!("Track {} not found", self.track_id))?;

        self.old_volume = Some(track.volume);
        track.set_volume(self.new_volume);

        Ok(CommandResult {
            success: true,
            message: format!("Track volume set to {:.2}", self.new_volume),
            affected_clip_ids: vec![],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let old_volume = self.old_volume.ok_or("No old volume stored")?;
        let track = timeline.find_track_mut(&self.track_id)
            .ok_or_else(|| format!("Track {} not found", self.track_id))?;

        track.set_volume(old_volume);

        Ok(CommandResult {
            success: true,
            message: "Volume change undone".to_string(),
            affected_clip_ids: vec![],
        })
    }

    fn description(&self) -> String {
        "Set track volume".to_string()
    }
}

/// Command to toggle a track's visibility (mute/unmute for audio)
#[derive(Debug, Clone)]
pub struct ToggleTrackVisibilityCommand {
    pub track_id: String,
    pub old_visible: Option<bool>,
}

impl ToggleTrackVisibilityCommand {
    pub fn new(track_id: String) -> Self {
        Self {
            track_id,
            old_visible: None,
        }
    }
}

impl Command for ToggleTrackVisibilityCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let track = timeline.find_track_mut(&self.track_id)
            .ok_or_else(|| format!("Track {} not found", self.track_id))?;

        self.old_visible = Some(track.visible);
        track.toggle_visibility();

        Ok(CommandResult {
            success: true,
            message: "Track visibility toggled".to_string(),
            affected_clip_ids: vec![],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let old_visible = self.old_visible.ok_or("No old visibility stored")?;
        let track = timeline.find_track_mut(&self.track_id)
            .ok_or_else(|| format!("Track {} not found", self.track_id))?;

        track.visible = old_visible;

        Ok(CommandResult {
            success: true,
            message: "Visibility toggle undone".to_string(),
            affected_clip_ids: vec![],
        })
    }

    fn description(&self) -> String {
        "Toggle track visibility".to_string()
    }
}

/// Command to add an effect to a clip
#[derive(Debug, Clone)]
pub struct AddEffectCommand {
    pub clip_id: String,
    pub effect: Option<crate::effects::Effect>,
    pub effect_id: String,
}

impl AddEffectCommand {
    pub fn new(clip_id: String, effect: crate::effects::Effect) -> Self {
        let effect_id = effect.id.clone();
        Self {
            clip_id,
            effect: Some(effect),
            effect_id,
        }
    }
}

impl Command for AddEffectCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let effect = self.effect.take().ok_or("No effect to add")?;
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
        clip.add_effect(effect);
        Ok(CommandResult {
            success: true,
            message: "Effect added".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
        self.effect = clip.remove_effect(&self.effect_id);
        Ok(CommandResult {
            success: true,
            message: "Effect addition undone".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn description(&self) -> String {
        "Add effect".to_string()
    }
}

/// Command to remove an effect from a clip
#[derive(Debug, Clone)]
pub struct RemoveEffectCommand {
    pub clip_id: String,
    pub effect_id: String,
    pub removed_effect: Option<crate::effects::Effect>,
}

impl RemoveEffectCommand {
    pub fn new(clip_id: String, effect_id: String) -> Self {
        Self {
            clip_id,
            effect_id,
            removed_effect: None,
        }
    }
}

impl Command for RemoveEffectCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
        self.removed_effect = clip.remove_effect(&self.effect_id);
        if self.removed_effect.is_none() {
            return Err(format!("Effect {} not found on clip {}", self.effect_id, self.clip_id));
        }
        Ok(CommandResult {
            success: true,
            message: "Effect removed".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let effect = self.removed_effect.take().ok_or("No effect to restore")?;
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
        clip.add_effect(effect);
        Ok(CommandResult {
            success: true,
            message: "Effect removal undone".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn description(&self) -> String {
        "Remove effect".to_string()
    }
}

/// Command to set an effect parameter value
#[derive(Debug, Clone)]
pub struct SetEffectParameterCommand {
    pub clip_id: String,
    pub effect_id: String,
    pub param_name: String,
    pub new_value: f32,
    pub old_value: Option<f32>,
}

impl SetEffectParameterCommand {
    pub fn new(clip_id: String, effect_id: String, param_name: String, new_value: f32) -> Self {
        Self {
            clip_id,
            effect_id,
            param_name,
            new_value,
            old_value: None,
        }
    }
}

impl Command for SetEffectParameterCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        // Store the old value for undo
        let effect = clip.effects.iter()
            .find(|e| e.id == self.effect_id)
            .ok_or_else(|| format!("Effect {} not found", self.effect_id))?;
        self.old_value = effect.get_parameter(&self.param_name);

        clip.set_effect_parameter(&self.effect_id, &self.param_name, self.new_value)?;

        Ok(CommandResult {
            success: true,
            message: format!("Parameter {} set to {:.2}", self.param_name, self.new_value),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let old_value = self.old_value.ok_or("No old value stored")?;
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
        clip.set_effect_parameter(&self.effect_id, &self.param_name, old_value)?;
        Ok(CommandResult {
            success: true,
            message: "Parameter change undone".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn description(&self) -> String {
        "Set effect parameter".to_string()
    }
}

/// Command to add a transition to a clip
#[derive(Debug, Clone)]
pub struct AddTransitionCommand {
    pub clip_id: String,
    pub transition: Option<crate::effects::Transition>,
    pub transition_type: String, // "in" or "out"
    pub old_transition: Option<crate::effects::Transition>,
}

impl AddTransitionCommand {
    pub fn new_in(clip_id: String, transition: crate::effects::Transition) -> Self {
        Self {
            clip_id,
            transition: Some(transition),
            transition_type: "in".to_string(),
            old_transition: None,
        }
    }

    pub fn new_out(clip_id: String, transition: crate::effects::Transition) -> Self {
        Self {
            clip_id,
            transition: Some(transition),
            transition_type: "out".to_string(),
            old_transition: None,
        }
    }
}

impl Command for AddTransitionCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let transition = self.transition.take().ok_or("No transition to add")?;
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        match self.transition_type.as_str() {
            "in" => {
                self.old_transition = clip.transition_in.take();
                clip.set_transition_in(transition);
            }
            "out" => {
                self.old_transition = clip.transition_out.take();
                clip.set_transition_out(transition);
            }
            _ => return Err("Invalid transition type, must be 'in' or 'out'".to_string()),
        }

        Ok(CommandResult {
            success: true,
            message: format!("Transition in added to clip {}", self.clip_id),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        match self.transition_type.as_str() {
            "in" => {
                clip.transition_in = self.old_transition.take();
            }
            "out" => {
                clip.transition_out = self.old_transition.take();
            }
            _ => return Err("Invalid transition type".to_string()),
        }

        Ok(CommandResult {
            success: true,
            message: "Transition addition undone".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn description(&self) -> String {
        "Add transition".to_string()
    }
}

/// Command to set a clip's speed curve
#[derive(Debug, Clone)]
pub struct SetSpeedCurveCommand {
    pub clip_id: String,
    pub new_curve: Option<super::speed_curve::SpeedCurve>,
    pub old_curve: Option<super::speed_curve::SpeedCurve>,
}

impl SetSpeedCurveCommand {
    pub fn new(clip_id: String, curve: super::speed_curve::SpeedCurve) -> Self {
        Self {
            clip_id,
            new_curve: Some(curve),
            old_curve: None,
        }
    }
}

impl Command for SetSpeedCurveCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        // Store old curve for undo
        self.old_curve = Some(clip.speed_curve.clone());

        // Apply new curve
        let new_curve = self.new_curve.take().ok_or("No speed curve to set")?;
        clip.set_speed_curve(new_curve);

        // Recalculate timeline duration since speed affects clip duration
        timeline.recalculate_duration();

        Ok(CommandResult {
            success: true,
            message: "Speed curve set".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let old_curve = self.old_curve.take().ok_or("No old speed curve stored")?;
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        // Store the current curve for redo
        self.new_curve = Some(clip.speed_curve.clone());
        clip.set_speed_curve(old_curve);
        timeline.recalculate_duration();

        Ok(CommandResult {
            success: true,
            message: "Speed curve change undone".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn description(&self) -> String {
        "Set speed curve".to_string()
    }
}

/// Command to add a keyframe to a clip's property track
#[derive(Debug, Clone)]
pub struct AddKeyframeCommand {
    pub clip_id: String,
    pub property: String,
    pub keyframe: Option<super::keyframe::Keyframe>,
    pub keyframe_id: String,
}

impl AddKeyframeCommand {
    pub fn new(clip_id: String, property: String, keyframe: super::keyframe::Keyframe) -> Self {
        let keyframe_id = keyframe.id.clone();
        Self {
            clip_id,
            property,
            keyframe: Some(keyframe),
            keyframe_id,
        }
    }
}

impl Command for AddKeyframeCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let keyframe = self.keyframe.take().ok_or("No keyframe to add")?;
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        // If a keyframe already exists at the same time, store it for undo
        if let Some(track) = clip.keyframe_track(&self.property) {
            if let Some(existing) = track.keyframes.iter().find(|k| k.time_ms == keyframe.time_ms) {
                self.keyframe = Some(existing.clone());
            } else {
                self.keyframe = Some(keyframe.clone());
            }
        }

        // Re-borrow to add the keyframe
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
        clip.add_keyframe(&self.property, keyframe)?;

        Ok(CommandResult {
            success: true,
            message: format!("Keyframe added to {}", self.property),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        // Remove the keyframe we added
        let removed = clip.remove_keyframe(&self.property, &self.keyframe_id)?;
        if !removed {
            return Err(format!("Keyframe {} not found for undo", self.keyframe_id));
        }

        Ok(CommandResult {
            success: true,
            message: "Keyframe addition undone".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn description(&self) -> String {
        "Add keyframe".to_string()
    }
}

/// Command to remove a keyframe from a clip's property track
#[derive(Debug, Clone)]
pub struct RemoveKeyframeCommand {
    pub clip_id: String,
    pub property: String,
    pub keyframe_id: String,
    pub removed_keyframe: Option<super::keyframe::Keyframe>,
}

impl RemoveKeyframeCommand {
    pub fn new(clip_id: String, property: String, keyframe_id: String) -> Self {
        Self {
            clip_id,
            property,
            keyframe_id,
            removed_keyframe: None,
        }
    }
}

impl Command for RemoveKeyframeCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        // Find and store the keyframe before removing
        if let Some(track) = clip.keyframe_track(&self.property) {
            if let Some(kf) = track.get(&self.keyframe_id) {
                self.removed_keyframe = Some(kf.clone());
            }
        }

        // Remove the keyframe
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
        let removed = clip.remove_keyframe(&self.property, &self.keyframe_id)?;
        if !removed {
            return Err(format!("Keyframe {} not found on clip {}", self.keyframe_id, self.clip_id));
        }

        Ok(CommandResult {
            success: true,
            message: "Keyframe removed".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let keyframe = self.removed_keyframe.take().ok_or("No keyframe to restore")?;
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        clip.add_keyframe(&self.property, keyframe)?;

        Ok(CommandResult {
            success: true,
            message: "Keyframe removal undone".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn description(&self) -> String {
        "Remove keyframe".to_string()
    }
}

/// Command to update a keyframe's value and/or easing
#[derive(Debug, Clone)]
pub struct UpdateKeyframeCommand {
    pub clip_id: String,
    pub property: String,
    pub keyframe_id: String,
    pub new_value: Option<f32>,
    pub new_easing: Option<super::speed_curve::EasingType>,
    pub old_value: Option<f32>,
    pub old_easing: Option<super::speed_curve::EasingType>,
}

impl UpdateKeyframeCommand {
    pub fn new(
        clip_id: String,
        property: String,
        keyframe_id: String,
        value: Option<f32>,
        easing: Option<super::speed_curve::EasingType>,
    ) -> Self {
        Self {
            clip_id,
            property,
            keyframe_id,
            new_value: value,
            new_easing: easing,
            old_value: None,
            old_easing: None,
        }
    }
}

impl Command for UpdateKeyframeCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;

        // Store old values for undo
        if let Some(track) = clip.keyframe_track(&self.property) {
            if let Some(kf) = track.get(&self.keyframe_id) {
                self.old_value = Some(kf.value);
                self.old_easing = Some(kf.easing);
            }
        }

        // Apply the update
        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
        let updated = clip.update_keyframe(
            &self.property,
            &self.keyframe_id,
            self.new_value,
            self.new_easing,
        )?;
        if !updated {
            return Err(format!("Keyframe {} not found", self.keyframe_id));
        }

        Ok(CommandResult {
            success: true,
            message: "Keyframe updated".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let old_value = self.old_value.ok_or("No old value stored")?;
        let old_easing = self.old_easing.ok_or("No old easing stored")?;

        let clip = timeline.find_clip_mut(&self.clip_id)
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
        let updated = clip.update_keyframe(
            &self.property,
            &self.keyframe_id,
            Some(old_value),
            Some(old_easing),
        )?;
        if !updated {
            return Err(format!("Keyframe {} not found for undo", self.keyframe_id));
        }

        Ok(CommandResult {
            success: true,
            message: "Keyframe update undone".to_string(),
            affected_clip_ids: vec![self.clip_id.clone()],
        })
    }

    fn description(&self) -> String {
        "Update keyframe".to_string()
    }
}

/// Command history manager for undo/redo
#[derive(Debug)]
#[derive(Default)]
pub struct CommandHistory {
    undo_stack: Vec<Box<dyn Command>>,
    redo_stack: Vec<Box<dyn Command>>,
    max_history: usize,
}

impl CommandHistory {
    pub fn new() -> Self {
        Self {
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            max_history: 100,
        }
    }

    /// Execute a command and add it to the undo stack
    pub fn execute(&mut self, mut command: Box<dyn Command>, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let result = command.execute(timeline)?;

        // Clear redo stack when a new command is executed
        self.redo_stack.clear();

        // Add to undo stack
        self.undo_stack.push(command);

        // Trim history if too long
        if self.undo_stack.len() > self.max_history {
            self.undo_stack.remove(0);
        }

        Ok(result)
    }

    /// Undo the last command
    pub fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let mut command = self.undo_stack.pop().ok_or("Nothing to undo")?;
        let result = command.undo(timeline)?;
        self.redo_stack.push(command);
        Ok(result)
    }

    /// Redo the last undone command
    pub fn redo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        let mut command = self.redo_stack.pop().ok_or("Nothing to redo")?;
        let result = command.execute(timeline)?;
        self.undo_stack.push(command);
        Ok(result)
    }

    /// Check if undo is available
    pub fn can_undo(&self) -> bool {
        !self.undo_stack.is_empty()
    }

    /// Check if redo is available
    pub fn can_redo(&self) -> bool {
        !self.redo_stack.is_empty()
    }

    /// Clear all history
    pub fn clear(&mut self) {
        self.undo_stack.clear();
        self.redo_stack.clear();
    }
}

// Implement Clone for CommandHistory (needed for Timeline Clone)
// Note: This creates an empty history since commands are not clonable
impl Clone for CommandHistory {
    fn clone(&self) -> Self {
        Self::new()
    }
}

// Implement Serialize/Deserialize for CommandHistory (skip the stacks)
impl Serialize for CommandHistory {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_none()
    }
}

impl<'de> Deserialize<'de> for CommandHistory {
    fn deserialize<D: serde::Deserializer<'de>>(_deserializer: D) -> Result<Self, D::Error> {
        Ok(Self::new())
    }
}
