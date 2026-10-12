//! Nested Sequences — Compound clips, nested timelines, flattening.
//!
//! Supports grouping clips into compound/nested sequences that can be edited
//! as a single clip on the parent timeline, with recursive nesting support.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A nested sequence (compound clip) that contains its own sub-timeline.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NestedSequence {
    pub id: String,
    pub name: String,
    pub sub_clips: Vec<SubClip>,
    pub width: u32,
    pub height: u32,
    pub fps: f64,
    pub metadata: HashMap<String, String>,
}

/// A clip within a nested sequence.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubClip {
    pub id: String,
    pub source_path: String,
    pub trim_in_ms: f64,
    pub trim_out_ms: f64,
    pub offset_ms: f64,     // Position in the sub-timeline
    pub speed: f64,
    pub volume: f32,
    pub muted: bool,
    pub effects: Vec<String>, // Effect IDs
}

impl NestedSequence {
    pub fn new(name: &str, width: u32, height: u32, fps: f64) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.to_string(),
            sub_clips: Vec::new(),
            width, height, fps,
            metadata: HashMap::new(),
        }
    }

    /// Add a sub-clip to the sequence.
    pub fn add_clip(&mut self, clip: SubClip) {
        self.sub_clips.push(clip);
        self.sub_clips.sort_by(|a, b| a.offset_ms.partial_cmp(&b.offset_ms).unwrap());
    }

    /// Remove a sub-clip by ID.
    pub fn remove_clip(&mut self, id: &str) -> Option<SubClip> {
        if let Some(pos) = self.sub_clips.iter().position(|c| c.id == id) {
            Some(self.sub_clips.remove(pos))
        } else { None }
    }

    /// Get the total duration of the nested sequence.
    pub fn duration_ms(&self) -> f64 {
        self.sub_clips.iter().map(|c| {
            let clip_dur = (c.trim_out_ms - c.trim_in_ms) / c.speed.max(0.01);
            c.offset_ms + clip_dur
        }).max_by(|a, b| a.partial_cmp(b).unwrap()).unwrap_or(0.0)
    }

    /// Find which sub-clip is active at a given time.
    pub fn clip_at_time(&self, time_ms: f64) -> Option<&SubClip> {
        self.sub_clips.iter().find(|c| {
            let clip_dur = (c.trim_out_ms - c.trim_in_ms) / c.speed.max(0.01);
            time_ms >= c.offset_ms && time_ms < c.offset_ms + clip_dur
        })
    }

    /// Flatten this nested sequence into a linear list of clips for rendering.
    pub fn flatten(&self) -> Vec<FlatClip> {
        self.sub_clips.iter().map(|c| {
            FlatClip {
                source_path: c.source_path.clone(),
                trim_in_ms: c.trim_in_ms,
                trim_out_ms: c.trim_out_ms,
                timeline_offset_ms: c.offset_ms,
                speed: c.speed,
                volume: c.volume,
                muted: c.muted,
                effects: c.effects.clone(),
            }
        }).collect()
    }

    /// Split a sub-clip at a time position.
    pub fn split_at(&mut self, clip_id: &str, time_ms: f64) -> Result<(), String> {
        let pos = self.sub_clips.iter().position(|c| c.id == clip_id)
            .ok_or("Clip not found")?;
        let clip = &self.sub_clips[pos];
        let clip_dur = (clip.trim_out_ms - clip.trim_in_ms) / clip.speed.max(0.01);
        let local_time = time_ms - clip.offset_ms;
        if local_time <= 0.0 || local_time >= clip_dur { return Err("Split point outside clip".into()); }

        let split_source = clip.trim_in_ms + local_time * clip.speed;
        let left = SubClip {
            id: uuid::Uuid::new_v4().to_string(),
            source_path: clip.source_path.clone(),
            trim_in_ms: clip.trim_in_ms,
            trim_out_ms: split_source,
            offset_ms: clip.offset_ms,
            speed: clip.speed,
            volume: clip.volume,
            muted: clip.muted,
            effects: clip.effects.clone(),
        };
        let right = SubClip {
            id: uuid::Uuid::new_v4().to_string(),
            source_path: clip.source_path.clone(),
            trim_in_ms: split_source,
            trim_out_ms: clip.trim_out_ms,
            offset_ms: time_ms,
            speed: clip.speed,
            volume: clip.volume,
            muted: clip.muted,
            effects: clip.effects.clone(),
        };

        self.sub_clips.remove(pos);
        self.sub_clips.push(left);
        self.sub_clips.push(right);
        self.sub_clips.sort_by(|a, b| a.offset_ms.partial_cmp(&b.offset_ms).unwrap());
        Ok(())
    }
}

/// A flattened clip for rendering.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlatClip {
    pub source_path: String,
    pub trim_in_ms: f64,
    pub trim_out_ms: f64,
    pub timeline_offset_ms: f64,
    pub speed: f64,
    pub volume: f32,
    pub muted: bool,
    pub effects: Vec<String>,
}

/// Manager for all nested sequences in a project.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NestedSequenceManager {
    pub sequences: HashMap<String, NestedSequence>,
}

impl NestedSequenceManager {
    pub fn new() -> Self { Self { sequences: HashMap::new() } }

