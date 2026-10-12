//! # EDITORS-PRO Engine
//!
//! Native video editing engine built in Rust for maximum performance
//! and memory safety. Designed to be called from Flutter via bridge.

pub mod analysis;
pub mod api;
pub mod audio;
pub mod cloud;
pub mod decoder;
pub mod effects;
pub mod export_engine;
pub mod pipeline;
pub mod project;
pub mod proxy;
pub mod renderer;
pub mod storage;
pub mod subtitle;
pub mod system;
pub mod template;
pub mod timeline;
pub mod utils;

#[cfg(test)]
mod tests;

use log::LevelFilter;

/// Initialize the editing engine.
/// Must be called once before any other engine operations.
/// Sets up logging and FFmpeg libraries.
pub fn init_engine() -> Result<(), EngineError> {
    // Initialize logger (only first call wins, repeated calls are safe)
    let _ = env_logger::Builder::new()
        .filter_level(LevelFilter::Info)
        .try_init();

    log::info!(
        "EDITORS-PRO Engine v{} initializing",
        env!("CARGO_PKG_VERSION")
    );

    // Initialize FFmpeg libraries
    #[cfg(feature = "ffmpeg")]
    ffmpeg_next::init().map_err(|e| {
        log::error!("Failed to initialize FFmpeg: {}", e);
        EngineError::InitializationFailed(format!("FFmpeg init error: {}", e))
    })?;

    log::info!("Engine initialized successfully");
    Ok(())
}

/// Get the engine version string
pub fn engine_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// Top-level engine error type
#[derive(Debug, thiserror::Error)]
pub enum EngineError {
    #[error("Initialization failed: {0}")]
    InitializationFailed(String),

    #[error("Decoder error: {0}")]
    DecoderError(String),

    #[error("Renderer error: {0}")]
    RendererError(String),

    #[error("Export error: {0}")]
    ExportError(String),

    #[error("Project error: {0}")]
    ProjectError(String),

    #[error("Timeline error: {0}")]
    TimelineError(String),

    #[error("Proxy error: {0}")]
    ProxyError(String),

    #[error("Bridge error: {0}")]
    BridgeError(String),

    #[error("Invalid state: {0}")]
    InvalidState(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),

    /// Phase C.17: catch-all for errors that don't fit the categories above.
    /// Used by the `From<String>` impl so that legacy `Result<_, String>`
    /// return types can be converted to `Result<_, EngineError>` via
    /// `?` or `.map_err(EngineError::from)`.
    #[error("{0}")]
    Other(String),
}

/// Phase C.17: allow `Result<_, String>` to be converted to
/// `Result<_, EngineError>` via `?` or `.map_err(EngineError::from)`.
///
/// This enables incremental migration of the codebase from `String`
/// errors to `EngineError` without touching every call site at once.
/// New code should use the specific variants (e.g., `DecoderError`)
/// rather than relying on this blanket conversion.
impl From<String> for EngineError {
    fn from(s: String) -> Self {
        EngineError::Other(s)
    }
}

/// Phase C.17: allow `Result<_, &str>` to be converted too, since
/// many error literals are `&str`.
impl From<&str> for EngineError {
    fn from(s: &str) -> Self {
        EngineError::Other(s.to_string())
    }
}

pub type EngineResult<T> = Result<T, EngineError>;
