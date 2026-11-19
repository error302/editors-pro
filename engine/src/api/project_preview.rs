//! Saved-project previews own their engine and never replace the editing project.
use std::collections::HashMap;
use std::path::Path;
use std::sync::Mutex;

use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};

use super::EditorsProEngine;
use crate::export_engine::ExportSettings;
use crate::project::Project;
use crate::timeline::track::TrackType;

const MAX_PREVIEW_MS: u64 = 10_000;
const MAX_JOBS: usize = 32;

#[derive(Debug, Clone, Serialize)]
pub struct SavedProjectInfo {
    pub source_paths: Vec<String>,
    pub duration_ms: u64,
    pub width: u32,
    pub height: u32,
}

pub fn inspect_saved_project(path: &str) -> Result<SavedProjectInfo, String> {
    let project = Project::load_from_epp(Path::new(path))?;
    let referenced: std::collections::HashSet<&str> = project
        .timeline
        .tracks
        .iter()
        .filter(|track| matches!(track.track_type, TrackType::Video | TrackType::Audio))
        .flat_map(|track| track.clips.iter())
        .map(|clip| clip.asset_id.as_str())
        .collect();
    if referenced
        .iter()
        .any(|id| !project.media_assets.iter().any(|asset| asset.id == *id))
    {
        return Err("The saved timeline references missing media metadata".into());
    }
    let mut paths: Vec<String> = project
        .media_assets
        .iter()
        .filter(|asset| referenced.contains(asset.id.as_str()))
        .map(|asset| asset.file_path.clone())
        .collect();
    paths.sort();
    paths.dedup();
    Ok(SavedProjectInfo {
        source_paths: paths,
        duration_ms: project.timeline.duration_ms,
        width: project.settings.width,
        height: project.settings.height,
    })
}

#[derive(Debug, Clone, Deserialize)]
pub struct CloneRequest {
    pub source_path: String,
    pub output_path: String,
    pub project_id: String,
    pub name: String,
}

/// Clone durable timeline data without ever loading the active editing engine.
pub fn clone_saved_project(request: CloneRequest) -> Result<Project, String> {
    if request.source_path == request.output_path || Path::new(&request.output_path).exists() {
        return Err("A project copy must use a new file".into());
    }
    let mut project = Project::load_from_epp(Path::new(&request.source_path))?;
    let ids: HashMap<String, String> = project
        .media_assets
        .iter()
        .map(|asset| (asset.id.clone(), uuid::Uuid::new_v4().to_string()))
        .collect();
    for asset in &mut project.media_assets {
        asset.id = ids[&asset.id].clone();
    }
    for clip in project
        .timeline
        .tracks
        .iter_mut()
        .flat_map(|track| track.clips.iter_mut())
    {
        if let Some(id) = ids.get(&clip.asset_id) {
            clip.asset_id = id.clone();
        }
    }
    let now = chrono::Utc::now().timestamp_millis();
    project.id = request.project_id;
    project.name = request.name;
    project.created_at = now;
    project.updated_at = now;
    project.thumbnail_path = None;
    ensure_parent(&request.output_path)?;
    project.save_as_epp(Path::new(&request.output_path))?;
    Ok(project)
}

