import 'package:flutter_test/flutter_test.dart';
import 'package:editors_pro/core/services/profiling_service.dart';

void main() {
  group('PerformanceMonitor', () {
    late PerformanceMonitor monitor;

    setUp(() {
      monitor = PerformanceMonitor.instance;
      monitor.reset();
    });

    test('initial state is clean', () {
      expect(monitor.averageFps, equals(0.0));
      expect(monitor.dropRate, equals(0.0));
      expect(monitor.cacheHitRate, equals(0.0));
      expect(monitor.isOnBudget, isTrue);
      expect(monitor.isMemoryPressure, isFalse);
    });

    test('recordFrameDuration tracks frames', () {
      monitor.setTargetFps(24.0);
      monitor.recordFrameDuration(const Duration(milliseconds: 41));
      monitor.recordFrameDuration(const Duration(milliseconds: 42));
      monitor.recordFrameDuration(const Duration(milliseconds: 40));

      expect(monitor.averageFps, greaterThan(0.0));
      expect(monitor.dropRate, closeTo(1 / 3, 0.001));
    });

    test('detects dropped frames', () {
      monitor.setTargetFps(24.0);
      // Fast frames
      for (int i = 0; i < 10; i++) {
        monitor.recordFrameDuration(const Duration(milliseconds: 20));
      }
      // Slow frames (over budget)
      for (int i = 0; i < 5; i++) {
        monitor.recordFrameDuration(const Duration(milliseconds: 80));
      }

      expect(monitor.dropRate, greaterThan(0.0));
    });

    test('recordDecodeDuration tracks decode times', () {
      monitor.recordDecodeDuration(const Duration(milliseconds: 5));
      monitor.recordDecodeDuration(const Duration(milliseconds: 8));
      monitor.recordDecodeDuration(const Duration(milliseconds: 6));

      expect(monitor.averageDecodeDuration.inMilliseconds, greaterThanOrEqualTo(5));
      expect(monitor.averageDecodeDuration.inMilliseconds, lessThanOrEqualTo(8));
    });

    test('recordRenderDuration tracks render times', () {
      monitor.recordRenderDuration(const Duration(milliseconds: 20));
      monitor.recordRenderDuration(const Duration(milliseconds: 30));

      expect(monitor.averageRenderDuration.inMilliseconds, greaterThanOrEqualTo(20));
    });

    test('cache statistics', () {
      monitor.recordCacheStats(
        hits: 80,
        misses: 20,
        evictions: 5,
        cachedFrames: 10,
      );

      expect(monitor.cacheHitRate, closeTo(0.8, 0.01));
    });

    test('buffer pool statistics', () {
      monitor.recordBufferPoolStats(
        pooledCount: 6,
        hits: 90,
        misses: 10,
      );

      expect(monitor.bufferPoolHitRate, closeTo(0.9, 0.01));
    });

    test('memory statistics', () {
      monitor.recordMemoryStats(
        rssBytes: 256 * 1024 * 1024,
        peakBytes: 300 * 1024 * 1024,
        availableBytes: 1024 * 1024 * 1024,
        pressureLevel: 'normal',
      );

      expect(monitor.memoryUsageMb, closeTo(256.0, 1.0));
      expect(monitor.isMemoryPressure, isFalse);
    });

    test('memory pressure detection', () {
      monitor.recordMemoryStats(
        rssBytes: 800 * 1024 * 1024,
        peakBytes: 850 * 1024 * 1024,
        availableBytes: 1024 * 1024 * 1024,
        pressureLevel: 'warning',
      );

      expect(monitor.isMemoryPressure, isTrue);
    });

    test('GPU statistics', () {
      monitor.recordGpuStats(
        available: true,
        adapterName: 'Adreno 740',
        backendName: 'Vulkan',
      );

      // Verify the snapshot includes GPU info
      final snapshot = monitor.takeSnapshot();
      expect(snapshot.gpuAvailable, isTrue);
      expect(snapshot.gpuAdapterName, equals('Adreno 740'));
      expect(snapshot.gpuBackendName, equals('Vulkan'));
    });

    test('export speed tracking', () {
      monitor.recordExportSpeed(15.0);
      monitor.recordExportSpeed(20.0);
      monitor.recordExportSpeed(18.0);

      expect(monitor.averageExportSpeed, greaterThan(14.0));
      expect(monitor.averageExportSpeed, lessThan(21.0));
    });

    test('p95 frame duration', () {
      // 90 fast frames
      for (int i = 0; i < 90; i++) {
        monitor.recordFrameDuration(const Duration(milliseconds: 30));
      }
      // 10 slow frames
      for (int i = 0; i < 10; i++) {
        monitor.recordFrameDuration(const Duration(milliseconds: 60));
      }

      final p95 = monitor.p95FrameDuration;
      expect(p95.inMilliseconds, greaterThanOrEqualTo(30));
    });

    test('setTargetFps', () {
      monitor.setTargetFps(60.0);
      expect(monitor.targetFps, closeTo(60.0, 1.0));
    });

    test('takeSnapshot returns immutable snapshot', () {
      monitor.setTargetFps(24.0);
      monitor.recordFrameDuration(const Duration(milliseconds: 41));

      final snapshot = monitor.takeSnapshot();
      expect(snapshot.averageFps, greaterThan(0.0));
      expect(snapshot.targetFps, closeTo(24.0, 1.0));
      expect(snapshot.timestamp, isNotNull);
    });

    test('snapshot fpsStatus', () {
      monitor.setTargetFps(24.0);
      monitor.recordFrameDuration(const Duration(milliseconds: 41));

      final snapshot = monitor.takeSnapshot();
      expect(snapshot.fpsStatus, equals('good'));
    });

    test('snapshot memoryStatus', () {
      monitor.recordMemoryStats(
        rssBytes: 256 * 1024 * 1024,
        peakBytes: 300 * 1024 * 1024,
        availableBytes: 1024 * 1024 * 1024,
        pressureLevel: 'normal',
      );

      final snapshot = monitor.takeSnapshot();
      expect(snapshot.memoryStatus, equals('good'));
    });

    test('snapshot toString', () {
      monitor.setTargetFps(24.0);
      monitor.recordFrameDuration(const Duration(milliseconds: 41));

      final snapshot = monitor.takeSnapshot();
      final str = snapshot.toString();
      expect(str, contains('fps'));
      expect(str, contains('mem'));
      expect(str, contains('gpu'));
    });

    test('reset clears all statistics', () {
      monitor.setTargetFps(24.0);
      monitor.recordFrameDuration(const Duration(milliseconds: 41));
      monitor.recordDecodeDuration(const Duration(milliseconds: 5));
      monitor.recordCacheStats(hits: 10, misses: 5, evictions: 1, cachedFrames: 3);
      monitor.recordMemoryStats(
        rssBytes: 256 * 1024 * 1024,
        peakBytes: 300 * 1024 * 1024,
        availableBytes: 1024 * 1024 * 1024,
        pressureLevel: 'normal',
      );

      monitor.reset();

      expect(monitor.averageFps, equals(0.0));
      expect(monitor.cacheHitRate, equals(0.0));
    });

    test('toMap returns complete summary', () {
      monitor.setTargetFps(24.0);
      monitor.recordFrameDuration(const Duration(milliseconds: 41));
      monitor.recordCacheStats(hits: 10, misses: 2, evictions: 1, cachedFrames: 5);

      final map = monitor.toMap();
      expect(map.containsKey('fps'), isTrue);
      expect(map.containsKey('targetFps'), isTrue);
      expect(map.containsKey('dropRate'), isTrue);
      expect(map.containsKey('cacheHitRate'), isTrue);
      expect(map.containsKey('memoryMb'), isTrue);
      expect(map.containsKey('gpuAvailable'), isTrue);
      expect(map.containsKey('onBudget'), isTrue);
    });

    test('onUpdate stream emits snapshots', () async {
      monitor.setTargetFps(24.0);
      monitor.recordFrameDuration(const Duration(milliseconds: 41));

      final future = monitor.onUpdate.first;
      monitor.emitUpdate();

      final snapshot = await future;
      expect(snapshot, isNotNull);
      expect(snapshot.averageFps, greaterThan(0.0));
    });

    test('throughput tracking', () {
      monitor.recordThroughput(
        itemsPerSecond: 24.0,
        bytesPerSecond: 200 * 1024 * 1024,
      );

      final snapshot = monitor.takeSnapshot();
      expect(snapshot.itemsPerSecond, equals(24.0));
      expect(snapshot.bytesPerSecondMb, closeTo(200.0, 1.0));
    });
  });
}
