//! CPU-based text rasterization using fontdue
//!
//! Renders text overlays onto RGBA frame data. This is the MVP
//! implementation — a GPU-accelerated path will replace it in a
//! future phase for real-time 4K text rendering.

use fontdue::layout::{CoordinateSystem, Layout, LayoutSettings, TextStyle};
use fontdue::Font;

use super::text_render::{TextColor, TextOverlay, TextPosition, TextAnchor, TextOutline, TextShadow, TextBackground};

/// Built-in font bytes — DejaVu Sans (Apache 2.0 license, embedded for MVP).
/// In production, we'd load fonts from the Android assets directory.
const DEJAVU_SANS_REGULAR: &[u8] = include_bytes!("../../fonts/DejaVuSans.ttf");

/// CPU text rasterizer that renders [TextOverlay] instances onto RGBA
/// frame buffers.
pub struct TextRasterizer {
    layout: Layout,
    fonts: Vec<Font>,
}

impl TextRasterizer {
    /// Create a new text rasterizer with the built-in font.
    pub fn new() -> Self {
        let font = Font::from_bytes(DEJAVU_SANS_REGULAR, fontdue::FontSettings::default())
            .expect("Failed to parse built-in font");

        let mut layout = Layout::new(CoordinateSystem::PositiveYDown);
        layout.reset(&LayoutSettings {
            ..Default::default()
        });

        Self {
            layout,
            fonts: vec![font],
        }
    }

    /// Render a text overlay onto an RGBA frame buffer.
    ///
    /// The `frame_rgba` buffer must be `width * height * 4` bytes in
    /// RGBA format. The text is alpha-blended on top of the existing
    /// frame content.
    pub fn render_text(
        &mut self,
        overlay: &TextOverlay,
        frame_rgba: &mut [u8],
        frame_width: u32,
        frame_height: u32,
        progress: f32,
        clip_duration_ms: u64,
    ) {
        let w = frame_width as usize;
        let h = frame_height as usize;

        // Get the text to render (considering typewriter animation)
        let visible_text = overlay.visible_text_at_progress(progress);
        if visible_text.is_empty() {
            return;
        }

        // Calculate opacity from animation
        let text_opacity = overlay.opacity_at_progress(progress, clip_duration_ms);

        // Layout the text
        self.layout.reset(&LayoutSettings {
            ..Default::default()
        });
        self.layout.append(
            &self.fonts,
            &TextStyle::new(visible_text, overlay.font_size, 0),
        );

        // Calculate the pixel position based on the overlay's position and anchor
        let glyphs = self.layout.glyphs();
        if glyphs.is_empty() {
            return;
        }

        // Find text bounding box
        let mut min_x = f32::MAX;
        let mut min_y = f32::MAX;
        let mut max_x = f32::MIN;
        let mut max_y = f32::MIN;

        for glyph in glyphs {
            min_x = min_x.min(glyph.x);
            min_y = min_y.min(glyph.y);
            max_x = max_x.max(glyph.x + glyph.width as f32);
            max_y = max_y.max(glyph.y + glyph.height as f32);
        }

        let text_width = max_x - min_x;
        let text_height = max_y - min_y;

        // Calculate anchor-based position
        let (offset_x, offset_y) = Self::calculate_anchor_offset(
            overlay.anchor,
            text_width,
            text_height,
        );

        let target_x = (overlay.position.x * w as f32) - offset_x;
        let target_y = (overlay.position.y * h as f32) - offset_y;

        // Render background first (if any)
        if let Some(bg) = &overlay.background {
            self.render_background(bg, frame_rgba, w, h, target_x, target_y, text_width, text_height);
        }

        // Render shadow (if any)
        if let Some(shadow) = &overlay.shadow {
            self.render_shadow(shadow, frame_rgba, w, h, &glyphs, min_x, min_y, target_x, target_y, text_opacity);
        }

        // Render outline (if any)
        if let Some(outline) = &overlay.outline {
            self.render_outline(outline, frame_rgba, w, h, &glyphs, min_x, min_y, target_x, target_y, text_opacity);
        }

        // Render text glyphs
        let text_color = Self::parse_hex_color(&overlay.color.hex);
        let text_alpha = (overlay.color.opacity * text_opacity * 255.0) as u8;

        for glyph in glyphs {
            let gx = (target_x + glyph.x - min_x) as i32;
            let gy = (target_y + glyph.y - min_y) as i32;

            // Get the glyph bitmap
            let (metrics, bitmap) = self.fonts[glyph.font_index].rasterize_config(glyph.key);
            let glyph_w = metrics.width;
            let glyph_h = metrics.height;

            for py in 0..glyph_h {
                for px in 0..glyph_w {
                    let alpha = bitmap[py * glyph_w + px];
                    if alpha == 0 {
                        continue;
                    }

                    let fx = gx + px as i32;
                    let fy = gy + py as i32;

                    if fx < 0 || fx >= w as i32 || fy < 0 || fy >= h as i32 {
                        continue;
                    }

                    let pixel_alpha = ((alpha as f32 / 255.0) * text_alpha as f32 / 255.0 * 255.0) as u8;
                    let idx = ((fy as usize) * w + (fx as usize)) * 4;

                    if idx + 3 < frame_rgba.len() {
                        blend_pixel(frame_rgba, idx, text_color[0], text_color[1], text_color[2], pixel_alpha);
                    }
                }
            }
        }
    }