    pub fn add(&mut self, seq: NestedSequence) { self.sequences.insert(seq.id.clone(), seq); }
    pub fn get(&self, id: &str) -> Option<&NestedSequence> { self.sequences.get(id) }
    pub fn get_mut(&mut self, id: &str) -> Option<&mut NestedSequence> { self.sequences.get_mut(id) }
    pub fn remove(&mut self, id: &str) -> Option<NestedSequence> { self.sequences.remove(id) }
    pub fn list(&self) -> Vec<&NestedSequence> { self.sequences.values().collect() }

    /// Flatten all nested sequences into a single render list.
    pub fn flatten_all(&self) -> HashMap<String, Vec<FlatClip>> {
        self.sequences.iter().map(|(id, seq)| (id.clone(), seq.flatten())).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_clip(offset: f64, duration: f64) -> SubClip {
        SubClip {
            id: uuid::Uuid::new_v4().to_string(),
            source_path: "/test.mp4".into(),
            trim_in_ms: 0.0,
            trim_out_ms: duration,
            offset_ms: offset,
            speed: 1.0,
            volume: 1.0,
            muted: false,
            effects: Vec::new(),
        }
    }

    #[test]
    fn test_nested_sequence_new() {
        let seq = NestedSequence::new("Test Seq", 1920, 1080, 30.0);
        assert_eq!(seq.name, "Test Seq");
        assert!(seq.sub_clips.is_empty());
    }

    #[test]
    fn test_add_clip() {
        let mut seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        seq.add_clip(make_clip(0.0, 5000.0));
        assert_eq!(seq.sub_clips.len(), 1);
    }

    #[test]
    fn test_remove_clip() {
        let mut seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        let clip = make_clip(0.0, 5000.0);
        let id = clip.id.clone();
        seq.add_clip(clip);
        assert!(seq.remove_clip(&id).is_some());
        assert!(seq.sub_clips.is_empty());
    }

    #[test]
    fn test_duration() {
        let mut seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        seq.add_clip(make_clip(0.0, 5000.0));
        seq.add_clip(make_clip(5000.0, 3000.0));
        let dur = seq.duration_ms();
        assert!((dur - 8000.0).abs() < 1.0);
    }

    #[test]
    fn test_clip_at_time() {
        let mut seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        seq.add_clip(make_clip(0.0, 5000.0));
        seq.add_clip(make_clip(5000.0, 3000.0));
        let clip = seq.clip_at_time(2500.0);
        assert!(clip.is_some());
    }

    #[test]
    fn test_clip_at_time_gap() {
        let mut seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        seq.add_clip(make_clip(0.0, 2000.0));
        seq.add_clip(make_clip(5000.0, 3000.0));
        assert!(seq.clip_at_time(3500.0).is_none());
    }

    #[test]
    fn test_flatten() {
        let mut seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        seq.add_clip(make_clip(0.0, 5000.0));
        seq.add_clip(make_clip(5000.0, 3000.0));
        let flat = seq.flatten();
        assert_eq!(flat.len(), 2);
    }

    #[test]
    fn test_split_at() {
        let mut seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        let clip = make_clip(0.0, 10000.0);
        let id = clip.id.clone();
        seq.add_clip(clip);
        seq.split_at(&id, 5000.0).unwrap();
        assert_eq!(seq.sub_clips.len(), 2);
    }

    #[test]
    fn test_split_outside_fails() {
        let mut seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        let clip = make_clip(0.0, 5000.0);
        let id = clip.id.clone();
        seq.add_clip(clip);
        assert!(seq.split_at(&id, -100.0).is_err());
        assert!(seq.split_at(&id, 6000.0).is_err());
    }

    #[test]
    fn test_manager_add_get() {
        let mut mgr = NestedSequenceManager::new();
        let seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        let id = seq.id.clone();
        mgr.add(seq);
        assert!(mgr.get(&id).is_some());
    }

    #[test]
    fn test_manager_remove() {
        let mut mgr = NestedSequenceManager::new();
        let seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        let id = seq.id.clone();
        mgr.add(seq);
        assert!(mgr.remove(&id).is_some());
        assert!(mgr.get(&id).is_none());
    }

    #[test]
    fn test_manager_flatten_all() {
        let mut mgr = NestedSequenceManager::new();
        let mut seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        seq.add_clip(make_clip(0.0, 5000.0));
        mgr.add(seq);
        let flat = mgr.flatten_all();
        assert_eq!(flat.len(), 1);
    }

    #[test]
    fn test_clips_sorted_on_add() {
        let mut seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        seq.add_clip(make_clip(5000.0, 3000.0));
        seq.add_clip(make_clip(0.0, 5000.0));
        assert_eq!(seq.sub_clips[0].offset_ms, 0.0);
    }

    #[test]
    fn test_speed_affects_duration() {
        let mut clip = make_clip(0.0, 10000.0);
        clip.speed = 2.0;
        let mut seq = NestedSequence::new("Test", 1920, 1080, 30.0);
        seq.add_clip(clip);
        let dur = seq.duration_ms();
        assert!((dur - 5000.0).abs() < 1.0);
    }
}
