//! Identity checks distinguish actual high-frame-rate decoding from rate metadata.
#![cfg(feature = "ffmpeg")]

use editors_pro_engine::decoder::{
    hardware::HardwareDecoder, software::SoftwareDecoder, FrameData,
};

fn fixture(directory: &std::path::Path, name: &str) -> String {
    let bytes: &[u8] = match name {
        "all_keyframes" => {
            include_bytes!("../../test/fixtures/high_frame_rate/all_keyframes_120fps.mp4")
        }
        "normal_gop" => include_bytes!("../../test/fixtures/high_frame_rate/normal_gop_120fps.mp4"),
        _ => panic!("Unknown fixture"),
    };
    let path = directory.join(format!("{name}.mp4"));
    std::fs::write(&path, bytes).unwrap();
    path.to_string_lossy().into_owned()
}

fn number(frame: &FrameData) -> u32 {
    (0..8).fold(0, |value, bit| {
        let y = 8 * frame.height as usize / 72;
        let x = (bit * 16 + 8) * frame.width as usize / 128;
        let offset = (y * frame.width as usize + x) * 4;
        value | (u32::from(frame.data[offset] > 128) << bit)
    })
}

#[test]
fn timeline_720p_120fps_export_contains_240_distinct_source_frames_and_stereo_audio() {
    use editors_pro_engine::{
        api::EditorsProEngine, audio::decoder::AudioDecoder, export_engine::ExportSettings,
        project::ProjectSettings, timeline::track::TrackType,
    };
    use ffmpeg_next as ff;
    let directory = tempfile::tempdir().unwrap();
    let source = fixture(directory.path(), "normal_gop");
    let song = directory.path().join("stereo.wav");
    write_stereo_wav(&song);
    let mut engine = EditorsProEngine::new();
    engine.initialize().unwrap();
    engine
        .create_project(
            "120 fps identity",
            Some(ProjectSettings {
                width: 1280,
                height: 720,
                fps: 120.0,
                ..Default::default()
            }),
        )
        .unwrap();
    let video = engine
        .add_track(TrackType::Video, Some("Numbered frames".into()))
        .unwrap();
    let audio = engine
        .add_track(TrackType::Audio, Some("Distinct stereo".into()))
        .unwrap();
    let asset = engine.import_media(&source).unwrap();
    let song_asset = engine.import_media(song.to_str().unwrap()).unwrap();
    engine.add_clip(&video.id, &asset.id, 0, 2000).unwrap();
    engine.add_clip(&audio.id, &song_asset.id, 0, 2000).unwrap();
    let output = directory.path().join("120fps.mp4");
    let mut settings = ExportSettings::hd_720p();
    settings.fps = 120.0;
    settings.audio_sample_rate = 48_000;
    assert!(
        engine
            .export_video(output.to_str().unwrap(), settings, &|_| {})
            .unwrap()
            .success
    );
    if let Some(retained) = std::env::var_os("EDITORS_PRO_QA_OUTPUT_DIR") {
        let retained = std::path::PathBuf::from(retained);
        std::fs::create_dir_all(&retained).unwrap();
        std::fs::copy(&output, retained.join("120fps.mp4")).unwrap();
    }
    let input = ff::format::input(&output).unwrap();
    let video_stream = input.streams().best(ff::media::Type::Video).unwrap();
    assert_eq!(video_stream.avg_frame_rate(), ff::Rational(120, 1));
    assert_eq!(
        video_stream.duration() * video_stream.time_base().numerator() as i64 * 1000
            / video_stream.time_base().denominator() as i64,
        2000,
        "The final video frame must have one full frame duration"
    );
    assert!((input.duration() - 2_000_000).abs() <= 30_000);
    assert!(input.streams().best(ff::media::Type::Audio).is_some());
    drop(input);
    let mut decoded = SoftwareDecoder::new();
    decoded.open(output.to_str().unwrap()).unwrap();
    for expected in 0..240 {
        let frame = decoded
            .decode_next_frame()
            .unwrap()
            .expect("Missing exported frame");
        assert_eq!((frame.width, frame.height), (1280, 720));
        assert_eq!(
            number(&frame),
            expected,
            "Exported frame {expected} identity"
        );
        assert_eq!(frame.timestamp_ms, expected as u64 * 1000 / 120);
    }
    assert!(decoded.decode_next_frame().unwrap().is_none());
    let mut audio_decoder = AudioDecoder::new();
    audio_decoder.open(output.to_str().unwrap()).unwrap();
    let decoded_audio = audio_decoder.decode_all(48_000, 2).unwrap();
    assert!((decoded_audio.frame_count() as i64 - 96_000).abs() <= 1024);
    assert!(decoded_audio
        .samples
        .iter()
        .all(|sample| sample.is_finite() && sample.abs() < 1.2));
    let tone = |channel: usize, frequency: f64| {
        let mut real = 0.0f64;
        let mut imaginary = 0.0f64;
        for (index, frame) in decoded_audio
            .samples
            .chunks_exact(2)
            .enumerate()
            .skip(2400)
            .take(90_000)
        {
            let angle = std::f64::consts::TAU * frequency * index as f64 / 48_000.0;
            real += frame[channel] as f64 * angle.cos();
            imaginary += frame[channel] as f64 * angle.sin();
        }
        real.hypot(imaginary) / 90_000.0
    };
    assert!(tone(0, 440.0) > 0.08 && tone(1, 880.0) > 0.025);
    assert!(tone(0, 440.0) > tone(0, 880.0) * 5.0);
    assert!(tone(1, 880.0) > tone(1, 440.0) * 5.0);
}

