//! Audio transcription using Whisper
//!
//! Transcribes audio from video files into timestamped text segments
//! that can be used to create subtitle clips on the timeline.
//!
//! ## Architecture
//!
//! 1. Extract audio from video file
//! 2. Convert to 16kHz mono WAV (Whisper requirement)
//! 3. Run Whisper inference for transcription
//! 4. Return timestamped segments
//!
//! ## Future: Whisper Integration
//!
//! Currently uses a simulation that generates realistic placeholder
//! segments based on estimated audio duration. Full Whisper integration
//! requires the `whisper-rs` crate which needs a trained model file
//! bundled with the app (~75MB for base model).

use std::fs;
use std::path::Path;
use std::process::Command;

use serde::{Deserialize, Serialize};

/// A transcribed text segment with timing information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionSegment {
    /// Unique ID
    pub id: String,
    /// The transcribed text
    pub text: String,
    /// Start time in milliseconds
    pub start_ms: u64,
    /// End time in milliseconds
    pub end_ms: u64,
    /// Confidence score (0.0-1.0)
    pub confidence: f32,
    /// Word-level timestamps (populated when word_timestamps is enabled)
    #[serde(default)]
    pub words: Vec<TranscriptionWord>,
}

impl TranscriptionSegment {
    /// Create a new transcription segment
    pub fn new(text: &str, start_ms: u64, end_ms: u64, confidence: f32) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            text: text.to_string(),
            start_ms,
            end_ms,
            confidence: confidence.clamp(0.0, 1.0),
            words: Vec::new(),
        }
    }

    /// Create a new transcription segment with word-level timestamps
    pub fn with_words(
        text: &str,
        start_ms: u64,
        end_ms: u64,
        confidence: f32,
        words: Vec<TranscriptionWord>,
    ) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            text: text.to_string(),
            start_ms,
            end_ms,
            confidence: confidence.clamp(0.0, 1.0),
            words,
        }
    }

    /// Duration of this segment in milliseconds
    pub fn duration_ms(&self) -> u64 {
        self.end_ms.saturating_sub(self.start_ms)
    }

    /// Check if this segment overlaps with a time range
    pub fn overlaps(&self, start_ms: u64, end_ms: u64) -> bool {
        self.start_ms < end_ms && self.end_ms > start_ms
    }

    /// Format as SRT timestamp (HH:MM:SS,mmm)
    pub fn srt_timestamp(ms: u64) -> String {
        let hours = ms / 3_600_000;
        let minutes = (ms % 3_600_000) / 60_000;
        let seconds = (ms % 60_000) / 1_000;
        let millis = ms % 1_000;
        format!("{:02}:{:02}:{:02},{:03}", hours, minutes, seconds, millis)
    }

    /// Format as VTT timestamp (HH:MM:SS.mmm)
    pub fn vtt_timestamp(ms: u64) -> String {
        let hours = ms / 3_600_000;
        let minutes = (ms % 3_600_000) / 60_000;
        let seconds = (ms % 60_000) / 1_000;
        let millis = ms % 1_000;
        format!("{:02}:{:02}:{:02}.{:03}", hours, minutes, seconds, millis)
    }
}

/// Word-level timestamp for fine-grained transcription
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionWord {
    /// The word text
    pub word: String,
    /// Start time in milliseconds
    pub start_ms: u64,
    /// End time in milliseconds
    pub end_ms: u64,
    /// Confidence score (0.0-1.0)
    pub confidence: f32,
}

impl TranscriptionWord {
    /// Create a new word-level timestamp entry
    pub fn new(word: &str, start_ms: u64, end_ms: u64, confidence: f32) -> Self {
        Self {
            word: word.to_string(),
            start_ms,
            end_ms,
            confidence: confidence.clamp(0.0, 1.0),
        }
    }

    /// Duration of this word in milliseconds
    pub fn duration_ms(&self) -> u64 {
        self.end_ms.saturating_sub(self.start_ms)
    }
}

/// Full transcription result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionResult {
    /// All segments in order
    pub segments: Vec<TranscriptionSegment>,
    /// Full text (all segments joined)
    pub full_text: String,
    /// Detected language code (e.g., "en", "es", "zh")
    pub language: String,
    /// Total duration of the transcribed audio in ms
    pub duration_ms: u64,
}

impl TranscriptionResult {
    /// Create an empty transcription
    pub fn empty() -> Self {
        Self {
            segments: Vec::new(),
            full_text: String::new(),
            language: "und".to_string(),
            duration_ms: 0,
        }
    }

    /// Create from segments
    pub fn from_segments(
        segments: Vec<TranscriptionSegment>,
        language: &str,
        duration_ms: u64,
    ) -> Self {
        let full_text = segments
            .iter()
            .map(|s| s.text.as_str())
            .collect::<Vec<&str>>()
            .join(" ");

        Self {
            segments,
            full_text,
            language: language.to_string(),
            duration_ms,
        }
    }

