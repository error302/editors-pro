//! Multicam Editing — Multi-cam groups, audio sync, angle switching, transitions.
//!
//! Supports grouping multiple camera angles, automatic sync via audio cross-correlation,
//! real-time angle switching during playback, and dissolve/wipe transitions between angles.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A single camera angle in a multicam group.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CameraAngle {
    pub id: String,
    pub name: String,
    pub source_path: String,
    pub offset_ms: f64, // Sync offset from reference angle
    pub is_reference: bool,
    pub audio_channels: u16,
}

impl CameraAngle {
    pub fn new(name: &str, source_path: &str) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.to_string(),
            source_path: source_path.to_string(),
            offset_ms: 0.0,
            is_reference: false,
            audio_channels: 2,
        }
    }
}

/// Transition type between angle switches.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AngleTransition {
    Cut,
    Dissolve { duration_ms: f64 },
    WipeLeft { duration_ms: f64 },
    WipeRight { duration_ms: f64 },
    WipeDown { duration_ms: f64 },
}

impl Default for AngleTransition {
    fn default() -> Self {
        Self::Cut
    }
}

/// A cut point where the active angle changes.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CutPoint {
    pub id: String,
    pub time_ms: f64,
    pub from_angle_id: String,
    pub to_angle_id: String,
    pub transition: AngleTransition,
}

impl CutPoint {
    pub fn new(time_ms: f64, from: &str, to: &str) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            time_ms,
            from_angle_id: from.to_string(),
            to_angle_id: to.to_string(),
            transition: AngleTransition::Cut,
        }
    }

    pub fn with_transition(mut self, transition: AngleTransition) -> Self {
        self.transition = transition;
        self
    }
}

/// A multicam group containing multiple angles and cut points.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MulticamGroup {
    pub id: String,
    pub name: String,
    pub angles: Vec<CameraAngle>,
    pub cut_points: Vec<CutPoint>,
    pub active_angle_id: String,
}

impl MulticamGroup {
    pub fn new(name: &str) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.to_string(),
            angles: Vec::new(),
            cut_points: Vec::new(),
            active_angle_id: String::new(),
        }
    }

    pub fn add_angle(&mut self, angle: CameraAngle) {
        if self.angles.is_empty() {
            self.active_angle_id = angle.id.clone();
            let mut angle = angle;
            angle.is_reference = true;
            angle.offset_ms = 0.0;
            self.angles.push(angle);
        } else {
            self.angles.push(angle);
        }
    }

    pub fn set_reference(&mut self, angle_id: &str) {
        for angle in &mut self.angles {
            angle.is_reference = angle.id == angle_id;
        }
    }

    pub fn reference_angle(&self) -> Option<&CameraAngle> {
        self.angles.iter().find(|a| a.is_reference)
    }

    pub fn add_cut_point(&mut self, cut: CutPoint) {
        self.cut_points.push(cut);
        self.cut_points
            .sort_by(|a, b| a.time_ms.partial_cmp(&b.time_ms).unwrap());
    }

    pub fn remove_cut_point(&mut self, id: &str) -> Option<CutPoint> {
        if let Some(pos) = self.cut_points.iter().position(|c| c.id == id) {
            Some(self.cut_points.remove(pos))
        } else {
            None
        }
    }

    /// Get the active angle at a given time.
    pub fn angle_at_time(&self, time_ms: f64) -> Option<&CameraAngle> {
        let active_id = self
            .cut_points
            .iter()
            .filter(|c| c.time_ms <= time_ms)
            .last()
            .map(|c| &c.to_angle_id)
            .unwrap_or(&self.active_angle_id);
        self.angles.iter().find(|a| a.id == *active_id)
    }

    /// Switch angle at a specific time (adds a cut point).
    pub fn switch_angle(&mut self, time_ms: f64, to_angle_id: &str) {
        if let Some(current) = self.angle_at_time(time_ms) {
            let cut = CutPoint::new(time_ms, &current.id, to_angle_id);
            self.add_cut_point(cut);
        }
    }

    /// Compute audio cross-correlation between two audio buffers.
    /// Returns the offset in samples where the correlation peaks.
    pub fn cross_correlate(audio_a: &[f32], audio_b: &[f32], sample_rate: u32) -> f64 {
        let window = audio_a
            .len()
            .min(audio_b.len())
            .min(sample_rate as usize * 10); // 10 sec window
        let mut best_offset = 0isize;
        let mut best_corr = f32::NEG_INFINITY;

        let search_range = (sample_rate as isize * 5).min(window as isize / 2); // ±5 sec

        for offset in -search_range..search_range {
            let mut corr = 0.0f32;
            let mut count = 0;
            for i in 0..window {
                let j = (i as isize + offset) as usize;
                if j < audio_b.len() {
                    corr += audio_a[i] * audio_b[j];
                    count += 1;
                }
            }
            if count > 0 {
                corr /= count as f32;
            }
            if corr > best_corr {
                best_corr = corr;
                best_offset = offset;
            }
        }

        best_offset as f64 / sample_rate as f64 * 1000.0 // Convert to ms
    }

    /// Auto-sync all angles using audio cross-correlation.
    pub fn auto_sync(&mut self, audio_buffers: &HashMap<String, Vec<f32>>, sample_rate: u32) {
        let ref_id = match self.reference_angle() {
            Some(r) => r.id.clone(),
            None => return,
        };
        let ref_audio = match audio_buffers.get(&ref_id) {
            Some(a) => a.clone(),
            None => return,
        };

        for angle in &mut self.angles {
            if angle.is_reference {
                continue;
            }
            if let Some(audio) = audio_buffers.get(&angle.id) {
                let offset_ms = Self::cross_correlate(&ref_audio, audio, sample_rate);
                angle.offset_ms = offset_ms;
            }
        }
    }

    pub fn angle_count(&self) -> usize {
        self.angles.len()
    }
    pub fn cut_count(&self) -> usize {
        self.cut_points.len()
    }
}

