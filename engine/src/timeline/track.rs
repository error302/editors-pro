//! Track model - A single horizontal lane on the timeline
//!
//! Each track holds clips of a specific type (video, audio, text, effect)
//! and provides operations for managing clips within the track.

use serde::{Deserialize, Serialize};

use super::clip::Clip;

/// The type of media a track can contain
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TrackType {
    Video,
    Audio,
    Text,
    Effect,
}

impl std::fmt::Display for TrackType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TrackType::Video => write!(f, "Video"),
            TrackType::Audio => write!(f, "Audio"),
            TrackType::Text => write!(f, "Text"),
            TrackType::Effect => write!(f, "Effect"),
        }
    }
}

/// A single track on the timeline containing clips of the same type
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Track {
    /// Unique track identifier
    pub id: String,
    /// Human-readable track name
    pub name: String,
    /// What type of media this track holds
    pub track_type: TrackType,
    /// Clips arranged on this track in temporal order
    pub clips: Vec<Clip>,
    /// Whether the track is locked (prevents editing)
    pub locked: bool,
    /// Whether the track is visible/audible
    pub visible: bool,
    /// Whether the track is muted
    pub muted: bool,
    /// Track volume level (0.0 to 2.0, 1.0 = normal)
    pub volume: f32,
    /// Track pan (-1.0 to 1.0, 0.0 = center)
    pub pan: f32,
    /// Vertical order on the timeline (0 = topmost)
    pub order_index: u32,
}

impl Track {
    /// Create a new empty track
    pub fn new(name: String, track_type: TrackType, order_index: u32) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            track_type,
            clips: Vec::new(),
            locked: false,
            visible: true,
            muted: false,
            volume: 1.0,
            pan: 0.0,
            order_index,
        }
    }

    /// Add a clip to this track, inserting it in temporal order
    pub fn add_clip(&mut self, clip: Clip) {
        // Find the correct position to maintain temporal order
        let insert_pos = self.clips.iter().position(|c| c.start_ms > clip.start_ms)
            .unwrap_or(self.clips.len());
        self.clips.insert(insert_pos, clip);
        log::info!("Added clip to track '{}' at position {}", self.name, insert_pos);
    }

    /// Remove a clip by its ID
    pub fn remove_clip(&mut self, clip_id: &str) -> Option<Clip> {
        if let Some(pos) = self.clips.iter().position(|c| c.id == clip_id) {
            Some(self.clips.remove(pos))
        } else {
            None
        }
    }

    /// Reorder clips by their start_ms (fix temporal ordering)
    pub fn reorder_clips(&mut self) {
        self.clips.sort_by_key(|c| c.start_ms);
    }

    /// Find a clip by its ID
    pub fn find_clip(&self, clip_id: &str) -> Option<&Clip> {
        self.clips.iter().find(|c| c.id == clip_id)
    }

    /// Find a clip mutably by its ID
    pub fn find_clip_mut(&mut self, clip_id: &str) -> Option<&mut Clip> {
        self.clips.iter_mut().find(|c| c.id == clip_id)
    }

    /// Get the total duration of all clips on this track
    pub fn total_duration_ms(&self) -> u64 {
        self.clips.iter().map(|c| c.start_ms + c.effective_duration()).max().unwrap_or(0)
    }

    /// Check if there would be an overlap if a clip is placed at the given position
    pub fn would_overlap(&self, clip_id: &str, new_start_ms: u64, new_duration_ms: u64) -> bool {
        let new_end = new_start_ms + new_duration_ms;
        self.clips.iter()
            .filter(|c| c.id != clip_id) // Exclude the clip being moved
            .any(|c| {
                let clip_end = c.start_ms + c.effective_duration();
                new_start_ms < clip_end && new_end > c.start_ms
            })
    }

    /// Get all clips that overlap with the given time range
    pub fn clips_in_range(&self, start_ms: u64, end_ms: u64) -> Vec<&Clip> {
        self.clips.iter()
            .filter(|c| {
                let clip_end = c.start_ms + c.effective_duration();
                start_ms < clip_end && end_ms > c.start_ms
            })
            .collect()
    }

    /// Set the track volume, clamping to valid range
    pub fn set_volume(&mut self, volume: f32) {
        self.volume = volume.clamp(0.0, 2.0);
    }

    /// Toggle the track lock state
    pub fn toggle_lock(&mut self) {
        self.locked = !self.locked;
    }

    /// Toggle the track visibility
    pub fn toggle_visibility(&mut self) {
        self.visible = !self.visible;
    }
}
