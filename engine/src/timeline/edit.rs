//! Atomic clip edits. Candidate track state is validated completely before
//! publication; history stores tracks, never a recursively cloned Timeline.

use super::clip::Clip;
use super::command::{Command, CommandResult};
use super::track::Track;
use super::Timeline;

#[derive(Debug, Clone, Copy)]
pub enum ClipEditOperation {
    Duplicate,
    RippleDelete,
    TrimIn { time_ms: u64 },
    TrimOut { time_ms: u64 },
}

#[derive(Debug, Clone)]
pub struct ClipEditCommand {
    clip_id: String,
    operation: ClipEditOperation,
    before: Option<Track>,
    after: Option<Track>,
    affected: Vec<String>,
}

impl ClipEditCommand {
    pub fn new(clip_id: String, operation: ClipEditOperation) -> Self {
        Self {
            clip_id,
            operation,
            before: None,
            after: None,
            affected: Vec::new(),
        }
    }

    fn result(&self, message: &str) -> CommandResult {
        CommandResult {
            success: true,
            message: message.into(),
            affected_clip_ids: self.affected.clone(),
        }
    }

    fn restore(timeline: &mut Timeline, track: &Track) -> Result<(), String> {
        let index = timeline
            .tracks
            .iter()
            .position(|t| t.id == track.id)
            .ok_or("Edited track no longer exists")?;
        timeline.tracks[index] = track.clone();
        timeline.recalculate_duration();
        Ok(())
    }
}