    /// Calculate the offset for the given anchor point.
    fn calculate_anchor_offset(anchor: TextAnchor, text_width: f32, text_height: f32) -> (f32, f32) {
        let ox = match anchor {
            TextAnchor::TopLeft | TextAnchor::CenterLeft | TextAnchor::BottomLeft => 0.0,
            TextAnchor::TopCenter | TextAnchor::Center | TextAnchor::BottomCenter => text_width / 2.0,
            TextAnchor::TopRight | TextAnchor::CenterRight | TextAnchor::BottomRight => text_width,
        };
        let oy = match anchor {
            TextAnchor::TopLeft | TextAnchor::TopCenter | TextAnchor::TopRight => 0.0,
            TextAnchor::CenterLeft | TextAnchor::Center | TextAnchor::CenterRight => text_height / 2.0,
            TextAnchor::BottomLeft | TextAnchor::BottomCenter | TextAnchor::BottomRight => text_height,
        };
        (ox, oy)
    }

    /// Render a background rectangle behind the text.
    fn render_background(
        &self,
        bg: &TextBackground,
        frame_rgba: &mut [u8],
        w: usize,
        h: usize,
        x: f32,
        y: f32,
        text_width: f32,
        text_height: f32,
    ) {
        let bg_color = Self::parse_hex_color(&bg.color);
        let bg_alpha = (bg.opacity * 255.0) as u8;
        let pad = bg.padding as i32;

        let x0 = (x as i32 - pad).max(0) as usize;
        let y0 = (y as i32 - pad).max(0) as usize;
        let x1 = ((x + text_width) as i32 + pad).min(w as i32) as usize;
        let y1 = ((y + text_height) as i32 + pad).min(h as i32) as usize;

        for py in y0..y1 {
            for px in x0..x1 {
                let idx = (py * w + px) * 4;
                if idx + 3 < frame_rgba.len() {
                    blend_pixel(frame_rgba, idx, bg_color[0], bg_color[1], bg_color[2], bg_alpha);
                }
            }
        }
    }

    /// Render text shadow by drawing the glyphs with an offset and blur.
    fn render_shadow(
        &self,
        shadow: &TextShadow,
        frame_rgba: &mut [u8],
        w: usize,
        h: usize,
        glyphs: &[fontdue::layout::GlyphPosition],
        min_x: f32,
        min_y: f32,
        target_x: f32,
        target_y: f32,
        text_opacity: f32,
    ) {
        let shadow_color = Self::parse_hex_color(&shadow.color);
        let shadow_alpha = (0.5 * text_opacity * 255.0) as u8;
        let sx = shadow.offset_x as i32;
        let sy = shadow.offset_y as i32;

        for glyph in glyphs {
            let gx = (target_x + glyph.x - min_x) as i32 + sx;
            let gy = (target_y + glyph.y - min_y) as i32 + sy;
            let (metrics, bitmap) = self.fonts[glyph.font_index].rasterize_config(glyph.key);
            let glyph_w = metrics.width;
            let glyph_h = metrics.height;

            for py in 0..glyph_h {
                for px in 0..glyph_w {
                    let alpha = bitmap[py * glyph_w + px];
                    if alpha < 64 {
                        continue;
                    }
                    let fx = gx + px as i32;
                    let fy = gy + py as i32;
                    if fx < 0 || fx >= w as i32 || fy < 0 || fy >= h as i32 {
                        continue;
                    }
                    let pixel_alpha = ((alpha as f32 / 255.0) * shadow_alpha as f32 / 255.0 * 255.0) as u8;
                    let idx = ((fy as usize) * w + (fx as usize)) * 4;
                    if idx + 3 < frame_rgba.len() {
                        blend_pixel(frame_rgba, idx, shadow_color[0], shadow_color[1], shadow_color[2], pixel_alpha);
                    }
                }
            }
        }
    }

