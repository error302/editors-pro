//! Project management - Save/load project files
//!
//! Handles the serialization and persistence of project data,
//! including timeline state, media references, and settings.

pub mod format;
pub mod interop;

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

use crate::timeline::Timeline;

/// A complete editing project
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Project {
    pub id: String,
    pub name: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub settings: ProjectSettings,
    pub timeline: Timeline,
    pub media_assets: Vec<MediaAsset>,
    pub thumbnail_path: Option<String>,
    /// Optional for older files; contains edits that previously lived only in the engine.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub render_state: Option<ProjectRenderState>,
}

impl Project {
    /// Create a new empty project
    pub fn new(name: &str) -> Self {
        let now = chrono::Utc::now().timestamp_millis();
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.to_string(),
            created_at: now,
            updated_at: now,
            settings: ProjectSettings::default(),
            timeline: Timeline::new(),
            media_assets: Vec::new(),
            thumbnail_path: None,
            render_state: None,
        }
    }

    /// Create a project with custom settings
    pub fn with_settings(name: &str, settings: ProjectSettings) -> Self {
        let now = chrono::Utc::now().timestamp_millis();
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.to_string(),
            created_at: now,
            updated_at: now,
            settings,
            timeline: Timeline::new(),
            media_assets: Vec::new(),
            thumbnail_path: None,
            render_state: None,
        }
    }

    /// Add a media asset to the project
    pub fn add_media_asset(&mut self, asset: MediaAsset) {
        self.updated_at = chrono::Utc::now().timestamp_millis();
        self.media_assets.push(asset);
    }

    /// Remove a media asset by ID
    pub fn remove_media_asset(&mut self, asset_id: &str) -> Option<MediaAsset> {
        if let Some(pos) = self.media_assets.iter().position(|a| a.id == asset_id) {
            Some(self.media_assets.remove(pos))
        } else {
            None
        }
    }

    /// Find a media asset by ID
    pub fn find_media_asset(&self, asset_id: &str) -> Option<&MediaAsset> {
        self.media_assets.iter().find(|a| a.id == asset_id)
    }

    /// Save the project to a JSON file
    pub fn save_to_file(&self, path: &Path) -> Result<(), String> {
        let json = serde_json::to_string_pretty(self)
            .map_err(|e| format!("Serialization failed: {}", e))?;

        std::fs::write(path, json).map_err(|e| format!("Failed to write file: {}", e))?;

        log::info!("Project saved to {:?}", path);
        Ok(())
    }

    /// Load a project from a JSON file
    pub fn load_from_file(path: &Path) -> Result<Self, String> {
        let json =
            std::fs::read_to_string(path).map_err(|e| format!("Failed to read file: {}", e))?;

        let project: Project =
            serde_json::from_str(&json).map_err(|e| format!("Deserialization failed: {}", e))?;

        log::info!("Project loaded from {:?}", path);
        Ok(project)
    }

    /// Save to the custom .epp format (JSON wrapped in a zip)
    pub fn save_as_epp(&self, path: &Path) -> Result<(), String> {
        let save_data = format::EppFormat::from_project(self);
        save_data.save(path)
    }

    /// Load from .epp format
    pub fn load_from_epp(path: &Path) -> Result<Self, String> {
        let save_data = format::EppFormat::load(path)?;
        Ok(save_data.to_project())
    }

    /// Update the modification timestamp
    pub fn touch(&mut self) {
        self.updated_at = chrono::Utc::now().timestamp_millis();
    }
}

/// Per-track mixer edits use the same typed values during editing and persistence.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct TrackMixerState {
    pub pan: f32,
    pub solo: bool,
}

/// Saved visual/audio edits, excluding decoded buffers and other disposable caches.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ProjectRenderState {
    pub active_lut: Option<crate::effects::lut::Lut>,
    pub active_lut_intensity: f32,
    pub track_mixer_state: HashMap<String, TrackMixerState>,
    pub track_eq_settings: HashMap<String, crate::audio::effects::EqSettings>,
    pub ducking_configs: HashMap<String, crate::audio::ducking::DuckingConfig>,
}

impl Default for ProjectRenderState {
    fn default() -> Self {
        Self {
            active_lut: None,
            active_lut_intensity: 1.0,
            track_mixer_state: HashMap::new(),
            track_eq_settings: HashMap::new(),
            ducking_configs: HashMap::new(),
        }
    }
}

