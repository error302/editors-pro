//! Audio decoder using FFmpeg
//!
//! Decodes audio streams from media files into PCM float32 samples
//! for playback and processing. Supports resampling to a target
//! sample rate and channel layout.

#[cfg(feature = "ffmpeg")]
use ffmpeg_next as ff;

/// Decoded audio data in interleaved f32 format
#[derive(Debug, Clone)]
pub struct DecodedAudio {
    /// Interleaved PCM samples (stereo: L R L R ...)
    pub samples: Vec<f32>,
    /// Sample rate of the decoded audio
    pub sample_rate: u32,
    /// Number of audio channels (1 = mono, 2 = stereo)
    pub channels: u32,
    /// Duration of the audio in milliseconds
    pub duration_ms: u64,
}

impl DecodedAudio {
    /// Create an empty audio buffer
    pub fn empty(sample_rate: u32, channels: u32) -> Self {
        Self {
            samples: Vec::new(),
            sample_rate,
            channels,
            duration_ms: 0,
        }
    }

    /// Create a silent audio buffer of a given duration
    pub fn silence(sample_rate: u32, channels: u32, duration_ms: u64) -> Self {
        let sample_count =
            (sample_rate as f64 * channels as f64 * duration_ms as f64 / 1000.0) as usize;
        Self {
            samples: vec![0.0f32; sample_count],
            sample_rate,
            channels,
            duration_ms,
        }
    }

    /// Get the number of audio frames (samples per channel)
    pub fn frame_count(&self) -> usize {
        if self.channels == 0 {
            0
        } else {
            self.samples.len() / self.channels as usize
        }
    }

    /// Get a segment of the audio between start_ms and end_ms
    pub fn segment(&self, start_ms: u64, end_ms: u64) -> Self {
        if self.samples.is_empty() || self.sample_rate == 0 {
            return Self::empty(self.sample_rate, self.channels);
        }

        let start_sample =
            (start_ms as f64 * self.sample_rate as f64 * self.channels as f64 / 1000.0) as usize;
        let end_sample =
            (end_ms as f64 * self.sample_rate as f64 * self.channels as f64 / 1000.0) as usize;

        let start = start_sample.min(self.samples.len());
        let end = end_sample.min(self.samples.len());

        let segment_duration = if end > start {
            ((end - start) as f64 * 1000.0 / (self.sample_rate as f64 * self.channels as f64))
                as u64
        } else {
            0
        };

        Self {
            samples: self.samples[start..end].to_vec(),
            sample_rate: self.sample_rate,
            channels: self.channels,
            duration_ms: segment_duration,
        }
    }

    /// Convert mono to stereo by duplicating the channel
    pub fn to_stereo(&self) -> Self {
        if self.channels == 2 {
            return self.clone();
        }

        let mut stereo = Vec::with_capacity(self.samples.len() * 2);
        for &sample in &self.samples {
            stereo.push(sample); // Left
            stereo.push(sample); // Right
        }

        Self {
            samples: stereo,
            sample_rate: self.sample_rate,
            channels: 2,
            duration_ms: self.duration_ms,
        }
    }
}

/// Audio decoder that reads audio from media files using FFmpeg
#[cfg(feature = "ffmpeg")]
pub struct AudioDecoder {
    /// Whether the decoder has an open file
    is_open: bool,
    /// The file path currently being decoded
    file_path: Option<String>,
    /// Sample rate of the source audio
    source_sample_rate: u32,
    /// Number of channels in the source audio
    source_channels: u32,
    /// Duration of the audio stream in milliseconds
    duration_ms: u64,
    /// Codec name of the audio stream
    codec_name: String,
}

#[cfg(feature = "ffmpeg")]
impl AudioDecoder {
    /// Create a new audio decoder
    pub fn new() -> Self {
        Self {
            is_open: false,
            file_path: None,
            source_sample_rate: 44100,
            source_channels: 2,
            duration_ms: 0,
            codec_name: String::new(),
        }
    }

