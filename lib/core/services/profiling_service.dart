import 'dart:async';

/// Real-time performance monitoring provider for the editor.
///
/// Tracks frame budgets, memory usage, cache hit rates, and
/// rendering statistics. Provides data for the performance overlay
/// and enables quality adaptation based on device capability.
///
/// ## Frame Budget
///
/// At 24fps, the frame budget is ~41.7ms. If frame rendering
/// consistently exceeds this, the preview quality is automatically
/// reduced to maintain smooth playback.
class PerformanceMonitor {
  PerformanceMonitor._();
  static final PerformanceMonitor instance = PerformanceMonitor._();

  // ─── Frame Budget Tracking ──────────────────────────────────────

  /// Target frame duration (default 24fps = 41.67ms)
  Duration _targetFrameDuration = const Duration(milliseconds: 41);

  /// Recent frame durations (ring buffer)
  final List<Duration> _frameDurations = [];
  static const int _maxFrameSamples = 120;

  /// Number of frames that exceeded the budget
  int _droppedFrames = 0;

  /// Total frames rendered
  int _totalFrames = 0;

  // ─── Decode Timing ──────────────────────────────────────────────

  /// Recent decode durations
  final List<Duration> _decodeDurations = [];
  static const int _maxDecodeSamples = 60;

  // ─── Render Timing ──────────────────────────────────────────────

  /// Recent render durations
  final List<Duration> _renderDurations = [];
  static const int _maxRenderSamples = 60;

  // ─── Cache Statistics ───────────────────────────────────────────

  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _cacheEvictions = 0;
  int _cachedFrameCount = 0;
  int _pooledBufferCount = 0;
  int _bufferPoolHits = 0;
  int _bufferPoolMisses = 0;

  // ─── Memory ─────────────────────────────────────────────────────

  int _memoryRssBytes = 0;
  int _memoryPeakBytes = 0;
  int _memoryAvailableBytes = 0;
  String _memoryPressureLevel = 'normal';

  // ─── GPU ────────────────────────────────────────────────────────

  bool _gpuAvailable = false;
  String _gpuAdapterName = '';
  String _gpuBackendName = '';

  // ─── Export ─────────────────────────────────────────────────────

  final List<double> _exportSpeeds = [];
  static const int _maxExportSamples = 10;

  // ─── Throughput ─────────────────────────────────────────────────

  double _itemsPerSecond = 0.0;
  double _bytesPerSecond = 0.0;

  // ─── Stream Controller ──────────────────────────────────────────

  final _updateController = StreamController<PerformanceSnapshot>.broadcast();

  /// Stream of performance updates (emit every frame)
  Stream<PerformanceSnapshot> get onUpdate => _updateController.stream;

  // ─── Recording Methods ──────────────────────────────────────────

  /// Record a frame rendering duration
  void recordFrameDuration(Duration duration) {
    _frameDurations.add(duration);
    if (_frameDurations.length > _maxFrameSamples) {
      _frameDurations.removeAt(0);
    }
    _totalFrames++;
    if (duration > _targetFrameDuration) {
      _droppedFrames++;
    }
  }

  /// Record a frame decode duration
  void recordDecodeDuration(Duration duration) {
    _decodeDurations.add(duration);
    if (_decodeDurations.length > _maxDecodeSamples) {
      _decodeDurations.removeAt(0);
    }
  }

  /// Record a render duration
  void recordRenderDuration(Duration duration) {
    _renderDurations.add(duration);
    if (_renderDurations.length > _maxRenderSamples) {
      _renderDurations.removeAt(0);
    }
  }

  /// Record cache statistics from the engine
  void recordCacheStats({
    required int hits,
    required int misses,
    required int evictions,
    required int cachedFrames,
  }) {
    _cacheHits = hits;
    _cacheMisses = misses;
    _cacheEvictions = evictions;
    _cachedFrameCount = cachedFrames;
  }

  /// Record buffer pool statistics
  void recordBufferPoolStats({
    required int pooledCount,
    required int hits,
    required int misses,
  }) {
    _pooledBufferCount = pooledCount;
    _bufferPoolHits = hits;
    _bufferPoolMisses = misses;
  }

  /// Record memory statistics from the engine
  void recordMemoryStats({
    required int rssBytes,
    required int peakBytes,
    required int availableBytes,
    required String pressureLevel,
  }) {
    _memoryRssBytes = rssBytes;
    _memoryPeakBytes = peakBytes;
    _memoryAvailableBytes = availableBytes;
    _memoryPressureLevel = pressureLevel;
  }

  /// Record GPU status from the engine
  void recordGpuStats({
    required bool available,
    required String adapterName,
    required String backendName,
  }) {
    _gpuAvailable = available;
    _gpuAdapterName = adapterName;
    _gpuBackendName = backendName;
  }

  /// Record an export speed in frames per second
  void recordExportSpeed(double fps) {
    _exportSpeeds.add(fps);
    if (_exportSpeeds.length > _maxExportSamples) {
      _exportSpeeds.removeAt(0);
    }
  }