    /// Get segments that overlap a time range
    pub fn segments_in_range(&self, start_ms: u64, end_ms: u64) -> Vec<&TranscriptionSegment> {
        self.segments
            .iter()
            .filter(|s| s.overlaps(start_ms, end_ms))
            .collect()
    }

    /// Export as SRT subtitle format
    pub fn to_srt(&self) -> String {
        let mut output = String::new();
        for (i, segment) in self.segments.iter().enumerate() {
            if i > 0 {
                output.push('\n');
            }
            output.push_str(&format!(
                "{}\n{} --> {}\n{}\n",
                i + 1,
                TranscriptionSegment::srt_timestamp(segment.start_ms),
                TranscriptionSegment::srt_timestamp(segment.end_ms),
                segment.text
            ));
        }
        output
    }

    /// Export as VTT subtitle format
    pub fn to_vtt(&self) -> String {
        let mut output = "WEBVTT\n\n".to_string();
        for (i, segment) in self.segments.iter().enumerate() {
            if i > 0 {
                output.push('\n');
            }
            output.push_str(&format!(
                "{}\n{} --> {}\n{}\n",
                i + 1,
                TranscriptionSegment::vtt_timestamp(segment.start_ms),
                TranscriptionSegment::vtt_timestamp(segment.end_ms),
                segment.text
            ));
        }
        output
    }

    /// Export as SRT subtitle format and write to a file
    pub fn export_srt(&self, output_path: &str) -> Result<(), String> {
        let content = self.to_srt();
        fs::write(output_path, content)
            .map_err(|e| format!("Failed to write SRT file '{}': {}", output_path, e))?;
        log::info!("Exported SRT to: {}", output_path);
        Ok(())
    }

    /// Export as VTT subtitle format and write to a file
    pub fn export_vtt(&self, output_path: &str) -> Result<(), String> {
        let content = self.to_vtt();
        fs::write(output_path, content)
            .map_err(|e| format!("Failed to write VTT file '{}': {}", output_path, e))?;
        log::info!("Exported VTT to: {}", output_path);
        Ok(())
    }

    /// Number of segments
    pub fn len(&self) -> usize {
        self.segments.len()
    }

    /// Whether there are any segments
    pub fn is_empty(&self) -> bool {
        self.segments.is_empty()
    }
}

/// Transcription configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionConfig {
    /// Language code (e.g., "en", "auto" for auto-detect)
    pub language: String,
    /// Model size: "tiny", "base", "small", "medium", "large"
    pub model_size: String,
    /// Whether to include word-level timestamps
    pub word_timestamps: bool,
    /// Maximum segment length in characters
    pub max_segment_length: usize,
}

impl Default for TranscriptionConfig {
    fn default() -> Self {
        Self {
            language: "auto".to_string(),
            model_size: "base".to_string(),
            word_timestamps: false,
            max_segment_length: 80,
        }
    }
}

/// Available Whisper model sizes
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TranscriptionModel {
    /// ~39M params — fastest, least accurate
    Tiny,
    /// ~74M params — good balance for mobile
    Base,
    /// ~244M params — higher accuracy
    Small,
    /// ~769M params — desktop-grade accuracy
    Medium,
    /// ~1550M params — best accuracy, slowest
    Large,
}

impl TranscriptionModel {
    /// Get the string identifier for this model
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Tiny => "tiny",
            Self::Base => "base",
            Self::Small => "small",
            Self::Medium => "medium",
            Self::Large => "large",
        }
    }

    /// Parse a model size string into a TranscriptionModel
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "tiny" => Some(Self::Tiny),
            "base" => Some(Self::Base),
            "small" => Some(Self::Small),
            "medium" => Some(Self::Medium),
            "large" => Some(Self::Large),
            _ => None,
        }
    }

    /// Estimated model file size in MB
    pub fn size_mb(&self) -> u64 {
        match self {
            Self::Tiny => 39,
            Self::Base => 74,
            Self::Small => 244,
            Self::Medium => 769,
            Self::Large => 1550,
        }
    }

    /// Relative speed factor (1.0 = base speed)
    pub fn speed_factor(&self) -> f32 {
        match self {
            Self::Tiny => 3.0,
            Self::Base => 2.0,
            Self::Small => 1.0,
            Self::Medium => 0.4,
            Self::Large => 0.2,
        }
    }
}

/// Current status of the transcription process
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TranscriptionStatus {
    /// Not currently transcribing
    Idle,
    /// Loading the Whisper model into memory
    LoadingModel,
    /// Extracting audio from the video file
    ExtractingAudio,
    /// Running Whisper inference
    Transcribing,
    /// Post-processing segments (splitting, word alignment)
    ProcessingSegments,
    /// Transcription complete
    Complete,
    /// An error occurred
    Error,
}

