//! Versioned, bounded imports of the implemented native filter stack.

use std::collections::BTreeMap;

use serde::Deserialize;

use super::EditorsProEngine;
use crate::effects::chroma_key::{create_chroma_key_effect, ChromaKeyConfig};
use crate::effects::filters::FilterType;
use crate::effects::EffectType;
use crate::timeline::command::ReplaceClipEffectsCommand;
use crate::timeline::track::TrackType;

const MAX_RECIPE_BYTES: usize = 128 * 1024;
const MAX_RECIPE_EFFECTS: usize = 32;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct EffectRecipe {
    version: u32,
    effects: Vec<RecipeEffect>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RecipeEffect {
    name: String,
    enabled: bool,
    parameters: BTreeMap<String, f32>,
}

impl EditorsProEngine {
    /// Replace native filters and chroma key as one undoable operation.
    ///
    /// Recipes contain canonical native names and parameter values. Look IDs,
    /// membership metadata and effect IDs are deliberately not imported.
    pub fn apply_effect_recipe(&mut self, clip_id: &str, recipe_json: &str) -> Result<(), String> {
        if recipe_json.len() > MAX_RECIPE_BYTES {
            return Err("Effect recipe exceeds the 128 KiB limit".into());
        }
        let recipe: EffectRecipe = serde_json::from_str(recipe_json)
            .map_err(|error| format!("Invalid effect recipe: {error}"))?;
        if recipe.version != 1 {
            return Err("Unsupported effect recipe version".into());
        }
        if recipe.effects.len() > MAX_RECIPE_EFFECTS {
            return Err("Effect recipes may contain at most 32 effects".into());
        }

        let project = self.project.as_mut().ok_or("No project open")?;
        let (track, clip) = project.timeline().find_clip(clip_id).ok_or("Clip not found")?;
        if track.track_type != TrackType::Video {
            return Err("Effect recipes require a photo or video clip on a video track".into());
        }
        if track.locked || clip.is_edit_locked() {
            return Err("Track or clip is locked".into());
        }

        let mut replacements = Vec::with_capacity(recipe.effects.len());
        for (order, requested) in recipe.effects.into_iter().enumerate() {
            let mut effect = if requested.name == "Chroma Key" {
                create_chroma_key_effect(&ChromaKeyConfig::default())
            } else {
                FilterType::all_filters().into_iter()
                    .find(|filter| filter.display_name() == requested.name)
                    .ok_or_else(|| format!("Unsupported recipe effect: {}", requested.name))?
                    .to_effect()
            };
            for (name, value) in requested.parameters {
                if name.starts_with("__look_") {
                    return Err("Look metadata is not an imported filter parameter".into());
                }
                effect.set_parameter(&name, value)?;
            }
            effect.enabled = requested.enabled;
            effect.order = order as u32;
            replacements.push(effect);
        }
        // Non-filter effect objects remain intact, including their own IDs,
        // metadata and ordering. They are not part of this recipe format.
        replacements.extend(clip.effects.iter().filter(|effect| {
            !matches!(effect.effect_type, EffectType::Filter | EffectType::ChromaKey)
        }).cloned());

        self.command_history.execute(
            Box::new(ReplaceClipEffectsCommand::new(clip_id.into(), replacements)),
            project.timeline_mut(),
        )?;
        Ok(())
    }
}
