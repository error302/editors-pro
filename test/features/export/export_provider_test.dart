import 'dart:async';

import 'package:editors_pro/features/export/providers/export_provider.dart';
import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── ExportState ─────────────────────────────────────────────────────

  group('ExportState', () {
    test('defaults are correct', () {
      const state = ExportState();

      expect(state.isExporting, isFalse);
      expect(state.progress, equals(0));
      expect(state.stageName, isEmpty);
      expect(state.currentFrame, equals(0));
      expect(state.totalFrames, equals(0));
      expect(state.estimatedSecondsRemaining, equals(0));
      expect(state.outputPath, isNull);
      expect(state.fileSizeHuman, isNull);
      expect(state.error, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      const state = ExportState(
        isExporting: true,
        progress: 0.5,
        stageName: 'Encoding',
        currentFrame: 150,
        totalFrames: 300,
        estimatedSecondsRemaining: 30,
        outputPath: '/tmp/out.mp4',
        fileSizeHuman: '12.3 MB',
        error: null,
      );

      final copied = state.copyWith(progress: 0.75);

      expect(copied.isExporting, isTrue);
      expect(copied.progress, equals(0.75));
      expect(copied.stageName, equals('Encoding'));
      expect(copied.currentFrame, equals(150));
      expect(copied.totalFrames, equals(300));
      expect(copied.estimatedSecondsRemaining, equals(30));
      expect(copied.outputPath, equals('/tmp/out.mp4'));
      expect(copied.fileSizeHuman, equals('12.3 MB'));
      expect(copied.error, isNull);
    });

    test('copyWith can set error', () {
      const state = ExportState();
      final errored = state.copyWith(error: 'Something went wrong');

      expect(errored.error, equals('Something went wrong'));
    });

    test('copyWith clearError removes error', () {
      const state = ExportState(error: 'Old error');
      final cleared = state.copyWith(clearError: true);

      expect(cleared.error, isNull);
    });

    test('copyWith clearError takes precedence over setting error', () {
      const state = ExportState(error: 'Old error');
      // When clearError is true, the error parameter is ignored.
      final cleared = state.copyWith(error: 'New error', clearError: true);

      expect(cleared.error, isNull);
    });

    test('copyWith without clearError preserves existing error', () {
      const state = ExportState(error: 'Old error');
      final copied = state.copyWith(isExporting: true);

      expect(copied.error, equals('Old error'));
    });

    // ─── isComplete ──────────────────────────────────────────────────

    test('isComplete is false by default', () {
      const state = ExportState();
      expect(state.isComplete, isFalse);
    });

    test(
        'isComplete is true when not exporting, progress 1.0, path set, no error',
        () {
      const state = ExportState(
        isExporting: false,
        progress: 1.0,
        outputPath: '/tmp/out.mp4',
      );
      expect(state.isComplete, isTrue);
    });

    test('isComplete is false when still exporting', () {
      const state = ExportState(
        isExporting: true,
        progress: 1.0,
        outputPath: '/tmp/out.mp4',
      );
      expect(state.isComplete, isFalse);
    });

    test('isComplete is false when progress < 1.0', () {
      const state = ExportState(
        isExporting: false,
        progress: 0.99,
        outputPath: '/tmp/out.mp4',
      );
      expect(state.isComplete, isFalse);
    });

    test('isComplete is false when outputPath is null', () {
      const state = ExportState(
        isExporting: false,
        progress: 1.0,
        outputPath: null,
      );
      expect(state.isComplete, isFalse);
    });

    test('isComplete is false when there is an error', () {
      const state = ExportState(
        isExporting: false,
        progress: 1.0,
        outputPath: '/tmp/out.mp4',
        error: 'Something failed',
      );
      expect(state.isComplete, isFalse);
    });

    // ─── hasError ───────────────────────────────────────────────────

    test('hasError is false by default', () {
      const state = ExportState();
      expect(state.hasError, isFalse);
    });

    test('hasError is true when error is set and not exporting', () {
      const state = ExportState(
        isExporting: false,
        error: 'Export failed',
      );
      expect(state.hasError, isTrue);
    });

    test('hasError is false when error is set but still exporting', () {
      const state = ExportState(
        isExporting: true,
        error: 'Something went wrong',
      );
      expect(state.hasError, isFalse);
    });

    test('hasError is false when error is null', () {
      const state = ExportState(isExporting: false, error: null);
      expect(state.hasError, isFalse);
    });

    // ─── progressText ───────────────────────────────────────────────

    test('progressText formats 0 as 0%', () {
      const state = ExportState(progress: 0);
      expect(state.progressText, equals('0%'));
    });

    test('progressText formats 0.45 as 45%', () {
      const state = ExportState(progress: 0.45);
      expect(state.progressText, equals('45%'));
    });

    test('progressText formats 1.0 as 100%', () {
      const state = ExportState(progress: 1.0);
      expect(state.progressText, equals('100%'));
    });

    test('progressText rounds correctly', () {
      // 0.456 * 100 = 45.6 → rounds to 46
      const state = ExportState(progress: 0.456);
      expect(state.progressText, equals('46%'));
    });

    // ─── estimatedTimeText ──────────────────────────────────────────

    test('estimatedTimeText is empty when seconds <= 0', () {
      const state = ExportState(estimatedSecondsRemaining: 0);
      expect(state.estimatedTimeText, isEmpty);
    });

    test('estimatedTimeText formats seconds only', () {
      const state = ExportState(estimatedSecondsRemaining: 45);
      expect(state.estimatedTimeText, equals('~45s remaining'));
    });

    test('estimatedTimeText formats minutes and seconds', () {
      const state = ExportState(estimatedSecondsRemaining: 150);
      // 150 seconds = 2m 30s
      expect(state.estimatedTimeText, equals('~2m 30s remaining'));
    });

    test('estimatedTimeText formats exact minutes', () {
      const state = ExportState(estimatedSecondsRemaining: 120);
      // 120 seconds = 2m 0s
      expect(state.estimatedTimeText, equals('~2m 0s remaining'));
    });

    test('estimatedTimeText handles large values', () {
      const state = ExportState(estimatedSecondsRemaining: 3661);
      // 3661 seconds = 61m 1s
      expect(state.estimatedTimeText, equals('~61m 1s remaining'));
    });

    // ─── frameProgressText ──────────────────────────────────────────

    test('frameProgressText is empty when totalFrames <= 0', () {
      const state = ExportState(currentFrame: 10, totalFrames: 0);
      expect(state.frameProgressText, isEmpty);
    });

    test('frameProgressText formats frame progress', () {
      const state = ExportState(currentFrame: 150, totalFrames: 300);
      expect(state.frameProgressText, equals('150 / 300 frames'));
    });
  });

  // ─── ExportNotifier ──────────────────────────────────────────────────

  group('ExportNotifier', () {
    test('initial state has defaults', () {
      final notifier = ExportNotifier();
      expect(notifier.state.isExporting, isFalse);
      expect(notifier.state.progress, equals(0));
      expect(notifier.state.error, isNull);
    });

    test('reset returns to default state', () {
      final notifier = ExportNotifier();
      // Simulate a completed state
      notifier.state = const ExportState(
        isExporting: false,
        progress: 1.0,
        outputPath: '/tmp/out.mp4',
        fileSizeHuman: '10 MB',
      );

      notifier.reset();

      expect(notifier.state.isExporting, isFalse);
      expect(notifier.state.progress, equals(0));
      expect(notifier.state.outputPath, isNull);
      expect(notifier.state.fileSizeHuman, isNull);
    });

    test('prepares cancellation before an immediate cancel can arrive',
        () async {
      final api = _FakeExportApi();
      final notifier = ExportNotifier(engineApi: api);
      final export = notifier.startExport(
        preset: '720p',
        outputPath: '/tmp/test-export.mp4',
      );

      expect(api.events, ['prepare']);
      await notifier.cancelExport();
      expect(api.events, containsAllInOrder(['prepare', 'cancel']));

      await Future<void>.delayed(Duration.zero);
      expect(api.events, contains('export'));
      api.result.complete(
        const BridgeExportResult(
          success: false,
          outputPath: '',
          fileSizeHuman: '',
          errorMessage: 'Export canceled',
        ),
      );
      await export;

      expect(notifier.state.isExporting, isFalse);
      expect(notifier.state.error, 'Export canceled');
      notifier.dispose();
    });
  });

  // ─── ExportPreset ────────────────────────────────────────────────────

  group('ExportPreset', () {
    test('all presets list has 5 entries', () {
      expect(ExportPreset.all.length, equals(5));
    });

    test('720p preset has correct values', () {
      const preset = ExportPreset(
        name: '720p',
        width: 1280,
        height: 720,
        bitrateKbps: 5000,
        description: 'HD 720p — Small file, fast export',
      );

      expect(preset.name, equals('720p'));
      expect(preset.width, equals(1280));
      expect(preset.height, equals(720));
      expect(preset.bitrateKbps, equals(5000));
    });

    test('1080p preset has correct values', () {
      const preset = ExportPreset(
        name: '1080p',
        width: 1920,
        height: 1080,
        bitrateKbps: 10000,
        description: 'Full HD — Best balance of quality and size',
      );

      expect(preset.name, equals('1080p'));
      expect(preset.width, equals(1920));
      expect(preset.height, equals(1080));
      expect(preset.bitrateKbps, equals(10000));
    });

    test('4K preset has correct values', () {
      const preset = ExportPreset(
        name: '4K',
        width: 3840,
        height: 2160,
        bitrateKbps: 40000,
        description: 'Ultra HD — Maximum quality, large file',
      );

      expect(preset.name, equals('4K'));
      expect(preset.width, equals(3840));
      expect(preset.height, equals(2160));
      expect(preset.bitrateKbps, equals(40000));
    });

    test('Social Vertical preset has correct values', () {
      const preset = ExportPreset(
        name: 'Social Vertical',
        width: 1080,
        height: 1920,
        bitrateKbps: 8000,
        description: '9:16 — TikTok, Reels, Shorts',
      );

      expect(preset.name, equals('Social Vertical'));
      expect(preset.width, equals(1080));
      expect(preset.height, equals(1920));
      expect(preset.bitrateKbps, equals(8000));
    });

    test('Social Square preset has correct values', () {
      const preset = ExportPreset(
        name: 'Social Square',
        width: 1080,
        height: 1080,
        bitrateKbps: 6000,
        description: '1:1 — Instagram posts',
      );

      expect(preset.name, equals('Social Square'));
      expect(preset.width, equals(1080));
      expect(preset.height, equals(1080));
      expect(preset.bitrateKbps, equals(6000));
    });

    test('all presets are const', () {
      // This just verifies the list exists and is accessible.
      for (final preset in ExportPreset.all) {
        expect(preset.name, isNotEmpty);
        expect(preset.width, greaterThan(0));
        expect(preset.height, greaterThan(0));
        expect(preset.bitrateKbps, greaterThan(0));
        expect(preset.description, isNotEmpty);
      }
    });

    test('preset names are unique', () {
      final names = ExportPreset.all.map((p) => p.name).toList();
      final uniqueNames = names.toSet();
      expect(names.length, equals(uniqueNames.length));
    });
  });
}

class _FakeExportApi extends EditorsProEngineApi {
  _FakeExportApi() : super.noOp();

  final events = <String>[];
  final result = Completer<BridgeExportResult>();

  @override
  void prepareExport() => events.add('prepare');

  @override
  Future<void> cancelExport() async {
    events.add('cancel');
  }

  @override
  Future<BridgeExportResult> exportVideoWithCallback({
    required String outputPath,
    required BridgeExportSettings settings,
  }) {
    events.add('export');
    return result.future;
  }
}