impl TranscriptionStatus {
    /// Human-readable label for this status
    pub fn label(&self) -> &'static str {
        match self {
            Self::Idle => "Idle",
            Self::LoadingModel => "Loading model…",
            Self::ExtractingAudio => "Extracting audio…",
            Self::Transcribing => "Transcribing…",
            Self::ProcessingSegments => "Processing segments…",
            Self::Complete => "Complete",
            Self::Error => "Error",
        }
    }

    /// Approximate progress range start for this phase
    pub fn progress_start(&self) -> f32 {
        match self {
            Self::Idle => 0.0,
            Self::LoadingModel => 0.0,
            Self::ExtractingAudio => 0.1,
            Self::Transcribing => 0.3,
            Self::ProcessingSegments => 0.85,
            Self::Complete => 1.0,
            Self::Error => 0.0,
        }
    }
}

/// Transcription engine that manages model loading and transcription state
pub struct TranscriptionEngine {
    /// Currently loaded model, if any
    loaded_model: Option<TranscriptionModel>,
    /// Current status
    status: TranscriptionStatus,
}

impl TranscriptionEngine {
    /// Create a new transcription engine
    pub fn new() -> Self {
        Self {
            loaded_model: None,
            status: TranscriptionStatus::Idle,
        }
    }

    /// Get the current transcription status
    pub fn status(&self) -> TranscriptionStatus {
        self.status
    }

    /// Get the currently loaded model, if any
    pub fn loaded_model(&self) -> Option<&TranscriptionModel> {
        self.loaded_model.as_ref()
    }

    /// Transcribe audio from a file
    ///
    /// When the whisper-rs crate is integrated, this will load the model
    /// and perform real inference. For now, it delegates to
    /// `simulate_transcription` for development/testing.
    pub fn transcribe(
        &mut self,
        audio_path: &str,
        config: &TranscriptionConfig,
        progress_callback: Option<&dyn Fn(f32, TranscriptionStatus)>,
    ) -> Result<TranscriptionResult, String> {
        // Validate audio file exists
        if !Path::new(audio_path).exists() {
            return Err(format!("Audio file not found: {}", audio_path));
        }

        // Parse the requested model size
        let model =
            TranscriptionModel::from_str(&config.model_size).unwrap_or(TranscriptionModel::Base);

        log::info!(
            "Transcription requested for: {} (language: {}, model: {})",
            audio_path,
            config.language,
            model.as_str()
        );

        // Use simulation for now — real Whisper integration will replace this
        self.simulate_transcription(audio_path, config, progress_callback)
    }

    /// Simulate realistic transcription for development/testing
    ///
    /// Reads the actual audio duration from the file using FFmpeg metadata
    /// and creates realistic-looking segments based on that duration.
    pub fn simulate_transcription(
        &mut self,
        audio_path: &str,
        config: &TranscriptionConfig,
        progress_callback: Option<&dyn Fn(f32, TranscriptionStatus)>,
    ) -> Result<TranscriptionResult, String> {
        let model =
            TranscriptionModel::from_str(&config.model_size).unwrap_or(TranscriptionModel::Base);

        // Phase 1: Loading model
        self.status = TranscriptionStatus::LoadingModel;
        if let Some(cb) = &progress_callback {
            cb(0.0, TranscriptionStatus::LoadingModel);
        }
        self.simulate_delay(100);
        if let Some(cb) = &progress_callback {
            cb(0.05, TranscriptionStatus::LoadingModel);
        }

        // Phase 2: Extracting audio
        self.status = TranscriptionStatus::ExtractingAudio;
        if let Some(cb) = &progress_callback {
            cb(0.1, TranscriptionStatus::ExtractingAudio);
        }

        // Read actual audio duration from FFmpeg metadata
        let duration_ms = self.get_audio_duration_ms(audio_path).unwrap_or(60_000);

        self.simulate_delay(50);
        if let Some(cb) = &progress_callback {
            cb(0.25, TranscriptionStatus::ExtractingAudio);
        }

        // Phase 3: Transcribing
        self.status = TranscriptionStatus::Transcribing;
        if let Some(cb) = &progress_callback {
            cb(0.3, TranscriptionStatus::Transcribing);
        }

        // Generate simulated segments based on duration
        let segments = self.generate_simulated_segments(duration_ms, &model, config);

        // Report progress during "transcription"
        let total_segments = segments.len();
        for (i, _) in segments.iter().enumerate() {
            if i % 3 == 0 {
                let progress = 0.3 + (0.55 * (i as f32 / total_segments.max(1) as f32));
                if let Some(cb) = &progress_callback {
                    cb(progress, TranscriptionStatus::Transcribing);
                }
            }
        }

        // Phase 4: Processing segments
        self.status = TranscriptionStatus::ProcessingSegments;
        if let Some(cb) = &progress_callback {
            cb(0.85, TranscriptionStatus::ProcessingSegments);
        }
        self.simulate_delay(50);

        if let Some(cb) = &progress_callback {
            cb(0.95, TranscriptionStatus::ProcessingSegments);
        }

        // Determine language
        let language = if config.language == "auto" {
            "en".to_string() // Simulation always "detects" English
        } else {
            config.language.clone()
        };

        let result = TranscriptionResult::from_segments(segments, &language, duration_ms);

        // Phase 5: Complete
        self.status = TranscriptionStatus::Complete;
        self.loaded_model = Some(model);
        if let Some(cb) = &progress_callback {
            cb(1.0, TranscriptionStatus::Complete);
        }

        log::info!(
            "Simulated transcription complete: {} segments, {}ms duration",
            result.len(),
            duration_ms
        );

        Ok(result)
    }