  /// Record throughput metrics
  void recordThroughput({
    required double itemsPerSecond,
    required double bytesPerSecond,
  }) {
    _itemsPerSecond = itemsPerSecond;
    _bytesPerSecond = bytesPerSecond;
  }

  /// Set the target frame rate
  void setTargetFps(double fps) {
    if (fps > 0) {
      _targetFrameDuration = Duration(microseconds: (1000000 / fps).round());
    }
  }

  // ─── Computed Properties ─────────────────────────────────────────

  /// Average frame duration over the sample window
  Duration get averageFrameDuration {
    if (_frameDurations.isEmpty) return Duration.zero;
    final totalMicros =
        _frameDurations.fold<int>(0, (sum, d) => sum + d.inMicroseconds);
    return Duration(microseconds: totalMicros ~/ _frameDurations.length);
  }

  /// Average FPS over the sample window
  double get averageFps {
    final avg = averageFrameDuration;
    if (avg.inMicroseconds == 0) return 0.0;
    return 1000000.0 / avg.inMicroseconds;
  }

  /// Frame drop rate (0.0 to 1.0)
  double get dropRate {
    if (_totalFrames == 0) return 0.0;
    return _droppedFrames / _totalFrames;
  }

  /// Cache hit rate (0.0 to 1.0)
  double get cacheHitRate {
    final total = _cacheHits + _cacheMisses;
    if (total == 0) return 0.0;
    return _cacheHits / total;
  }

  /// Buffer pool hit rate (0.0 to 1.0)
  double get bufferPoolHitRate {
    final total = _bufferPoolHits + _bufferPoolMisses;
    if (total == 0) return 0.0;
    return _bufferPoolHits / total;
  }

  /// Average decode duration
  Duration get averageDecodeDuration {
    if (_decodeDurations.isEmpty) return Duration.zero;
    final totalMicros =
        _decodeDurations.fold<int>(0, (sum, d) => sum + d.inMicroseconds);
    return Duration(microseconds: totalMicros ~/ _decodeDurations.length);
  }

  /// Average render duration
  Duration get averageRenderDuration {
    if (_renderDurations.isEmpty) return Duration.zero;
    final totalMicros =
        _renderDurations.fold<int>(0, (sum, d) => sum + d.inMicroseconds);
    return Duration(microseconds: totalMicros ~/ _renderDurations.length);
  }

