//! Timeline module - Core data model for the editing timeline
//!
//! The timeline is the heart of the editor. It contains tracks
//! (video, audio, text, effect) arranged vertically, and clips
//! arranged horizontally on each track representing segments of media.

pub mod advanced_trim;
pub mod clip;
pub mod command;
pub mod edit;
pub mod keyframe;
pub mod speed_curve;
pub mod track;

#[cfg(test)]
mod clip_tests;
#[cfg(test)]
mod command_tests;
#[cfg(test)]
mod track_tests;

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use clip::Clip;
use command::CommandHistory;
use track::Track;

/// Unique identifier for a timeline
pub type TimelineId = String;

/// The main timeline structure holding all tracks and providing
/// operations for editing, navigation, and rendering.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Timeline {
    pub id: TimelineId,
    pub tracks: Vec<Track>,
    pub duration_ms: u64,
    pub settings: TimelineSettings,
    #[serde(skip)]
    pub command_history: CommandHistory,
}

/// Settings that define the timeline's properties
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineSettings {
    pub width: u32,
    pub height: u32,
    pub fps: f32,
    pub sample_rate: u32,
    pub background_color: String,
}

impl Default for TimelineSettings {
    fn default() -> Self {
        Self {
            width: 1920,
            height: 1080,
            fps: 30.0,
            sample_rate: 44100,
            background_color: "#000000".to_string(),
        }
    }
}