    /// Open a media file and read audio stream information
    pub fn open(&mut self, file_path: &str) -> Result<(), String> {
        self.close();

        let input = ff::format::input(&file_path)
            .map_err(|e| format!("Failed to open file '{}': {}", file_path, e))?;

        // Find the best audio stream
        let audio_stream = input
            .streams()
            .best(ff::media::Type::Audio)
            .ok_or_else(|| format!("No audio stream found in '{}'", file_path))?;

        let context = ff::codec::context::Context::from_parameters(audio_stream.parameters())
            .map_err(|e| format!("Failed to create codec context: {}", e))?;

        let codec = context
            .decoder()
            .audio()
            .map_err(|e| format!("Failed to get audio decoder: {}", e))?;

        self.source_sample_rate = codec.rate();
        self.source_channels = codec.channels() as u32;
        self.codec_name = codec
            .codec()
            .map(|c| c.name().to_string())
            .unwrap_or_default();

        // Calculate duration
        if audio_stream.duration() > 0 {
            self.duration_ms = (audio_stream.duration() as f64
                * 1000.0
                * f64::from(audio_stream.time_base())) as u64;
        } else {
            // Fallback: estimate from format duration.
            // Phase A fix: guard against AV_NOPTS_VALUE (INT64_MIN) which
            // would overflow on `as u64` + `* 1000`.
            const AV_NOPTS_VALUE: i64 = i64::MIN;
            let container_duration = input.duration();
            self.duration_ms = if container_duration > 0 && container_duration != AV_NOPTS_VALUE {
                (container_duration as u64)
                    .saturating_mul(1000)
                    .checked_div(ff::sys::AV_TIME_BASE as u64)
                    .unwrap_or(0)
            } else {
                0
            };
        }

        self.file_path = Some(file_path.to_string());
        self.is_open = true;

        log::info!(
            "AudioDecoder opened: {} ({}Hz, {}ch, {}ms, codec={})",
            file_path,
            self.source_sample_rate,
            self.source_channels,
            self.duration_ms,
            self.codec_name
        );

        Ok(())
    }

    /// Close the currently open file
    pub fn close(&mut self) {
        self.is_open = false;
        self.file_path = None;
        self.source_sample_rate = 44100;
        self.source_channels = 2;
        self.duration_ms = 0;
        self.codec_name = String::new();
    }

    /// Check if a file is currently open
    pub fn is_open(&self) -> bool {
        self.is_open
    }

    /// Get audio information for the currently open file
    pub fn audio_info(&self) -> AudioInfo {
        AudioInfo {
            sample_rate: self.source_sample_rate,
            channels: self.source_channels,
            duration_ms: self.duration_ms,
            codec_name: self.codec_name.clone(),
        }
    }

