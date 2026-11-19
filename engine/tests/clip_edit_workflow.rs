use editors_pro_engine::effects::filters::FilterType;
use editors_pro_engine::timeline::clip::Clip;
use editors_pro_engine::timeline::command::Command;
use editors_pro_engine::timeline::edit::{ClipEditCommand, ClipEditOperation};
use editors_pro_engine::timeline::keyframe::Keyframe;
use editors_pro_engine::timeline::speed_curve::{EasingType, SpeedCurve};
use editors_pro_engine::timeline::track::{Track, TrackType};
use editors_pro_engine::timeline::Timeline;

fn timeline_with(clip: Clip) -> Timeline {
    let mut timeline = Timeline::new();
    let mut track = Track::new("Owned video".into(), TrackType::Video, 0);
    track.add_clip(clip);
    timeline.tracks.push(track);
    timeline.recalculate_duration();
    timeline
}

fn snapshot(timeline: &Timeline) -> String {
    serde_json::to_string(timeline).unwrap()
}

#[test]
fn duplicate_inserts_without_overwriting_preserves_recipe_and_redoes_stable_ids() {
    let mut clip = Clip::new("owned-source", 1_000, 2_000);
    clip.trim_start_ms = 125;
    clip.properties
        .insert("title".into(), "My actual edit".into());
    clip.opacity = 0.7;
    clip.muted = true;
    let mut look = FilterType::Grayscale.to_effect();
    look.id = "look:noir:original-effect".into();
    clip.effects.push(look);
    clip.add_keyframe("rotation", Keyframe::linear(1_000, 20.0))
        .unwrap();
    let id = clip.id.clone();
    let mut timeline = timeline_with(clip.clone());
    let follower = Clip::new("follower", 3_500, 1_000);
    let follower_id = follower.id.clone();
    timeline.tracks[0].add_clip(follower);
    timeline.recalculate_duration();
    let before = snapshot(&timeline);
    let mut command = ClipEditCommand::new(id, ClipEditOperation::Duplicate);
    let result = command.execute(&mut timeline).unwrap();
    let duplicate_id = result.affected_clip_ids[0].clone();
    let duplicate = timeline.find_clip(&duplicate_id).unwrap().1;
    assert_ne!(duplicate.id, clip.id);
    assert_eq!(
        (
            duplicate.start_ms,
            duplicate.duration_ms,
            duplicate.trim_start_ms
        ),
        (3_000, 2_000, 125)
    );
    assert_eq!(duplicate.properties, clip.properties);
    assert_eq!((duplicate.opacity, duplicate.muted), (0.7, true));
    assert!(duplicate.effects[0].id.starts_with("look:noir:"));
    assert_ne!(duplicate.effects[0].id, clip.effects[0].id);
    assert_eq!(
        duplicate.effects[0].parameters.len(),
        clip.effects[0].parameters.len()
    );
    assert_ne!(
        duplicate.keyframes.rotation.keyframes[0].id,
        clip.keyframes.rotation.keyframes[0].id
    );
    assert_eq!(duplicate.keyframes.rotation.keyframes[0].time_ms, 3_000);
    assert_eq!(timeline.find_clip(&follower_id).unwrap().1.start_ms, 5_500);
    assert_eq!(timeline.duration_ms, 6_500);
    let after = snapshot(&timeline);
    command.undo(&mut timeline).unwrap();
    assert_eq!(snapshot(&timeline), before);
    let redo = command.execute(&mut timeline).unwrap();
    assert_eq!(redo.affected_clip_ids[0], duplicate_id);
    assert_eq!(snapshot(&timeline), after);
}