  /// 95th percentile frame duration
  Duration get p95FrameDuration {
    if (_frameDurations.isEmpty) return Duration.zero;
    final sorted = List<Duration>.from(_frameDurations)..sort();
    final idx = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  /// Average export speed in fps
  double get averageExportSpeed {
    if (_exportSpeeds.isEmpty) return 0;
    return _exportSpeeds.reduce((a, b) => a + b) / _exportSpeeds.length;
  }

  /// Whether the current performance is on budget
  bool get isOnBudget => averageFrameDuration <= _targetFrameDuration;

  /// Memory usage in MB
  double get memoryUsageMb => _memoryRssBytes / (1024 * 1024);

  /// Memory utilization as a fraction of available memory
  double get memoryUtilization {
    if (_memoryAvailableBytes == 0) return 0.0;
    return _memoryRssBytes / _memoryAvailableBytes;
  }

  /// Get the target FPS
  double get targetFps {
    if (_targetFrameDuration.inMicroseconds == 0) return 0;
    return 1000000.0 / _targetFrameDuration.inMicroseconds;
  }

  /// Whether memory is under pressure
  bool get isMemoryPressure =>
      _memoryPressureLevel == 'warning' || _memoryPressureLevel == 'critical';

  // ─── Snapshot ────────────────────────────────────────────────────

  /// Take a snapshot of all performance metrics
  PerformanceSnapshot takeSnapshot() {
    return PerformanceSnapshot(
      timestamp: DateTime.now(),
      averageFps: averageFps,
      targetFps: targetFps,
      droppedFrames: _droppedFrames,
      totalFrames: _totalFrames,
      dropRate: dropRate,
      averageFrameDuration: averageFrameDuration,
      p95FrameDuration: p95FrameDuration,
      averageDecodeDuration: averageDecodeDuration,
      averageRenderDuration: averageRenderDuration,
      cacheHitRate: cacheHitRate,
      cacheHits: _cacheHits,
      cacheMisses: _cacheMisses,
      cacheEvictions: _cacheEvictions,
      cachedFrameCount: _cachedFrameCount,
      bufferPoolHitRate: bufferPoolHitRate,
      pooledBufferCount: _pooledBufferCount,
      memoryRssMb: memoryUsageMb,
      memoryPeakMb: _memoryPeakBytes / (1024 * 1024),
      memoryAvailableMb: _memoryAvailableBytes / (1024 * 1024),
      memoryPressureLevel: _memoryPressureLevel,
      gpuAvailable: _gpuAvailable,
      gpuAdapterName: _gpuAdapterName,
      gpuBackendName: _gpuBackendName,
      averageExportSpeed: averageExportSpeed,
      itemsPerSecond: _itemsPerSecond,
      bytesPerSecondMb: _bytesPerSecond / (1024 * 1024),
      isOnBudget: isOnBudget,
    );
  }

  /// Emit a performance update snapshot
  void emitUpdate() {
    if (!_updateController.isClosed) {
      _updateController.add(takeSnapshot());
    }
  }

  /// Reset all statistics
  void reset() {
    _frameDurations.clear();
    _decodeDurations.clear();
    _renderDurations.clear();
    _exportSpeeds.clear();
    _droppedFrames = 0;
    _totalFrames = 0;
    _cacheHits = 0;
    _cacheMisses = 0;
    _cacheEvictions = 0;
    _cachedFrameCount = 0;
    _pooledBufferCount = 0;
    _bufferPoolHits = 0;
    _bufferPoolMisses = 0;
    _itemsPerSecond = 0.0;
    _bytesPerSecond = 0.0;
  }

  /// Dispose the monitor
  void dispose() {
    _updateController.close();
  }

  /// Get a summary map suitable for logging or reporting
  Map<String, dynamic> toMap() {
    final snapshot = takeSnapshot();
    return {
      'fps': snapshot.averageFps.toStringAsFixed(1),
      'targetFps': snapshot.targetFps.toStringAsFixed(1),
      'dropRate': '${(snapshot.dropRate * 100).toStringAsFixed(1)}%',
      'avgFrameMs': snapshot.averageFrameDuration.inMilliseconds,
      'p95FrameMs': snapshot.p95FrameDuration.inMilliseconds,
      'avgDecodeMs': snapshot.averageDecodeDuration.inMilliseconds,
      'avgRenderMs': snapshot.averageRenderDuration.inMilliseconds,
      'cacheHitRate': '${(snapshot.cacheHitRate * 100).toStringAsFixed(1)}%',
      'memoryMb': snapshot.memoryRssMb.toStringAsFixed(1),
      'memoryPressure': snapshot.memoryPressureLevel,
      'gpuAvailable': snapshot.gpuAvailable,
      'gpuAdapter': snapshot.gpuAdapterName,
      'onBudget': snapshot.isOnBudget,
    };
  }
}

/// Immutable snapshot of performance metrics at a point in time
class PerformanceSnapshot {
  const PerformanceSnapshot({
    required this.timestamp,
    required this.averageFps,
    required this.targetFps,
    required this.droppedFrames,
    required this.totalFrames,
    required this.dropRate,
    required this.averageFrameDuration,
    required this.p95FrameDuration,
    required this.averageDecodeDuration,
    required this.averageRenderDuration,
    required this.cacheHitRate,
    required this.cacheHits,
    required this.cacheMisses,
    required this.cacheEvictions,
    required this.cachedFrameCount,
    required this.bufferPoolHitRate,
    required this.pooledBufferCount,
    required this.memoryRssMb,
    required this.memoryPeakMb,
    required this.memoryAvailableMb,
    required this.memoryPressureLevel,
    required this.gpuAvailable,
    required this.gpuAdapterName,
    required this.gpuBackendName,
    required this.averageExportSpeed,
    required this.itemsPerSecond,
    required this.bytesPerSecondMb,
    required this.isOnBudget,
  });
  final DateTime timestamp;

  // Frame timing
  final double averageFps;
  final double targetFps;
  final int droppedFrames;
  final int totalFrames;
  final double dropRate;
  final Duration averageFrameDuration;
  final Duration p95FrameDuration;
  final Duration averageDecodeDuration;
  final Duration averageRenderDuration;

  // Cache
  final double cacheHitRate;
  final int cacheHits;
  final int cacheMisses;
  final int cacheEvictions;
  final int cachedFrameCount;

  // Buffer pool
  final double bufferPoolHitRate;
  final int pooledBufferCount;

  // Memory
  final double memoryRssMb;
  final double memoryPeakMb;
  final double memoryAvailableMb;
  final String memoryPressureLevel;

  // GPU
  final bool gpuAvailable;
  final String gpuAdapterName;
  final String gpuBackendName;

  // Export
  final double averageExportSpeed;

  // Throughput
  final double itemsPerSecond;
  final double bytesPerSecondMb;

  // Overall
  final bool isOnBudget;

  /// Get a color-coded FPS status
  String get fpsStatus {
    if (averageFps >= targetFps * 0.95) return 'good';
    if (averageFps >= targetFps * 0.75) return 'warning';
    return 'critical';
  }

  /// Get a color-coded memory status
  String get memoryStatus {
    if (memoryPressureLevel == 'normal') return 'good';
    if (memoryPressureLevel == 'warning') return 'warning';
    return 'critical';
  }

  @override
  String toString() {
    return 'PerformanceSnapshot(fps=${averageFps.toStringAsFixed(1)}/$targetFps, '
        'drop=${(dropRate * 100).toStringAsFixed(1)}%, '
        'cache=${(cacheHitRate * 100).toStringAsFixed(1)}%, '
        'mem=${memoryRssMb.toStringAsFixed(0)}MB, '
        'gpu=$gpuAvailable, '
        'budget=$isOnBudget)';
  }
}