    /// Decode the entire audio stream from the open file
    ///
    /// Returns the audio as interleaved f32 samples at the source
    /// sample rate. For resampling to a different rate, use
    /// `decode_samples_with_rate()`.
    pub fn decode_all(
        &self,
        target_sample_rate: u32,
        target_channels: u32,
    ) -> Result<DecodedAudio, String> {
        let file_path = self.file_path.as_ref().ok_or("No file is open")?;

        let mut input =
            ff::format::input(file_path).map_err(|e| format!("Failed to open file: {}", e))?;

        let audio_stream = input
            .streams()
            .best(ff::media::Type::Audio)
            .ok_or("No audio stream found")?;

        let stream_index = audio_stream.index();

        let context = ff::codec::context::Context::from_parameters(audio_stream.parameters())
            .map_err(|e| format!("Failed to create codec context: {}", e))?;

        let mut decoder = context
            .decoder()
            .audio()
            .map_err(|e| format!("Failed to get audio decoder: {}", e))?;

        // Set up resampler if needed
        let needs_resample = decoder.rate() != target_sample_rate
            || decoder.channels() as u32 != target_channels
            || decoder.format() != ff::format::Sample::F32(ff::format::sample::Type::Packed);

        let mut resampler = if needs_resample {
            let in_rate = decoder.rate();
            let out_rate = target_sample_rate;
            let source_layout = decoder.channel_layout();
            let in_layout = if source_layout.is_empty() {
                ff::channel_layout::ChannelLayout::default(decoder.channels() as i32)
            } else {
                source_layout
            };
            let out_layout = ff::channel_layout::ChannelLayout::default(target_channels as i32);
            let in_format = decoder.format();
            let out_format = ff::format::Sample::F32(ff::format::sample::Type::Packed);

            Some(
                ff::software::resampling::context::Context::get(
                    in_format, in_layout, in_rate, out_format, out_layout, out_rate,
                )
                .map_err(|e| format!("Failed to create resampler: {}", e))?,
            )
        } else {
            None
        };

        let mut all_samples: Vec<f32> = Vec::new();
        let mut frames_decoded = 0u64;

        // Decode packets
        let mut receive_and_send =
            |decoder: &mut ff::decoder::Audio,
             resampler: &mut Option<ff::software::resampling::context::Context>|
             -> Result<(), String> {
                // Send packet already done outside
                let mut frame = ff::util::frame::Audio::empty();

                loop {
                    match decoder.receive_frame(&mut frame) {
                        Ok(()) => {
                            frames_decoded += 1;

                            if let Some(r) = resampler {
                                let mut resampled = ff::util::frame::Audio::empty();
                                r.run(&frame, &mut resampled)
                                    .map_err(|e| format!("Resampling failed: {}", e))?;

                                let data = resampled.data(0);
                                let sample_count = data.len() / 4; // f32 = 4 bytes
                                let samples = unsafe {
                                    std::slice::from_raw_parts(
                                        data.as_ptr() as *const f32,
                                        sample_count,
                                    )
                                };
                                all_samples.extend_from_slice(samples);
                            } else {
                                // Direct f32 packed data
                                let data = frame.data(0);
                                let sample_count = data.len() / 4;
                                let samples = unsafe {
                                    std::slice::from_raw_parts(
                                        data.as_ptr() as *const f32,
                                        sample_count,
                                    )
                                };
                                all_samples.extend_from_slice(samples);
                            }

                            frame = ff::util::frame::Audio::empty();
                        }
                        Err(ff::Error::Other {
                            errno: ff::sys::EAGAIN,
                        }) => {
                            // Need more input
                            break;
                        }
                        Err(ff::Error::Eof) => {
                            // Flush resampler
                            if let Some(r) = resampler {
                                let mut resampled = ff::util::frame::Audio::empty();
                                r.flush(&mut resampled)
                                    .map_err(|e| format!("Resampler flush failed: {}", e))?;
                                let data = resampled.data(0);
                                let sample_count = data.len() / 4;
                                let samples = unsafe {
                                    std::slice::from_raw_parts(
                                        data.as_ptr() as *const f32,
                                        sample_count,
                                    )
                                };
                                all_samples.extend_from_slice(samples);
                            }
                            break;
                        }
                        Err(e) => {
                            log::warn!("Audio decode error: {}", e);
                            break;
                        }
                    }
                }

                Ok(())
            };

        // Process all packets from the audio stream
        for (stream, packet) in input.packets() {
            if stream.index() == stream_index {
                decoder
                    .send_packet(&packet)
                    .map_err(|e| format!("Failed to send packet: {}", e))?;
                receive_and_send(&mut decoder, &mut resampler)?;
            }
        }

        // Flush decoder
        decoder
            .send_eof()
            .map_err(|e| format!("Failed to send EOF: {}", e))?;
        receive_and_send(&mut decoder, &mut resampler)?;

        let duration_ms = if target_sample_rate > 0 && target_channels > 0 {
            (all_samples.len() as f64 * 1000.0
                / (target_sample_rate as f64 * target_channels as f64)) as u64
        } else {
            0
        };

        log::info!(
            "Decoded {} frames, {} samples ({}ms at {}Hz/{})",
            frames_decoded,
            all_samples.len(),
            duration_ms,
            target_sample_rate,
            target_channels
        );

        Ok(DecodedAudio {
            samples: all_samples,
            sample_rate: target_sample_rate,
            channels: target_channels,
            duration_ms,
        })
    }