#[test]
fn trim_in_and_out_convert_timeline_delta_to_source_at_half_and_double_speed() {
    for speed in [0.5, 2.0] {
        for trim_in in [true, false] {
            let mut clip = Clip::new("owned-source", 1_000, 4_000);
            clip.trim_start_ms = 100;
            clip.trim_end_ms = 200;
            clip.speed_curve = SpeedCurve::constant(speed);
            let id = clip.id.clone();
            let mut timeline = timeline_with(clip);
            let before = snapshot(&timeline);
            let op = if trim_in {
                ClipEditOperation::TrimIn { time_ms: 2_000 }
            } else {
                ClipEditOperation::TrimOut { time_ms: 4_000 }
            };
            let mut command = ClipEditCommand::new(id.clone(), op);
            assert_eq!(
                command.execute(&mut timeline).unwrap().affected_clip_ids[0],
                id
            );
            let edited = timeline.find_clip(&id).unwrap().1;
            let delta = (1_000.0 * speed) as u64;
            assert_eq!(edited.duration_ms, 3_000);
            assert_eq!(edited.start_ms, if trim_in { 2_000 } else { 1_000 });
            assert_eq!(edited.trim_start_ms, 100 + if trim_in { delta } else { 0 });
            assert_eq!(edited.trim_end_ms, 200 + if trim_in { 0 } else { delta });
            command.undo(&mut timeline).unwrap();
            assert_eq!(snapshot(&timeline), before);
        }
    }
}

#[test]
fn ripple_delete_closes_only_selected_track_and_preserves_gaps_and_animation() {
    let early = Clip::new("early", 0, 500);
    let target = Clip::new("target", 1_000, 2_000);
    let id = target.id.clone();
    let mut late = Clip::new("late", 3_500, 1_000);
    late.add_keyframe("opacity", Keyframe::linear(3_500, 0.3))
        .unwrap();
    let late_id = late.id.clone();
    let mut timeline = timeline_with(target);
    timeline.tracks[0].add_clip(early.clone());
    timeline.tracks[0].add_clip(late);
    let mut other = Track::new("Other track".into(), TrackType::Audio, 1);
    other.add_clip(Clip::new("music", 3_500, 2_000));
    timeline.tracks.push(other);
    timeline.recalculate_duration();
    let before = snapshot(&timeline);
    let other_before = serde_json::to_string(&timeline.tracks[1]).unwrap();
    let mut command = ClipEditCommand::new(id.clone(), ClipEditOperation::RippleDelete);
    let result = command.execute(&mut timeline).unwrap();
    assert_eq!(result.affected_clip_ids, vec![id.clone(), late_id.clone()]);
    assert!(timeline.find_clip(&id).is_none());
    assert_eq!(timeline.find_clip(&early.id).unwrap().1.start_ms, 0);
    let shifted = timeline.find_clip(&late_id).unwrap().1;
    assert_eq!(shifted.start_ms, 1_500);
    assert_eq!(shifted.keyframes.opacity.keyframes[0].time_ms, 1_500);
    assert_eq!(
        serde_json::to_string(&timeline.tracks[1]).unwrap(),
        other_before
    );
    command.undo(&mut timeline).unwrap();
    assert_eq!(snapshot(&timeline), before);
}

#[test]
fn rejected_clip_edits_leave_every_byte_of_timeline_state_unchanged() {
    for operation in [
        ClipEditOperation::Duplicate,
        ClipEditOperation::RippleDelete,
        ClipEditOperation::TrimIn { time_ms: 2_000 },
        ClipEditOperation::TrimOut { time_ms: 2_000 },
    ] {
        for lock_track in [true, false] {
            let mut clip = Clip::new("owned-source", 1_000, 4_000);
            clip.properties
                .insert("locked".into(), (!lock_track).into());
            let id = clip.id.clone();
            let mut timeline = timeline_with(clip);
            timeline.tracks[0].locked = lock_track;
            let before = snapshot(&timeline);
            let mut command = ClipEditCommand::new(id, operation.clone());
            assert!(command.execute(&mut timeline).is_err());
            assert_eq!(snapshot(&timeline), before);
        }
    }
}

#[test]
fn insertion_and_ripple_reject_locked_followers_and_straddling_overlaps() {
    for operation in [
        ClipEditOperation::Duplicate,
        ClipEditOperation::RippleDelete,
    ] {
        for straddles in [true, false] {
            let target = Clip::new("target", 1_000, 2_000);
            let id = target.id.clone();
            let mut timeline = timeline_with(target);
            let mut other = Clip::new("other", if straddles { 2_500 } else { 3_500 }, 1_000);
            if !straddles {
                other.properties.insert("locked".into(), true.into());
            }
            timeline.tracks[0].add_clip(other);
            timeline.recalculate_duration();
            let before = snapshot(&timeline);
            assert!(ClipEditCommand::new(id, operation.clone())
                .execute(&mut timeline)
                .is_err());
            assert_eq!(snapshot(&timeline), before);
        }
    }
}

