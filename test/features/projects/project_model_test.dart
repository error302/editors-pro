import 'package:editors_pro/data/models/project_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectModel', () {
    test('ProjectModel has correct defaults', () {
      const model = ProjectModel(
        id: 'test-id',
        name: 'Test Project',
        createdAt: 1704067200000, // 2024-01-01T00:00:00Z as millis
        updatedAt: 1704067200000,
        width: 1920,
        height: 1080,
        fps: 30.0,
        durationMs: 0,
      );

      expect(model.id, equals('test-id'));
      expect(model.name, equals('Test Project'));
      expect(model.width, equals(1920));
      expect(model.height, equals(1080));
      expect(model.fps, equals(30.0));
      expect(model.createdAt, equals(1704067200000));
    });

    test('ProjectModel copyWith works correctly', () {
      const model = ProjectModel(
        id: 'test-id',
        name: 'Test Project',
        createdAt: 1704067200000,
        updatedAt: 1704067200000,
        width: 1920,
        height: 1080,
        fps: 30.0,
      );

      final updated = model.copyWith(
        name: 'Updated Project',
        durationMs: 5000,
      );

      expect(updated.name, equals('Updated Project'));
      expect(updated.durationMs, equals(5000));
      expect(updated.id, equals('test-id')); // unchanged
    });

    test('ProjectModel equality reflects changes to the project snapshot', () {
      const model1 = ProjectModel(
        id: 'same-id',
        name: 'Project A',
        createdAt: 1000,
        updatedAt: 1000,
        width: 1920,
        height: 1080,
        fps: 30.0,
      );
      const model2 = ProjectModel(
        id: 'same-id',
        name: 'Project B',
        createdAt: 2000,
        updatedAt: 2000,
        width: 1280,
        height: 720,
        fps: 24.0,
      );

      expect(model1, isNot(equals(model2)));
      expect(model1.copyWith(), equals(model1));
    });

    test('TrackModel stores track properties', () {
      const track = TrackModel(
        id: 'track-1',
        name: 'Video 1',
        trackType: TrackType.video,
        locked: false,
        visible: true,
        volume: 1.0,
      );

      expect(track.id, equals('track-1'));
      expect(track.name, equals('Video 1'));
      expect(track.trackType, equals(TrackType.video));
      expect(track.locked, isFalse);
      expect(track.visible, isTrue);
    });

    test('TrackModel copyWith works correctly', () {
      const track = TrackModel(
        id: 'track-1',
        name: 'Video 1',
        trackType: TrackType.video,
      );

      final updated = track.copyWith(
        volume: 0.5,
        visible: false,
      );

      expect(updated.volume, equals(0.5));
      expect(updated.visible, isFalse);
      expect(updated.id, equals('track-1')); // unchanged
    });

    test('ClipModel stores clip properties', () {
      const clip = ClipModel(
        id: 'clip-1',
        assetId: 'asset-1',
        startMs: 1000,
        durationMs: 5000,
        trimStartMs: 0,
        trimEndMs: 0,
        speed: 1.0,
        opacity: 1.0,
      );

      expect(clip.id, equals('clip-1'));
      expect(clip.assetId, equals('asset-1'));
      expect(clip.startMs, equals(1000));
      expect(clip.durationMs, equals(5000));
      expect(clip.speed, equals(1.0));
    });

    test('ClipModel copyWith works correctly', () {
      const clip = ClipModel(
        id: 'clip-1',
        assetId: 'asset-1',
        startMs: 1000,
        durationMs: 5000,
      );

      final trimmed = clip.copyWith(
        trimStartMs: 500,
        speed: 2.0,
      );

      expect(trimmed.trimStartMs, equals(500));
      expect(trimmed.speed, equals(2.0));
      expect(trimmed.id, equals('clip-1')); // unchanged
    });

    test('EffectModel stores effect properties', () {
      const effect = EffectModel(
        id: 'effect-1',
        name: 'Brightness',
        effectType: 'Filter',
        enabled: true,
        order: 0,
      );

      expect(effect.id, equals('effect-1'));
      expect(effect.name, equals('Brightness'));
      expect(effect.enabled, isTrue);
      expect(effect.effectType, equals('Filter'));
    });

    test('MediaAssetModel stores media properties', () {
      const asset = MediaAssetModel(
        id: 'asset-1',
        filePath: '/path/to/video.mp4',
        fileName: 'video.mp4',
        mediaType: MediaType.video,
        durationMs: 30000,
        width: 1920,
        height: 1080,
        fileSizeBytes: 10485760,
      );

      expect(asset.id, equals('asset-1'));
      expect(asset.mediaType, equals(MediaType.video));
      expect(asset.durationMs, equals(30000));
    });

    test('TransitionModel stores transition properties', () {
      const transition = TransitionModel(
        id: 'trans-1',
        transitionType: 'Fade',
        durationMs: 500,
        fromClipId: 'clip-1',
        toClipId: 'clip-2',
      );

      expect(transition.id, equals('trans-1'));
      expect(transition.transitionType, equals('Fade'));
      expect(transition.durationMs, equals(500));
    });
  });
}
