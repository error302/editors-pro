use editors_pro_engine::api::EditorsProEngine;
use editors_pro_engine::effects::text_rasterizer::TextRasterizer;
use editors_pro_engine::effects::text_render::{TextOverlay, TextPosition};
use editors_pro_engine::timeline::track::TrackType;

#[test]
fn native_text_updates_round_trip_and_undo_atomically() {
    let directory = tempfile::tempdir_in(env!("CARGO_MANIFEST_DIR")).unwrap();
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Text persistence", None).unwrap();
    let track = engine
        .add_track(TrackType::Text, Some("Titles".into()))
        .unwrap();
    let clip = engine
        .add_text_clip(
            &track.id,
            "Résumé\nNairobi",
            "Inter",
            24.0,
            "#ff0000",
            0.25,
            0.75,
            0,
            1000,
        )
        .unwrap();
    assert_eq!(clip.properties["content"], "Résumé\nNairobi");
    let before = clip.properties.clone();
    let original_frame = engine.get_frame(250).unwrap();
    assert!(original_frame.data.chunks_exact(4).any(|pixel| pixel[0] > 200 && pixel[1] == 0 && pixel[2] == 0));
    engine
        .update_text_overlay(
            &clip.id,
            Some("Updated café"),
            Some("Inter-Bold"),
            Some(72.0),
            Some("#00ff00"),
            Some(0.75),
            Some(0.25),
        )
        .unwrap();
    let updated = engine
        .get_timeline_state()
        .unwrap()
        .tracks
        .into_iter()
        .find(|t| t.id == track.id)
        .unwrap()
        .clips
        .remove(0)
        .properties;
    assert_eq!(updated["content"], "Updated café");
    assert_eq!(updated["font_family"], "Inter-Bold");
    assert_eq!(updated["font_size"], 72.0);
    assert_eq!(updated["color_hex"], "#00FF00");
    let updated_frame = engine.get_frame(250).unwrap();
    assert_ne!(original_frame.data, updated_frame.data);
    assert!(updated_frame.data.chunks_exact(4).any(|pixel| pixel[1] > 200 && pixel[0] == 0 && pixel[2] == 0));
    engine.undo().unwrap();
    let undone = engine
        .get_timeline_state()
        .unwrap()
        .tracks
        .into_iter()
        .find(|t| t.id == track.id)
        .unwrap()
        .clips
        .remove(0)
        .properties;
    assert_eq!(undone, before);
    engine.redo().unwrap();
    let path = directory.path().join("text.epp");
    engine.save_project(path.to_str().unwrap()).unwrap();
    engine.load_project(path.to_str().unwrap()).unwrap();
    let reopened = engine
        .get_timeline_state()
        .unwrap()
        .tracks
        .into_iter()
        .find(|t| t.id == track.id)
        .unwrap()
        .clips
        .remove(0)
        .properties;
    assert_eq!(reopened, updated);
    assert_eq!(engine.get_frame(250).unwrap().data, updated_frame.data);
    assert!(engine.get_frame(1000).unwrap().data.chunks_exact(4).all(|pixel| pixel[..3] == [0, 0, 0]));
    engine
        .update_text_overlay(&clip.id, None, None, None, Some("#0000FF"), None, None)
        .unwrap();
    let recolored = engine
        .get_timeline_state()
        .unwrap()
        .tracks
        .into_iter()
        .find(|t| t.id == track.id)
        .unwrap()
        .clips
        .remove(0)
        .properties;
    assert_eq!(recolored["content"], reopened["content"]);
    assert_eq!(recolored["font_size"], reopened["font_size"]);
    assert_eq!(recolored["position_x"], reopened["position_x"]);
}

#[test]
fn invalid_text_changes_leave_all_properties_untouched() {
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Text validation", None).unwrap();
    let track = engine.add_track(TrackType::Text, None).unwrap();
    let clip = engine
        .add_text_clip(
            &track.id, "Keep me", "Inter", 36.0, "#FFFFFF", 0.5, 0.5, 0, 1000,
        )
        .unwrap();
    for size in [f32::NAN, f32::INFINITY, -1.0, 0.0, 513.0] {
        assert!(engine
            .update_text_overlay(
                &clip.id,
                Some("Must not save"),
                None,
                Some(size),
                None,
                None,
                None
            )
            .is_err());
    }
    assert!(engine
        .update_text_overlay(&clip.id, None, Some("Missing font"), None, None, None, None)
        .is_err());
    assert!(engine
        .update_text_overlay(&clip.id, None, None, None, Some("#XYZXYZ"), None, None)
        .is_err());
    assert!(engine
        .update_text_overlay(&clip.id, None, None, None, None, Some(2.0), None)
        .is_err());
    let current = engine
        .get_timeline_state()
        .unwrap()
        .tracks
        .into_iter()
        .find(|t| t.id == track.id)
        .unwrap()
        .clips
        .remove(0)
        .properties;
    assert_eq!(current, clip.properties);
}

fn rasterize(family: &str, size: f32, color: &str, x: f32, y: f32) -> Vec<u8> {
    let mut rasterizer = TextRasterizer::new();
    let mut overlay = TextOverlay::simple("Size Café");
    overlay.font_family = family.into();
    overlay.font_size = size;
    overlay.color.hex = color.into();
    overlay.position = TextPosition::at(x, y);
    overlay.shadow = None;
    let mut pixels = vec![0; 640 * 360 * 4];
    rasterizer.render_text(&overlay, &mut pixels, 640, 360, 0.5, 1000);
    pixels
}

fn bounds(pixels: &[u8]) -> (usize, usize, usize, usize) {
    let mut bounds = (usize::MAX, usize::MAX, 0, 0);
    for (index, pixel) in pixels.chunks_exact(4).enumerate() {
        if pixel[0].max(pixel[1]).max(pixel[2]) > 16 {
            let (x, y) = (index % 640, index / 640);
            bounds = (
                bounds.0.min(x),
                bounds.1.min(y),
                bounds.2.max(x),
                bounds.3.max(y),
            );
        }
    }
    assert_ne!(bounds.0, usize::MAX, "text must paint visible glyphs");
    bounds
}

#[test]
fn embedded_font_faces_sizes_colors_and_positions_change_real_pixels() {
    let engine = EditorsProEngine::new();
    let fonts = engine.get_available_fonts();
    let mut ids = std::collections::HashSet::new();
    let mut rendered = Vec::new();
    for font in fonts {
        assert!(
            ids.insert(font.family.clone()),
            "font dropdown IDs must be unique"
        );
        let pixels = rasterize(&font.family, 36.0, "#FF0000", 0.5, 0.5);
        bounds(&pixels);
        assert!(
            rendered.iter().all(|previous| previous != &pixels),
            "advertised font faces must render distinct glyphs"
        );
        rendered.push(pixels);
    }
    assert_eq!(ids.len(), 4);
    let small = rasterize("Inter", 24.0, "#FF0000", 0.25, 0.25);
    let large = rasterize("Inter", 72.0, "#00FF00", 0.75, 0.75);
    let s = bounds(&small);
    let l = bounds(&large);
    assert!(l.2 - l.0 > 2 * (s.2 - s.0));
    assert!(l.3 - l.1 > 2 * (s.3 - s.1));
    assert!(l.0 > s.0 && l.1 > s.1);
    assert!(small
        .chunks_exact(4)
        .any(|p| p[0] > 200 && p[1] == 0 && p[2] == 0));
    assert!(large
        .chunks_exact(4)
        .any(|p| p[1] > 200 && p[0] == 0 && p[2] == 0));
}
