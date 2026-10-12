//! Error handling and crash reporting utilities
//!
//! Provides structured error types, error chains, crash-safe recovery,
//! and error reporting for the EDITORS-PRO engine.
//!
//! ## Error Handling Philosophy
//!
//! 1. **All errors are structured** — No stringly-typed errors; every error
//!    has a category, code, and context
//! 2. **Errors are recoverable** — The engine should never crash; errors
//!    are reported and operations are degraded gracefully
//! 3. **Error chains preserve context** — When an error propagates, the
//!    original cause is preserved
//! 4. **Crash-safe state** — Auto-save before risky operations so the
//!    user never loses work

use std::fmt;
use std::sync::Arc;

/// Error severity level for categorization and reporting
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ErrorSeverity {
    /// Informational — not really an error, just a note
    Info,
    /// Warning — operation succeeded but with issues
    Warning,
    /// Error — operation failed but app can continue
    Error,
    /// Critical — data loss may occur, need immediate attention
    Critical,
}

impl fmt::Display for ErrorSeverity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ErrorSeverity::Info => write!(f, "INFO"),
            ErrorSeverity::Warning => write!(f, "WARNING"),
            ErrorSeverity::Error => write!(f, "ERROR"),
            ErrorSeverity::Critical => write!(f, "CRITICAL"),
        }
    }
}

/// Error category for grouping related errors
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ErrorCategory {
    /// Decoding errors (FFmpeg, video/audio parsing)
    Decode,
    /// Rendering errors (compositing, effects)
    Render,
    /// Export errors (encoding, muxing)
    Export,
    /// Storage errors (file I/O, SAF, MediaStore)
    Storage,
    /// Memory errors (OOM, pressure)
    Memory,
    /// Project errors (format, corruption)
    Project,
    /// Bridge errors (Flutter-Rust communication)
    Bridge,
    /// GPU errors (shader compilation, device lost)
    Gpu,
    /// Network errors (cloud sync)
    Network,
    /// Configuration errors (invalid settings)
    Config,
}

impl fmt::Display for ErrorCategory {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ErrorCategory::Decode => write!(f, "DECODE"),
            ErrorCategory::Render => write!(f, "RENDER"),
            ErrorCategory::Export => write!(f, "EXPORT"),
            ErrorCategory::Storage => write!(f, "STORAGE"),
            ErrorCategory::Memory => write!(f, "MEMORY"),
            ErrorCategory::Project => write!(f, "PROJECT"),
            ErrorCategory::Bridge => write!(f, "BRIDGE"),
            ErrorCategory::Gpu => write!(f, "GPU"),
            ErrorCategory::Network => write!(f, "NETWORK"),
            ErrorCategory::Config => write!(f, "CONFIG"),
        }
    }
}

use serde::{Deserialize, Serialize};

/// A structured error with full context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EngineErrorDetail {
    /// Error category
    pub category: ErrorCategory,
    /// Error severity
    pub severity: ErrorSeverity,
    /// Machine-readable error code (e.g., "DECODE_001")
    pub code: String,
    /// Human-readable error message
    pub message: String,
    /// Additional context (key-value pairs)
    pub context: std::collections::HashMap<String, String>,
    /// Original error message (if wrapped from another error)
    pub cause: Option<String>,
    /// Timestamp when the error occurred (epoch millis)
    pub timestamp_ms: u64,
    /// Whether this error is recoverable
    pub recoverable: bool,
    /// Suggested recovery action
    pub recovery_hint: Option<String>,
}

impl EngineErrorDetail {
    /// Create a new error detail
    pub fn new(
        category: ErrorCategory,
        severity: ErrorSeverity,
        code: &str,
        message: &str,
    ) -> Self {
        Self {
            category,
            severity,
            code: code.to_string(),
            message: message.to_string(),
            context: std::collections::HashMap::new(),
            cause: None,
            timestamp_ms: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
            recoverable: true,
            recovery_hint: None,
        }
    }

    /// Add context to the error
    pub fn with_context(mut self, key: &str, value: &str) -> Self {
        self.context.insert(key.to_string(), value.to_string());
        self
    }

    /// Set the cause (original error)
    pub fn with_cause(mut self, cause: &str) -> Self {
        self.cause = Some(cause.to_string());
        self
    }

    /// Mark the error as unrecoverable
    pub fn unrecoverable(mut self) -> Self {
        self.recoverable = false;
        self
    }

    /// Add a recovery hint
    pub fn with_recovery_hint(mut self, hint: &str) -> Self {
        self.recovery_hint = Some(hint.to_string());
        self
    }