impl ProjectRenderState {
    /// Reject corrupt tables before they can index a frame or partially replace the open project.
    pub fn validate(&self) -> Result<(), String> {
        if !self.active_lut_intensity.is_finite()
            || !(0.0..=1.0).contains(&self.active_lut_intensity)
        {
            return Err("Saved LUT intensity must be finite and between 0 and 1".into());
        }
        if let Some(lut) = &self.active_lut {
            let valid = match lut {
                crate::effects::lut::Lut::Lut1D(lut) => {
                    lut.size > 0
                        && lut.table.iter().all(|channel| {
                            channel.len() == lut.size
                                && channel.iter().all(|value| value.is_finite())
                        })
                }
                crate::effects::lut::Lut::Lut3D(lut) => {
                    lut.size > 0
                        && lut
                            .size
                            .checked_pow(3)
                            .and_then(|count| count.checked_mul(3))
                            == Some(lut.table.len())
                        && lut.table.iter().all(|value| value.is_finite())
                }
            };
            if !valid {
                return Err("Saved LUT table is incomplete or invalid".into());
            }
        }
        if self
            .track_mixer_state
            .values()
            .any(|state| !state.pan.is_finite())
            || self.track_eq_settings.values().any(|eq| {
                !eq.high_pass_hz.is_finite()
                    || !eq.low_pass_hz.is_finite()
                    || eq.bands.iter().any(|band| {
                        !band.frequency.is_finite()
                            || !band.gain_db.is_finite()
                            || !band.q.is_finite()
                    })
            })
            || self
                .ducking_configs
                .values()
                .any(|duck| !duck.duck_level.is_finite() || !duck.threshold.is_finite())
        {
            return Err("Saved audio settings must contain finite values".into());
        }
        Ok(())
    }
}

/// Project-level settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectSettings {
    pub width: u32,
    pub height: u32,
    pub fps: f32,
    pub sample_rate: u32,
    pub background_color: String,
    pub auto_save_interval_ms: u64,
    pub proxy_enabled: bool,
    pub proxy_quality: ProxyQuality,
}

impl ProjectSettings {
    /// Project canvases can be smaller than encoded video, but allocation must stay bounded.
    pub fn validate_for_rendering(&self) -> Result<(), String> {
        if self.width == 0
            || self.height == 0
            || self.width > 8192
            || self.height > 8192
            || u64::from(self.width) * u64::from(self.height) > 67_108_864
        {
            return Err(
                "Project canvas dimensions must be positive and at most 8192 pixels per axis"
                    .into(),
            );
        }
        if !self.fps.is_finite() || self.fps <= 0.0 || self.fps > 240.0 {
            return Err("Project FPS must be finite, positive, and at most 240".into());
        }
        Ok(())
    }
}

impl Default for ProjectSettings {
    fn default() -> Self {
        Self {
            width: 1920,
            height: 1080,
            fps: 30.0,
            sample_rate: 44100,
            background_color: "#000000".to_string(),
            auto_save_interval_ms: 30000, // 30 seconds
            proxy_enabled: true,
            proxy_quality: ProxyQuality::Half,
        }
    }
}

/// Proxy quality for smooth editing on weak devices
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ProxyQuality {
    Quarter,
    Half,
    ThreeQuarter,
}

/// A media asset imported into the project
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaAsset {
    pub id: String,
    pub file_path: String,
    pub file_name: String,
    pub media_type: MediaType,
    pub duration_ms: Option<u64>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub file_size_bytes: u64,
    pub codec: Option<String>,
    pub bitrate: Option<u64>,
    pub import_date: i64,
    pub thumbnail_path: Option<String>,
}

impl MediaAsset {
    /// Create a new media asset from a file path
    pub fn new(file_path: &str, media_type: MediaType) -> Self {
        let path = Path::new(file_path);
        let file_name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string();

        let file_size = std::fs::metadata(file_path).map(|m| m.len()).unwrap_or(0);

        Self {
            id: uuid::Uuid::new_v4().to_string(),
            file_path: file_path.to_string(),
            file_name,
            media_type,
            duration_ms: None,
            width: None,
            height: None,
            file_size_bytes: file_size,
            codec: None,
            bitrate: None,
            import_date: chrono::Utc::now().timestamp_millis(),
            thumbnail_path: None,
        }
    }

    /// Check if this asset is a video
    pub fn is_video(&self) -> bool {
        matches!(self.media_type, MediaType::Video)
    }

    /// Check if this asset is audio
    pub fn is_audio(&self) -> bool {
        matches!(self.media_type, MediaType::Audio)
    }

    /// Check if this asset is an image
    pub fn is_image(&self) -> bool {
        matches!(self.media_type, MediaType::Image)
    }
}

/// Type of media
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum MediaType {
    Video,
    Audio,
    Image,
}
