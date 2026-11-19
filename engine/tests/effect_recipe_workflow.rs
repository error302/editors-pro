use editors_pro_engine::api::EditorsProEngine;
use editors_pro_engine::effects::{Effect, EffectType};
use editors_pro_engine::project::{Project, ProjectSettings};
use editors_pro_engine::timeline::track::TrackType;
use image::{Rgba, RgbaImage};
use serde_json::{json, Value};

fn fixture() -> (tempfile::TempDir, EditorsProEngine, String, String) {
    let directory = tempfile::tempdir_in(env!("CARGO_MANIFEST_DIR")).unwrap();
    let path = directory.path().join("recipe.png");
    RgbaImage::from_fn(8, 8, |x, y| Rgba([90 + x as u8 * 10, 60 + y as u8 * 9, 35, 255])).save(&path).unwrap();
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Recipe", Some(ProjectSettings { width: 8, height: 8, ..Default::default() })).unwrap();
    let track = engine.add_track(TrackType::Video, None).unwrap();
    let asset = engine.import_media(path.to_str().unwrap()).unwrap();
    let first = engine.add_clip(&track.id, &asset.id, 0, 1_000).unwrap();
    let second = engine.add_clip(&track.id, &asset.id, 1_000, 1_000).unwrap();
    (directory, engine, first.id, second.id)
}

fn snapshot(engine: &EditorsProEngine, clip: &str) -> Value {
    serde_json::to_value(engine.get_clip_effects(clip).unwrap()).unwrap()
}

#[test]
fn captured_scaled_look_and_manual_stack_replays_pixels_with_one_step_undo_redo() {
    let (_directory, mut engine, source, destination) = fixture();
    engine.set_filter_look(&source, "warm", 0.65, true).unwrap();
    let manual = engine.add_effect(&source, "Brightness").unwrap();
    engine.set_effect_parameter(&source, &manual.id, "brightness", 0.08).unwrap();
    let disabled = engine.add_effect(&source, "Invert").unwrap();
    engine.toggle_effect(&source, &disabled.id).unwrap();
    let original = engine.get_clip_effects(&source).unwrap();
    let recipe = json!({"version": 1, "effects": original.iter().map(|effect| {
        let parameters: serde_json::Map<String, Value> = effect.parameters.iter()
            .filter(|parameter| !parameter.name.starts_with("__look_"))
            .map(|parameter| (parameter.name.clone(), json!(parameter.value))).collect();
        json!({"name": effect.name, "enabled": effect.enabled, "parameters": parameters})
    }).collect::<Vec<_>>()});
    engine.add_effect(&destination, "Invert").unwrap();
    let before = snapshot(&engine, &destination);
    let expected = engine.get_frame(500).unwrap().data.clone();
    engine.apply_effect_recipe(&destination, &recipe.to_string()).unwrap();
    assert_eq!(engine.get_frame(1_500).unwrap().data, expected);
    let applied = snapshot(&engine, &destination);
    for effect in engine.get_clip_effects(&destination).unwrap() {
        assert!(!effect.id.starts_with("look:"));
        assert!(!original.iter().any(|old| old.id == effect.id));
        assert!(!effect.parameters.iter().any(|p| p.name.starts_with("__look_")));
    }
    engine.undo().unwrap();
    assert_eq!(snapshot(&engine, &destination), before);
    engine.redo().unwrap();
    assert_eq!(snapshot(&engine, &destination), applied);
    assert_eq!(engine.get_frame(1_500).unwrap().data, expected);
}

