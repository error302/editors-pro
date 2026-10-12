//! Effects module - Visual effects pipeline
//!
//! Manages the application of visual effects including filters,
//! transitions, text overlays, and chroma key to timeline frames.
//!
//! ## Architecture
//!
//! - `filters` — Pixel-level filter functions using rayon for parallel processing
//! - `transitions` — Clip-to-clip transition blending with spatial effects
//! - `text_render` — Text overlay rendering (model only, rasterization in Phase 6)
//! - `chroma_key` — Green/blue screen color keying with HSV color space
//!
//! The `EffectsPipeline` applies a chain of effects to a frame in order,
//! respecting each effect's `enabled` flag and `order` field.

pub mod chroma_key;
pub mod color_match;
pub mod compositing;
pub mod color_space;
pub mod filters;
pub mod grain;
pub mod gpu_filters;
pub mod legalizer;
pub mod lens_correction;
pub mod lut;
pub mod macro_system;
pub mod masking;
pub mod markers;
pub mod mixer_pro;
pub mod motion_tracking;
pub mod multicam;
pub mod nested_sequence;
pub mod noise_reduction;
pub mod preset;
pub mod retiming;
pub mod sky_replace;
pub mod stabilization;
pub mod text_render;
pub mod text_rasterizer;
pub mod transitions;
pub mod workspace;

use serde::{Deserialize, Serialize};

pub use transitions::{Transition, TransitionType};

/// Types of visual effects supported by the engine
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum EffectType {
    Filter,
    Transition,
    TextOverlay,
    ChromaKey,
    Masking,
    Compositing,
    NoiseReduction,
    LensCorrection,
    SpeedRamp,
    ColorSpace,
    FilmGrain,
}

/// An effect that can be applied to a clip
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Effect {
    pub id: String,
    pub name: String,
    pub effect_type: EffectType,
    pub enabled: bool,
    pub order: u32,
    pub parameters: Vec<EffectParameter>,
}

impl Effect {
    /// Create a new effect with the given name and type
    pub fn new(name: &str, effect_type: EffectType, parameters: Vec<EffectParameter>) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.to_string(),
            effect_type,
            enabled: true,
            order: 0,
            parameters,
        }
    }

    /// Toggle the enabled state of this effect
    pub fn toggle_enabled(&mut self) {
        self.enabled = !self.enabled;
    }

    /// Set a parameter value by name
    pub fn set_parameter(&mut self, name: &str, value: f32) -> Result<(), String> {
        let param = self.parameters.iter_mut()
            .find(|p| p.name == name)
            .ok_or_else(|| format!("Parameter '{}' not found", name))?;
        param.set_value(value);
        Ok(())
    }

    /// Get a parameter value by name
    pub fn get_parameter(&self, name: &str) -> Option<f32> {
        self.parameters.iter().find(|p| p.name == name).map(|p| p.value)
    }
}

/// A single parameter for an effect
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EffectParameter {
    pub name: String,
    pub display_name: String,
    pub value: f32,
    pub min_value: f32,
    pub max_value: f32,
    pub default_value: f32,
    pub step: f32,
}

impl EffectParameter {
    pub fn new(name: &str, display_name: &str, value: f32, min: f32, max: f32, step: f32) -> Self {
        Self {
            name: name.to_string(),
            display_name: display_name.to_string(),
            value: value.clamp(min, max),
            min_value: min,
            max_value: max,
            default_value: value,
            step,
        }
    }

    pub fn set_value(&mut self, value: f32) {
        self.value = value.clamp(self.min_value, self.max_value);
    }

    pub fn reset(&mut self) {
        self.value = self.default_value;
    }
}

/// Pipeline that applies effects in order to frame data
///
/// The pipeline processes effects sequentially in `order` field order.
/// Only enabled effects are applied. For filter effects, each filter's
/// `apply_to_frame()` method is called with the effect's parameters.
pub struct EffectsPipeline {
    effects: Vec<Effect>,
}

impl EffectsPipeline {
    pub fn new(effects: Vec<Effect>) -> Self {
        let mut sorted = effects;
        sorted.sort_by_key(|e| e.order);
        Self { effects: sorted }
    }

    /// Create an empty pipeline
    pub fn empty() -> Self {
        Self { effects: Vec::new() }
    }

    /// Add an effect to the pipeline
    pub fn add_effect(&mut self, effect: Effect) {
        self.effects.push(effect);
        self.effects.sort_by_key(|e| e.order);
    }

    /// Remove an effect by ID
    pub fn remove_effect(&mut self, effect_id: &str) -> Option<Effect> {
        if let Some(pos) = self.effects.iter().position(|e| e.id == effect_id) {
            Some(self.effects.remove(pos))
        } else {
            None
        }
    }

