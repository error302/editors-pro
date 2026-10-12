//! Macro System — Record, playback, and automate editing operations.
//!
//! Professional macro recording for repetitive editing tasks.
//! Supports recording actions, editing macro steps, and replaying at speed.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Type of editable action.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActionType {
    AddEffect,
    RemoveEffect,
    SetParameter,
    SplitClip,
    DeleteClip,
    MoveClip,
    AddMarker,
    SetVolume,
    SetPan,
    SetSpeed,
    AddMask,
    RemoveMask,
    SetBlendMode,
    SwitchAngle,
    Custom(String),
}

/// A single recorded action.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MacroAction {
    pub action_type: ActionType,
    pub target_id: String,         // Clip/track/effect ID
    pub parameters: HashMap<String, f64>,
    pub timestamp_ms: f64,         // Relative to macro start
    pub description: String,
}

impl MacroAction {
    pub fn new(action_type: ActionType, target_id: &str, timestamp_ms: f64) -> Self {
        let description = format!("{:?}", action_type);
        Self { action_type, target_id: target_id.to_string(), parameters: HashMap::new(), timestamp_ms, description }
    }

    pub fn with_param(mut self, key: &str, value: f64) -> Self {
        self.parameters.insert(key.to_string(), value);
        self
    }

    pub fn with_description(mut self, desc: &str) -> Self {
        self.description = desc.to_string();
        self
    }
}

/// A recorded macro.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Macro {
    pub id: String,
    pub name: String,
    pub description: String,
    pub actions: Vec<MacroAction>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub playback_speed: f64,  // 1.0 = normal, 2.0 = fast
    pub loop_count: u32,      // How many times to replay (0 = infinite if loop enabled)
    pub is_looping: bool,
}

impl Macro {
    pub fn new(name: &str) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.to_string(),
            description: String::new(),
            actions: Vec::new(),
            created_at: chrono::Utc::now(),
            playback_speed: 1.0,
            loop_count: 1,
            is_looping: false,
        }
    }

    pub fn record(&mut self, action: MacroAction) {
        self.actions.push(action);
    }

    pub fn remove_action(&mut self, index: usize) -> Option<MacroAction> {
        if index < self.actions.len() { Some(self.actions.remove(index)) } else { None }
    }

    pub fn insert_action(&mut self, index: usize, action: MacroAction) {
        if index <= self.actions.len() { self.actions.insert(index, action); }
    }

    pub fn action_count(&self) -> usize { self.actions.len() }

    pub fn total_duration_ms(&self) -> f64 {
        self.actions.last().map(|a| a.timestamp_ms).unwrap_or(0.0)
    }

    /// Get actions that should fire at a given playback time.
    pub fn actions_at_time(&self, time_ms: f64) -> Vec<&MacroAction> {
        self.actions.iter().filter(|a| (a.timestamp_ms - time_ms).abs() < 50.0).collect()
    }

    /// Export macro as JSON.
    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string_pretty(self).map_err(|e| format!("Serialize error: {}", e))
    }

    /// Import macro from JSON.
    pub fn from_json(json: &str) -> Result<Self, String> {
        serde_json::from_str(json).map_err(|e| format!("Parse error: {}", e))
    }
}

/// Macro recorder state.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecorderState {
    Idle,
    Recording,
    Paused,
}

/// Macro recorder.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MacroRecorder {
    pub state: RecorderState,
    pub current_macro: Option<Macro>,
    pub start_time_ms: f64,
}

impl MacroRecorder {
    pub fn new() -> Self { Self { state: RecorderState::Idle, current_macro: None, start_time_ms: 0.0 } }

    pub fn start_recording(&mut self, name: &str) {
        self.state = RecorderState::Recording;
        self.current_macro = Some(Macro::new(name));
        self.start_time_ms = 0.0;
    }

    pub fn pause(&mut self) {
        if self.state == RecorderState::Recording { self.state = RecorderState::Paused; }
    }