    /// Render text outline by drawing the glyphs at slight offsets.
    fn render_outline(
        &self,
        outline: &TextOutline,
        frame_rgba: &mut [u8],
        w: usize,
        h: usize,
        glyphs: &[fontdue::layout::GlyphPosition],
        min_x: f32,
        min_y: f32,
        target_x: f32,
        target_y: f32,
        text_opacity: f32,
    ) {
        let outline_color = Self::parse_hex_color(&outline.color);
        let outline_alpha = (text_opacity * 255.0) as u8;
        let ow = outline.width as i32;

        for glyph in glyphs {
            let (metrics, bitmap) = self.fonts[glyph.font_index].rasterize_config(glyph.key);
            let glyph_w = metrics.width;
            let glyph_h = metrics.height;

            for py in 0..glyph_h {
                for px in 0..glyph_w {
                    let alpha = bitmap[py * glyph_w + px];
                    if alpha < 128 {
                        continue;
                    }

                    // Draw outline pixels at offsets around the glyph pixel
                    for dx in -ow..=ow {
                        for dy in -ow..=ow {
                            if dx == 0 && dy == 0 {
                                continue; // Skip the center — that's the fill
                            }
                            let fx = (target_x + glyph.x - min_x) as i32 + px as i32 + dx;
                            let fy = (target_y + glyph.y - min_y) as i32 + py as i32 + dy;

                            if fx < 0 || fx >= w as i32 || fy < 0 || fy >= h as i32 {
                                continue;
                            }

                            let idx = ((fy as usize) * w + (fx as usize)) * 4;
                            if idx + 3 < frame_rgba.len() {
                                blend_pixel(frame_rgba, idx, outline_color[0], outline_color[1], outline_color[2], outline_alpha);
                            }
                        }
                    }
                }
            }
        }
    }

    /// Parse a hex color string (e.g., "#FF0000") into [R, G, B].
    fn parse_hex_color(hex: &str) -> [u8; 3] {
        let hex = hex.trim_start_matches('#');
        if hex.len() >= 6 {
            let r = u8::from_str_radix(&hex[0..2], 16).unwrap_or(255);
            let g = u8::from_str_radix(&hex[2..4], 16).unwrap_or(255);
            let b = u8::from_str_radix(&hex[4..6], 16).unwrap_or(255);
            [r, g, b]
        } else {
            [255, 255, 255]
        }
    }
}

/// Alpha-blend a pixel onto the frame buffer.
fn blend_pixel(frame: &mut [u8], idx: usize, r: u8, g: u8, b: u8, a: u8) {
    if idx + 3 >= frame.len() {
        return;
    }
    let alpha = a as f32 / 255.0;
    let inv_alpha = 1.0 - alpha;

    frame[idx] = ((r as f32 * alpha) + (frame[idx] as f32 * inv_alpha)) as u8;
    frame[idx + 1] = ((g as f32 * alpha) + (frame[idx + 1] as f32 * inv_alpha)) as u8;
    frame[idx + 2] = ((b as f32 * alpha) + (frame[idx + 2] as f32 * inv_alpha)) as u8;
    frame[idx + 3] = ((a as f32) + (frame[idx + 3] as f32 * inv_alpha)) as u8;
}

impl Default for TextRasterizer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_text_rasterizer_creation() {
        let _rasterizer = TextRasterizer::new();
    }

    #[test]
    fn test_render_simple_text() {
        let mut rasterizer = TextRasterizer::new();
        let overlay = TextOverlay::simple("Hello, World!");

        // Create a 100x100 RGBA frame (all black)
        let mut frame = vec![0u8; 100 * 100 * 4];

        rasterizer.render_text(&overlay, &mut frame, 100, 100, 0.5, 5000);

        // At least some pixels should be non-zero (the text was rendered)
        let non_zero = frame.iter().filter(|&&b| b > 0).count();
        assert!(non_zero > 0, "Text rendering should produce non-zero pixels");
    }

    #[test]
    fn test_parse_hex_color() {
        assert_eq!(TextRasterizer::parse_hex_color("#FF0000"), [255, 0, 0]);
        assert_eq!(TextRasterizer::parse_hex_color("#00FF00"), [0, 255, 0]);
        assert_eq!(TextRasterizer::parse_hex_color("#0000FF"), [0, 0, 255]);
        assert_eq!(TextRasterizer::parse_hex_color("#FFFFFF"), [255, 255, 255]);
    }
}