impl Timeline {
    /// Create a new empty timeline with default settings
    pub fn new() -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            tracks: Vec::new(),
            duration_ms: 0,
            settings: TimelineSettings::default(),
            command_history: CommandHistory::new(),
        }
    }

    /// Create a timeline with custom settings
    pub fn with_settings(settings: TimelineSettings) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            tracks: Vec::new(),
            duration_ms: 0,
            settings,
            command_history: CommandHistory::new(),
        }
    }

    /// Add a new track to the timeline
    pub fn add_track(&mut self, track_type: track::TrackType, name: Option<String>) -> &Track {
        let order_index = self.tracks.len() as u32;
        let track_name = name.unwrap_or_else(|| {
            let type_name = match track_type {
                track::TrackType::Video => "Video",
                track::TrackType::Audio => "Audio",
                track::TrackType::Text => "Text",
                track::TrackType::Effect => "Effect",
            };
            format!("{} {}", type_name, order_index + 1)
        });

        let track = Track::new(track_name, track_type, order_index);
        self.tracks.push(track);
        self.tracks.last().unwrap()
    }

    /// Remove a track by its ID
    pub fn remove_track(&mut self, track_id: &str) -> Option<Track> {
        if let Some(pos) = self.tracks.iter().position(|t| t.id == track_id) {
            let removed = self.tracks.remove(pos);
            // Re-order remaining tracks
            for (i, track) in self.tracks.iter_mut().enumerate() {
                track.order_index = i as u32;
            }
            self.recalculate_duration();
            Some(removed)
        } else {
            None
        }
    }

    /// Find a track by ID
    pub fn find_track(&self, track_id: &str) -> Option<&Track> {
        self.tracks.iter().find(|t| t.id == track_id)
    }

    /// Find a track mutably by ID
    pub fn find_track_mut(&mut self, track_id: &str) -> Option<&mut Track> {
        self.tracks.iter_mut().find(|t| t.id == track_id)
    }

    /// Find a clip across all tracks by its ID
    pub fn find_clip(&self, clip_id: &str) -> Option<(&Track, &Clip)> {
        for track in &self.tracks {
            if let Some(clip) = track.find_clip(clip_id) {
                return Some((track, clip));
            }
        }
        None
    }

    /// Find a clip mutably across all tracks
    pub fn find_clip_mut(&mut self, clip_id: &str) -> Option<&mut Clip> {
        for track in &mut self.tracks {
            if let Some(clip) = track.find_clip_mut(clip_id) {
                return Some(clip);
            }
        }
        None
    }

    /// Add a clip to a specific track
    pub fn add_clip_to_track(&mut self, track_id: &str, clip: Clip) -> Result<(), String> {
        if let Some(track) = self.find_track_mut(track_id) {
            track.add_clip(clip);
            self.recalculate_duration();
            Ok(())
        } else {
            Err(format!("Track {} not found", track_id))
        }
    }

    /// Remove a clip from any track
    pub fn remove_clip(&mut self, clip_id: &str) -> Option<Clip> {
        for track in &mut self.tracks {
            if let Some(clip) = track.remove_clip(clip_id) {
                self.recalculate_duration();
                return Some(clip);
            }
        }
        None
    }

    /// Split a clip at the given timestamp
    pub fn split_clip(&mut self, clip_id: &str, time_ms: u64) -> Result<(Clip, Clip), String> {
        // Find the track containing the clip
        let track_id = self
            .tracks
            .iter()
            .find(|t| t.find_clip(clip_id).is_some())
            .map(|t| t.id.clone())
            .ok_or_else(|| format!("Clip {} not found", clip_id))?;

        // Get the original clip data
        let original = self
            .find_clip(clip_id)
            .map(|(_, c)| c.clone())
            .ok_or_else(|| format!("Clip {} not found", clip_id))?;

        let track = self.find_track(&track_id).ok_or("Track not found")?;
        if track.locked { return Err("Track is locked".into()); }
        for clip in self.tracks.iter().flat_map(|t| &t.clips) { clip.checked_end_ms()?; }
        let (left_clip, right_clip) = original.split_at(time_ms)?;

        let left_clone = left_clip.clone();
        let right_clone = right_clip.clone();

        // Validate first, then replace in one track publication. No fallible
        // source-range operation occurs after the original is removed.
        let mut candidate = track.clone();
        for neighbor in &mut candidate.clips {
            if neighbor.id == original.id { continue; }
            for link in [&mut neighbor.transition_in, &mut neighbor.transition_out].into_iter().flatten() {
                if link.from_clip_id != original.id && link.to_clip_id != original.id { continue; }
                if neighbor.properties.get("locked").and_then(serde_json::Value::as_bool) == Some(true) {
                    return Err("A linked neighboring clip is locked".into());
                }
                if link.from_clip_id == original.id { link.from_clip_id = right_clone.id.clone(); }
                if link.to_clip_id == original.id { link.to_clip_id = left_clone.id.clone(); }
                if let Some(boundary) = [&left_clone.transition_in, &right_clone.transition_out]
                    .into_iter().flatten().find(|b| b.from_clip_id == link.from_clip_id && b.to_clip_id == link.to_clip_id) {
                    link.id = boundary.id.clone();
                }
            }
        }
        candidate.remove_clip(clip_id);
        candidate.add_clip(left_clip);
        candidate.add_clip(right_clip);
        *self.find_track_mut(&track_id).ok_or("Track not found")? = candidate;
        self.recalculate_duration();

        Ok((left_clone, right_clone))
    }

    /// Recalculate the total timeline duration based on all clips
    pub fn recalculate_duration(&mut self) {
        let max_end = self.tracks.iter().flat_map(|t| {
            t.clips.iter().map(|c| c.start_ms + c.effective_duration())
        }).max();

        self.duration_ms = max_end.unwrap_or(0);
    }

    /// Get all clips at a specific timestamp (for rendering)
    pub fn get_clips_at_time(&self, time_ms: u64) -> Vec<(&Track, &Clip)> {
        self.tracks.iter()
            .filter(|t| t.visible)
            .flat_map(|track| {
                track.clips.iter()
                    .filter(move |clip| time_ms >= clip.start_ms && time_ms < clip.start_ms + clip.effective_duration())
                    .map(move |clip| (track, clip))
            })
            .collect()
    }

    /// Phase B.12: get the total duration in seconds.
    pub fn get_duration(&self) -> f64 {
        self.duration_ms as f64 / 1000.0
    }

    /// Phase B.12: find a clip at a given time (seconds).
    pub fn find_clip_at(&self, time_s: f64) -> Option<&Clip> {
        let time_ms = (time_s * 1000.0) as u64;
        self.tracks.iter()
            .flat_map(|t| t.clips.iter())
            .find(|c| time_ms >= c.start_ms && time_ms < c.start_ms + c.effective_duration())
    }

    /// Compatibility alias for find_clip_at
    pub fn find_clip_at_time(&self, time_s: f64) -> Option<&Clip> {
        self.find_clip_at(time_s)
    }

    /// Get tracks filtered by type
    pub fn tracks_of_type(&self, track_type: track::TrackType) -> Vec<&Track> {
        self.tracks.iter().filter(|t| t.track_type == track_type).collect()
    }

    /// Export the timeline state as a serializable format (for project saving)
    pub fn to_save_data(&self) -> TimelineSaveData {
        TimelineSaveData {
            id: self.id.clone(),
            tracks: self.tracks.clone(),
            duration_ms: self.duration_ms,
            settings: self.settings.clone(),
        }
    }
}

/// Serializable timeline data (without command history which is runtime-only)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineSaveData {
    pub id: TimelineId,
    pub tracks: Vec<Track>,
    pub duration_ms: u64,
    pub settings: TimelineSettings,
}

impl From<TimelineSaveData> for Timeline {
    fn from(data: TimelineSaveData) -> Self {
        Self {
            id: data.id,
            tracks: data.tracks,
            duration_ms: data.duration_ms,
            settings: data.settings,
            command_history: CommandHistory::new(),
        }
    }
}
