use editors_pro_engine::api::EditorsProEngine;
use editors_pro_engine::effects::filters::FilterType;
use editors_pro_engine::effects::EffectsPipeline;
use editors_pro_engine::project::ProjectSettings;
use editors_pro_engine::timeline::track::TrackType;
use image::{Rgba, RgbaImage};

fn apply(filter: FilterType, name: &str, value: f32, source: &[u8], width: u32, height: u32) -> Vec<u8> {
    let mut effect = filter.to_effect();
    effect.set_parameter(name, value).unwrap();
    let mut pixels = source.to_vec();
    EffectsPipeline::new(vec![effect]).apply(&mut pixels, width, height);
    pixels
}

#[test]
fn catalog_adjustments_reach_composed_project_pixels_and_bypass_restores_source() {
    let directory = tempfile::tempdir_in(env!("CARGO_MANIFEST_DIR")).unwrap();
    let path = directory.path().join("filter-input.png");
    let image = RgbaImage::from_fn(9, 9, |x, y| {
        if x == 4 && y == 4 { Rgba([190, 120, 55, 255]) }
        else { Rgba([45 + x as u8 * 5, 90 + y as u8 * 3, 130, 255]) }
    });
    image.save(&path).unwrap();
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Catalog output", Some(ProjectSettings {
        width: 9, height: 9, ..Default::default()
    })).unwrap();
    let track = engine.add_track(TrackType::Video, None).unwrap();
    let asset = engine.import_media(path.to_str().unwrap()).unwrap();
    let clip = engine.add_clip(&track.id, &asset.id, 0, 1_000).unwrap();
    let baseline = engine.get_frame(500).unwrap().data.clone();
    for (name, parameter, value) in [
        ("Brightness", "brightness", 0.3),
        ("Contrast", "contrast", 0.5),
        ("Saturation", "saturation", 0.0),
        ("Hue", "hue", 120.0),
        ("Blur", "blur", 2.0),
        ("Sharpen", "sharpen", 1.0),
        ("Grayscale", "grayscale", 1.0),
        ("Sepia", "sepia", 0.8),
        ("Invert", "", 0.0),
        ("Vignette", "vignette", 0.8),
        ("Temperature", "temperature", 1.0),
    ] {
        let effect = engine.add_effect(&clip.id, name).unwrap();
        if !parameter.is_empty() {
            engine.set_effect_parameter(&clip.id, &effect.id, parameter, value).unwrap();
        }
        let rendered = engine.get_frame(500).unwrap().data.clone();
        assert_ne!(rendered, baseline, "{name} must affect composed pixels");
        assert!(rendered.chunks_exact(4).all(|p| p[3] == 255));
        engine.toggle_effect(&clip.id, &effect.id).unwrap();
        assert_eq!(engine.get_frame(500).unwrap().data, baseline, "{name} bypass");
        engine.remove_effect(&clip.id, &effect.id).unwrap();
        assert_eq!(engine.get_frame(500).unwrap().data, baseline, "{name} removal");
    }
}

#[test]
fn neutral_adjustments_are_exact_identity_including_saturation_rounding() {
    let source: Vec<u8> = (0..=255u8).flat_map(|r| [r, 255 - r, r / 3, r]).collect();
    for (filter, name, neutral) in [
        (FilterType::Brightness, "brightness", 0.0),
        (FilterType::Contrast, "contrast", 0.0),
        (FilterType::Saturation, "saturation", 1.0),
        (FilterType::Hue, "hue", 0.0),
        (FilterType::Blur, "blur", 0.0),
        (FilterType::Sharpen, "sharpen", 0.0),
        (FilterType::Grayscale, "grayscale", 0.0),
        (FilterType::Sepia, "sepia", 0.0),
        (FilterType::Vignette, "vignette", 0.0),
        (FilterType::Temperature, "temperature", 0.0),
    ] {
        assert_eq!(apply(filter, name, neutral, &source, 16, 16), source, "{filter:?} neutral");
    }
}

#[test]
fn fractional_blur_does_not_shift_a_centered_highlight() {
    let mut source = vec![0; 9 * 9 * 4];
    for pixel in source.chunks_exact_mut(4) { pixel[3] = 255; }
    source[(4 * 9 + 4) * 4..(4 * 9 + 4) * 4 + 3].fill(255);
    for radius in [0.5, 1.5, 2.5] {
        let actual = apply(FilterType::Blur, "blur", radius, &source, 9, 9);
        assert_ne!(actual, source);
        for y in 0..9 {
            for x in 0..9 {
                assert_eq!(actual[(y * 9 + x) * 4], actual[(y * 9 + 8 - x) * 4], "radius={radius}, x={x}, y={y}");
                assert_eq!(actual[(y * 9 + x) * 4], actual[((8 - y) * 9 + x) * 4], "radius={radius}, x={x}, y={y}");
            }
        }
    }
}