impl Command for ClipEditCommand {
    fn execute(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        if let Some(after) = &self.after {
            Self::restore(timeline, after)?;
            return Ok(self.result("Clip edit redone"));
        }
        let (track_index, clip_index) = timeline
            .tracks
            .iter()
            .enumerate()
            .find_map(|(ti, track)| {
                track
                    .clips
                    .iter()
                    .position(|c| c.id == self.clip_id)
                    .map(|ci| (ti, ci))
            })
            .ok_or_else(|| format!("Clip {} not found", self.clip_id))?;
        let track = &timeline.tracks[track_index];
        let original = &track.clips[clip_index];
        if track.locked || original.is_edit_locked() {
            return Err("Track or clip is locked".into());
        }
        let end = original.checked_end_ms()?;
        let speed = original.constant_speed_for_edit()?;
        let source_duration = Clip::source_delta(original.duration_ms, speed)?;
        original
            .trim_start_ms
            .checked_add(source_duration)
            .and_then(|v| v.checked_add(original.trim_end_ms))
            .ok_or("Source trim overflow")?;
        // Validate every end before recalculation can encounter unchecked legacy data.
        for clip in timeline.tracks.iter().flat_map(|t| &t.clips) {
            clip.checked_end_ms()?;
        }
        let mut candidate = track.clone();
        let mut affected = vec![original.id.clone()];
        match self.operation {
            ClipEditOperation::Duplicate | ClipEditOperation::RippleDelete => {
                // Insertion/deletion across an overlapping interval needs an
                // explicit overlap policy. Refuse it rather than move half a clip.
                for clip in &track.clips {
                    if clip.id == original.id {
                        continue;
                    }
                    let other_end = clip.checked_end_ms()?;
                    let conflicts = if matches!(self.operation, ClipEditOperation::Duplicate) {
                        clip.start_ms < end && other_end > end
                    } else {
                        clip.start_ms < end && other_end > original.start_ms
                    };
                    if conflicts {
                        return Err("Overlapping clips prevent this track edit".into());
                    }
                }
                for clip in candidate.clips.iter_mut().filter(|c| c.start_ms >= end) {
                    if clip.is_edit_locked() {
                        return Err("A following clip is locked".into());
                    }
                    let new_start = match self.operation {
                        ClipEditOperation::Duplicate => {
                            clip.start_ms.checked_add(original.duration_ms)
                        }
                        _ => clip.start_ms.checked_sub(original.duration_ms),
                    }
                    .ok_or("Clip timestamp overflow")?;
                    clip.shift_to(new_start)?;
                    affected.push(clip.id.clone());
                }
                if matches!(self.operation, ClipEditOperation::Duplicate) {
                    let mut duplicate = original.independent_copy();
                    duplicate.shift_to(end)?;
                    duplicate.transition_in = None;
                    candidate.clips[clip_index].transition_out = None;
                    for neighbor in &mut candidate.clips {
                        if neighbor.id == original.id {
                            continue;
                        }
                        for link in [&mut neighbor.transition_in, &mut neighbor.transition_out]
                            .into_iter()
                            .flatten()
                        {
                            if link.from_clip_id == original.id {
                                if neighbor
                                    .properties
                                    .get("locked")
                                    .and_then(serde_json::Value::as_bool)
                                    == Some(true)
                                {
                                    return Err("A linked neighboring clip is locked".into());
                                }
                                link.from_clip_id = duplicate.id.clone();
                                if let Some(boundary) = &duplicate.transition_out {
                                    if boundary.to_clip_id == link.to_clip_id {
                                        link.id = boundary.id.clone();
                                    }
                                }
                                if !affected.contains(&neighbor.id) {
                                    affected.push(neighbor.id.clone());
                                }
                            }
                        }
                    }
                    affected.insert(0, duplicate.id.clone());
                    candidate.add_clip(duplicate);
                } else {
                    candidate.clips.remove(clip_index);
                    for neighbor in &mut candidate.clips {
                        let touches = [&neighbor.transition_in, &neighbor.transition_out]
                            .into_iter()
                            .flatten()
                            .any(|link| {
                                link.from_clip_id == original.id || link.to_clip_id == original.id
                            });
                        if !touches {
                            continue;
                        }
                        if neighbor.is_edit_locked() {
                            return Err("A linked neighboring clip is locked".into());
                        }
                        for link in [&mut neighbor.transition_in, &mut neighbor.transition_out] {
                            if link.as_ref().is_some_and(|t| {
                                t.from_clip_id == original.id || t.to_clip_id == original.id
                            }) {
                                *link = None;
                            }
                        }
                        if !affected.contains(&neighbor.id) {
                            affected.push(neighbor.id.clone());
                        }
                    }
                }
                candidate.reorder_clips();
            }
            ClipEditOperation::TrimIn { time_ms } | ClipEditOperation::TrimOut { time_ms } => {
                if time_ms <= original.start_ms || time_ms >= end {
                    return Err("Trim point must be strictly inside the clip".into());
                }
                let clip = &mut candidate.clips[clip_index];
                if matches!(self.operation, ClipEditOperation::TrimIn { .. }) {
                    let removed = time_ms - original.start_ms;
                    clip.trim_start_ms = original
                        .trim_start_ms
                        .checked_add(Clip::source_delta(removed, speed)?)
                        .ok_or("Source trim overflow")?;
                    clip.start_ms = time_ms;
                    clip.duration_ms = end - time_ms;
                    clip.transition_in = None;
                } else {
                    clip.trim_end_ms = original
                        .trim_end_ms
                        .checked_add(Clip::source_delta(end - time_ms, speed)?)
                        .ok_or("Source trim overflow")?;
                    clip.duration_ms = time_ms - original.start_ms;
                    clip.transition_out = None;
                }
                candidate.reorder_clips();
            }
        }
        let removed_boundary = match self.operation {
            ClipEditOperation::TrimIn { .. } => original.transition_in.as_ref(),
            ClipEditOperation::TrimOut { .. } => original.transition_out.as_ref(),
            _ => None,
        };
        if let Some(boundary) = removed_boundary {
            for neighbor in &mut candidate.clips {
                if neighbor.id == original.id {
                    continue;
                }
                let touches = [&neighbor.transition_in, &neighbor.transition_out]
                    .into_iter()
                    .flatten()
                    .any(|link| {
                        link.from_clip_id == boundary.from_clip_id
                            && link.to_clip_id == boundary.to_clip_id
                    });
                if !touches {
                    continue;
                }
                if neighbor.is_edit_locked() {
                    return Err("A linked neighboring clip is locked".into());
                }
                for link in [&mut neighbor.transition_in, &mut neighbor.transition_out] {
                    if link.as_ref().is_some_and(|t| {
                        t.from_clip_id == boundary.from_clip_id
                            && t.to_clip_id == boundary.to_clip_id
                    }) {
                        *link = None;
                    }
                }
                if !affected.contains(&neighbor.id) {
                    affected.push(neighbor.id.clone());
                }
            }
        }
        self.before = Some(track.clone());
        self.after = Some(candidate.clone());
        self.affected = affected;
        timeline.tracks[track_index] = candidate;
        timeline.recalculate_duration();
        Ok(self.result("Clip edited"))
    }

    fn undo(&mut self, timeline: &mut Timeline) -> Result<CommandResult, String> {
        Self::restore(
            timeline,
            self.before.as_ref().ok_or("Clip edit has not executed")?,
        )?;
        Ok(self.result("Clip edit undone"))
    }

    fn description(&self) -> String {
        format!("{:?}", self.operation)
    }
}