    /// Format as a log-friendly string
    pub fn format_log(&self) -> String {
        let ctx = if self.context.is_empty() {
            String::new()
        } else {
            format!(
                " [{}]",
                self.context
                    .iter()
                    .map(|(k, v)| format!("{}={}", k, v))
                    .collect::<Vec<_>>()
                    .join(", ")
            )
        };
        let cause = self
            .cause
            .as_ref()
            .map(|c| format!(" (caused by: {})", c))
            .unwrap_or_default();
        let recovery = self
            .recovery_hint
            .as_ref()
            .map(|h| format!(" [recovery: {}]", h))
            .unwrap_or_default();

        format!(
            "[{}][{}] {}: {}{}{}{}",
            self.severity, self.category, self.code, self.message, ctx, cause, recovery
        )
    }
}

impl fmt::Display for EngineErrorDetail {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.format_log())
    }
}

impl std::error::Error for EngineErrorDetail {}

/// Error reporter that collects and reports errors
pub struct ErrorReporter {
    /// Recent errors (ring buffer)
    recent_errors: Vec<EngineErrorDetail>,
    /// Maximum number of recent errors to keep
    max_recent: usize,
    /// Total error count by category
    error_counts: std::collections::HashMap<ErrorCategory, u64>,
}

impl ErrorReporter {
    /// Create a new error reporter
    pub fn new(max_recent: usize) -> Self {
        Self {
            recent_errors: Vec::with_capacity(max_recent),
            max_recent,
            error_counts: std::collections::HashMap::new(),
        }
    }

    /// Report an error
    pub fn report(&mut self, error: EngineErrorDetail) {
        // Log the error
        match error.severity {
            ErrorSeverity::Info => log::info!("{}", error.format_log()),
            ErrorSeverity::Warning => log::warn!("{}", error.format_log()),
            ErrorSeverity::Error => log::error!("{}", error.format_log()),
            ErrorSeverity::Critical => log::error!("⚠️ CRITICAL: {}", error.format_log()),
        }

        // Update counts
        *self
            .error_counts
            .entry(error.category)
            .or_insert(0) += 1;

        // Add to recent errors (ring buffer)
        if self.recent_errors.len() >= self.max_recent {
            self.recent_errors.remove(0);
        }
        self.recent_errors.push(error);
    }

    /// Get recent errors
    pub fn recent_errors(&self) -> &[EngineErrorDetail] {
        &self.recent_errors
    }

    /// Get error count by category
    pub fn error_count(&self, category: ErrorCategory) -> u64 {
        *self.error_counts.get(&category).unwrap_or(&0)
    }

    /// Get total error count
    pub fn total_errors(&self) -> u64 {
        self.error_counts.values().sum()
    }

    /// Get error counts by category
    pub fn error_counts(&self) -> &std::collections::HashMap<ErrorCategory, u64> {
        &self.error_counts
    }

    /// Clear recent errors and counts
    pub fn clear(&mut self) {
        self.recent_errors.clear();
        self.error_counts.clear();
    }

    /// Generate a crash report summary
    pub fn crash_report(&self) -> String {
        let mut report = String::new();
        report.push_str("=== EDITORS-PRO Error Report ===\n");
        report.push_str(&format!("Total errors: {}\n", self.total_errors()));
        report.push_str("Errors by category:\n");
        for (cat, count) in &self.error_counts {
            report.push_str(&format!("  {}: {}\n", cat, count));
        }
        report.push_str("\nRecent errors:\n");
        for error in self.recent_errors.iter().rev() {
            report.push_str(&format!("  {}\n", error.format_log()));
        }
        report.push_str("================================\n");
        report
    }
}

/// Thread-safe global error reporter
static GLOBAL_REPORTER: std::sync::OnceLock<std::sync::Mutex<ErrorReporter>> =
    std::sync::OnceLock::new();

/// Get the global error reporter
pub fn global_reporter() -> &'static std::sync::Mutex<ErrorReporter> {
    GLOBAL_REPORTER.get_or_init(|| std::sync::Mutex::new(ErrorReporter::new(100)))
}

/// Report an error to the global reporter
pub fn report_error(error: EngineErrorDetail) {
    let reporter = global_reporter();
    if let Ok(mut guard) = reporter.lock() {
        guard.report(error);
    }
}

/// Convenience functions for creating specific error types
pub mod errors {
    use super::*;

    /// Create a decode error
    pub fn decode_error(message: &str, cause: Option<&str>) -> EngineErrorDetail {
        let mut err = EngineErrorDetail::new(
            ErrorCategory::Decode,
            ErrorSeverity::Error,
            "DECODE_001",
            message,
        );
        if let Some(c) = cause {
            err = err.with_cause(c);
        }
        err.with_recovery_hint("Try a different video format or re-encode the source file")
    }

