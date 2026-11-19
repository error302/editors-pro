//! Text rendering for overlays on video frames
//!
//! Handles rendering text with various fonts, sizes, colors, positions,
//! and animation effects onto video frame data.

use serde::{Deserialize, Serialize};

/// Stable resource IDs shared with Flutter. Every advertised face has embedded bytes.
pub const SUPPORTED_TEXT_FONTS: &[(&str, &str, &str)] = &[
    ("Inter Regular", "Inter", "Regular"),
    ("Inter SemiBold", "Inter-SemiBold", "SemiBold"),
    ("Inter Bold", "Inter-Bold", "Bold"),
    ("DejaVu Sans Regular", "sans-serif", "Regular"),
];

/// Legacy UI builds wrote these names without supplying a corresponding font.
pub fn canonical_font_family(family: &str) -> Option<&'static str> {
    match family {
        "Inter" | "Inter-Regular" | "Inter-Medium" | "Inter-Italic" => Some("Inter"),
        "Inter-SemiBold" => Some("Inter-SemiBold"),
        "Inter-Bold" | "Inter-Bold-Italic" => Some("Inter-Bold"),
        "sans-serif"
        | "sans-serif-Bold"
        | "sans-serif-Italic"
        | "sans-serif-Bold-Italic"
        | "serif"
        | "serif-Bold"
        | "monospace"
        | "DejaVu Sans" => Some("sans-serif"),
        _ => None,
    }
}

pub fn validate_text_values(
    content: &str,
    family: &str,
    size: f32,
    color: &str,
    x: f32,
    y: f32,
) -> Result<(), String> {
    if content.len() > 65_536 || content.contains('\0') {
        return Err("Text must be at most 65536 UTF-8 bytes and contain no NUL characters".into());
    }
    if canonical_font_family(family).is_none() {
        return Err(format!("Font '{}' is not installed for rendering", family));
    }
    if !size.is_finite() || !(8.0..=512.0).contains(&size) {
        return Err("Font size must be between 8 and 512 project pixels".into());
    }
    if color.len() != 7
        || !color.starts_with('#')
        || !color.as_bytes()[1..].iter().all(u8::is_ascii_hexdigit)
    {
        return Err("Text color must be #RRGGBB".into());
    }
    if !x.is_finite() || !y.is_finite() || !(0.0..=1.0).contains(&x) || !(0.0..=1.0).contains(&y) {
        return Err("Text positions must be finite values between 0 and 1".into());
    }
    Ok(())
}

/// A text overlay that can be placed on the timeline
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextOverlay {
    pub id: String,
    pub content: String,
    pub font_family: String,
    pub font_size: f32,
    pub color: TextColor,
    pub background: Option<TextBackground>,
    pub position: TextPosition,
    pub anchor: TextAnchor,
    pub animation: TextAnimation,
    pub outline: Option<TextOutline>,
    pub shadow: Option<TextShadow>,
}

impl TextOverlay {
    /// Read the persisted native contract. Missing legacy values have deterministic defaults.
    pub fn from_properties(
        properties: &std::collections::HashMap<String, serde_json::Value>,
    ) -> Self {
        let string = |key: &str| properties.get(key).and_then(|value| value.as_str());
        let number = |key: &str, fallback: f32| {
            properties
                .get(key)
                .and_then(|value| value.as_f64())
                .map(|value| value as f32)
                .filter(|value| value.is_finite())
                .unwrap_or(fallback)
        };
        let mut overlay = Self::simple(string("content").unwrap_or(""));
        overlay.font_family = canonical_font_family(string("font_family").unwrap_or("sans-serif"))
            .unwrap_or("sans-serif")
            .into();
        overlay.font_size = number("font_size", 36.0).clamp(8.0, 512.0);
        overlay.color = TextColor::with_hex(string("color_hex").unwrap_or("#FFFFFF"));
        overlay.position = TextPosition::at(
            number("position_x", 0.5).clamp(0.0, 1.0),
            number("position_y", 0.5).clamp(0.0, 1.0),
        );
        overlay.shadow = None;
        overlay
    }