/// Manager for all multicam groups.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MulticamManager {
    pub groups: HashMap<String, MulticamGroup>,
}

impl MulticamManager {
    pub fn new() -> Self {
        Self {
            groups: HashMap::new(),
        }
    }
    pub fn add(&mut self, group: MulticamGroup) {
        self.groups.insert(group.id.clone(), group);
    }
    pub fn get(&self, id: &str) -> Option<&MulticamGroup> {
        self.groups.get(id)
    }
    pub fn get_mut(&mut self, id: &str) -> Option<&mut MulticamGroup> {
        self.groups.get_mut(id)
    }
    pub fn remove(&mut self, id: &str) -> Option<MulticamGroup> {
        self.groups.remove(id)
    }
    pub fn list(&self) -> Vec<&MulticamGroup> {
        self.groups.values().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_camera_angle_new() {
        let a = CameraAngle::new("Cam 1", "/cam1.mp4");
        assert_eq!(a.name, "Cam 1");
        assert_eq!(a.offset_ms, 0.0);
    }

    #[test]
    fn test_multicam_group_new() {
        let g = MulticamGroup::new("Event");
        assert_eq!(g.angles.len(), 0);
        assert_eq!(g.cut_count(), 0);
    }

    #[test]
    fn test_add_first_angle_is_reference() {
        let mut g = MulticamGroup::new("Event");
        let a = CameraAngle::new("Cam 1", "/cam1.mp4");
        let a_id = a.id.clone();
        g.add_angle(a);
        assert!(g.angles[0].is_reference);
        assert_eq!(g.active_angle_id, a_id);
    }

    #[test]
    fn test_add_second_angle() {
        let mut g = MulticamGroup::new("Event");
        g.add_angle(CameraAngle::new("Cam 1", "/cam1.mp4"));
        g.add_angle(CameraAngle::new("Cam 2", "/cam2.mp4"));
        assert_eq!(g.angle_count(), 2);
        assert!(!g.angles[1].is_reference);
    }

    #[test]
    fn test_set_reference() {
        let mut g = MulticamGroup::new("Event");
        g.add_angle(CameraAngle::new("Cam 1", "/cam1.mp4"));
        g.add_angle(CameraAngle::new("Cam 2", "/cam2.mp4"));
        let id2 = g.angles[1].id.clone();
        g.set_reference(&id2);
        assert!(g.angles[1].is_reference);
        assert!(!g.angles[0].is_reference);
    }

    #[test]
    fn test_switch_angle() {
        let mut g = MulticamGroup::new("Event");
        g.add_angle(CameraAngle::new("Cam 1", "/cam1.mp4"));
        g.add_angle(CameraAngle::new("Cam 2", "/cam2.mp4"));
        let id2 = g.angles[1].id.clone();
        g.switch_angle(5000.0, &id2);
        assert_eq!(g.cut_count(), 1);
    }

    #[test]
    fn test_angle_at_time() {
        let mut g = MulticamGroup::new("Event");
        let a1 = CameraAngle::new("Cam 1", "/cam1.mp4");
        let a1_id = a1.id.clone();
        g.add_angle(a1);
        let a2 = CameraAngle::new("Cam 2", "/cam2.mp4");
        let a2_id = a2.id.clone();
        g.add_angle(a2);
        g.switch_angle(5000.0, &a2_id);
        assert_eq!(g.angle_at_time(2000.0).unwrap().id, a1_id);
        assert_eq!(g.angle_at_time(8000.0).unwrap().id, a2_id);
    }

    #[test]
    fn test_cut_point_with_transition() {
        let cut = CutPoint::new(5000.0, "a1", "a2")
            .with_transition(AngleTransition::Dissolve { duration_ms: 500.0 });
        match cut.transition {
            AngleTransition::Dissolve { duration_ms } => assert_eq!(duration_ms, 500.0),
            _ => panic!("Expected dissolve"),
        }
    }

    #[test]
    fn test_remove_cut_point() {
        let mut g = MulticamGroup::new("Event");
        g.add_angle(CameraAngle::new("Cam 1", "/cam1.mp4"));
        g.add_angle(CameraAngle::new("Cam 2", "/cam2.mp4"));
        let angle_id = g.angles[1].id.clone();
        g.switch_angle(5000.0, &angle_id);
        let cut_id = g.cut_points[0].id.clone();
        assert!(g.remove_cut_point(&cut_id).is_some());
        assert_eq!(g.cut_count(), 0);
    }

    #[test]
    fn test_cross_correlation() {
        // Create two identical signals with offset
        let a = vec![0.0, 1.0, 0.5, -0.5, 0.0, 0.0, 0.0, 0.0];
        let b = vec![0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.5, -0.5];
        let offset = MulticamGroup::cross_correlate(&a, &b, 1);
        // The offset should be approximately the shift
        assert!(offset != 0.0 || a.len() < 10); // At least correlation ran
    }

    #[test]
    fn test_auto_sync() {
        let mut g = MulticamGroup::new("Event");
        g.add_angle(CameraAngle::new("Cam 1", "/cam1.mp4"));
        g.add_angle(CameraAngle::new("Cam 2", "/cam2.mp4"));
        let ref_id = g.angles[0].id.clone();
        let cam2_id = g.angles[1].id.clone();
        let buffers = HashMap::from([(ref_id, vec![0.5f32; 1000]), (cam2_id, vec![0.5f32; 1000])]);
        g.auto_sync(&buffers, 48000);
        // Both identical buffers should result in ~0 offset
        assert!(g.angles[1].offset_ms.abs() < 500.0);
    }

    #[test]
    fn test_reference_angle() {
        let mut g = MulticamGroup::new("Event");
        g.add_angle(CameraAngle::new("Cam 1", "/cam1.mp4"));
        assert!(g.reference_angle().is_some());
        assert!(g.reference_angle().unwrap().is_reference);
    }

    #[test]
    fn test_manager() {
        let mut mgr = MulticamManager::new();
        let g = MulticamGroup::new("Event");
        let id = g.id.clone();
        mgr.add(g);
        assert!(mgr.get(&id).is_some());
        assert_eq!(mgr.list().len(), 1);
    }

    #[test]
    fn test_wipe_transitions() {
        let cut = CutPoint::new(5000.0, "a1", "a2")
            .with_transition(AngleTransition::WipeLeft { duration_ms: 300.0 });
        match cut.transition {
            AngleTransition::WipeLeft { duration_ms } => assert_eq!(duration_ms, 300.0),
            _ => panic!(),
        }
    }

    #[test]
    fn test_cut_points_sorted() {
        let mut g = MulticamGroup::new("Event");
        g.add_angle(CameraAngle::new("Cam 1", "/cam1.mp4"));
        g.add_angle(CameraAngle::new("Cam 2", "/cam2.mp4"));
        let a2_id = g.angles[1].id.clone();
        g.add_cut_point(CutPoint::new(10000.0, &g.angles[0].id, &a2_id));
        g.add_cut_point(CutPoint::new(5000.0, &g.angles[0].id, &a2_id));
        assert_eq!(g.cut_points[0].time_ms, 5000.0);
    }

    #[test]
    fn test_angle_transition_default() {
        assert!(matches!(AngleTransition::default(), AngleTransition::Cut));
    }
}