#[test]
fn duplicate_preserves_an_earlier_overlap_that_does_not_cross_insertion_boundary() {
    let target = Clip::new("target", 1_000, 2_000);
    let id = target.id.clone();
    let mut timeline = timeline_with(target);
    let overlapping = Clip::new("earlier overlapping layer", 500, 1_500);
    let overlap_id = overlapping.id.clone();
    timeline.tracks[0].add_clip(overlapping);
    timeline.recalculate_duration();
    let result = ClipEditCommand::new(id, ClipEditOperation::Duplicate)
        .execute(&mut timeline)
        .unwrap();
    assert_eq!(timeline.find_clip(&overlap_id).unwrap().1.start_ms, 500);
    assert_eq!(
        timeline
            .find_clip(&result.affected_clip_ids[0])
            .unwrap()
            .1
            .start_ms,
        3_000
    );
}

#[test]
fn trim_rejects_boundaries_variable_speed_and_timestamp_overflow_atomically() {
    for time in [999, 1_000, 5_000, 5_001] {
        for operation in [
            ClipEditOperation::TrimIn { time_ms: time },
            ClipEditOperation::TrimOut { time_ms: time },
        ] {
            let clip = Clip::new("source", 1_000, 4_000);
            let mut timeline = timeline_with(clip.clone());
            let before = snapshot(&timeline);
            assert!(ClipEditCommand::new(clip.id, operation)
                .execute(&mut timeline)
                .is_err());
            assert_eq!(snapshot(&timeline), before);
        }
    }
    let mut clip = Clip::new("source", 1_000, 4_000);
    clip.speed_curve = SpeedCurve::ramp(0.5, 2.0, 4_000, EasingType::Linear);
    let mut timeline = timeline_with(clip.clone());
    let before = snapshot(&timeline);
    assert!(
        ClipEditCommand::new(clip.id, ClipEditOperation::TrimIn { time_ms: 2_000 })
            .execute(&mut timeline)
            .is_err()
    );
    assert_eq!(snapshot(&timeline), before);
    let clip = Clip::new("source", u64::MAX - 4_000, 3_000);
    let mut timeline = timeline_with(clip.clone());
    let before = snapshot(&timeline);
    assert!(ClipEditCommand::new(clip.id, ClipEditOperation::Duplicate)
        .execute(&mut timeline)
        .is_err());
    assert_eq!(snapshot(&timeline), before);
}

#[test]
fn malformed_speed_and_zero_length_fail_before_any_clip_is_published() {
    for speed in [0.0, -1.0, f32::NAN, f32::INFINITY, f32::MAX] {
        let mut clip = Clip::new("source", 1_000, 4_000);
        clip.speed_curve = SpeedCurve::constant(speed);
        let id = clip.id.clone();
        let mut timeline = timeline_with(clip);
        // NaN isn't representable in JSON; debug formatting also preserves it.
        let before = format!("{:?}", timeline.tracks);
        assert!(ClipEditCommand::new(id, ClipEditOperation::Duplicate)
            .execute(&mut timeline)
            .is_err());
        assert_eq!(format!("{:?}", timeline.tracks), before);
    }
    let clip = Clip::new("source", 1_000, 0);
    let mut timeline = timeline_with(clip.clone());
    let before = snapshot(&timeline);
    assert!(ClipEditCommand::new(clip.id, ClipEditOperation::Duplicate)
        .execute(&mut timeline)
        .is_err());
    assert_eq!(snapshot(&timeline), before);
}

#[test]
fn split_keeps_only_external_boundaries_and_remaps_transition_owner_ids() {
    use editors_pro_engine::effects::transitions::{Transition, TransitionType};
    let mut clip = Clip::new("source", 1_000, 4_000);
    clip.transition_in = Some(Transition::new(
        TransitionType::Dissolve,
        200,
        "before",
        &clip.id,
    ));
    clip.transition_out = Some(Transition::new(
        TransitionType::Fade,
        200,
        &clip.id,
        "after",
    ));
    let (left, right) = clip.split_at(3_000).unwrap();
    assert!(left.transition_out.is_none());
    assert!(right.transition_in.is_none());
    assert_eq!(left.transition_in.as_ref().unwrap().to_clip_id, left.id);
    assert_eq!(
        right.transition_out.as_ref().unwrap().from_clip_id,
        right.id
    );
    assert_ne!(
        left.transition_in.as_ref().unwrap().id,
        clip.transition_in.as_ref().unwrap().id
    );
}

