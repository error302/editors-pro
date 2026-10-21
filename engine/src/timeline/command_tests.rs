//! Comprehensive tests for the command system (undo/redo)
//!
//! Covers: AddClip, RemoveClip, MoveClip, SplitClip, TrimClip,
//! CommandHistory execution and undo/redo stacks.

use super::clip::Clip;
use super::command::{
    AddClipCommand, Command, CommandHistory, MoveClipCommand, RemoveClipCommand, SplitClipCommand,
    TrimClipCommand,
};
use super::track::TrackType;
use super::Timeline;

fn make_clip(start_ms: u64, duration_ms: u64) -> Clip {
    Clip::new("asset-1", start_ms, duration_ms)
}

fn make_timeline_with_track() -> Timeline {
    let mut tl = Timeline::new();
    tl.add_track(TrackType::Video, Some("V1".into()));
    tl
}

// ─── AddClipCommand ──────────────────────────────────────────

#[test]
fn add_clip_command_executes_and_undo() {
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();
    let clip = make_clip(0, 1000);
    let clip_id = clip.id.clone();

    let mut cmd = AddClipCommand::new(track_id.clone(), clip);

    // Execute
    let result = cmd.execute(&mut tl).unwrap();
    assert!(result.success);
    assert!(tl.find_clip(&clip_id).is_some());

    // Undo
    let undo_result = cmd.undo(&mut tl).unwrap();
    assert!(undo_result.success);
    assert!(tl.find_clip(&clip_id).is_none());
}

#[test]
fn add_clip_command_wrong_track_fails() {
    let mut tl = make_timeline_with_track();
    let clip = make_clip(0, 1000);
    let mut cmd = AddClipCommand::new("nonexistent-track".into(), clip);

    let result = cmd.execute(&mut tl);
    assert!(result.is_err());
}

#[test]
fn add_clip_command_double_execute_fails() {
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();
    let clip = make_clip(0, 1000);
    let mut cmd = AddClipCommand::new(track_id, clip);

    cmd.execute(&mut tl).unwrap();
    let second = cmd.execute(&mut tl);
    assert!(second.is_err()); // clip was taken
}

// ─── RemoveClipCommand ──────────────────────────────────────

#[test]
fn remove_clip_command_executes_and_undo() {
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();
    let clip = make_clip(0, 1000);
    let clip_id = clip.id.clone();

    tl.add_clip_to_track(&track_id, clip).unwrap();

    let mut cmd = RemoveClipCommand::new(clip_id.clone());

    let result = cmd.execute(&mut tl).unwrap();
    assert!(result.success);
    assert!(tl.find_clip(&clip_id).is_none());

    // Undo restores the clip
    let undo_result = cmd.undo(&mut tl).unwrap();
    assert!(undo_result.success);
    assert!(tl.find_clip(&clip_id).is_some());
}

#[test]
fn remove_clip_command_nonexistent_clip_fails() {
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();

    let mut cmd = RemoveClipCommand::new("nonexistent".into());

    let result = cmd.execute(&mut tl);
    assert!(result.is_err());
}

// ─── MoveClipCommand ─────────────────────────────────────────

#[test]
fn move_clip_command_changes_start_ms() {
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();
    let clip = make_clip(0, 1000);
    let clip_id = clip.id.clone();

    tl.add_clip_to_track(&track_id, clip).unwrap();

    let mut cmd = MoveClipCommand::new(clip_id.clone(), 5000, None);

    let result = cmd.execute(&mut tl).unwrap();
    assert!(result.success);
    assert_eq!(tl.find_clip(&clip_id).unwrap().1.start_ms, 5000);

    // Undo
    cmd.undo(&mut tl).unwrap();
    assert_eq!(tl.find_clip(&clip_id).unwrap().1.start_ms, 0);
}

#[test]
fn move_clip_command_nonexistent_clip_fails() {
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();

    let mut cmd = MoveClipCommand::new("nonexistent".into(), 5000, None);

    let result = cmd.execute(&mut tl);
    assert!(result.is_err());
}

// ─── SplitClipCommand ────────────────────────────────────────

#[test]
fn split_clip_command_splits_and_undo() {
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();
    let clip = make_clip(0, 5000);
    let clip_id = clip.id.clone();

    tl.add_clip_to_track(&track_id, clip).unwrap();

    let mut cmd = SplitClipCommand::new(clip_id.clone(), 2500);

    let result = cmd.execute(&mut tl).unwrap();
    assert!(result.success);
    // Original clip should be gone
    assert!(tl.find_clip(&clip_id).is_none());
    // Should have two clips now
    assert_eq!(tl.tracks[0].clips.len(), 2);

    // Undo should restore the original
    cmd.undo(&mut tl).unwrap();
    assert_eq!(tl.tracks[0].clips.len(), 1);
}

#[test]
fn split_clip_command_invalid_time_fails() {
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();
    let clip = make_clip(0, 5000);
    let clip_id = clip.id.clone();

    tl.add_clip_to_track(&track_id, clip).unwrap();

    let mut cmd = SplitClipCommand::new(clip_id, 0);

    let result = cmd.execute(&mut tl);
    assert!(result.is_err());
}

// ─── TrimClipCommand ─────────────────────────────────────────