    pub fn resume(&mut self) {
        if self.state == RecorderState::Paused { self.state = RecorderState::Recording; }
    }

    pub fn stop_recording(&mut self) -> Option<Macro> {
        self.state = RecorderState::Idle;
        self.current_macro.take()
    }

    pub fn record_action(&mut self, action_type: ActionType, target_id: &str, params: HashMap<String, f64>) {
        if self.state != RecorderState::Recording { return; }
        if let Some(m) = &mut self.current_macro {
            let elapsed = m.total_duration_ms() + 100.0; // 100ms between actions
            let mut action = MacroAction::new(action_type, target_id, elapsed);
            action.parameters = params;
            m.record(action);
        }
    }

    pub fn is_recording(&self) -> bool { self.state == RecorderState::Recording }
}

/// Macro player for replaying recorded macros.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MacroPlayer {
    pub is_playing: bool,
    pub current_time_ms: f64,
    pub next_action_idx: usize,
    pub completed_loops: u32,
}

impl MacroPlayer {
    pub fn new() -> Self { Self { is_playing: false, current_time_ms: 0.0, next_action_idx: 0, completed_loops: 0 } }

    pub fn start(&mut self) { self.is_playing = true; self.current_time_ms = 0.0; self.next_action_idx = 0; self.completed_loops = 0; }
    pub fn stop(&mut self) { self.is_playing = false; }