    /// Get audio duration in milliseconds using FFprobe
    fn get_audio_duration_ms(&self, audio_path: &str) -> Result<u64, String> {
        let output = Command::new("ffprobe")
            .args([
                "-v",
                "quiet",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                audio_path,
            ])
            .output()
            .map_err(|e| format!("Failed to run ffprobe: {}", e))?;

        if !output.status.success() {
            return Err("ffprobe failed to get audio duration".to_string());
        }

        let duration_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let duration_secs: f64 = duration_str
            .parse()
            .map_err(|e| format!("Failed to parse duration '{}': {}", duration_str, e))?;

        Ok((duration_secs * 1000.0) as u64)
    }

    /// Generate simulated transcription segments based on audio duration
    fn generate_simulated_segments(
        &self,
        duration_ms: u64,
        model: &TranscriptionModel,
        config: &TranscriptionConfig,
    ) -> Vec<TranscriptionSegment> {
        // Average segment duration: 3-6 seconds depending on model quality
        let base_segment_ms: u64 = match model {
            TranscriptionModel::Tiny => 5000,
            TranscriptionModel::Base => 4500,
            TranscriptionModel::Small => 4000,
            TranscriptionModel::Medium => 3500,
            TranscriptionModel::Large => 3000,
        };

        let num_segments = ((duration_ms as f64 / base_segment_ms as f64).ceil() as usize).max(1);
        let segment_ms = duration_ms / num_segments.max(1) as u64;

        // Sample phrases for simulation
        let phrases = [
            "Welcome to this video presentation",
            "Today we're going to explore an important topic",
            "Let's start by looking at the key concepts",
            "This is a fundamental principle to understand",
            "Moving on to the next section",
            "Here we can see the main idea in action",
            "Let's examine this more closely",
            "The results speak for themselves",
            "As you can see from the data",
            "This brings us to an important conclusion",
            "Now let's consider the implications",
            "There are several factors to consider here",
            "The first point to note is this",
            "Looking at it from another perspective",
            "This is particularly relevant when",
            "Let me illustrate with an example",
            "That brings us to the end of this section",
            "To summarize what we've covered so far",
            "In the next part we'll dive deeper",
            "Thank you for watching",
            "The key takeaway from this is",
            "Let's break this down step by step",
            "One important thing to remember",
            "This approach has several advantages",
            "Consider the following scenario",
            "What makes this interesting is",
            "Let's move forward and discuss",
            "A critical aspect of this topic",
            "Building on what we just learned",
            "This connects directly to our next point",
        ];

        let mut segments = Vec::with_capacity(num_segments);
        let mut current_ms: u64 = 0;

        for i in 0..num_segments {
            let start_ms = current_ms;
            let end_ms = (current_ms + segment_ms).min(duration_ms);

            // Pick a phrase (cycle through available phrases)
            let phrase = phrases[i % phrases.len()];

            // Simulate confidence: higher quality models → higher confidence
            let base_confidence = match model {
                TranscriptionModel::Tiny => 0.70,
                TranscriptionModel::Base => 0.80,
                TranscriptionModel::Small => 0.87,
                TranscriptionModel::Medium => 0.92,
                TranscriptionModel::Large => 0.96,
            };
            // Add slight random-ish variation based on index
            let confidence =
                (base_confidence + (((i * 7 + 3) % 11) as f32 / 110.0) - 0.05).clamp(0.3, 1.0);

            // Generate word-level timestamps if enabled
            let words = if config.word_timestamps {
                self.split_into_words(phrase, start_ms, end_ms, confidence)
            } else {
                Vec::new()
            };

            let mut segment = if config.word_timestamps {
                TranscriptionSegment::with_words(phrase, start_ms, end_ms, confidence, words)
            } else {
                TranscriptionSegment::new(phrase, start_ms, end_ms, confidence)
            };

            // Truncate text to max_segment_length if needed
            if segment.text.len() > config.max_segment_length {
                segment.text.truncate(config.max_segment_length);
                if let Some(last_space) = segment.text.rfind(' ') {
                    segment.text.truncate(last_space);
                }
                segment.text.push('…');
            }

            segments.push(segment);
            current_ms = end_ms;
        }

        segments
    }

