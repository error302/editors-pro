import 'dart:developer' as developer;

/// Lightweight performance monitoring service for the app.
///
/// Tracks key lifecycle timings and can be extended to monitor
/// frame decode times, memory pressure events, and export speed.
class PerformanceService {
  PerformanceService._();

  static final PerformanceService instance = PerformanceService._();

  // ─── Cold-start timing ────────────────────────────────────────

  // Timing may be queried before startup has been marked.
  // ignore: use_late_for_private_fields_and_variables
  DateTime? _appStartTime;
  DateTime? _engineReadyTime;

  /// Mark the moment the app begins initialisation.
  void markAppStart() {
    _appStartTime = DateTime.now();
  }

  /// Mark the moment the Rust engine is fully ready.
  void markEngineReady() {
    _engineReadyTime = DateTime.now();
  }

  /// Duration from [markAppStart] to [markEngineReady], or `null`
  /// if either mark has not been set yet.
  Duration? get coldStartDuration =>
      _engineReadyTime?.difference(_appStartTime!);

  // ─── Frame decode tracking ────────────────────────────────────

  final List<Duration> _recentDecodeTimes = [];
  static const _maxDecodeSamples = 60;

  /// Record a single frame decode duration.
  void recordFrameDecode(Duration duration) {
    _recentDecodeTimes.add(duration);
    if (_recentDecodeTimes.length > _maxDecodeSamples) {
      _recentDecodeTimes.removeAt(0);
    }
  }

  /// Average frame decode time over the recent sample window.
  Duration get averageDecodeTime {
    if (_recentDecodeTimes.isEmpty) return Duration.zero;
    final totalMicros =
        _recentDecodeTimes.fold<int>(0, (sum, d) => sum + d.inMicroseconds);
    return Duration(microseconds: totalMicros ~/ _recentDecodeTimes.length);
  }

  // ─── Memory pressure ──────────────────────────────────────────

  int _memoryPressureEvents = 0;

  /// Record a memory pressure event from the OS.
  void recordMemoryPressure() {
    _memoryPressureEvents++;
    developer.log(
      'Memory pressure event (total: $_memoryPressureEvents)',
      name: 'PerformanceService',
    );
  }

  /// Total number of memory pressure events since app start.
  int get memoryPressureEventCount => _memoryPressureEvents;

  // ─── Export speed tracking ────────────────────────────────────

  final List<double> _exportSpeeds = [];
  static const _maxExportSamples = 10;

  /// Record an export speed in frames-per-second.
  void recordExportSpeed(double fps) {
    _exportSpeeds.add(fps);
    if (_exportSpeeds.length > _maxExportSamples) {
      _exportSpeeds.removeAt(0);
    }
  }

  /// Average export speed in fps over the recent sample window.
  double get averageExportSpeed {
    if (_exportSpeeds.isEmpty) return 0;
    return _exportSpeeds.reduce((a, b) => a + b) / _exportSpeeds.length;
  }

  // ─── Diagnostics ──────────────────────────────────────────────

  /// Return a summary map suitable for logging or reporting.
  Map<String, dynamic> toMap() {
    return {
      'coldStartMs': coldStartDuration?.inMilliseconds,
      'avgDecodeMs': averageDecodeTime.inMilliseconds,
      'memoryPressureEvents': _memoryPressureEvents,
      'avgExportFps': averageExportSpeed.toStringAsFixed(1),
    };
  }
}