    pub fn tick<'a>(&mut self, delta_ms: f64, macro_def: &'a Macro) -> Vec<&'a MacroAction> {
        if !self.is_playing {
            return Vec::new();
        }
        let speed = macro_def.playback_speed;
        self.current_time_ms += delta_ms * speed;
        let mut fired = Vec::new();
        let actions = &macro_def.actions;
        while self.next_action_idx < actions.len() {
            let action = &actions[self.next_action_idx];
            if action.timestamp_ms <= self.current_time_ms {
                fired.push(action);
                self.next_action_idx += 1;
            } else {
                break;
            }
        }
        // Check if macro completed
        if self.next_action_idx >= actions.len() {
            self.completed_loops += 1;
            if macro_def.is_looping || self.completed_loops < macro_def.loop_count {
                self.next_action_idx = 0;
                self.current_time_ms = 0.0;
            } else {
                self.is_playing = false;
            }
        }
        fired
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_macro_new() {
        let m = Macro::new("Test Macro");
        assert_eq!(m.name, "Test Macro");
        assert!(m.actions.is_empty());
    }

    #[test]
    fn test_macro_record() {
        let mut m = Macro::new("Test");
        m.record(MacroAction::new(ActionType::SetParameter, "effect1", 100.0));
        assert_eq!(m.action_count(), 1);
    }

    #[test]
    fn test_macro_remove_action() {
        let mut m = Macro::new("Test");
        m.record(MacroAction::new(ActionType::SetParameter, "e1", 0.0));
        m.record(MacroAction::new(ActionType::SetParameter, "e2", 100.0));
        assert!(m.remove_action(0).is_some());
        assert_eq!(m.action_count(), 1);
    }

    #[test]
    fn test_macro_insert_action() {
        let mut m = Macro::new("Test");
        m.record(MacroAction::new(ActionType::SetParameter, "e1", 0.0));
        m.record(MacroAction::new(ActionType::SetParameter, "e2", 200.0));
        m.insert_action(1, MacroAction::new(ActionType::SplitClip, "clip1", 100.0));
        assert_eq!(m.action_count(), 3);
    }

    #[test]
    fn test_macro_duration() {
        let mut m = Macro::new("Test");
        m.record(MacroAction::new(ActionType::SetParameter, "e1", 0.0));
        m.record(MacroAction::new(ActionType::SetParameter, "e2", 500.0));
        assert_eq!(m.total_duration_ms(), 500.0);
    }

    #[test]
    fn test_macro_json_roundtrip() {
        let mut m = Macro::new("Test");
        m.record(MacroAction::new(ActionType::SetParameter, "e1", 0.0));
        let json = m.to_json().unwrap();
        let restored = Macro::from_json(&json).unwrap();
        assert_eq!(restored.name, "Test");
        assert_eq!(restored.action_count(), 1);
    }

    #[test]
    fn test_action_with_params() {
        let action = MacroAction::new(ActionType::SetParameter, "effect1", 100.0)
            .with_param("intensity", 0.75)
            .with_description("Set intensity");
        assert_eq!(action.parameters.len(), 1);
        assert_eq!(action.description, "Set intensity");
    }

    #[test]
    fn test_recorder_start_stop() {
        let mut rec = MacroRecorder::new();
        rec.start_recording("Test");
        assert!(rec.is_recording());
        let result = rec.stop_recording();
        assert!(result.is_some());
        assert!(!rec.is_recording());
    }

    #[test]
    fn test_recorder_record_action() {
        let mut rec = MacroRecorder::new();
        rec.start_recording("Test");
        rec.record_action(ActionType::SetParameter, "e1", HashMap::from([("val".to_string(), 0.5)]));
        let m = rec.stop_recording().unwrap();
        assert_eq!(m.action_count(), 1);
    }

    #[test]
    fn test_recorder_pause_resume() {
        let mut rec = MacroRecorder::new();
        rec.start_recording("Test");
        rec.pause();
        assert_eq!(rec.state, RecorderState::Paused);
        rec.record_action(ActionType::SetParameter, "e1", HashMap::new()); // Should not record
        rec.resume();
        rec.record_action(ActionType::SetParameter, "e2", HashMap::new());
        let m = rec.stop_recording().unwrap();
        assert_eq!(m.action_count(), 1);
    }

    #[test]
    fn test_player_tick() {
        let mut m = Macro::new("Test");
        m.record(MacroAction::new(ActionType::SetParameter, "e1", 0.0));
        m.record(MacroAction::new(ActionType::SetParameter, "e2", 200.0));
        let mut player = MacroPlayer::new();
        player.start();
        let fired = player.tick(250.0, &m);
        assert_eq!(fired.len(), 2);
    }

    #[test]
    fn test_player_sequential() {
        let mut m = Macro::new("Test");
        m.record(MacroAction::new(ActionType::SetParameter, "e1", 0.0));
        m.record(MacroAction::new(ActionType::SetParameter, "e2", 200.0));
        let mut player = MacroPlayer::new();
        player.start();
        let f1 = player.tick(100.0, &m);
        assert_eq!(f1.len(), 1);
        let f2 = player.tick(150.0, &m);
        assert_eq!(f2.len(), 1);
    }

    #[test]
    fn test_player_loops() {
        let mut m = Macro::new("Test");
        m.loop_count = 2;
        m.record(MacroAction::new(ActionType::SetParameter, "e1", 0.0));
        let mut player = MacroPlayer::new();
        player.start();
        player.tick(100.0, &m);
        player.tick(100.0, &m);
        assert_eq!(player.completed_loops, 2);
        assert!(!player.is_playing);
    }

    #[test]
    fn test_player_speed() {
        let mut m = Macro::new("Test");
        m.playback_speed = 2.0;
        m.record(MacroAction::new(ActionType::SetParameter, "e1", 100.0));
        let mut player = MacroPlayer::new();
        player.start();
        let fired = player.tick(60.0, &m); // 60*2=120ms elapsed
        assert_eq!(fired.len(), 1);
    }

    #[test]
    fn test_macro_actions_at_time() {
        let mut m = Macro::new("Test");
        m.record(MacroAction::new(ActionType::SetParameter, "e1", 100.0));
        assert_eq!(m.actions_at_time(100.0).len(), 1);
        assert_eq!(m.actions_at_time(200.0).len(), 0);
    }
}