    /// Get all enabled effects in order
    pub fn enabled_effects(&self) -> Vec<&Effect> {
        self.effects.iter().filter(|e| e.enabled).collect()
    }

    /// Get the number of effects in the pipeline
    pub fn len(&self) -> usize {
        self.effects.len()
    }

    /// Check if the pipeline is empty
    pub fn is_empty(&self) -> bool {
        self.effects.is_empty()
    }

    /// Apply all enabled filter effects to RGBA frame data.
    ///
    /// This method iterates through enabled effects and applies each
    /// one based on its type:
    /// - **Filter** effects use `FilterType::apply_to_frame()` with rayon
    /// - **ChromaKey** effects use `chroma_key::apply_chroma_key()` with rayon
    /// - **TextOverlay** and **Transition** effects are handled separately
    ///
    /// Non-filter effects (transitions, text overlays) are handled
    /// elsewhere and are NOT applied by this method.
    pub fn apply(&self, frame_data: &mut [u8], width: u32, height: u32) {
        for effect in self.enabled_effects() {
            match effect.effect_type {
                EffectType::Filter => {
                    // Look up the filter type by name
                    if let Some(filter_type) = filters::FilterType::all_filters().iter()
                        .find(|ft| ft.display_name() == effect.name)
                    {
                        filter_type.apply_to_frame(frame_data, width, height, &effect.parameters);
                    } else {
                        log::warn!("Unknown filter effect: {}", effect.name);
                    }
                }
                EffectType::TextOverlay => {
                    // Text overlay rendering is handled in the renderer
                    log::debug!("Text overlay effect: {} (handled in renderer)", effect.name);
                }
                EffectType::Transition => {
                    // Transitions are handled during clip transition detection
                    log::debug!("Transition effect: {} (handled during transitions)", effect.name);
                }
                EffectType::ChromaKey => {
                    // Note: ChromaKey can also be GPU-accelerated via gpu_filters
                    // when GPU is available. The gpu_filters module maps "chroma_key"
                    // to the dedicated chroma_key.wgsl compute shader which performs
                    // the same HSV-based keying, smoothstep feathering, and spill
                    // suppression entirely on the GPU. When the GPU pipeline is active,
                    // the GpuFilterDispatcher will create a descriptor for this effect
                    // and dispatch it as a compute pass instead of using this CPU path.
                    let config = chroma_key::ChromaKeyConfig::from_parameters(&effect.parameters);
                    chroma_key::apply_chroma_key(frame_data, width, height, &config);
                }
                _ => {
                    log::debug!("Effect type {:?} not handled in CPU apply loop", effect.effect_type);
                }
            }
        }
    }

    /// Get effects of a specific type
    pub fn effects_of_type(&self, effect_type: &EffectType) -> Vec<&Effect> {
        self.effects.iter().filter(|e| &e.effect_type == effect_type).collect()
    }

    /// Clear all effects
    pub fn clear(&mut self) {
        self.effects.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_effect_parameter_clamping() {
        let param = EffectParameter::new("test", "Test", 0.5, 0.0, 1.0, 0.01);
        assert_eq!(param.value, 0.5);

        let mut param = param;
        param.set_value(1.5);
        assert_eq!(param.value, 1.0, "Should clamp to max");

        param.set_value(-0.5);
        assert_eq!(param.value, 0.0, "Should clamp to min");
    }

    #[test]
    fn test_effect_toggle() {
        let mut effect = Effect::new("Brightness", EffectType::Filter, vec![]);
        assert!(effect.enabled);
        effect.toggle_enabled();
        assert!(!effect.enabled);
        effect.toggle_enabled();
        assert!(effect.enabled);
    }

    #[test]
    fn test_pipeline_ordering() {
        let e1 = Effect { id: "1".into(), name: "Brightness".into(), effect_type: EffectType::Filter, enabled: true, order: 2, parameters: vec![] };
        let e2 = Effect { id: "2".into(), name: "Contrast".into(), effect_type: EffectType::Filter, enabled: true, order: 1, parameters: vec![] };
        let pipeline = EffectsPipeline::new(vec![e1, e2]);
        let enabled = pipeline.enabled_effects();
        assert_eq!(enabled[0].name, "Contrast");
        assert_eq!(enabled[1].name, "Brightness");
    }

    #[test]
    fn test_pipeline_apply_brightness() {
        let brightness_effect = filters::FilterType::Brightness.to_effect();
        let pipeline = EffectsPipeline::new(vec![brightness_effect]);

        let mut frame = vec![128u8; 100 * 100 * 4]; // Gray frame
        pipeline.apply(&mut frame, 100, 100);

        // After brightness +0.0 (default), no change
        assert_eq!(frame[0], 128);
    }
}
