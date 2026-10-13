use std::sync::atomic::{AtomicBool, AtomicU64, AtomicU8, Ordering};

use crate::export_engine::{ExportProgress, ExportStage};

static ACTIVE: AtomicBool = AtomicBool::new(false);
static CURRENT_FRAME: AtomicU64 = AtomicU64::new(0);
static TOTAL_FRAMES: AtomicU64 = AtomicU64::new(0);
static ESTIMATED_SECONDS_REMAINING: AtomicU64 = AtomicU64::new(0);
static STAGE: AtomicU8 = AtomicU8::new(0);
static PROGRESS_BITS: AtomicU64 = AtomicU64::new(0.0f64.to_bits());

pub struct ExportStatusGuard;

impl ExportStatusGuard {
    pub fn begin(total_frames: u64) -> Self {
        CURRENT_FRAME.store(0, Ordering::Relaxed);
        TOTAL_FRAMES.store(total_frames, Ordering::Relaxed);
        ESTIMATED_SECONDS_REMAINING.store(0, Ordering::Relaxed);
        PROGRESS_BITS.store(0.0f64.to_bits(), Ordering::Relaxed);
        STAGE.store(stage_code(&ExportStage::Preparing), Ordering::Relaxed);
        ACTIVE.store(true, Ordering::Release);
        Self
    }
}

impl Drop for ExportStatusGuard {
    fn drop(&mut self) {
        ACTIVE.store(false, Ordering::Release);
    }
}

pub fn report(progress: &ExportProgress) {
    if progress.total_frames > 0 {
        TOTAL_FRAMES.store(progress.total_frames, Ordering::Relaxed);
    }
    CURRENT_FRAME.store(progress.current_frame, Ordering::Relaxed);
    ESTIMATED_SECONDS_REMAINING.store(progress.estimated_seconds_remaining, Ordering::Relaxed);
    PROGRESS_BITS.store((progress.progress as f64).to_bits(), Ordering::Relaxed);
    STAGE.store(stage_code(&progress.stage), Ordering::Relaxed);
}

pub fn snapshot_json() -> String {
    let stage = match STAGE.load(Ordering::Acquire) {
        1 => "Preparing",
        2 => "Rendering",
        3 => "Encoding",
        4 => "Finalizing",
        5 => "Complete",
        6 => "Error",
        _ => "",
    };
    let status = serde_json::json!({
        "active": ACTIVE.load(Ordering::Acquire),
        "current_frame": CURRENT_FRAME.load(Ordering::Relaxed),
        "total_frames": TOTAL_FRAMES.load(Ordering::Relaxed),
        "estimated_seconds_remaining": ESTIMATED_SECONDS_REMAINING.load(Ordering::Relaxed),
        "progress": f64::from_bits(PROGRESS_BITS.load(Ordering::Relaxed)),
        "stage_name": stage,
    });
    status.to_string()
}

fn stage_code(stage: &ExportStage) -> u8 {
    match stage {
        ExportStage::Preparing => 1,
        ExportStage::Rendering => 2,
        ExportStage::Encoding => 3,
        ExportStage::Finalizing => 4,
        ExportStage::Complete => 5,
        ExportStage::Error(_) => 6,
    }
}