#[test]
fn malformed_unsupported_or_unbounded_recipes_leave_the_whole_stack_unchanged() {
    let (_directory, mut engine, clip, _) = fixture();
    engine.add_effect(&clip, "Sepia").unwrap();
    let before = snapshot(&engine, &clip);
    let pixel_before = engine.get_frame(500).unwrap().data.clone();
    let effect = json!({"name":"Brightness","enabled":true,"parameters":{"brightness":0.2}});
    let mut invalid = vec![
        json!({"version":2,"effects":[]}).to_string(),
        json!({"version":1,"effects":[],"unknown":true}).to_string(),
        json!({"version":1,"effects":[{"name":"Brightness","enabled":true,"parameters":{},"unknown":true}]}).to_string(),
        json!({"version":1,"effects":[{"name":"Unsupported glow","enabled":true,"parameters":{}}]}).to_string(),
        json!({"version":1,"effects":[{"name":"Brightness","enabled":true,"parameters":{"intensity":0.2}}]}).to_string(),
        json!({"version":1,"effects":[{"name":"Brightness","enabled":true,"parameters":{"brightness":1.1}}]}).to_string(),
        json!({"version":1,"effects":[{"name":"Brightness","enabled":true,"parameters":{"__look_intensity":0.5}}]}).to_string(),
        json!({"version":1,"effects":vec![effect.clone();33]}).to_string(),
        format!("{}{{\"version\":1,\"effects\":[]}}", " ".repeat(128 * 1024)),
        "{\"version\":1,\"effects\":[{\"name\":\"Brightness\",\"enabled\":true,\"parameters\":{\"brightness\":1e100}}]}".to_string(),
    ];
    // An earlier valid effect must not be applied before a later invalid one.
    invalid.push(json!({"version":1,"effects":[effect, {"name":"Blur","enabled":true,"parameters":{"blur":-1}}]}).to_string());
    for recipe in invalid {
        assert!(engine.apply_effect_recipe(&clip, &recipe).is_err());
        assert_eq!(snapshot(&engine, &clip), before);
        assert_eq!(engine.get_frame(500).unwrap().data, pixel_before);
    }
    // A rejected import must not insert an extra history entry.
    engine.undo().unwrap();
    assert!(engine.get_clip_effects(&clip).unwrap().is_empty());
}

#[test]
fn empty_recipe_preserves_other_effect_types_and_locks_are_enforced() {
    let (directory, mut engine, clip, _) = fixture();
    engine.add_effect(&clip, "Sepia").unwrap();
    let path = directory.path().join("recipe.epp");
    engine.save_project(path.to_str().unwrap()).unwrap();
    let mut project = Project::load_from_epp(&path).unwrap();
    let preserved = Effect::new("Preserved text metadata", EffectType::TextOverlay, vec![]);
    project.timeline.find_clip_mut(&clip).unwrap().effects.push(preserved.clone());
    project.save_as_epp(&path).unwrap();
    engine.load_project(path.to_str().unwrap()).unwrap();
    engine.apply_effect_recipe(&clip, "{\"version\":1,\"effects\":[]}").unwrap();
    let remaining = engine.get_clip_effects(&clip).unwrap();
    assert_eq!(remaining.len(), 1);
    assert_eq!(remaining[0].id, preserved.id);

    for lock_clip in [true, false] {
        let mut locked = project.clone();
        let track = locked.timeline.tracks.iter_mut().find(|track| track.clips.iter().any(|c| c.id == clip)).unwrap();
        if lock_clip { track.find_clip_mut(&clip).unwrap().properties.insert("locked".into(), json!(true)); }
        else { track.locked = true; }
        locked.save_as_epp(&path).unwrap();
        engine.load_project(path.to_str().unwrap()).unwrap();
        let before = snapshot(&engine, &clip);
        assert!(engine.apply_effect_recipe(&clip, "{\"version\":1,\"effects\":[]}").is_err());
        assert_eq!(snapshot(&engine, &clip), before);
    }
    let mut audio = project.clone();
    audio.timeline.tracks.iter_mut().find(|track| track.clips.iter().any(|c| c.id == clip)).unwrap().track_type = TrackType::Audio;
    audio.save_as_epp(&path).unwrap();
    engine.load_project(path.to_str().unwrap()).unwrap();
    assert!(engine.apply_effect_recipe(&clip, "{\"version\":1,\"effects\":[]}").is_err());
}