    /// Split a phrase into word-level timestamps
    fn split_into_words(
        &self,
        phrase: &str,
        start_ms: u64,
        end_ms: u64,
        segment_confidence: f32,
    ) -> Vec<TranscriptionWord> {
        let words: Vec<&str> = phrase.split_whitespace().collect();
        if words.is_empty() {
            return Vec::new();
        }

        let total_duration = end_ms.saturating_sub(start_ms);
        let per_word_ms = total_duration / words.len() as u64;

        words
            .iter()
            .enumerate()
            .map(|(i, word)| {
                let word_start = start_ms + (i as u64) * per_word_ms;
                let word_end = word_start + per_word_ms;
                // Word confidence varies slightly from segment confidence
                let word_conf =
                    (segment_confidence + (((i * 3 + 1) % 7) as f32 / 70.0) - 0.05).clamp(0.2, 1.0);
                TranscriptionWord::new(word, word_start, word_end, word_conf)
            })
            .collect()
    }

    /// Simulate a small delay (for realistic progress reporting in simulation)
    fn simulate_delay(&self, _millis: u64) {
        // In a real implementation, this would be actual work.
        // For simulation, we skip the actual delay in tests.
        #[cfg(not(test))]
        {
            std::thread::sleep(std::time::Duration::from_millis(_millis.min(10)));
        }
    }
}

impl Default for TranscriptionEngine {
    fn default() -> Self {
        Self::new()
    }
}

