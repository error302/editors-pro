import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bridge DTOs', () {
    group('BridgeProjectSettings', () {
      test('creates with required fields', () {
        const settings = BridgeProjectSettings(
          width: 1920,
          height: 1080,
          fps: 30.0,
        );

        expect(settings.width, equals(1920));
        expect(settings.height, equals(1080));
        expect(settings.fps, equals(30.0));
      });

      test('serializes to JSON', () {
        const settings = BridgeProjectSettings(
          width: 1280,
          height: 720,
          fps: 24.0,
        );

        final json = settings.toJson();
        expect(json['width'], equals(1280));
        expect(json['height'], equals(720));
        expect(json['fps'], equals(24.0));
      });

      test('deserializes from JSON', () {
        final json = {
          'width': 3840,
          'height': 2160,
          'fps': 60.0,
        };

        final settings = BridgeProjectSettings.fromJson(json);
        expect(settings.width, equals(3840));
        expect(settings.height, equals(2160));
        expect(settings.fps, equals(60.0));
      });

      test('round-trip JSON serialization', () {
        const original = BridgeProjectSettings(
          width: 1920,
          height: 1080,
          fps: 29.97,
        );

        final json = original.toJson();
        final restored = BridgeProjectSettings.fromJson(json);

        expect(restored.width, equals(original.width));
        expect(restored.height, equals(original.height));
        expect(restored.fps, equals(original.fps));
      });
    });

    group('BridgeExportSettings', () {
      test('creates with defaults', () {
        const settings = BridgeExportSettings(
          width: 1920,
          height: 1080,
          fps: 30.0,
          bitrateKbps: 8000,
          codec: 'H.264',
          format: 'MP4',
        );

        expect(settings.audioBitrateKbps, equals(128));
        expect(settings.audioSampleRate, equals(44100));
        expect(settings.audioChannels, equals(2));
        expect(settings.includeAudio, isTrue);
        expect(settings.twoPass, isFalse);
      });

      test('serializes to JSON with snake_case keys', () {
        const settings = BridgeExportSettings(
          width: 1920,
          height: 1080,
          fps: 30.0,
          bitrateKbps: 8000,
          codec: 'H.264',
          format: 'MP4',
          audioBitrateKbps: 256,
        );

        final json = settings.toJson();
        expect(json.containsKey('bitrate_kbps'), isTrue);
        expect(json.containsKey('audio_bitrate_kbps'), isTrue);
        expect(json.containsKey('two_pass'), isTrue);
        expect(json['audio_bitrate_kbps'], equals(256));
      });
    });

    group('ProjectInfo', () {
      test('creates from JSON', () {
        final json = {
          'id': 'proj-1',
          'name': 'My Project',
          'width': 1920,
          'height': 1080,
          'fps': 30.0,
          'duration_ms': 60000,
          'track_count': 3,
          'media_count': 2,
        };

        final info = ProjectInfo.fromJson(json);
        expect(info.id, equals('proj-1'));
        expect(info.name, equals('My Project'));
        expect(info.width, equals(1920));
        expect(info.height, equals(1080));
        expect(info.durationMs, equals(60000));
        expect(info.trackCount, equals(3));
        expect(info.mediaCount, equals(2));
      });
    });

    group('ClipInfo', () {
      test('creates from JSON with BigInt fields', () {
        final json = {
          'id': 'clip-1',
          'track_id': 'track-1',
          'asset_id': 'asset-1',
          'start_ms': 5000,
          'duration_ms': 10000,
          'trim_start_ms': 250,
          'trim_end_ms': 500,
        };

        final clip = ClipInfo.fromJson(json);
        expect(clip.id, equals('clip-1'));
        expect(clip.trackId, equals('track-1'));
        expect(clip.startMs, equals(5000));
        expect(clip.durationMs, equals(10000));
        expect(clip.trimStartMs, equals(250));
        expect(clip.trimEndMs, equals(500));
      });
    });

    group('EffectInfo', () {
      test('creates from JSON with parameters', () {
        final json = {
          'id': 'effect-1',
          'name': 'Brightness',
          'effect_type': 'Filter',
          'enabled': true,
          'order': 0,
          'parameters': [
            {
              'name': 'brightness',
              'display_name': 'Brightness',
              'value': 0.5,
              'min_value': -1.0,
              'max_value': 1.0,
              'default_value': 0.0,
              'step': 0.01,
            },
          ],
        };

        final effect = EffectInfo.fromJson(json);
        expect(effect.id, equals('effect-1'));
        expect(effect.name, equals('Brightness'));
        expect(effect.parameters, hasLength(1));
        expect(effect.parameters[0].value, equals(0.5));
        expect(effect.parameters[0].displayName, equals('Brightness'));
      });
    });

    group('TimelineState', () {
      test('creates from JSON with nested tracks and clips', () {
        final json = {
          'tracks': [
            {
              'id': 'track-1',
              'name': 'Video 1',
              'track_type': 'Video',
              'clips': [
                {
                  'id': 'clip-1',
                  'asset_id': 'asset-1',
                  'start_ms': 0,
                  'duration_ms': 5000,
                  'trim_start_ms': 0,
                  'trim_end_ms': 0,
                  'speed': 1.0,
                  'opacity': 1.0,
                  'effects': [],
                  'transition_in': null,
                  'transition_out': null,
                },
              ],
              'locked': false,
              'visible': true,
              'volume': 1.0,
            },
          ],
          'duration_ms': 5000,
        };

        final state = TimelineState.fromJson(json);
        expect(state.tracks, hasLength(1));
        expect(state.tracks[0].id, equals('track-1'));
        expect(state.tracks[0].clips, hasLength(1));
        expect(state.tracks[0].clips[0].id, equals('clip-1'));
        expect(state.durationMs, equals(5000));
      });
    });

    group('BridgeDuckingConfig', () {
      test('has correct default values', () {
        const config = BridgeDuckingConfig(enabled: false, duckLevel: 0.3);
        expect(config.enabled, isFalse);
        expect(config.duckLevel, equals(0.3));
      });
    });

    group('TransitionInfo', () {
      test('creates from JSON', () {
        final json = {
          'id': 'trans-1',
          'transition_type': 'Fade',
          'duration_ms': 500,
          'direction': 'left_to_right',
        };

        final info = TransitionInfo.fromJson(json);
        expect(info.id, equals('trans-1'));
        expect(info.transitionType, equals('Fade'));
        expect(info.durationMs, equals(500));
        expect(info.direction, equals('left_to_right'));
      });
    });
  });
}
