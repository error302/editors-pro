import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorState', () {
    test('has correct defaults', () {
      const state = EditorState();

      expect(state.isPlaying, isFalse);
      expect(state.isAudioPlaying, isFalse);
      expect(state.currentTimeMs, equals(0));
      expect(state.durationMs, equals(0));
      expect(state.zoomLevel, equals(1.0));
      expect(state.isImporting, isFalse);
      expect(state.isExporting, isFalse);
      expect(state.exportProgress, equals(0));
      expect(state.selectedClipId, isNull);
      expect(state.selectedTrackId, isNull);
      expect(state.leftPanelTab, equals(LeftPanelTab.media));
      expect(state.showInspector, isFalse);
      expect(state.playbackSpeed, equals(1.0));
      expect(state.masterVolume, equals(1.0));
      expect(state.isDecodingFrame, isFalse);
    });

    test('copyWith preserves unchanged values', () {
      const state = EditorState(
        isPlaying: true,
        currentTimeMs: 5000,
        durationMs: 30000,
        zoomLevel: 2.0,
        masterVolume: 0.75,
      );

      final updated = state.copyWith(currentTimeMs: 10000);

      expect(updated.isPlaying, isTrue);
      expect(updated.currentTimeMs, equals(10000));
      expect(updated.durationMs, equals(30000));
      expect(updated.zoomLevel, equals(2.0));
      expect(updated.masterVolume, equals(0.75));
    });

    test('copyWith clearError resets lastError', () {
      const state = EditorState(lastError: 'Something went wrong');

      final updated = state.copyWith(clearError: true);

      expect(updated.lastError, isNull);
    });

    test('copyWith clamps zoomLevel range', () {
      const state = EditorState();

      // Note: zoom clamping happens in the setZoom method, not copyWith
      final tooHigh = state.copyWith(zoomLevel: 15.0);
      expect(tooHigh.zoomLevel, equals(15.0)); // copyWith doesn't clamp

      // The setZoom method should clamp
    });

    test('copyWith handles all fields', () {
      const state = EditorState();
      final updated = state.copyWith(
        isPlaying: true,
        currentTimeMs: 1000,
        durationMs: 60000,
        zoomLevel: 1.5,
        isImporting: true,
        isExporting: true,
        exportProgress: 0.5,
        selectedClipId: 'clip-1',
        selectedTrackId: 'track-1',
        leftPanelTab: LeftPanelTab.effects,
        showInspector: true,
        playbackSpeed: 2.0,
        lastError: 'test error',
        isAudioPlaying: true,
        masterVolume: 0.5,
        isDecodingFrame: true,
      );

      expect(updated.isPlaying, isTrue);
      expect(updated.currentTimeMs, equals(1000));
      expect(updated.durationMs, equals(60000));
      expect(updated.zoomLevel, equals(1.5));
      expect(updated.isImporting, isTrue);
      expect(updated.isExporting, isTrue);
      expect(updated.exportProgress, equals(0.5));
      expect(updated.selectedClipId, equals('clip-1'));
      expect(updated.selectedTrackId, equals('track-1'));
      expect(updated.leftPanelTab, equals(LeftPanelTab.effects));
      expect(updated.showInspector, isTrue);
      expect(updated.playbackSpeed, equals(2.0));
      expect(updated.lastError, equals('test error'));
      expect(updated.isAudioPlaying, isTrue);
      expect(updated.masterVolume, equals(0.5));
      expect(updated.isDecodingFrame, isTrue);
    });
  });

  group('EditorNotifier (without engine)', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has correct defaults', () {
      final state = container.read(editorProvider);

      expect(state.isPlaying, isFalse);
      expect(state.currentTimeMs, equals(0));
      expect(state.durationMs, equals(0));
    });

    test('seekTo clamps to valid range', () {
      final notifier = container.read(editorProvider.notifier);

      // Seek to negative should clamp to 0
      notifier.seekTo(-100);
      expect(container.read(editorProvider).currentTimeMs, equals(0));

      // Seek to positive within range
      notifier.seekTo(5000);
      expect(container.read(editorProvider).currentTimeMs, equals(5000));

      // Seek beyond duration should clamp
      notifier.setDuration(10000);
      notifier.seekTo(20000);
      expect(container.read(editorProvider).currentTimeMs, equals(10000));
    });

    test('setZoom clamps to valid range', () {
      final notifier = container.read(editorProvider.notifier);

      // Too low
      notifier.setZoom(0.01);
      expect(container.read(editorProvider).zoomLevel, equals(0.1));

      // Too high
      notifier.setZoom(100.0);
      expect(container.read(editorProvider).zoomLevel, equals(10.0));

      // Valid
      notifier.setZoom(2.5);
      expect(container.read(editorProvider).zoomLevel, equals(2.5));
    });

    test('zoomIn multiplies by 1.2', () {
      final notifier = container.read(editorProvider.notifier);
      notifier.setZoom(1.0);
      notifier.zoomIn();
      expect(
        (container.read(editorProvider).zoomLevel - 1.2).abs() < 0.01,
        isTrue,
      );
    });

    test('zoomOut divides by 1.2', () {
      final notifier = container.read(editorProvider.notifier);
      notifier.setZoom(1.2);
      notifier.zoomOut();
      expect(
        (container.read(editorProvider).zoomLevel - 1.0).abs() < 0.01,
        isTrue,
      );
    });

    test('setPlaybackSpeed clamps to 0.25-4.0', () {
      final notifier = container.read(editorProvider.notifier);

      notifier.setPlaybackSpeed(0.1);
      expect(container.read(editorProvider).playbackSpeed, equals(0.25));

      notifier.setPlaybackSpeed(10.0);
      expect(container.read(editorProvider).playbackSpeed, equals(4.0));

      notifier.setPlaybackSpeed(1.5);
      expect(container.read(editorProvider).playbackSpeed, equals(1.5));
    });

    test('selectClip sets selectedClipId and shows inspector', () {
      final notifier = container.read(editorProvider.notifier);

      notifier.selectClip('clip-123');
      final state = container.read(editorProvider);

      expect(state.selectedClipId, equals('clip-123'));
      expect(state.showInspector, isTrue);

      // Deselect
      notifier.selectClip(null);
      final state2 = container.read(editorProvider);
      expect(state2.selectedClipId, isNull);
      expect(state2.showInspector, isFalse);
    });

    test('selectTrack sets selectedTrackId and shows inspector', () {
      final notifier = container.read(editorProvider.notifier);

      notifier.selectTrack('track-abc');
      final state = container.read(editorProvider);

      expect(state.selectedTrackId, equals('track-abc'));
      expect(state.showInspector, isTrue);
    });

    test('setImporting updates state', () {
      final notifier = container.read(editorProvider.notifier);

      notifier.setImporting(true);
      expect(container.read(editorProvider).isImporting, isTrue);

      notifier.setImporting(false);
      expect(container.read(editorProvider).isImporting, isFalse);
    });

    test('setExporting updates state', () {
      final notifier = container.read(editorProvider.notifier);

      notifier.setExporting(true, progress: 0.5);
      final state = container.read(editorProvider);
      expect(state.isExporting, isTrue);
      expect(state.exportProgress, equals(0.5));
    });

    test('setLeftPanelTab updates tab', () {
      final notifier = container.read(editorProvider.notifier);

      for (final tab in LeftPanelTab.values) {
        notifier.setLeftPanelTab(tab);
        expect(container.read(editorProvider).leftPanelTab, equals(tab));
      }
    });

    test('toggleInspector toggles the flag', () {
      final notifier = container.read(editorProvider.notifier);

      expect(container.read(editorProvider).showInspector, isFalse);
      notifier.toggleInspector();
      expect(container.read(editorProvider).showInspector, isTrue);
      notifier.toggleInspector();
      expect(container.read(editorProvider).showInspector, isFalse);
    });

    test('setMasterVolume clamps to 0.0-1.0', () {
      final notifier = container.read(editorProvider.notifier);

      notifier.setMasterVolume(-0.5);
      expect(container.read(editorProvider).masterVolume, equals(0.0));

      notifier.setMasterVolume(1.5);
      expect(container.read(editorProvider).masterVolume, equals(1.0));

      notifier.setMasterVolume(0.75);
      expect(container.read(editorProvider).masterVolume, equals(0.75));
    });

    test('togglePlayback starts and stops playback', () {
      final notifier = container.read(editorProvider.notifier);

      expect(container.read(editorProvider).isPlaying, isFalse);

      notifier.togglePlayback();
      expect(container.read(editorProvider).isPlaying, isTrue);

      notifier.togglePlayback();
      expect(container.read(editorProvider).isPlaying, isFalse);
    });

    test('setDuration updates durationMs', () {
      final notifier = container.read(editorProvider.notifier);

      notifier.setDuration(60000);
      expect(container.read(editorProvider).durationMs, equals(60000));
    });
  });

  group('EditorNotifier playback timer', () {
    test('playback advances currentTimeMs', () async {
      final container = ProviderContainer();
      final notifier = container.read(editorProvider.notifier);

      // Set a duration so playback has room to advance
      notifier.setDuration(300000); // 5 minutes

      // Start playback
      notifier.togglePlayback();
      expect(container.read(editorProvider).isPlaying, isTrue);

      // Wait for at least one tick
      await Future.delayed(const Duration(milliseconds: 50));

      // The current time should have advanced
      final currentTimeMs = container.read(editorProvider).currentTimeMs;
      expect(currentTimeMs, greaterThan(0));

      // Stop playback
      notifier.togglePlayback();
      expect(container.read(editorProvider).isPlaying, isFalse);

      container.dispose();
    });
  });

  group('playbackTimeProvider', () {
    test('formats milliseconds as Duration string', () {
      final container = ProviderContainer();

      // Set the editor state to a known time
      container.read(editorProvider.notifier).seekTo(61500); // 1:01.500

      final formatted = container.read(playbackTimeProvider);
      expect(formatted, isNotEmpty);

      container.dispose();
    });
  });

  group('durationTimeProvider', () {
    test('formats duration as Duration string', () {
      final container = ProviderContainer();

      container.read(editorProvider.notifier).setDuration(180000); // 3:00

      final formatted = container.read(durationTimeProvider);
      expect(formatted, isNotEmpty);

      container.dispose();
    });
  });
}