/// Transcribe audio from a video file
///
/// This is a convenience function that creates a TranscriptionEngine
/// and runs transcription. For more control (e.g., reusing a loaded
/// model), use `TranscriptionEngine::transcribe` directly.
///
/// Currently uses simulation mode. Full implementation requires
/// whisper-rs integration.
pub fn transcribe_audio(
    audio_path: &str,
    config: &TranscriptionConfig,
    progress_callback: Option<Box<dyn Fn(f32) + Send>>,
) -> Result<TranscriptionResult, String> {
    log::info!(
        "Transcription requested for: {} (language: {}, model: {}) [simulation]",
        audio_path,
        config.language,
        config.model_size
    );

    // Validate audio file exists
    if !Path::new(audio_path).exists() {
        // For the bridge API which may pass asset IDs rather than real paths,
        // we still run simulation but warn
        log::warn!(
            "Audio file not found at '{}', running simulation with default duration",
            audio_path
        );
    }

    let mut engine = TranscriptionEngine::new();

    // Adapt the simple progress callback to the engine's richer callback
    let result = engine.simulate_transcription(
        audio_path,
        config,
        Some(&|progress, _status| {
            if let Some(ref cb) = progress_callback {
                cb(progress);
            }
        }),
    )?;

    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn test_transcription_segment_new() {
        let seg = TranscriptionSegment::new("Hello world", 1000, 3000, 0.95);
        assert_eq!(seg.text, "Hello world");
        assert_eq!(seg.start_ms, 1000);
        assert_eq!(seg.end_ms, 3000);
        assert!((seg.confidence - 0.95).abs() < 0.001);
        assert!(seg.words.is_empty());
    }

    #[test]
    fn test_transcription_segment_with_words() {
        let words = vec![
            TranscriptionWord::new("Hello", 1000, 1500, 0.96),
            TranscriptionWord::new("world", 1500, 3000, 0.93),
        ];
        let seg = TranscriptionSegment::with_words("Hello world", 1000, 3000, 0.95, words);
        assert_eq!(seg.text, "Hello world");
        assert_eq!(seg.words.len(), 2);
        assert_eq!(seg.words[0].word, "Hello");
        assert_eq!(seg.words[1].word, "world");
    }

    #[test]
    fn test_transcription_segment_duration() {
        let seg = TranscriptionSegment::new("Test", 1000, 3000, 0.9);
        assert_eq!(seg.duration_ms(), 2000);
    }

    #[test]
    fn test_transcription_segment_overlaps() {
        let seg = TranscriptionSegment::new("Test", 1000, 3000, 0.9);
        assert!(seg.overlaps(0, 2000)); // starts before segment
        assert!(seg.overlaps(2000, 4000)); // overlaps in middle
        assert!(seg.overlaps(1500, 2500)); // fully contained
        assert!(!seg.overlaps(0, 500)); // before segment
        assert!(!seg.overlaps(4000, 5000)); // after segment
    }

    #[test]
    fn test_srt_timestamp() {
        assert_eq!(TranscriptionSegment::srt_timestamp(0), "00:00:00,000");
        assert_eq!(TranscriptionSegment::srt_timestamp(3661500), "01:01:01,500");
        assert_eq!(
            TranscriptionSegment::srt_timestamp(7_384_567),
            "02:03:04,567"
        );
    }

    #[test]
    fn test_vtt_timestamp() {
        assert_eq!(TranscriptionSegment::vtt_timestamp(0), "00:00:00.000");
        assert_eq!(TranscriptionSegment::vtt_timestamp(3661500), "01:01:01.500");
    }

    #[test]
    fn test_transcription_word_new() {
        let word = TranscriptionWord::new("hello", 1000, 1500, 0.95);
        assert_eq!(word.word, "hello");
        assert_eq!(word.start_ms, 1000);
        assert_eq!(word.end_ms, 1500);
        assert!((word.confidence - 0.95).abs() < 0.001);
    }

    #[test]
    fn test_transcription_word_duration() {
        let word = TranscriptionWord::new("test", 2000, 3500, 0.9);
        assert_eq!(word.duration_ms(), 1500);
    }

    #[test]
    fn test_transcription_word_confidence_clamped() {
        let word = TranscriptionWord::new("test", 0, 100, 1.5);
        assert!((word.confidence - 1.0).abs() < 0.001);
        let word2 = TranscriptionWord::new("test", 0, 100, -0.5);
        assert!((word2.confidence - 0.0).abs() < 0.001);
    }

    #[test]
    fn test_transcription_result_empty() {
        let result = TranscriptionResult::empty();
        assert!(result.is_empty());
        assert_eq!(result.len(), 0);
        assert_eq!(result.full_text, "");
        assert_eq!(result.language, "und");
    }

    #[test]
    fn test_transcription_result_from_segments() {
        let segments = vec![
            TranscriptionSegment::new("Hello", 0, 1000, 0.9),
            TranscriptionSegment::new("World", 1000, 2000, 0.85),
        ];
        let result = TranscriptionResult::from_segments(segments, "en", 2000);
        assert_eq!(result.len(), 2);
        assert_eq!(result.full_text, "Hello World");
        assert_eq!(result.language, "en");
        assert_eq!(result.duration_ms, 2000);
    }

    #[test]
    fn test_transcription_result_segments_in_range() {
        let segments = vec![
            TranscriptionSegment::new("First", 0, 1000, 0.9),
            TranscriptionSegment::new("Second", 1000, 2000, 0.85),
            TranscriptionSegment::new("Third", 2000, 3000, 0.88),
        ];
        let result = TranscriptionResult::from_segments(segments, "en", 3000);
        let in_range = result.segments_in_range(500, 2500);
        assert_eq!(in_range.len(), 3);
    }

    #[test]
    fn test_transcription_result_to_srt() {
        let segments = vec![
            TranscriptionSegment::new("Hello world", 0, 2000, 0.9),
            TranscriptionSegment::new("Goodbye", 2000, 4000, 0.85),
        ];
        let result = TranscriptionResult::from_segments(segments, "en", 4000);
        let srt = result.to_srt();

        assert!(srt.contains("1\n"));
        assert!(srt.contains("00:00:00,000 --> 00:00:02,000"));
        assert!(srt.contains("Hello world"));
        assert!(srt.contains("2\n"));
        assert!(srt.contains("00:00:02,000 --> 00:00:04,000"));
        assert!(srt.contains("Goodbye"));
    }

    #[test]
    fn test_transcription_result_to_vtt() {
        let segments = vec![TranscriptionSegment::new("Hello world", 0, 2000, 0.9)];
        let result = TranscriptionResult::from_segments(segments, "en", 2000);
        let vtt = result.to_vtt();

        assert!(vtt.starts_with("WEBVTT\n\n"));
        assert!(vtt.contains("00:00:00.000 --> 00:00:02.000"));
        assert!(vtt.contains("Hello world"));
    }

    #[test]
    fn test_transcription_result_export_srt() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.srt");
        let path_str = path.to_str().unwrap();

        let segments = vec![TranscriptionSegment::new("Test export", 0, 1000, 0.9)];
        let result = TranscriptionResult::from_segments(segments, "en", 1000);

        result.export_srt(path_str).unwrap();
        let content = fs::read_to_string(path).unwrap();
        assert!(content.contains("Test export"));
        assert!(content.contains("00:00:00,000 --> 00:00:01,000"));
    }

    #[test]
    fn test_transcription_result_export_vtt() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.vtt");
        let path_str = path.to_str().unwrap();

        let segments = vec![TranscriptionSegment::new("Test export", 0, 1000, 0.9)];
        let result = TranscriptionResult::from_segments(segments, "en", 1000);

        result.export_vtt(path_str).unwrap();
        let content = fs::read_to_string(path).unwrap();
        assert!(content.starts_with("WEBVTT"));
        assert!(content.contains("Test export"));
    }

    #[test]
    fn test_transcription_config_default() {
        let config = TranscriptionConfig::default();
        assert_eq!(config.language, "auto");
        assert_eq!(config.model_size, "base");
        assert!(!config.word_timestamps);
        assert_eq!(config.max_segment_length, 80);
    }

    #[test]
    fn test_transcription_model_from_str() {
        assert_eq!(
            TranscriptionModel::from_str("tiny"),
            Some(TranscriptionModel::Tiny)
        );
        assert_eq!(
            TranscriptionModel::from_str("base"),
            Some(TranscriptionModel::Base)
        );
        assert_eq!(
            TranscriptionModel::from_str("small"),
            Some(TranscriptionModel::Small)
        );
        assert_eq!(
            TranscriptionModel::from_str("medium"),
            Some(TranscriptionModel::Medium)
        );
        assert_eq!(
            TranscriptionModel::from_str("large"),
            Some(TranscriptionModel::Large)
        );
        assert_eq!(TranscriptionModel::from_str("unknown"), None);
        assert_eq!(
            TranscriptionModel::from_str("TINY"),
            Some(TranscriptionModel::Tiny)
        );
    }

    #[test]
    fn test_transcription_model_as_str() {
        assert_eq!(TranscriptionModel::Tiny.as_str(), "tiny");
        assert_eq!(TranscriptionModel::Base.as_str(), "base");
        assert_eq!(TranscriptionModel::Small.as_str(), "small");
        assert_eq!(TranscriptionModel::Medium.as_str(), "medium");
        assert_eq!(TranscriptionModel::Large.as_str(), "large");
    }

    #[test]
    fn test_transcription_model_size_mb() {
        assert_eq!(TranscriptionModel::Tiny.size_mb(), 39);
        assert_eq!(TranscriptionModel::Base.size_mb(), 74);
        assert_eq!(TranscriptionModel::Small.size_mb(), 244);
        assert_eq!(TranscriptionModel::Medium.size_mb(), 769);
        assert_eq!(TranscriptionModel::Large.size_mb(), 1550);
    }

    #[test]
    fn test_transcription_model_speed_factor() {
        assert!(TranscriptionModel::Tiny.speed_factor() > TranscriptionModel::Base.speed_factor());
        assert!(TranscriptionModel::Base.speed_factor() > TranscriptionModel::Small.speed_factor());
    }

    #[test]
    fn test_transcription_status_label() {
        assert_eq!(TranscriptionStatus::Idle.label(), "Idle");
        assert_eq!(TranscriptionStatus::LoadingModel.label(), "Loading model…");
        assert_eq!(
            TranscriptionStatus::ExtractingAudio.label(),
            "Extracting audio…"
        );
        assert_eq!(TranscriptionStatus::Transcribing.label(), "Transcribing…");
        assert_eq!(
            TranscriptionStatus::ProcessingSegments.label(),
            "Processing segments…"
        );
        assert_eq!(TranscriptionStatus::Complete.label(), "Complete");
        assert_eq!(TranscriptionStatus::Error.label(), "Error");
    }

    #[test]
    fn test_transcription_status_progress_start() {
        assert_eq!(TranscriptionStatus::LoadingModel.progress_start(), 0.0);
        assert!(TranscriptionStatus::ExtractingAudio.progress_start() > 0.0);
        assert!(
            TranscriptionStatus::Transcribing.progress_start()
                > TranscriptionStatus::ExtractingAudio.progress_start()
        );
        assert_eq!(TranscriptionStatus::Complete.progress_start(), 1.0);
    }

    #[test]
    fn test_transcription_engine_new() {
        let engine = TranscriptionEngine::new();
        assert_eq!(engine.status(), TranscriptionStatus::Idle);
        assert!(engine.loaded_model().is_none());
    }

    #[test]
    fn test_transcription_engine_default() {
        let engine = TranscriptionEngine::default();
        assert_eq!(engine.status(), TranscriptionStatus::Idle);
    }

    #[test]
    fn test_transcription_engine_simulate() {
        let mut engine = TranscriptionEngine::new();
        let config = TranscriptionConfig::default();

        // Create a dummy file for the path check to not fail early
        let dir = tempfile::tempdir().unwrap();
        let dummy_path = dir.path().join("audio.wav");
        let mut f = fs::File::create(&dummy_path).unwrap();
        f.write_all(b"dummy audio data").unwrap();

        let progress_values = std::sync::Mutex::new(Vec::<(f32, TranscriptionStatus)>::new());
        let result = engine
            .simulate_transcription(
                dummy_path.to_str().unwrap(),
                &config,
                Some(&|progress, status| {
                    progress_values.lock().unwrap().push((progress, status));
                }),
            )
            .unwrap();

        // Should have generated segments
        assert!(!result.is_empty());
        assert_eq!(engine.status(), TranscriptionStatus::Complete);
        assert!(engine.loaded_model().is_some());

        let progress_values = progress_values.lock().unwrap();
        // Progress should have been reported
        assert!(!progress_values.is_empty());

        // First progress should be near 0
        assert!(progress_values.first().unwrap().0 < 0.1);

        // Last progress should be 1.0
        assert!((progress_values.last().unwrap().0 - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_transcription_engine_simulate_with_words() {
        let mut engine = TranscriptionEngine::new();
        let config = TranscriptionConfig {
            word_timestamps: true,
            ..Default::default()
        };

        let dir = tempfile::tempdir().unwrap();
        let dummy_path = dir.path().join("audio.wav");
        fs::File::create(&dummy_path).unwrap();

        let result = engine
            .simulate_transcription(dummy_path.to_str().unwrap(), &config, None)
            .unwrap();

        // Segments should have word-level timestamps
        assert!(!result.is_empty());
        for seg in &result.segments {
            assert!(!seg.words.is_empty());
        }
    }

    #[test]
    fn test_transcription_engine_simulate_tiny_model() {
        let mut engine = TranscriptionEngine::new();
        let config = TranscriptionConfig {
            model_size: "tiny".to_string(),
            ..Default::default()
        };

        let dir = tempfile::tempdir().unwrap();
        let dummy_path = dir.path().join("audio.wav");
        fs::File::create(&dummy_path).unwrap();

        let result = engine
            .simulate_transcription(dummy_path.to_str().unwrap(), &config, None)
            .unwrap();

        assert!(!result.is_empty());
        assert_eq!(engine.loaded_model().unwrap(), &TranscriptionModel::Tiny);
    }

    #[test]
    fn test_transcribe_audio_placeholder() {
        let config = TranscriptionConfig::default();
        let result = transcribe_audio("/path/to/nonexistent/audio.wav", &config, None).unwrap();
        // With a nonexistent file, simulation still runs with default duration
        assert!(!result.is_empty());
    }

    #[test]
    fn test_transcribe_audio_with_progress() {
        let config = TranscriptionConfig::default();
        let progress_values = std::sync::Arc::new(std::sync::Mutex::new(Vec::<f32>::new()));
        let callback_values = progress_values.clone();
        let result = transcribe_audio(
            "/path/to/audio.wav",
            &config,
            Some(Box::new(move |p| callback_values.lock().unwrap().push(p))),
        )
        .unwrap();
        assert!(!result.is_empty());
        assert!(!progress_values.lock().unwrap().is_empty());
    }

    #[test]
    fn test_transcription_segment_serialization() {
        let seg = TranscriptionSegment::new("Hello world", 1000, 3000, 0.95);
        let json = serde_json::to_string(&seg).expect("Failed to serialize");
        let deserialized: TranscriptionSegment =
            serde_json::from_str(&json).expect("Failed to deserialize");
        assert_eq!(deserialized.text, "Hello world");
        assert_eq!(deserialized.start_ms, 1000);
        assert_eq!(deserialized.end_ms, 3000);
    }

    #[test]
    fn test_transcription_segment_with_words_serialization() {
        let words = vec![
            TranscriptionWord::new("Hello", 1000, 1500, 0.96),
            TranscriptionWord::new("world", 1500, 3000, 0.93),
        ];
        let seg = TranscriptionSegment::with_words("Hello world", 1000, 3000, 0.95, words);
        let json = serde_json::to_string(&seg).expect("Failed to serialize");
        let deserialized: TranscriptionSegment =
            serde_json::from_str(&json).expect("Failed to deserialize");
        assert_eq!(deserialized.words.len(), 2);
        assert_eq!(deserialized.words[0].word, "Hello");
    }

    #[test]
    fn test_transcription_result_serialization() {
        let result = TranscriptionResult::from_segments(
            vec![TranscriptionSegment::new("Test", 0, 1000, 0.9)],
            "en",
            1000,
        );
        let json = serde_json::to_string(&result).expect("Failed to serialize");
        let deserialized: TranscriptionResult =
            serde_json::from_str(&json).expect("Failed to deserialize");
        assert_eq!(deserialized.len(), 1);
        assert_eq!(deserialized.language, "en");
    }

    #[test]
    fn test_transcription_word_serialization() {
        let word = TranscriptionWord::new("test", 100, 500, 0.88);
        let json = serde_json::to_string(&word).expect("Failed to serialize");
        let deserialized: TranscriptionWord =
            serde_json::from_str(&json).expect("Failed to deserialize");
        assert_eq!(deserialized.word, "test");
        assert_eq!(deserialized.start_ms, 100);
        assert!((deserialized.confidence - 0.88).abs() < 0.001);
    }

    #[test]
    fn test_transcription_model_serialization() {
        let model = TranscriptionModel::Base;
        let json = serde_json::to_string(&model).expect("Failed to serialize");
        let deserialized: TranscriptionModel =
            serde_json::from_str(&json).expect("Failed to deserialize");
        assert_eq!(deserialized, TranscriptionModel::Base);
    }

    #[test]
    fn test_transcription_status_serialization() {
        let status = TranscriptionStatus::Transcribing;
        let json = serde_json::to_string(&status).expect("Failed to serialize");
        let deserialized: TranscriptionStatus =
            serde_json::from_str(&json).expect("Failed to deserialize");
        assert_eq!(deserialized, TranscriptionStatus::Transcribing);
    }

    #[test]
    fn test_max_segment_length_truncation() {
        let mut engine = TranscriptionEngine::new();
        let config = TranscriptionConfig {
            max_segment_length: 20,
            ..Default::default()
        };

        let dir = tempfile::tempdir().unwrap();
        let dummy_path = dir.path().join("audio.wav");
        fs::File::create(&dummy_path).unwrap();

        let result = engine
            .simulate_transcription(dummy_path.to_str().unwrap(), &config, None)
            .unwrap();

        // All segment texts should be at most ~20 chars + ellipsis
        for seg in &result.segments {
            // The truncation adds "…" so max length is max_segment_length + 1
            assert!(
                seg.text.len() <= config.max_segment_length + 1,
                "Segment text too long: '{}' ({} chars)",
                seg.text,
                seg.text.len()
            );
        }
    }
}