    /// Create a render error
    pub fn render_error(message: &str) -> EngineErrorDetail {
        EngineErrorDetail::new(
            ErrorCategory::Render,
            ErrorSeverity::Error,
            "RENDER_001",
            message,
        )
        .with_recovery_hint("Reduce preview quality or disable GPU acceleration")
    }

    /// Create an export error
    pub fn export_error(message: &str, cause: Option<&str>) -> EngineErrorDetail {
        let mut err = EngineErrorDetail::new(
            ErrorCategory::Export,
            ErrorSeverity::Error,
            "EXPORT_001",
            message,
        );
        if let Some(c) = cause {
            err = err.with_cause(c);
        }
        err.with_recovery_hint("Check available storage and try again")
    }

    /// Create a storage error
    pub fn storage_error(message: &str, path: Option<&str>) -> EngineErrorDetail {
        let mut err = EngineErrorDetail::new(
            ErrorCategory::Storage,
            ErrorSeverity::Error,
            "STORAGE_001",
            message,
        );
        if let Some(p) = path {
            err = err.with_context("path", p);
        }
        err.with_recovery_hint("Check file permissions and available storage")
    }

    /// Create a memory warning
    pub fn memory_warning(rss_mb: f64, available_mb: f64) -> EngineErrorDetail {
        EngineErrorDetail::new(
            ErrorCategory::Memory,
            ErrorSeverity::Warning,
            "MEMORY_001",
            &format!(
                "High memory usage: {:.0}MB RSS, {:.0}MB available",
                rss_mb, available_mb
            ),
        )
        .with_context("rss_mb", &format!("{:.1}", rss_mb))
        .with_context("available_mb", &format!("{:.1}", available_mb))
        .with_recovery_hint("Close other apps or reduce preview quality")
    }

    /// Create a critical memory error
    pub fn memory_critical(rss_mb: f64) -> EngineErrorDetail {
        EngineErrorDetail::new(
            ErrorCategory::Memory,
            ErrorSeverity::Critical,
            "MEMORY_002",
            &format!("Critical memory pressure: {:.0}MB RSS", rss_mb),
        )
        .with_context("rss_mb", &format!("{:.1}", rss_mb))
        .unrecoverable()
        .with_recovery_hint("Restart the app to free memory")
    }

    /// Create a project corruption error
    pub fn project_corruption(message: &str) -> EngineErrorDetail {
        EngineErrorDetail::new(
            ErrorCategory::Project,
            ErrorSeverity::Critical,
            "PROJECT_001",
            message,
        )
        .with_recovery_hint("Recover from auto-save or start a new project")
    }

    /// Create a GPU error
    pub fn gpu_error(message: &str) -> EngineErrorDetail {
        EngineErrorDetail::new(
            ErrorCategory::Gpu,
            ErrorSeverity::Warning,
            "GPU_001",
            message,
        )
        .with_recovery_hint("Falling back to CPU rendering")
    }
}