#[test]
fn split_updates_neighbor_links_atomically_and_undo_restores_them() {
    use editors_pro_engine::effects::transitions::{Transition, TransitionType};
    use editors_pro_engine::timeline::command::SplitClipCommand;
    let mut before = Clip::new("before", 0, 1_000);
    let mut target = Clip::new("target", 1_000, 4_000);
    let mut after = Clip::new("after", 5_000, 1_000);
    let incoming = Transition::new(TransitionType::Fade, 200, &before.id, &target.id);
    let outgoing = Transition::new(TransitionType::Dissolve, 200, &target.id, &after.id);
    before.transition_out = Some(incoming.clone());
    target.transition_in = Some(incoming);
    target.transition_out = Some(outgoing.clone());
    after.transition_in = Some(outgoing);
    let id = target.id.clone();
    let mut timeline = timeline_with(target);
    timeline.tracks[0].add_clip(before.clone());
    timeline.tracks[0].add_clip(after.clone());
    timeline.recalculate_duration();
    let original = snapshot(&timeline);
    let mut command = SplitClipCommand::new(id, 3_000);
    let result = command.execute(&mut timeline).unwrap();
    let left = timeline.find_clip(&result.affected_clip_ids[0]).unwrap().1;
    let right = timeline.find_clip(&result.affected_clip_ids[1]).unwrap().1;
    let before_link = timeline
        .find_clip(&before.id)
        .unwrap()
        .1
        .transition_out
        .as_ref()
        .unwrap();
    let after_link = timeline
        .find_clip(&after.id)
        .unwrap()
        .1
        .transition_in
        .as_ref()
        .unwrap();
    assert_eq!(before_link.to_clip_id, left.id);
    assert_eq!(before_link.id, left.transition_in.as_ref().unwrap().id);
    assert_eq!(after_link.from_clip_id, right.id);
    assert_eq!(after_link.id, right.transition_out.as_ref().unwrap().id);
    command.undo(&mut timeline).unwrap();
    assert_eq!(snapshot(&timeline), original);
    timeline
        .find_clip_mut(&before.id)
        .unwrap()
        .properties
        .insert("locked".into(), true.into());
    let locked = snapshot(&timeline);
    let target_id = timeline.tracks[0]
        .clips
        .iter()
        .find(|c| c.asset_id == "target")
        .unwrap()
        .id
        .clone();
    assert!(SplitClipCommand::new(target_id, 3_000)
        .execute(&mut timeline)
        .is_err());
    assert_eq!(snapshot(&timeline), locked);
}

#[test]
fn ripple_delete_clears_dangling_boundary_links_and_undo_restores_them() {
    use editors_pro_engine::effects::transitions::{Transition, TransitionType};
    let mut before = Clip::new("before", 0, 1_000);
    let target = Clip::new("target", 1_000, 2_000);
    let id = target.id.clone();
    before.transition_out = Some(Transition::new(TransitionType::Fade, 200, &before.id, &id));
    let mut timeline = timeline_with(target);
    timeline.tracks[0].add_clip(before.clone());
    timeline.recalculate_duration();
    let original = snapshot(&timeline);
    let mut command = ClipEditCommand::new(id, ClipEditOperation::RippleDelete);
    command.execute(&mut timeline).unwrap();
    assert!(timeline
        .find_clip(&before.id)
        .unwrap()
        .1
        .transition_out
        .is_none());
    command.undo(&mut timeline).unwrap();
    assert_eq!(snapshot(&timeline), original);
}