    /// Create a simple text overlay with default styling
    pub fn simple(content: &str) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            content: content.to_string(),
            font_family: "sans-serif".to_string(),
            font_size: 48.0,
            color: TextColor::white(),
            background: None,
            position: TextPosition::bottom_center(),
            anchor: TextAnchor::Center,
            animation: TextAnimation::None,
            outline: None,
            shadow: Some(TextShadow::default()),
        }
    }

    /// Create a subtitle-style text overlay
    pub fn subtitle(content: &str) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            content: content.to_string(),
            font_family: "sans-serif".to_string(),
            font_size: 36.0,
            color: TextColor::white(),
            background: Some(TextBackground {
                color: "#000000".to_string(),
                opacity: 0.7,
                padding: 8.0,
                corner_radius: 4.0,
            }),
            position: TextPosition::bottom_center(),
            anchor: TextAnchor::Center,
            animation: TextAnimation::None,
            outline: None,
            shadow: None,
        }
    }

    /// Create a title text overlay
    pub fn title(content: &str) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            content: content.to_string(),
            font_family: "sans-serif".to_string(),
            font_size: 72.0,
            color: TextColor::white(),
            background: None,
            position: TextPosition { x: 0.5, y: 0.3 },
            anchor: TextAnchor::Center,
            animation: TextAnimation::FadeIn { duration_ms: 500 },
            outline: Some(TextOutline {
                color: "#000000".to_string(),
                width: 3.0,
            }),
            shadow: Some(TextShadow::default()),
        }
    }

    /// Get the opacity at a given progress through the clip, considering animation
    pub fn opacity_at_progress(&self, progress: f32, clip_duration_ms: u64) -> f32 {
        match &self.animation {
            TextAnimation::None => 1.0,
            TextAnimation::FadeIn { duration_ms } => {
                let anim_progress = (clip_duration_ms as f32 * progress) / *duration_ms as f32;
                anim_progress.clamp(0.0, 1.0)
            }
            TextAnimation::FadeOut { duration_ms } => {
                let time_from_end = clip_duration_ms as f32 * (1.0 - progress);
                let anim_progress = time_from_end / *duration_ms as f32;
                anim_progress.clamp(0.0, 1.0)
            }
            TextAnimation::Typewriter { .. } => 1.0,
            TextAnimation::SlideIn { .. } => {
                let anim_progress = (clip_duration_ms as f32 * progress / 300.0).clamp(0.0, 1.0);
                smooth_step(anim_progress)
            }
            TextAnimation::Bounce { .. } => 1.0,
            TextAnimation::PopIn { duration_ms } => {
                let anim_progress =
                    (clip_duration_ms as f32 * progress / *duration_ms as f32).clamp(0.0, 1.0);
                if anim_progress < 0.5 {
                    let t = anim_progress * 2.0;
                    t * t // Ease in
                } else {
                    let t = (anim_progress - 0.5) * 2.0;
                    1.0 - (1.0 - t) * (1.0 - t) * 0.2 // Overshoot and settle
                }
            }
        }
    }

    /// Get the visible text content at a given progress (for typewriter effect)
    pub fn visible_text_at_progress(&self, progress: f32) -> &str {
        match &self.animation {
            TextAnimation::Typewriter { chars_per_second } => {
                // Calculate how many characters should be visible
                // This is a simplified version - the actual implementation
                // would need the clip duration to calculate properly
                let visible_chars =
                    (progress.clamp(0.0, 1.0) * self.content.chars().count() as f32) as usize;
                let end = self
                    .content
                    .char_indices()
                    .nth(visible_chars)
                    .map(|(index, _)| index)
                    .unwrap_or(self.content.len());
                &self.content[..end]
            }
            _ => &self.content,
        }
    }
}

fn smooth_step(t: f32) -> f32 {
    t * t * (3.0 - 2.0 * t)
}

/// Text color definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextColor {
    pub hex: String,
    pub opacity: f32,
}

impl TextColor {
    pub fn white() -> Self {
        Self {
            hex: "#FFFFFF".to_string(),
            opacity: 1.0,
        }
    }
    pub fn black() -> Self {
        Self {
            hex: "#000000".to_string(),
            opacity: 1.0,
        }
    }
    pub fn with_hex(hex: &str) -> Self {
        Self {
            hex: hex.to_string(),
            opacity: 1.0,
        }
    }
}

/// Text background
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextBackground {
    pub color: String,
    pub opacity: f32,
    pub padding: f32,
    pub corner_radius: f32,
}

/// Position as normalized coordinates (0.0-1.0 relative to frame)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextPosition {
    pub x: f32,
    pub y: f32,
}

impl TextPosition {
    pub fn center() -> Self {
        Self { x: 0.5, y: 0.5 }
    }
    pub fn bottom_center() -> Self {
        Self { x: 0.5, y: 0.9 }
    }
    pub fn top_center() -> Self {
        Self { x: 0.5, y: 0.1 }
    }
    pub fn at(x: f32, y: f32) -> Self {
        Self { x, y }
    }
}

/// Text anchor point
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum TextAnchor {
    TopLeft,
    TopCenter,
    TopRight,
    CenterLeft,
    Center,
    CenterRight,
    BottomLeft,
    BottomCenter,
    BottomRight,
}

/// Text animation types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TextAnimation {
    None,
    FadeIn {
        duration_ms: u64,
    },
    FadeOut {
        duration_ms: u64,
    },
    Typewriter {
        chars_per_second: f32,
    },
    SlideIn {
        direction: SlideDirection,
        duration_ms: u64,
    },
    Bounce {
        height: f32,
        duration_ms: u64,
    },
    PopIn {
        duration_ms: u64,
    },
}

/// Slide direction for text animations
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum SlideDirection {
    Left,
    Right,
    Top,
    Bottom,
}

/// Text outline
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextOutline {
    pub color: String,
    pub width: f32,
}

/// Text shadow
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextShadow {
    pub color: String,
    pub offset_x: f32,
    pub offset_y: f32,
    pub blur: f32,
}

impl Default for TextShadow {
    fn default() -> Self {
        Self {
            color: "#000000".to_string(),
            offset_x: 2.0,
            offset_y: 2.0,
            blur: 4.0,
        }
    }
}