// ─── Unit tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_severity_display() {
        assert_eq!(format!("{}", ErrorSeverity::Info), "INFO");
        assert_eq!(format!("{}", ErrorSeverity::Warning), "WARNING");
        assert_eq!(format!("{}", ErrorSeverity::Error), "ERROR");
        assert_eq!(format!("{}", ErrorSeverity::Critical), "CRITICAL");
    }

    #[test]
    fn test_error_category_display() {
        assert_eq!(format!("{}", ErrorCategory::Decode), "DECODE");
        assert_eq!(format!("{}", ErrorCategory::Render), "RENDER");
        assert_eq!(format!("{}", ErrorCategory::Export), "EXPORT");
        assert_eq!(format!("{}", ErrorCategory::Gpu), "GPU");
    }

    #[test]
    fn test_engine_error_detail_new() {
        let err = EngineErrorDetail::new(
            ErrorCategory::Decode,
            ErrorSeverity::Error,
            "DECODE_001",
            "Failed to decode video",
        );
        assert_eq!(err.category, ErrorCategory::Decode);
        assert_eq!(err.severity, ErrorSeverity::Error);
        assert_eq!(err.code, "DECODE_001");
        assert!(err.recoverable);
        assert!(err.cause.is_none());
    }

    #[test]
    fn test_engine_error_with_context() {
        let err = EngineErrorDetail::new(
            ErrorCategory::Storage,
            ErrorSeverity::Error,
            "STORAGE_001",
            "File not found",
        )
        .with_context("path", "/data/video.mp4")
        .with_context("size", "1024");

        assert_eq!(err.context.get("path"), Some(&"/data/video.mp4".to_string()));
        assert_eq!(err.context.get("size"), Some(&"1024".to_string()));
    }

    #[test]
    fn test_engine_error_with_cause() {
        let err = EngineErrorDetail::new(
            ErrorCategory::Decode,
            ErrorSeverity::Error,
            "DECODE_001",
            "Decode failed",
        )
        .with_cause("FFmpeg returned error code -22");

        assert_eq!(
            err.cause,
            Some("FFmpeg returned error code -22".to_string())
        );
    }

    #[test]
    fn test_engine_error_unrecoverable() {
        let err = EngineErrorDetail::new(
            ErrorCategory::Memory,
            ErrorSeverity::Critical,
            "MEMORY_002",
            "OOM",
        )
        .unrecoverable();

        assert!(!err.recoverable);
    }

    #[test]
    fn test_engine_error_recovery_hint() {
        let err = EngineErrorDetail::new(
            ErrorCategory::Export,
            ErrorSeverity::Error,
            "EXPORT_001",
            "Export failed",
        )
        .with_recovery_hint("Check storage space");

        assert_eq!(err.recovery_hint, Some("Check storage space".to_string()));
    }

    #[test]
    fn test_error_reporter() {
        let mut reporter = ErrorReporter::new(10);
        reporter.report(EngineErrorDetail::new(
            ErrorCategory::Decode,
            ErrorSeverity::Error,
            "DECODE_001",
            "Test error 1",
        ));
        reporter.report(EngineErrorDetail::new(
            ErrorCategory::Render,
            ErrorSeverity::Warning,
            "RENDER_001",
            "Test warning",
        ));

        assert_eq!(reporter.total_errors(), 2);
        assert_eq!(reporter.error_count(ErrorCategory::Decode), 1);
        assert_eq!(reporter.error_count(ErrorCategory::Render), 1);
        assert_eq!(reporter.recent_errors().len(), 2);
    }

    #[test]
    fn test_error_reporter_ring_buffer() {
        let mut reporter = ErrorReporter::new(3);
        for i in 0..5 {
            reporter.report(EngineErrorDetail::new(
                ErrorCategory::Decode,
                ErrorSeverity::Error,
                "DECODE_001",
                &format!("Error {}", i),
            ));
        }
        // Only last 3 should remain
        assert_eq!(reporter.recent_errors().len(), 3);
        assert_eq!(reporter.total_errors(), 5);
    }

    #[test]
    fn test_error_reporter_crash_report() {
        let mut reporter = ErrorReporter::new(10);
        reporter.report(EngineErrorDetail::new(
            ErrorCategory::Decode,
            ErrorSeverity::Error,
            "DECODE_001",
            "Test error",
        ));
        let report = reporter.crash_report();
        assert!(report.contains("EDITORS-PRO Error Report"));
        assert!(report.contains("DECODE"));
    }

    #[test]
    fn test_convenience_errors() {
        let decode_err = errors::decode_error("Bad video", Some("FFmpeg error"));
        assert_eq!(decode_err.category, ErrorCategory::Decode);

        let render_err = errors::render_error("Shader failed");
        assert_eq!(render_err.category, ErrorCategory::Render);

        let export_err = errors::export_error("Muxing failed", None);
        assert_eq!(export_err.category, ErrorCategory::Export);

        let storage_err = errors::storage_error("File not found", Some("/path/to/file"));
        assert_eq!(storage_err.category, ErrorCategory::Storage);

        let mem_warn = errors::memory_warning(500.0, 200.0);
        assert_eq!(mem_warn.severity, ErrorSeverity::Warning);

        let mem_crit = errors::memory_critical(800.0);
        assert_eq!(mem_crit.severity, ErrorSeverity::Critical);
        assert!(!mem_crit.recoverable);

        let proj_err = errors::project_corruption("Invalid JSON");
        assert_eq!(proj_err.category, ErrorCategory::Project);

        let gpu_err = errors::gpu_error("Device lost");
        assert_eq!(gpu_err.category, ErrorCategory::Gpu);
    }

    #[test]
    fn test_global_reporter() {
        report_error(EngineErrorDetail::new(
            ErrorCategory::Bridge,
            ErrorSeverity::Warning,
            "BRIDGE_001",
            "Test global report",
        ));
        let reporter = global_reporter();
        let guard = reporter.lock().unwrap();
        assert!(guard.total_errors() >= 1);
    }

    #[test]
    fn test_format_log() {
        let err = EngineErrorDetail::new(
            ErrorCategory::Decode,
            ErrorSeverity::Error,
            "DECODE_001",
            "Failed to decode",
        )
        .with_context("codec", "h264")
        .with_cause("FFmpeg error");

        let log = err.format_log();
        assert!(log.contains("ERROR"));
        assert!(log.contains("DECODE"));
        assert!(log.contains("DECODE_001"));
        assert!(log.contains("codec=h264"));
        assert!(log.contains("FFmpeg error"));
    }
}
