use editors_pro_engine::audio::decoder::DecodedAudio;

#[test]
fn submillisecond_channel_rounding_never_swaps_stereo_or_leaves_partial_frames() {
    let samples: Vec<f32> = (0..1000).flat_map(|index| [index as f32, -(index as f32)]).collect();
    let buffer = DecodedAudio { samples, sample_rate: 44_100, channels: 2, duration_ms: 22 };
    let segment = buffer.segment(5, 10);
    assert_eq!(segment.samples.len() % 2, 0);
    assert_eq!(&segment.samples[..2], &[220.0, -220.0]);
    assert!(segment.samples.chunks_exact(2).all(|frame| frame[0] == -frame[1]));
    assert!(buffer.segment(10, 5).samples.is_empty());
    assert!(buffer.segment(30, 40).samples.is_empty());
    assert_eq!(DecodedAudio::silence(44_100, 2, 5).samples.len(), 440);
}

#[cfg(feature = "ffmpeg")]
mod codecs {
    use editors_pro_engine::audio::decoder::AudioDecoder;
    use editors_pro_engine::export_engine::encoder::{interleaved_f32_audio_frame, AudioEncoder};
    use std::path::Path;
    use ffmpeg_next as ff;

    fn stereo_tones(rate: u32, frames: usize) -> Vec<f32> {
        (0..frames).flat_map(|index| {
            let time = index as f32 / rate as f32;
            [(std::f32::consts::TAU * 440.0 * time).sin() * 0.45,
             (std::f32::consts::TAU * 880.0 * time).sin() * 0.18]
        }).collect()
    }

    fn write_wav(path: &Path, rate: u32, samples: &[f32]) {
        let data_size = samples.len() as u32 * 2;
        let mut wav = Vec::new();
        wav.extend_from_slice(b"RIFF"); wav.extend_from_slice(&(36 + data_size).to_le_bytes());
        wav.extend_from_slice(b"WAVEfmt "); wav.extend_from_slice(&16u32.to_le_bytes());
        wav.extend_from_slice(&1u16.to_le_bytes()); wav.extend_from_slice(&2u16.to_le_bytes());
        wav.extend_from_slice(&rate.to_le_bytes()); wav.extend_from_slice(&(rate * 4).to_le_bytes());
        wav.extend_from_slice(&4u16.to_le_bytes()); wav.extend_from_slice(&16u16.to_le_bytes());
        wav.extend_from_slice(b"data"); wav.extend_from_slice(&data_size.to_le_bytes());
        for sample in samples { wav.extend_from_slice(&((*sample * 32767.0) as i16).to_le_bytes()); }
        std::fs::write(path, wav).unwrap();
    }

    fn tone_magnitude(samples: &[f32], channel: usize, frequency: f64, rate: u32) -> f64 {
        let skip = (rate / 20) as usize; // Exclude codec startup/tail transients.
        let count = samples.len() / 2;
        let mut real = 0.0;
        let mut imaginary = 0.0;
        for index in skip..count.saturating_sub(skip) {
            let angle = std::f64::consts::TAU * frequency * index as f64 / rate as f64;
            real += samples[index * 2 + channel] as f64 * angle.cos();
            imaginary += samples[index * 2 + channel] as f64 * angle.sin();
        }
        real.hypot(imaginary) / count.max(1) as f64
    }

    fn assert_stereo_tones(samples: &[f32], rate: u32) {
        assert!(!samples.is_empty());
        assert!(samples.iter().all(|sample| sample.is_finite() && sample.abs() < 1.2));
        let left = tone_magnitude(samples, 0, 440.0, rate);
        let right = tone_magnitude(samples, 1, 880.0, rate);
        assert!(left > 0.08, "Left tone must remain audible: {left}");
        assert!(right > 0.025, "Right tone must remain audible: {right}");
        assert!(left > tone_magnitude(samples, 0, 880.0, rate) * 5.0, "Left must retain its distinct tone");
        assert!(right > tone_magnitude(samples, 1, 440.0, rate) * 5.0, "Right must retain its distinct tone");
    }