fn write_stereo_wav(path: &std::path::Path) {
    let rate = 48_000u32;
    let data_size = rate * 2 * 4;
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"RIFF");
    bytes.extend_from_slice(&(36 + data_size).to_le_bytes());
    bytes.extend_from_slice(b"WAVEfmt ");
    bytes.extend_from_slice(&16u32.to_le_bytes());
    bytes.extend_from_slice(&1u16.to_le_bytes());
    bytes.extend_from_slice(&2u16.to_le_bytes());
    bytes.extend_from_slice(&rate.to_le_bytes());
    bytes.extend_from_slice(&(rate * 4).to_le_bytes());
    bytes.extend_from_slice(&4u16.to_le_bytes());
    bytes.extend_from_slice(&16u16.to_le_bytes());
    bytes.extend_from_slice(b"data");
    bytes.extend_from_slice(&data_size.to_le_bytes());
    for index in 0..rate * 2 {
        let time = index as f32 / rate as f32;
        for (frequency, amplitude) in [(440.0, 0.45), (880.0, 0.18)] {
            let sample = (std::f32::consts::TAU * frequency * time).sin() * amplitude;
            bytes.extend_from_slice(&((sample * 32767.0) as i16).to_le_bytes());
        }
    }
    std::fs::write(path, bytes).unwrap();
}

#[test]
fn hardware_decoder_preserves_every_120fps_source_frame_and_backward_seeks() {
    let directory = tempfile::tempdir().unwrap();
    for source in ["all_keyframes", "normal_gop"] {
        let mut decoder = HardwareDecoder::new();
        decoder.open(&fixture(directory.path(), source)).unwrap();
        assert_eq!(decoder.get_video_info().unwrap().fps, 120.0);
        for expected in (0..240u32).chain([180, 17, 239, 0, 119, 120]) {
            let time_ms = expected as u64 * 1000 / 120;
            let decoded = decoder.decode_frame_at(time_ms).unwrap();
            assert_eq!(number(&decoded), expected, "{source} at {time_ms}ms");
            assert_eq!(decoded.timestamp_ms, time_ms, "{source} frame {expected}");
        }
        for (time_ms, expected) in [(1, 0), (7, 0), (9, 1), (15, 1), (24, 2), (1998, 239)] {
            assert_eq!(
                number(&decoder.decode_frame_at(time_ms).unwrap()),
                expected,
                "{source} must hold the preceding frame at {time_ms}ms"
            );
        }
    }
}

#[test]
fn software_decoder_preserves_every_120fps_source_frame_and_backward_seeks() {
    let directory = tempfile::tempdir().unwrap();
    for source in ["all_keyframes", "normal_gop"] {
        let mut decoder = SoftwareDecoder::new();
        decoder.open(&fixture(directory.path(), source)).unwrap();
        for expected in (0..240u32).chain([180, 17, 239, 0, 119, 120]) {
            let time_ms = expected as u64 * 1000 / 120;
            let decoded = decoder.decode_frame_at(time_ms).unwrap();
            assert_eq!(number(&decoded), expected, "{source} at {time_ms}ms");
            assert_eq!(decoded.timestamp_ms, time_ms, "{source} frame {expected}");
        }
        for (time_ms, expected) in [(1, 0), (7, 0), (9, 1), (15, 1), (24, 2), (1998, 239)] {
            assert_eq!(
                number(&decoder.decode_frame_at(time_ms).unwrap()),
                expected,
                "{source} must hold the preceding frame at {time_ms}ms"
            );
        }
    }
}