#[test]
fn fractional_blur_keeps_strength_between_adjacent_integer_radii() {
    let mut source = vec![0; 9 * 9 * 4];
    for pixel in source.chunks_exact_mut(4) { pixel[3] = 255; }
    let center = (4 * 9 + 4) * 4;
    source[center..center + 3].fill(255);
    let half = apply(FilterType::Blur, "blur", 0.5, &source, 9, 9);
    let full = apply(FilterType::Blur, "blur", 1.0, &source, 9, 9);
    assert!(half[center] < source[center], "fractional blur must be visible");
    assert!(half[center] > full[center], "half-step blur must retain more of the highlight than radius 1");
}

#[test]
fn vignette_darkens_opposite_corners_equally() {
    let source = vec![255; 8 * 6 * 4];
    let actual = apply(FilterType::Vignette, "vignette", 0.8, &source, 8, 6);
    let corners = [actual[0], actual[7 * 4], actual[5 * 8 * 4], actual[(6 * 8 - 1) * 4]];
    assert!(corners.iter().all(|&v| v == corners[0]), "opposite corners: {corners:?}");
    assert!(actual[(3 * 8 + 4) * 4] > corners[0]);
}

#[test]
fn partial_filter_strength_changes_pixels_less_than_full_strength_and_preserves_alpha() {
    let source = [100, 150, 200, 117];
    for (filter, name, half, full) in [
        (FilterType::Brightness, "brightness", 0.1, 0.2),
        (FilterType::Contrast, "contrast", 0.2, 0.4),
        (FilterType::Saturation, "saturation", 0.5, 0.0),
        (FilterType::Grayscale, "grayscale", 0.5, 1.0),
        (FilterType::Sepia, "sepia", 0.5, 1.0),
        (FilterType::Temperature, "temperature", 0.5, 1.0),
    ] {
        let intermediate = apply(filter, name, half, &source, 1, 1);
        let strongest = apply(filter, name, full, &source, 1, 1);
        let distance = |pixels: &[u8]| (0..3).map(|c| (i32::from(pixels[c]) - i32::from(source[c])).abs()).sum::<i32>();
        assert!(distance(&intermediate) > 0, "{filter:?} half-strength must be visible");
        assert!(distance(&intermediate) < distance(&strongest), "{filter:?} intensity must affect output");
        assert_eq!(intermediate[3], 117);
        assert_eq!(strongest[3], 117);
    }
}

#[test]
fn effect_stack_uses_saved_order_rather_than_vector_order() {
    let mut brightness = FilterType::Brightness.to_effect();
    brightness.set_parameter("brightness", 0.2).unwrap();
    brightness.order = 7;
    let mut invert = FilterType::Invert.to_effect();
    invert.order = 3;
    let mut pixels = [60, 90, 120, 73];
    EffectsPipeline::new(vec![brightness, invert]).apply(&mut pixels, 1, 1);
    // Invert first: [195,165,135], then add 51 to each RGB channel.
    assert_eq!(pixels, [246, 216, 186, 73]);
}

#[test]
fn catalog_chroma_key_exposes_the_lower_video_layer() {
    let directory = tempfile::tempdir_in(env!("CARGO_MANIFEST_DIR")).unwrap();
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Key composition", Some(ProjectSettings {
        width: 4, height: 4, ..Default::default()
    })).unwrap();
    let mut upper_clip = String::new();
    // Later tracks have lower visual priority (order index 0 is topmost).
    for (name, color) in [("Foreground", [0, 255, 0, 255]), ("Background", [220, 40, 20, 255])] {
        let path = directory.path().join(format!("{name}.png"));
        RgbaImage::from_pixel(4, 4, Rgba(color)).save(&path).unwrap();
        let track = engine.add_track(TrackType::Video, Some(name.into())).unwrap();
        let asset = engine.import_media(path.to_str().unwrap()).unwrap();
        let clip = engine.add_clip(&track.id, &asset.id, 0, 1_000).unwrap();
        if name == "Foreground" { upper_clip = clip.id; }
    }
    assert_eq!(&engine.get_frame(500).unwrap().data[..4], &[0, 255, 0, 255]);
    let effect = engine.add_effect(&upper_clip, "Chroma Key").unwrap();
    assert_eq!(&engine.get_frame(500).unwrap().data[..4], &[220, 40, 20, 255]);
    engine.toggle_effect(&upper_clip, &effect.id).unwrap();
    assert_eq!(&engine.get_frame(500).unwrap().data[..4], &[0, 255, 0, 255]);
}