#[test]
fn trimming_a_linked_edge_detaches_both_sides_or_refuses_a_locked_neighbor() {
    use editors_pro_engine::effects::transitions::{Transition, TransitionType};
    for trim_in in [true, false] {
        for locked in [true, false] {
            let mut target = Clip::new("target", 1_000, 2_000);
            let mut neighbor = Clip::new("neighbor", if trim_in { 0 } else { 3_000 }, 1_000);
            let boundary = if trim_in {
                Transition::new(TransitionType::Fade, 200, &neighbor.id, &target.id)
            } else {
                Transition::new(TransitionType::Fade, 200, &target.id, &neighbor.id)
            };
            if trim_in {
                target.transition_in = Some(boundary.clone());
                neighbor.transition_out = Some(boundary);
            } else {
                target.transition_out = Some(boundary.clone());
                neighbor.transition_in = Some(boundary);
            }
            neighbor.properties.insert("locked".into(), locked.into());
            let neighbor_id = neighbor.id.clone();
            let target_id = target.id.clone();
            let mut timeline = timeline_with(target);
            timeline.tracks[0].add_clip(neighbor);
            timeline.recalculate_duration();
            let before = snapshot(&timeline);
            let operation = if trim_in {
                ClipEditOperation::TrimIn { time_ms: 2_000 }
            } else {
                ClipEditOperation::TrimOut { time_ms: 2_000 }
            };
            let mut command = ClipEditCommand::new(target_id.clone(), operation);
            let result = command.execute(&mut timeline);
            if locked {
                assert!(result.is_err());
                assert_eq!(snapshot(&timeline), before);
            } else {
                result.unwrap();
                let target = timeline.find_clip(&target_id).unwrap().1;
                let neighbor = timeline.find_clip(&neighbor_id).unwrap().1;
                assert!(if trim_in {
                    target.transition_in.is_none() && neighbor.transition_out.is_none()
                } else {
                    target.transition_out.is_none() && neighbor.transition_in.is_none()
                });
                command.undo(&mut timeline).unwrap();
                assert_eq!(snapshot(&timeline), before);
            }
        }
    }
}

#[test]
fn split_constant_speed_preserves_both_source_ranges() {
    for speed in [0.5, 2.0] {
        let mut clip = Clip::new("owned-source", 1_000, 4_000);
        clip.trim_start_ms = 250;
        clip.trim_end_ms = 125;
        clip.speed_curve = SpeedCurve::constant(speed);
        let (left, right) = clip.split_at(2_000).unwrap();
        assert_eq!(left.trim_start_ms, 250);
        assert_eq!(left.trim_end_ms, 125 + (3_000.0 * speed) as u64);
        assert_eq!(right.trim_start_ms, 250 + (1_000.0 * speed) as u64);
        assert_eq!(right.trim_end_ms, 125);
        assert_eq!(left.duration_ms + right.duration_ms, clip.duration_ms);
        assert_eq!(right.end_ms(), clip.end_ms());
    }
}

#[test]
fn split_refuses_variable_speed_and_locked_clips() {
    let mut clip = Clip::new("owned-source", 1_000, 4_000);
    clip.speed_curve = SpeedCurve::ramp(0.5, 2.0, 4_000, EasingType::Linear);
    assert!(clip.split_at(2_000).is_err());
    clip.speed_curve = SpeedCurve::constant(1.0);
    clip.properties.insert("locked".into(), true.into());
    assert!(clip.split_at(2_000).is_err());
}

#[test]
fn split_keeps_animation_at_boundary_with_independent_keyframe_ids() {
    let mut clip = Clip::new("owned-source", 1_000, 4_000);
    clip.add_keyframe("rotation", Keyframe::linear(1_000, 0.0))
        .unwrap();
    clip.add_keyframe("rotation", Keyframe::linear(5_000, 90.0))
        .unwrap();
    let (left, right) = clip.split_at(3_000).unwrap();
    for time in [1_000, 2_500, 3_000, 4_500] {
        assert_eq!(
            left.interpolate_at(time).rotation,
            clip.interpolate_at(time).rotation
        );
        assert_eq!(
            right.interpolate_at(time).rotation,
            clip.interpolate_at(time).rotation
        );
    }
    assert_ne!(
        left.keyframes.rotation.keyframes[0].id,
        right.keyframes.rotation.keyframes[0].id
    );
    assert_ne!(
        left.keyframes.rotation.keyframes[0].id,
        clip.keyframes.rotation.keyframes[0].id
    );
}