    #[test]
    fn planar_aac_frame_initializes_both_channels_and_tail_padding_exactly() {
        ff::init().unwrap();
        let frame = interleaved_f32_audio_frame(&[0.125, -0.25, 0.5, -0.75], 2, 4, 48_000, 123).unwrap();
        assert_eq!(frame.plane::<f32>(0), &[0.125, 0.5, 0.0, 0.0]);
        assert_eq!(frame.plane::<f32>(1), &[-0.25, -0.75, 0.0, 0.0]);
        assert_eq!(frame.pts(), Some(123));
        assert_eq!(frame.rate(), 48_000);
        for sample in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY] {
            assert!(interleaved_f32_audio_frame(&[sample, 0.0], 2, 1, 48_000, 0).is_err());
        }
        assert!(interleaved_f32_audio_frame(&[0.5], 2, 1, 48_000, 0).is_err());
        assert!(AudioEncoder::new(48_000, 3, 128).is_err());
    }

    #[test]
    fn stereo_wav_resampling_preserves_distinct_channels_and_exact_duration() {
        ff::init().unwrap();
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("stereo.wav");
        let original = stereo_tones(44_100, 16_537);
        write_wav(&input, 44_100, &original);
        let mut decoder = AudioDecoder::new(); decoder.open(input.to_str().unwrap()).unwrap();
        let decoded = decoder.decode_all(48_000, 2).unwrap();
        assert!((decoded.frame_count() as i64 - 18_000).abs() <= 2, "Resampling must exclude allocation padding and retain the tail: {}", decoded.frame_count());
        assert_stereo_tones(&decoded.samples, 48_000);
        assert!(decoder.decode_all(0, 2).is_err());
        assert!(decoder.decode_all(48_000, 0).is_err());
    }

    #[test]
    fn aac_roundtrip_preserves_finite_distinct_stereo_and_partial_final_frame() {
        ff::init().unwrap();
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("stereo.m4a");
        let mut output = ff::format::output(&path).unwrap();
        let mut encoder = AudioEncoder::new(48_000, 2, 192).unwrap();
        encoder.add_stream(&mut output).unwrap(); output.write_header().unwrap();
        let original = stereo_tones(48_000, 18_000);
        // Uneven chunks exercise buffering across channel and AAC boundaries.
        for chunk in original.chunks(777) { encoder.encode_samples(&mut output, chunk).unwrap(); }
        encoder.flush(&mut output).unwrap(); output.write_trailer().unwrap(); drop(output);
        let mut decoder = AudioDecoder::new(); decoder.open(path.to_str().unwrap()).unwrap();
        let decoded = decoder.decode_all(48_000, 2).unwrap();
        assert_stereo_tones(&decoded.samples, 48_000);
        assert!((decoded.frame_count() as i64 - 18_000).abs() <= 1024, "Only one final AAC frame may be padded: {}", decoded.frame_count());
    }

    #[cfg(target_os = "android")]
    #[test]
    fn edited_photo_song_text_export_and_saved_playable_preview_roundtrip() {
        use editors_pro_engine::{api::{EditorsProEngine, project_preview}, project::ProjectSettings,
            timeline::track::TrackType, export_engine::ExportSettings};
        let directory = tempfile::tempdir().unwrap().keep();
        let photo = directory.join("photo.png");
        image::RgbaImage::from_pixel(320, 180, image::Rgba([80, 150, 50, 255])).save(&photo).unwrap();
        let song = directory.join("song.wav");
        write_wav(&song, 44_100, &stereo_tones(44_100, 44_100));
        let mut engine = EditorsProEngine::new(); engine.initialize().unwrap();
        engine.create_project("Android media workflow QA", Some(ProjectSettings {
            width: 320, height: 180, fps: 12.0, ..Default::default()
        })).unwrap();
        let video = engine.add_track(TrackType::Video, Some("Photo".into())).unwrap();
        let audio = engine.add_track(TrackType::Audio, Some("Song".into())).unwrap();
        let text = engine.add_track(TrackType::Text, Some("Title".into())).unwrap();
        let image_asset = engine.import_media(photo.to_str().unwrap()).unwrap();
        let song_asset = engine.import_media(song.to_str().unwrap()).unwrap();
        assert_eq!(song_asset.media_type, "Audio");
        let clip = engine.add_clip(&video.id, &image_asset.id, 0, 1000).unwrap();
        engine.add_clip(&audio.id, &song_asset.id, 0, 1000).unwrap();
        engine.set_filter_look(&clip.id, "noir", 1.0, true).unwrap();
        engine.add_text_clip(&text.id, "Editors Pro", "Inter-Bold", 26.0, "#FF0000", 0.5, 0.5, 0, 1000).unwrap();
        let expected = engine.get_frame(500).unwrap();
        assert!(expected.data.chunks_exact(4).filter(|p| p[0] > 150 && p[0] > p[1].saturating_add(50)).count() > 60);
        let project = directory.join("edited.epp");
        engine.save_project(project.to_str().unwrap()).unwrap(); engine.load_project(project.to_str().unwrap()).unwrap();
        assert_eq!(engine.get_frame(500).unwrap().data, expected.data);
        let output = directory.join("export.mp4");
        let mut settings = ExportSettings::hd_720p(); settings.width=320; settings.height=180;
        settings.fps=12.0; settings.audio_sample_rate=48_000; settings.bitrate_kbps=900;
        assert!(engine.export_video(output.to_str().unwrap(), settings, &|_| {}).unwrap().success);
        let input = ff::format::input(&output).unwrap();
        assert!(input.streams().best(ff::media::Type::Video).is_some());
        assert!(input.streams().best(ff::media::Type::Audio).is_some()); drop(input);
        let mut decoder = AudioDecoder::new(); decoder.open(output.to_str().unwrap()).unwrap();
        assert_stereo_tones(&decoder.decode_all(48_000, 2).unwrap().samples, 48_000);
        let exported = engine.import_media(output.to_str().unwrap()).unwrap();
        assert_eq!((exported.width, exported.height), (Some(320), Some(180)));
        let cover = directory.join("cover.png"); let preview = directory.join("preview.mp4");
        let job = project_preview::start_job(project_preview::PreviewRequest {
            project_path: project.to_str().unwrap().into(), cover_path: cover.to_str().unwrap().into(),
            video_path: Some(preview.to_str().unwrap().into())
        }).unwrap();
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(90);
        loop {
            let status = project_preview::job_status(&job.job_id).unwrap();
            if status.finished {
                assert!(status.error.is_none(), "{:?}", status.error);
                assert!(status.cover_ready && status.video_ready); break;
            }
            assert!(std::time::Instant::now() < deadline, "Preview timed out");
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        project_preview::release_job(&job.job_id).unwrap();
        assert_eq!(image::open(&cover).unwrap().to_rgba8().as_raw(), &expected.data);
        decoder.open(preview.to_str().unwrap()).unwrap();
        assert_stereo_tones(&decoder.decode_all(48_000, 2).unwrap().samples, 48_000);
        println!("ANDROID_MEDIA_WORKFLOW_OUTPUT={}", directory.display());
    }
}
