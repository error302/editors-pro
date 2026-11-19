use editors_pro_engine::api::EditorsProEngine;
use editors_pro_engine::timeline::clip::Clip;
use editors_pro_engine::timeline::command::{Command, SplitClipCommand, TrimClipCommand};
use editors_pro_engine::timeline::speed_curve::SpeedCurve;
use editors_pro_engine::timeline::track::TrackType;
use editors_pro_engine::timeline::Timeline;

#[test]
fn legacy_split_redo_preserves_both_clip_ids() {
    let mut timeline = Timeline::new();
    let track_id = timeline.add_track(TrackType::Video, None).id.clone();
    let clip = Clip::new("owned-source", 1_000, 4_000);
    let id = clip.id.clone();
    timeline.add_clip_to_track(&track_id, clip).unwrap();
    let mut command = SplitClipCommand::new(id, 3_000);
    let first = command.execute(&mut timeline).unwrap().affected_clip_ids;
    command.undo(&mut timeline).unwrap();
    assert_eq!(
        command.execute(&mut timeline).unwrap().affected_clip_ids,
        first
    );
}

#[test]
fn legacy_absolute_source_trim_is_repeatable_at_half_and_double_speed() {
    for speed in [0.5, 2.0] {
        let mut timeline = Timeline::new();
        let track_id = timeline.add_track(TrackType::Video, None).id.clone();
        let mut clip = Clip::new("owned-source", 1_000, 4_000);
        clip.speed_curve = SpeedCurve::constant(speed);
        clip.trim_start_ms = 100;
        clip.trim_end_ms = 200;
        let id = clip.id.clone();
        timeline.add_clip_to_track(&track_id, clip).unwrap();
        let mut first = TrimClipCommand::new(id.clone(), 200, 300);
        first.execute(&mut timeline).unwrap();
        let expected = ((4_000.0 * speed + 300.0 - 500.0) / speed) as u64;
        assert_eq!(timeline.find_clip(&id).unwrap().1.duration_ms, expected);
        let after_first = serde_json::to_string(&timeline).unwrap();
        let mut same = TrimClipCommand::new(id.clone(), 200, 300);
        same.execute(&mut timeline).unwrap();
        assert_eq!(serde_json::to_string(&timeline).unwrap(), after_first);
        same.undo(&mut timeline).unwrap();
        assert_eq!(serde_json::to_string(&timeline).unwrap(), after_first);
    }
}

#[test]
fn legacy_trim_rejects_locked_track_and_impossible_source_ranges_without_mutation() {
    let mut timeline = Timeline::new();
    let track_id = timeline.add_track(TrackType::Video, None).id.clone();
    let clip = Clip::new("owned-source", 1_000, 4_000);
    let id = clip.id.clone();
    timeline.add_clip_to_track(&track_id, clip).unwrap();
    for locked in [false, true] {
        timeline.tracks[0].locked = locked;
        let before = serde_json::to_string(&timeline).unwrap();
        let mut command = TrimClipCommand::new(id.clone(), if locked { 100 } else { 4_000 }, 0);
        assert!(command.execute(&mut timeline).is_err());
        assert_eq!(serde_json::to_string(&timeline).unwrap(), before);
    }
}

#[test]
fn split_api_succeeds_for_one_clip_instead_of_reporting_failure_after_mutation() {
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine
        .create_project("Single cut regression", None)
        .unwrap();
    let track = engine.add_track(TrackType::Text, None).unwrap();
    let clip = engine
        .add_text_clip(
            &track.id,
            "Owned title",
            "Inter",
            48.0,
            "#FFFFFF",
            0.5,
            0.5,
            1_000,
            4_000,
        )
        .unwrap();
    let result = engine.split_clip(&clip.id, 3_000);
    assert!(
        result.is_ok(),
        "A valid cut must return its actual halves: {result:?}"
    );
    let (left, right) = result.unwrap();
    assert_eq!((left.start_ms, right.start_ms), (1_000, 3_000));
}

#[test]
fn split_api_returns_exact_halves_when_other_tracks_overlap_the_cut() {
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Owned cut regression", None).unwrap();
    let original_track = engine
        .add_track(TrackType::Text, Some("Original track".into()))
        .unwrap();
    let first = engine
        .add_text_clip(
            &original_track.id,
            "Original",
            "Inter",
            48.0,
            "#FFFFFF",
            0.5,
            0.5,
            1_000,
            4_000,
        )
        .unwrap();
    let other = engine
        .add_track(TrackType::Text, Some("Overlapping other track".into()))
        .unwrap();
    let overlapping = engine
        .add_text_clip(
            &other.id, "Other", "Inter", 48.0, "#FFFFFF", 0.5, 0.5, 0, 8_000,
        )
        .unwrap();
    assert_ne!(first.id, overlapping.id);
    let result = engine.split_clip(&first.id, 3_000);
    assert!(
        result.is_ok(),
        "Successful mutation must return both split IDs: {result:?}; extra track {}",
        other.id
    );
    let (left, right) = result.unwrap();
    assert_ne!(left.id, right.id);
    assert_ne!(left.id, overlapping.id);
    assert_ne!(right.id, overlapping.id);
    assert_eq!((left.start_ms, left.duration_ms), (1_000, 2_000));
    assert_eq!((right.start_ms, right.duration_ms), (3_000, 2_000));
    engine.undo().unwrap();
    let state = engine.get_timeline_state().unwrap();
    assert!(state
        .tracks
        .iter()
        .flat_map(|t| &t.clips)
        .any(|c| c.id == first.id));
    assert!(!state
        .tracks
        .iter()
        .flat_map(|t| &t.clips)
        .any(|c| c.id == left.id || c.id == right.id));
}