#[derive(Debug, Clone, Deserialize)]
pub struct PreviewRequest {
    pub project_path: String,
    pub cover_path: String,
    pub video_path: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct PreviewJobStatus {
    pub job_id: String,
    pub cover_ready: bool,
    pub video_ready: bool,
    pub finished: bool,
    pub error: Option<String>,
    pub duration_ms: u64,
    pub preview_duration_ms: u64,
    pub progress: f32,
}

struct Job {
    request: PreviewRequest,
    status: PreviewJobStatus,
}

static JOBS: Lazy<Mutex<HashMap<String, Job>>> = Lazy::new(|| Mutex::new(HashMap::new()));

/// Starts a bounded worker; dispatch must call this before acquiring ENGINE.
pub fn start_job(request: PreviewRequest) -> Result<PreviewJobStatus, String> {
    let mut jobs = JOBS.lock().map_err(|_| "Preview jobs unavailable")?;
    if let Some(job) = jobs.values().find(|job| {
        !job.status.finished
            && job.request.project_path == request.project_path
            && job.request.cover_path == request.cover_path
            && job.request.video_path == request.video_path
    }) {
        return Ok(job.status.clone());
    }
    // Keep decoding/encoding memory bounded, including requests from another isolate.
    if jobs.values().filter(|job| !job.status.finished).count() >= 1 {
        return Err("Another preview is being prepared. Try again shortly.".into());
    }
    if jobs.len() >= MAX_JOBS {
        jobs.retain(|_, job| !job.status.finished);
    }
    let id = uuid::Uuid::new_v4().to_string();
    let status = PreviewJobStatus {
        job_id: id.clone(),
        cover_ready: false,
        video_ready: false,
        finished: false,
        error: None,
        duration_ms: 0,
        preview_duration_ms: 0,
        progress: 0.0,
    };
    jobs.insert(
        id.clone(),
        Job {
            request: request.clone(),
            status: status.clone(),
        },
    );
    drop(jobs);
    let thread_id = id.clone();
    let spawned = std::thread::Builder::new()
        .name("project-preview".into())
        .spawn(move || {
            let outcome = std::panic::catch_unwind(|| render_job(&thread_id, &request));
            let error = match outcome {
                Ok(Ok(())) => None,
                Ok(Err(error)) => Some(error),
                Err(_) => Some("Preview rendering failed unexpectedly".into()),
            };
            update(&thread_id, |status| {
                status.finished = true;
                status.error = error;
                status.progress = 1.0;
            });
        });
    if let Err(error) = spawned {
        update(&id, |status| {
            status.finished = true;
            status.error = Some(format!("Could not start preview: {error}"));
        });
    }
    Ok(status)
}

pub fn job_status(job_id: &str) -> Result<PreviewJobStatus, String> {
    JOBS.lock()
        .map_err(|_| "Preview jobs unavailable")?
        .get(job_id)
        .map(|job| job.status.clone())
        .ok_or_else(|| "Preview job no longer exists".into())
}

pub fn release_job(job_id: &str) -> Result<(), String> {
    let mut jobs = JOBS.lock().map_err(|_| "Preview jobs unavailable")?;
    if jobs.get(job_id).is_some_and(|job| !job.status.finished) {
        return Err("Preview is still being prepared".into());
    }
    jobs.remove(job_id);
    Ok(())
}

fn update(id: &str, change: impl FnOnce(&mut PreviewJobStatus)) {
    if let Ok(mut jobs) = JOBS.lock() {
        if let Some(job) = jobs.get_mut(id) {
            change(&mut job.status);
        }
    }
}

fn preview_dimensions(width: u32, height: u32) -> (u32, u32) {
    let scale = (480.0 / f64::from(width.min(height).max(1)))
        .min(854.0 / f64::from(width.max(height).max(1)))
        .min(1.0);
    let even = |value: u32| (((f64::from(value) * scale / 2.0).round() as u32) * 2).max(2);
    (even(width), even(height))
}

fn render_job(id: &str, request: &PreviewRequest) -> Result<(), String> {
    let mut engine = EditorsProEngine::new();
    engine.initialize().map_err(|error| error.to_string())?;
    engine.load_project(&request.project_path)?;
    let project = engine
        .project
        .as_ref()
        .ok_or("Saved project was not loaded")?;
    let duration = project.timeline.duration_ms;
    let (width, height) = preview_dimensions(project.settings.width, project.settings.height);
    // Prefer the first actual visual clip over a leading empty gap.
    let cover_time = project
        .timeline
        .tracks
        .iter()
        .filter(|track| {
            track.visible && matches!(track.track_type, TrackType::Video | TrackType::Text)
        })
        .flat_map(|track| track.clips.iter())
        .filter(|clip| clip.duration_ms > 0)
        .min_by_key(|clip| clip.start_ms)
        .map(|clip| clip.start_ms + (clip.duration_ms / 3).min(1000))
        .unwrap_or(0);
    update(id, |status| {
        status.duration_ms = duration;
        status.preview_duration_ms = duration.min(MAX_PREVIEW_MS);
    });
    if duration == 0 {
        return Ok(());
    }

    let frame = engine
        .get_frame(cover_time)
        .map_err(|error| error.to_string())?;
    let frame = engine.renderer.resize_frame(&frame, width, height);
    ensure_parent(&request.cover_path)?;
    image::save_buffer_with_format(
        &request.cover_path,
        &frame.data,
        width,
        height,
        image::ColorType::Rgba8,
        image::ImageFormat::Png,
    )
    .map_err(|error| format!("Could not write project cover: {error}"))?;
    update(id, |status| {
        status.cover_ready = true;
        status.progress = 0.05;
    });

    if let Some(path) = &request.video_path {
        ensure_parent(path)?;
        let mut settings = ExportSettings::hd_720p();
        settings.width = width;
        settings.height = height;
        settings.fps = 12.0;
        settings.bitrate_kbps = 900;
        settings.audio_bitrate_kbps = 96;
        settings.include_audio = true;
        let result = engine.export_preview_video(path, settings, MAX_PREVIEW_MS, &|progress| {
            update(id, |status| status.progress = progress.progress);
        })?;
        if !result.success {
            return Err(result
                .error_message
                .unwrap_or("Preview encoding failed".into()));
        }
        update(id, |status| status.video_ready = true);
    }
    Ok(())
}

fn ensure_parent(path: &str) -> Result<(), String> {
    if let Some(parent) = Path::new(path).parent() {
        std::fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dimensions_preserve_portrait_square_and_even_encoder_bounds() {
        assert_eq!(preview_dimensions(1920, 1080), (854, 480));
        assert_eq!(preview_dimensions(1080, 1920), (480, 854));
        assert_eq!(preview_dimensions(1080, 1080), (480, 480));
        assert_eq!(preview_dimensions(1, 1), (2, 2));
    }

    #[test]
    fn inspect_reads_saved_assets_without_an_active_engine() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("test.epp");
        Project::new("Saved").save_as_epp(&path).unwrap();
        let info = inspect_saved_project(path.to_str().unwrap()).unwrap();
        assert_eq!(info.duration_ms, 0);
        assert!(info.source_paths.is_empty());
        assert!(inspect_saved_project(temp.path().join("missing.epp").to_str().unwrap()).is_err());
    }
}
