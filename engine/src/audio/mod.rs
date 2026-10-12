//! Audio module - Audio processing, decoding, and mixing
//!
//! Handles audio decoding from media files, multi-track mixing,
//! waveform visualization data generation, audio ducking, and
//! audio transcription for auto-captions.

pub mod decoder;
pub mod ducking;
pub mod effects;
pub mod mixer;
pub mod transcription;
pub mod waveform;

#[cfg(test)]
mod waveform_tests;
