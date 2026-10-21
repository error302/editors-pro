#[cfg(feature = "ffmpeg")]
mod ffmpeg_tests {
    use editors_pro_engine::api::EditorsProEngine;
    use editors_pro_engine::timeline::track::TrackType;
    use std::fs;
    use std::path::Path;

    fn write_pcm_wav(path: &Path, duration_ms: u32) {
        let sample_rate = 8_000_u32;
        let channels = 1_u16;
        let bits_per_sample = 16_u16;
        let sample_count = sample_rate * duration_ms / 1_000;
        let data_size = sample_count * u32::from(channels) * u32::from(bits_per_sample) / 8;
        let mut wav = Vec::with_capacity(44 + data_size as usize);
        wav.extend_from_slice(b"RIFF");
        wav.extend_from_slice(&(36 + data_size).to_le_bytes());
        wav.extend_from_slice(b"WAVEfmt ");
        wav.extend_from_slice(&16_u32.to_le_bytes());
        wav.extend_from_slice(&1_u16.to_le_bytes());
        wav.extend_from_slice(&channels.to_le_bytes());
        wav.extend_from_slice(&sample_rate.to_le_bytes());
        let byte_rate = sample_rate * u32::from(channels) * u32::from(bits_per_sample) / 8;
        wav.extend_from_slice(&byte_rate.to_le_bytes());
        wav.extend_from_slice(&(channels * bits_per_sample / 8).to_le_bytes());
        wav.extend_from_slice(&bits_per_sample.to_le_bytes());
        wav.extend_from_slice(b"data");
        wav.extend_from_slice(&data_size.to_le_bytes());
        for index in 0..sample_count {
            let value = ((index as f32 * 440.0 * std::f32::consts::TAU / sample_rate as f32).sin()
                * 8_000.0) as i16;
            wav.extend_from_slice(&value.to_le_bytes());
        }
        fs::write(path, wav).unwrap();
    }

    #[test]
    fn imported_audio_can_be_added_saved_and_reopened() {
        let directory = tempfile::tempdir().unwrap();
        let audio_path = directory.path().join("voice.wav");
        write_pcm_wav(&audio_path, 1_000);

        let mut engine = EditorsProEngine::new();
        engine.initialize().unwrap();
        engine.create_project("Audio import QA", None).unwrap();
        let audio_track = engine
            .add_track(TrackType::Audio, Some("Voice".to_string()))
            .unwrap();
        let asset = engine.import_media(audio_path.to_str().unwrap()).unwrap();

        assert_eq!(asset.media_type, "Audio");
        assert_eq!(asset.duration_ms, Some(1_000));
        assert_eq!(asset.codec.as_deref(), Some("pcm_s16le"));
        engine
            .add_clip(&audio_track.id, &asset.id, 0, asset.duration_ms.unwrap())
            .unwrap();

        let project_path = directory.path().join("audio-project.epp");
        engine.save_project(project_path.to_str().unwrap()).unwrap();
        engine.load_project(project_path.to_str().unwrap()).unwrap();

        let timeline = engine.get_timeline_state().unwrap();
        assert!(timeline.tracks.iter().any(|track| {
            track.id == audio_track.id
                && track
                    .clips
                    .iter()
                    .any(|clip| clip.asset_id == asset.id && clip.duration_ms == 1_000)
        }));
    }

    #[test]
    fn exported_timeline_contains_audible_audio_and_video() {
        use editors_pro_engine::audio::decoder::AudioDecoder;
        use editors_pro_engine::export_engine::ExportSettings;
        let directory = tempfile::tempdir().unwrap();
        let audio_path = directory.path().join("tone.wav");
        write_pcm_wav(&audio_path, 1_000);
        let image_path = directory.path().join("frame.png");
        image::RgbaImage::from_pixel(16, 16, image::Rgba([50, 80, 120, 255]))
            .save(&image_path)
            .unwrap();
        let mut engine = EditorsProEngine::new();
        engine.initialize().unwrap();
        engine
            .create_project("Audio export regression", None)
            .unwrap();
        let video = engine.add_track(TrackType::Video, None).unwrap();
        let audio = engine.add_track(TrackType::Audio, None).unwrap();
        let image = engine.import_media(image_path.to_str().unwrap()).unwrap();
        let tone = engine.import_media(audio_path.to_str().unwrap()).unwrap();
        engine.add_clip(&video.id, &image.id, 0, 1_000).unwrap();
        engine.add_clip(&audio.id, &tone.id, 0, 1_000).unwrap();
        let output = directory.path().join("timeline.mp4");
        let mut settings = ExportSettings::hd_720p();
        settings.width = 320;
        settings.height = 240;
        settings.fps = 24.0;
        settings.audio_sample_rate = 48_000;
        engine
            .export_video(output.to_str().unwrap(), settings, &|_| {})
            .unwrap();
        let input = ffmpeg_next::format::input(&output).unwrap();
        assert!(input
            .streams()
            .best(ffmpeg_next::media::Type::Video)
            .is_some());
        assert!(input
            .streams()
            .best(ffmpeg_next::media::Type::Audio)
            .is_some());
        let mut decoded = AudioDecoder::new();
        decoded.open(output.to_str().unwrap()).unwrap();
        let buffer = decoded.decode_all(48_000, 2).unwrap();
        assert!(
            buffer.samples.iter().any(|sample| sample.abs() > 0.05),
            "Export must preserve the audible tone"
        );
        assert_eq!(buffer.sample_rate, 48_000);
        assert!(
            (buffer.duration_ms as i64 - 1_000).abs() < 100,
            "Decoded duration must exclude padded frame capacity: {}ms",
            buffer.duration_ms
        );
    }
}

#[cfg(not(feature = "ffmpeg"))]
#[test]
fn audio_import_reports_missing_ffmpeg_instead_of_accepting_unknown_duration() {
    use editors_pro_engine::api::EditorsProEngine;
    use std::fs;

    let directory = tempfile::tempdir().unwrap();
    let audio_path = directory.path().join("voice.wav");
    fs::write(&audio_path, b"audio decoder unavailable in this build").unwrap();

    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine.create_project("Audio import QA", None).unwrap();
    let error = engine
        .import_media(audio_path.to_str().unwrap())
        .unwrap_err();

    assert!(error.contains("FFmpeg is not available"));
}