    /// Decode a specific time range of audio
    ///
    /// Seeks to `start_ms` and decodes until `end_ms`.
    pub fn decode_range(
        &self,
        start_ms: u64,
        end_ms: u64,
        target_sample_rate: u32,
        target_channels: u32,
    ) -> Result<DecodedAudio, String> {
        let full_audio = self.decode_all(target_sample_rate, target_channels)?;
        Ok(full_audio.segment(start_ms, end_ms))
    }
}

/// Information about an audio stream
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AudioInfo {
    pub sample_rate: u32,
    pub channels: u32,
    pub duration_ms: u64,
    pub codec_name: String,
}

#[cfg(feature = "ffmpeg")]
impl Default for AudioDecoder {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Stub implementation when FFmpeg is not available ──────────────────────────

#[cfg(not(feature = "ffmpeg"))]
pub struct AudioDecoder {
    is_open: bool,
    file_path: Option<String>,
    source_sample_rate: u32,
    source_channels: u32,
    duration_ms: u64,
    codec_name: String,
}

#[cfg(not(feature = "ffmpeg"))]
impl AudioDecoder {
    pub fn new() -> Self {
        Self {
            is_open: false,
            file_path: None,
            source_sample_rate: 44100,
            source_channels: 2,
            duration_ms: 0,
            codec_name: String::new(),
        }
    }

    pub fn open(&mut self, _file_path: &str) -> Result<(), String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn close(&mut self) {
        self.is_open = false;
        self.file_path = None;
    }

    pub fn is_open(&self) -> bool {
        self.is_open
    }

    pub fn audio_info(&self) -> AudioInfo {
        AudioInfo {
            sample_rate: self.source_sample_rate,
            channels: self.source_channels,
            duration_ms: self.duration_ms,
            codec_name: self.codec_name.clone(),
        }
    }

    pub fn decode_all(
        &self,
        _target_sample_rate: u32,
        _target_channels: u32,
    ) -> Result<DecodedAudio, String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }

    pub fn decode_range(
        &self,
        _start_ms: u64,
        _end_ms: u64,
        _target_sample_rate: u32,
        _target_channels: u32,
    ) -> Result<DecodedAudio, String> {
        Err("FFmpeg is not available. Enable the 'ffmpeg' feature.".to_string())
    }
}

#[cfg(not(feature = "ffmpeg"))]
impl Default for AudioDecoder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decoded_audio_silence() {
        let silence = DecodedAudio::silence(44100, 2, 1000);
        assert_eq!(silence.sample_rate, 44100);
        assert_eq!(silence.channels, 2);
        assert_eq!(silence.duration_ms, 1000);
        assert_eq!(silence.frame_count(), 44100);
        assert!(silence.samples.iter().all(|&s| s == 0.0));
    }

    #[test]
    fn test_decoded_audio_segment() {
        let mut audio = DecodedAudio::silence(44100, 2, 2000);
        // Put a marker at sample index 44100 (1 second in)
        audio.samples[44100 * 2] = 1.0;

        let segment = audio.segment(500, 1500);
        assert!(segment.duration_ms > 0);
        // The marker should not be in the 0.5s-1.5s segment
        // because the marker is at exactly 1.0s which maps to
        // sample index 44100*2 in the original, which becomes
        // index (44100 - 22050)*2 = 44100 in the segment
    }

    #[test]
    fn test_decoded_audio_to_stereo() {
        let mono = DecodedAudio {
            samples: vec![0.5, -0.3, 0.8],
            sample_rate: 44100,
            channels: 1,
            duration_ms: 100,
        };

        let stereo = mono.to_stereo();
        assert_eq!(stereo.channels, 2);
        assert_eq!(stereo.samples.len(), 6);
        assert_eq!(stereo.samples[0], 0.5); // L
        assert_eq!(stereo.samples[1], 0.5); // R
        assert_eq!(stereo.samples[2], -0.3); // L
        assert_eq!(stereo.samples[3], -0.3); // R
    }

    #[test]
    fn test_audio_decoder_new() {
        let decoder = AudioDecoder::new();
        assert!(!decoder.is_open());
        let info = decoder.audio_info();
        assert_eq!(info.sample_rate, 44100);
        assert_eq!(info.channels, 2);
    }
}
