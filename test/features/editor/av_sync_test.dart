import 'package:flutter_test/flutter_test.dart';

import 'package:editors_pro/features/editor/services/av_sync_coordinator.dart';

void main() {
  group('AvSyncDiagnostics', () {
    test('calculates driftExceededRatio correctly', () {
      const diagnostics = AvSyncDiagnostics(
        syncTickCount: 100,
        driftExceededCount: 5,
        totalDriftCorrectionMs: 150,
        smoothedDriftMs: 0,
        audioInitialized: true,
        detectedLatencyMs: 0,
        adaptiveBufferAheadMs: 400,
        adaptiveChunkMs: 200,
        frameRate: 30,
      );

      expect(diagnostics.driftExceededRatio, closeTo(0.05, 0.001));
    });

    test('driftExceededRatio returns 0 when no ticks', () {
      const diagnostics = AvSyncDiagnostics(
        syncTickCount: 0,
        driftExceededCount: 0,
        totalDriftCorrectionMs: 0,
        smoothedDriftMs: 0,
        audioInitialized: false,
        detectedLatencyMs: 0,
        adaptiveBufferAheadMs: 400,
        adaptiveChunkMs: 200,
        frameRate: 30,
      );

      expect(diagnostics.driftExceededRatio, equals(0.0));
    });

    test('calculates avgCorrectionMs correctly', () {
      const diagnostics = AvSyncDiagnostics(
        syncTickCount: 50,
        driftExceededCount: 10,
        totalDriftCorrectionMs: 500,
        smoothedDriftMs: 0,
        audioInitialized: true,
        detectedLatencyMs: 0,
        adaptiveBufferAheadMs: 400,
        adaptiveChunkMs: 200,
        frameRate: 30,
      );

      expect(diagnostics.avgCorrectionMs, equals(10.0));
    });

    test('avgCorrectionMs returns 0 when no ticks', () {
      const diagnostics = AvSyncDiagnostics(
        syncTickCount: 0,
        driftExceededCount: 0,
        totalDriftCorrectionMs: 0,
        smoothedDriftMs: 0,
        audioInitialized: false,
        detectedLatencyMs: 0,
        adaptiveBufferAheadMs: 400,
        adaptiveChunkMs: 200,
        frameRate: 30,
      );

      expect(diagnostics.avgCorrectionMs, equals(0.0));
    });

    test('toString contains key info', () {
      const diagnostics = AvSyncDiagnostics(
        syncTickCount: 100,
        driftExceededCount: 5,
        totalDriftCorrectionMs: 150,
        smoothedDriftMs: 0,
        audioInitialized: true,
        detectedLatencyMs: 0,
        adaptiveBufferAheadMs: 400,
        adaptiveChunkMs: 200,
        frameRate: 30,
      );

      final str = diagnostics.toString();
      expect(str, contains('ticks=100'));
      expect(str, contains('drift_exceeded=5'));
      expect(str, contains('audio=true'));
    });
  });
}