#[test]
fn trim_clip_command_changes_trim_points() {
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();
    let clip = make_clip(0, 5000);
    let clip_id = clip.id.clone();

    tl.add_clip_to_track(&track_id, clip).unwrap();

    let mut cmd = TrimClipCommand::new(clip_id.clone(), 500, 500);

    let result = cmd.execute(&mut tl).unwrap();
    assert!(result.success);

    let found = tl.find_clip(&clip_id).unwrap().1;
    assert_eq!(found.trim_start_ms, 500);
    assert_eq!(found.trim_end_ms, 500);

    // Undo
    cmd.undo(&mut tl).unwrap();
    let found = tl.find_clip(&clip_id).unwrap().1;
    assert_eq!(found.trim_start_ms, 0);
    assert_eq!(found.trim_end_ms, 0);
}

#[test]
fn trim_clip_command_nonexistent_clip_fails() {
    let mut tl = make_timeline_with_track();

    let mut cmd = TrimClipCommand::new("nonexistent".into(), 500, 0);

    let result = cmd.execute(&mut tl);
    assert!(result.is_err());
}

// ─── CommandHistory ──────────────────────────────────────────

#[test]
fn command_history_new_is_empty() {
    let history = CommandHistory::new();
    assert_eq!(history.undo_stack_len(), 0);
    assert_eq!(history.redo_stack_len(), 0);
}

#[test]
fn command_history_execute_pushes_to_undo_stack() {
    let mut history = CommandHistory::new();
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();
    let clip = make_clip(0, 1000);

    let cmd = AddClipCommand::new(track_id, clip);
    history.execute(Box::new(cmd), &mut tl).unwrap();

    assert_eq!(history.undo_stack_len(), 1);
    assert_eq!(history.redo_stack_len(), 0);
}

#[test]
fn command_history_undo_moves_to_redo_stack() {
    let mut history = CommandHistory::new();
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();
    let clip = make_clip(0, 1000);

    let cmd = AddClipCommand::new(track_id, clip);
    history.execute(Box::new(cmd), &mut tl).unwrap();

    history.undo(&mut tl).unwrap();
    assert_eq!(history.undo_stack_len(), 0);
    assert_eq!(history.redo_stack_len(), 1);
}

#[test]
fn command_history_redo_restores_command() {
    let mut history = CommandHistory::new();
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();
    let clip = make_clip(0, 1000);
    let clip_id = clip.id.clone();

    let cmd = AddClipCommand::new(track_id, clip);
    history.execute(Box::new(cmd), &mut tl).unwrap();
    history.undo(&mut tl).unwrap();

    assert!(tl.find_clip(&clip_id).is_none());

    history.redo(&mut tl).unwrap();
    assert!(tl.find_clip(&clip_id).is_some());
    assert_eq!(history.undo_stack_len(), 1);
    assert_eq!(history.redo_stack_len(), 0);
}

#[test]
fn command_history_undo_on_empty_does_nothing() {
    let mut history = CommandHistory::new();
    let mut tl = Timeline::new();
    let result = history.undo(&mut tl);
    assert!(result.is_err());
}

#[test]
fn command_history_redo_on_empty_does_nothing() {
    let mut history = CommandHistory::new();
    let mut tl = Timeline::new();
    let result = history.redo(&mut tl);
    assert!(result.is_err());
}

#[test]
fn command_history_new_command_clears_redo_stack() {
    let mut history = CommandHistory::new();
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();

    // First command
    let clip1 = make_clip(0, 1000);
    let cmd1 = AddClipCommand::new(track_id.clone(), clip1);
    history.execute(Box::new(cmd1), &mut tl).unwrap();

    // Undo
    history.undo(&mut tl).unwrap();
    assert_eq!(history.redo_stack_len(), 1);

    // New command should clear redo stack
    let clip2 = make_clip(2000, 1000);
    let cmd2 = AddClipCommand::new(track_id, clip2);
    history.execute(Box::new(cmd2), &mut tl).unwrap();

    assert_eq!(history.redo_stack_len(), 0);
    assert_eq!(history.undo_stack_len(), 1);
}

#[test]
fn command_history_description() {
    let history = CommandHistory::new();
    assert!(!history.can_undo());
    assert!(!history.can_redo());
}

#[test]
fn command_history_clear() {
    let mut history = CommandHistory::new();
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();
    let clip = make_clip(0, 1000);
    let cmd = AddClipCommand::new(track_id, clip);
    history.execute(Box::new(cmd), &mut tl).unwrap();

    history.clear();
    assert_eq!(history.undo_stack_len(), 0);
    assert_eq!(history.redo_stack_len(), 0);
}

#[test]
fn command_history_multiple_undo_redo() {
    let mut history = CommandHistory::new();
    let mut tl = make_timeline_with_track();
    let track_id = tl.tracks[0].id.clone();

    for i in 0..5 {
        let clip = make_clip(i * 1000, 1000);
        let cmd = AddClipCommand::new(track_id.clone(), clip);
        history.execute(Box::new(cmd), &mut tl).unwrap();
    }

    assert_eq!(history.undo_stack_len(), 5);

    // Undo all
    for _ in 0..5 {
        history.undo(&mut tl).unwrap();
    }
    assert_eq!(history.undo_stack_len(), 0);
    assert_eq!(history.redo_stack_len(), 5);

    // Redo all
    for _ in 0..5 {
        history.redo(&mut tl).unwrap();
    }
    assert_eq!(history.undo_stack_len(), 5);
    assert_eq!(history.redo_stack_len(), 0);
}
