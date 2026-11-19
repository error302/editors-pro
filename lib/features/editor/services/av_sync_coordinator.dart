import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/audio_player_service.dart';
import '../../../core/services/engine_service.dart';
import '../providers/editor_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════════════════════

/// Coordinates video timeline updates and queued native preview PCM.
///
/// Video positions derive from elapsed wall-clock time and the project frame
/// grid. This schedules frame requests; it does not guarantee display deadlines
/// or a measured device-level synchronization tolerance.
///
/// Audio fetches are serialized and stale results are rejected after lifecycle
/// changes. The player retains partial writes in a bounded queue. The default
/// lookahead is 400ms; no hardware-latency estimate is currently collected for
/// the optional adaptive-buffer calculation.
///
/// At 1x, drift checks compare AudioTrack's played-frame cursor with the video
/// clock and re-prime after a large smoothed discrepancy. Small discrepancies
/// are observed without destructive seeks. Native preview PCM remains at its
/// fixed rate: adjusting chunk duration at other playback speeds does not
/// implement time stretching or pitch correction, and synchronized non-1x
/// audio is unsupported.
///
/// Seeking snaps the requested timeline position to a project frame boundary,
/// flushes old audio, and re-primes from that position. Hardware output latency
/// still affects when the new samples become audible.
class AvSyncCoordinator {
  AvSyncCoordinator(this._ref);
  final Ref _ref;

  // ── Timing ────────────────────────────────────────────────────────

  /// How often the sync loop runs (approximately 30 Hz).
  static const int _syncTickMs = 33;

  /// Default frame rate for PTS calculations (frames per second).
  static const double _defaultFrameRate = 30.0;

  /// The acceptable drift between audio and video in milliseconds.
  /// Below this threshold, no correction is applied.
  static const int _driftToleranceMs = 30;

  /// Hard safety limit — if drift exceeds this, an immediate seek
  /// correction is applied regardless of the EWMA state.
  static const int _driftHardLimitMs = 150;

  // ── EWMA Drift Correction ─────────────────────────────────────────

  /// Smoothing factor for the exponentially-weighted moving average.
  /// Higher α makes the filter more responsive to new measurements;
  /// lower α makes it smoother. 0.2 is a good balance.
  static const double _ewmaAlpha = 0.2;

  // ── Adaptive Buffer ───────────────────────────────────────────────

  /// Minimum audio lookahead buffer in milliseconds.
  static const int _minBufferAheadMs = 200;

  /// Maximum audio lookahead buffer in milliseconds.
  static const int _maxBufferAheadMs = 1200;

  /// Default audio chunk duration to request from the engine (ms).
  static const int _defaultAudioChunkMs = 200;

  /// Latency-to-buffer scaling factor. For every 1 ms of detected
  /// hardware latency, we add this many ms to the lookahead buffer.
  static const double _latencyBufferScale = 3.0;

  /// Number of latency probes to collect before trusting the estimate.
  static const int _latencyProbeMinSamples = 5;

  // ── Playback Rate ─────────────────────────────────────────────────

  /// Supported playback rates (must match EditorState clamping).

  // ── Internal State ────────────────────────────────────────────────

  Timer? _syncTimer;
  int _audioEpoch = 0;
  bool _audioFetchInFlight = false;
  bool _driftCheckInFlight = false;

  /// Monotonically-increasing wall-clock origin for PTS calculations.
  DateTime? _playbackOrigin;

  /// Timeline position (in ms) at the moment playback started or was
  /// last seeked. Combined with the wall-clock origin and the current
  /// speed, this yields the exact PTS for any point in time.
  int _playbackOriginMs = 0;

  /// The audio position as reported by the AudioPlayerService.
  int _audioPositionMs = 0;

  /// Whether we've initialized the AudioPlayerService for this session.
  bool _audioInitialized = false;

  /// Current adaptive buffer-ahead duration (ms).
  int _audioBufferAheadMs = 400;

  /// Current adaptive chunk duration (ms).
  int _audioChunkMs = _defaultAudioChunkMs;

  /// EWMA-smoothed drift value (ms). Positive means audio is ahead.
  double _smoothedDriftMs = 0.0;

  /// Cumulative drift correction applied (for logging/diagnostics).
  int _totalDriftCorrectionMs = 0;

  /// Number of sync ticks that exceeded drift tolerance (diagnostics).
  int _driftExceededCount = 0;

  /// Total number of sync ticks (diagnostics).
  int _syncTickCount = 0;

  /// Detected audio hardware output latency (ms).
  double _detectedLatencyMs = 0.0;

  /// Number of latency samples collected so far.
  int _latencySampleCount = 0;

  /// Frame rate for PTS calculations. Can be updated from the project.
  double _frameRate = _defaultFrameRate;

  /// Frame duration in milliseconds derived from [_frameRate].
  double get _frameDurationMs => 1000.0 / _frameRate;

  /// The last playback speed we saw. Used to detect speed changes
  /// and re-anchor the PTS origin accordingly.
  double _lastPlaybackSpeed = 1.0;

  /// Whether a seek is in progress (suppresses drift correction
  /// until both audio and video have settled at the new position).
  bool _seekInProgress = false;

  /// Timestamp of the last seek, used to suppress drift checks
  /// for a few ticks after seeking.
  DateTime? _lastSeekTime;

  // ═══════════════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════════════

  /// Start synchronized playback from the current playhead position.
  Future<void> start() async {
    if (!_engineReady) return;

    final epoch = ++_audioEpoch;
    _syncTimer?.cancel();
    _syncTimer = null;
    _audioFetchInFlight = false;
    final editorState = _ref.read(editorProvider);
    final currentMs = editorState.currentTimeMs;
    final durationMs = editorState.durationMs;
    final masterVolume = editorState.masterVolume;

    // Initialize audio player if needed
    if (!_audioInitialized) {
      final success = await AudioPlayerService.instance.initialize(
        sampleRate: 44100,
        channels: 2,
      );
      if (epoch != _audioEpoch) return;
      if (!success) {
        developer.log(
          'Audio init failed — playback will be video-only',
          name: 'AvSyncCoordinator',
        );
        return;
      }
      _audioInitialized = true;
    }

    await AudioPlayerService.instance.seekTo(currentMs);
    await AudioPlayerService.instance.setVolume(masterVolume);
    if (epoch != _audioEpoch) return;
    _audioPositionMs = currentMs;

    // ── Anchor the PTS origin ─────────────────────────────────────
    _playbackOrigin = DateTime.now();
    _playbackOriginMs = currentMs;
    _lastPlaybackSpeed = editorState.playbackSpeed;

    // ── Prime the audio buffer ────────────────────────────────────
    await _primeAudioBuffer(currentMs, durationMs);
    if (epoch != _audioEpoch) return;
    // Anchor after decoding/priming so startup work does not advance video.
    _playbackOrigin = DateTime.now();
    await AudioPlayerService.instance.play();
    if (epoch != _audioEpoch) return;

    // ── Start the sync timer ──────────────────────────────────────
    _syncTickCount = 0;
    _driftExceededCount = 0;
    _totalDriftCorrectionMs = 0;
    _smoothedDriftMs = 0.0;
    _seekInProgress = false;
    _lastSeekTime = null;

    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(
      const Duration(milliseconds: _syncTickMs),
      _onSyncTick,
    );

    developer.log(
      'AV sync started at ${currentMs}ms (duration=${durationMs}ms, '
      'speed=${editorState.playbackSpeed}x, bufferAhead=${_audioBufferAheadMs}ms)',
      name: 'AvSyncCoordinator',
    );
  }

  /// Stop synchronized playback.
  Future<void> stop() async {
    _audioEpoch++;
    _audioFetchInFlight = false;
    _syncTimer?.cancel();
    _syncTimer = null;
    _playbackOrigin = null;
    _seekInProgress = false;
    _lastSeekTime = null;

    if (_audioInitialized) {
      await AudioPlayerService.instance.stop();
    }

    developer.log(
      'AV sync stopped (ticks=$_syncTickCount, drift_exceeded=$_driftExceededCount, '
      'total_correction=${_totalDriftCorrectionMs}ms, '
      'smoothed_drift=${_smoothedDriftMs.toStringAsFixed(1)}ms)',
      name: 'AvSyncCoordinator',
    );
  }

  /// Pause synchronized playback.
  Future<void> pause() async {
    _audioEpoch++;
    _audioFetchInFlight = false;
    _syncTimer?.cancel();
    _syncTimer = null;
    _playbackOrigin = null;

    if (_audioInitialized) {
      await AudioPlayerService.instance.pause();
    }
  }

  /// Resume synchronized playback from the current position.
  Future<void> resume() async {
    await start();
  }

  /// Seek to a new position with frame-boundary snapping and re-priming.
  ///
  /// Re-prime audio from the same snapped timeline position as video.
  /// This does not guarantee exact presentation alignment on the device.
  Future<void> seekTo(int positionMs) async {
    if (!_audioInitialized) return;

    final epoch = ++_audioEpoch;
    _audioFetchInFlight = false;
    _seekInProgress = true;
    _lastSeekTime = DateTime.now();

    // ── Snap to nearest frame boundary ────────────────────────────
    final snappedMs = _snapToFrameBoundary(positionMs);

    // ── Pause audio during seek ───────────────────────────────────
    await AudioPlayerService.instance.pause();
    await AudioPlayerService.instance.seekTo(snappedMs);
    if (epoch != _audioEpoch) return;
    _audioPositionMs = snappedMs;

    // ── Re-anchor the PTS origin at the snapped position ──────────
    _playbackOrigin = DateTime.now();
    _playbackOriginMs = snappedMs;
    _smoothedDriftMs = 0.0;

    // ── Re-prime the audio buffer from the snapped position ───────
    final editorState = _ref.read(editorProvider);
    await _primeAudioBuffer(snappedMs, editorState.durationMs);
    if (epoch != _audioEpoch) return;
    _playbackOrigin = DateTime.now();

    // ── Update the video playhead to the snapped position ─────────
    _ref.read(editorProvider.notifier).seekTo(snappedMs);

    // ── Resume audio playback ─────────────────────────────────────
    await AudioPlayerService.instance.play();

    developer.log(
      'Seek: requested=${positionMs}ms, snapped=${snappedMs}ms, '
      'frame=${_msToFrameNumber(snappedMs)}',
      name: 'AvSyncCoordinator',
    );
  }

  /// Update the master volume.
  Future<void> setVolume(double volume) async {
    if (!_audioInitialized) return;
    await AudioPlayerService.instance.setVolume(volume);
  }

  /// Update the project frame rate (e.g. when switching between
  /// 24/25/30/60 fps timelines).
  void setFrameRate(double fps) {
    _frameRate = fps.clamp(1.0, 240.0);
    developer.log(
      'Frame rate set to ${_frameRate}fps '
      '(frame_duration=${_frameDurationMs.toStringAsFixed(2)}ms)',
      name: 'AvSyncCoordinator',
    );
  }

  /// Release all audio resources.
  Future<void> release() async {
    await stop();
    if (_audioInitialized) {
      await AudioPlayerService.instance.release();
      _audioInitialized = false;
    }
  }

  /// Get sync diagnostics.
  AvSyncDiagnostics get diagnostics => AvSyncDiagnostics(
        syncTickCount: _syncTickCount,
        driftExceededCount: _driftExceededCount,
        totalDriftCorrectionMs: _totalDriftCorrectionMs,
        smoothedDriftMs: _smoothedDriftMs,
        audioInitialized: _audioInitialized,
        detectedLatencyMs: _detectedLatencyMs,
        adaptiveBufferAheadMs: _audioBufferAheadMs,
        adaptiveChunkMs: _audioChunkMs,
        frameRate: _frameRate,
      );

  // ═══════════════════════════════════════════════════════════════════
  // Sync Timer Loop
  // ═══════════════════════════════════════════════════════════════════

  void _onSyncTick(Timer timer) {
    final editorState = _ref.read(editorProvider);
    if (!editorState.isPlaying) {
      timer.cancel();
      _syncTimer = null;
      return;
    }

    final now = DateTime.now();

    _syncTickCount++;

    // ── Detect playback speed changes and re-anchor ───────────────
    final speed = editorState.playbackSpeed;
    if (speed != _lastPlaybackSpeed) {
      // Re-anchor the PTS origin at the current position so that the
      // frame timeline doesn't jump discontinuously.
      _playbackOrigin = now;
      _playbackOriginMs = editorState.currentTimeMs;
      _lastPlaybackSpeed = speed;

      developer.log(
        'Speed changed to ${speed}x — re-anchored PTS origin at '
        '${_playbackOriginMs}ms',
        name: 'AvSyncCoordinator',
      );
    }

    // ── Compute exact PTS for the current moment ──────────────────
    final preciseTimeMs = _computeCurrentPts(now, speed);

    final durationMs = editorState.durationMs;
    if (preciseTimeMs >= durationMs && durationMs > 0) {
      // ── Loop back to start ───────────────────────────────────────
      final snappedZero = _snapToFrameBoundary(0);
      _playbackOrigin = now;
      _playbackOriginMs = snappedZero;
      _ref.read(editorProvider.notifier).seekTo(snappedZero);
      unawaited(seekTo(snappedZero));
      return;
    }

    // ── Snap to frame boundary for the display position ───────────
    final displayMs = _snapToFrameBoundary(preciseTimeMs);
    _ref.read(editorProvider.notifier).seekTo(displayMs);

    // ── Feed audio samples (rate-aware) ───────────────────────────
    _feedAudioAhead(displayMs, durationMs, speed);

    // ── Drift correction (suppressed briefly after seeks) ─────────
    if (_seekInProgress) {
      // Allow a few ticks for the seek to settle
      final ticksSinceSeek = _lastSeekTime != null
          ? now.difference(_lastSeekTime!).inMilliseconds
          : _syncTickMs * 5;
      if (ticksSinceSeek > _syncTickMs * 3) {
        _seekInProgress = false;
      }
    }

    if (!_seekInProgress) {
      _correctDrift(displayMs, speed);
    }

    // ── Adaptively tune the buffer on each tick ───────────────────
    _adaptBuffer();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Frame Timing Precision — PTS Calculation
  // ═══════════════════════════════════════════════════════════════════

  /// Compute the precise presentation timestamp (PTS) in milliseconds
  /// for the current moment.
  ///
  /// PTS = origin_position + (wall_elapsed × playback_speed)
  ///
  /// This ensures that each frame's display time is derived from a
  /// single, coherent clock rather than accumulated per-tick deltas
  /// (which suffer from rounding drift).
  int _computeCurrentPts(DateTime now, double speed) {
    if (_playbackOrigin == null) return 0;

    final wallElapsedMs = now.difference(_playbackOrigin!).inMilliseconds;
    // Use floating-point arithmetic for precision, then round.
    final pts = _playbackOriginMs + (wallElapsedMs * speed);
    return pts.round();
  }

  /// Snap a millisecond position to the nearest frame boundary.
  ///
  /// Frame N occupies the interval [N × frameDuration, (N+1) × frameDuration).
  /// The snapped position is the start of the nearest frame.
  int _snapToFrameBoundary(int positionMs) {
    if (_frameDurationMs <= 0) return positionMs;
    final frameNumber = (positionMs / _frameDurationMs).round();
    return (frameNumber * _frameDurationMs).round();
  }

  /// Convert a millisecond position to a frame number.
  int _msToFrameNumber(int positionMs) {
    if (_frameDurationMs <= 0) return 0;
    return (positionMs / _frameDurationMs).round();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Audio Buffer Management — Adaptive Strategy
  // ═══════════════════════════════════════════════════════════════════

  /// Apply the adaptive calculation only after latency samples exist.
  /// No hardware-latency sampler currently supplies these inputs, so playback
  /// retains its default lookahead rather than claiming measured adaptation.
  void _adaptBuffer() {
    if (_latencySampleCount < _latencyProbeMinSamples) return;

    // Target buffer = max(min, min(max, base + scale × latency))
    final targetBufferMs =
        (_minBufferAheadMs + _latencyBufferScale * _detectedLatencyMs)
            .clamp(_minBufferAheadMs.toDouble(), _maxBufferAheadMs.toDouble())
            .round();

    // Smooth the transition — don't change the buffer size by more
    // than 50ms per tick to avoid sudden jumps.
    final delta = targetBufferMs - _audioBufferAheadMs;
    if (delta.abs() > 50) {
      _audioBufferAheadMs += (delta > 0 ? 50 : -50);
    } else {
      _audioBufferAheadMs = targetBufferMs;
    }

    // Adjust chunk size proportionally: larger buffer → larger chunks
    // to keep the number of fetches per second reasonable.
    _audioChunkMs =
        (_defaultAudioChunkMs * (_audioBufferAheadMs / _minBufferAheadMs))
            .round()
            .clamp(_defaultAudioChunkMs, 600);
  }

  /// Prime the audio buffer with initial samples starting at [startMs].
  Future<void> _primeAudioBuffer(int startMs, int durationMs) async {
    if (!_engineReady || !_audioInitialized) return;

    final epoch = _audioEpoch;
    final length =
        math.min(_audioBufferAheadMs, math.max(0, durationMs - startMs));
    if (length == 0) return;
    _audioFetchInFlight = true;
    try {
      final api = EngineService.instance.api;
      final samples = await api.mixAudioAtTime(
        startMs: BigInt.from(startMs),
        durationMs: BigInt.from(length),
      );

      if (epoch != _audioEpoch) return;
      if (samples.isNotEmpty) {
        final floatSamples = Float32List.fromList(samples);
        await AudioPlayerService.instance.writeSamples(floatSamples);
        if (epoch == _audioEpoch) _audioPositionMs = startMs + length;
      }
    } catch (e) {
      developer.log(
        'Prime audio buffer failed: $e',
        name: 'AvSyncCoordinator',
      );
    } finally {
      if (epoch == _audioEpoch) _audioFetchInFlight = false;
    }
  }

  /// Feed audio samples ahead of the current playhead position.
  ///
  /// Chunk requests are scaled by the playback-speed setting, but PCM is
  /// still played at the fixed preview sample rate. This request scaling
  /// alone does not provide synchronized or pitch-corrected non-1x audio.
  void _feedAudioAhead(int playheadMs, int durationMs, double speed) {
    if (!_engineReady || !_audioInitialized || _audioFetchInFlight) return;

    final bufferEndMs = _audioPositionMs;
    // The amount of *timeline* time we need ahead of the playhead.
    final neededAheadMs =
        math.min(durationMs, playheadMs + _audioBufferAheadMs);

    if (bufferEndMs < neededAheadMs) {
      // Scale fetch granularity only. AudioTrack's playback rate is unchanged;
      // this is not a time-stretch implementation.
      final scaledChunkMs =
          (_audioChunkMs / speed).round().clamp(50, _maxBufferAheadMs);

      final fetchStartMs = math.max(bufferEndMs, playheadMs);
      final fetchEndMs =
          (fetchStartMs + scaledChunkMs).clamp(0, neededAheadMs).round();

      if (fetchEndMs > fetchStartMs) {
        _fetchAndWriteAudio(fetchStartMs, fetchEndMs - fetchStartMs, speed);
      }
    }
  }

  /// Fetch audio samples from the engine and write to the audio player.
  ///
  /// The native mixer receives a timeline range, without a playback-speed
  /// argument. [speed] is diagnostic context; no time stretch is requested.
  void _fetchAndWriteAudio(int startMs, int durationMs, double speed) {
    if (!_engineReady || !_audioInitialized || _audioFetchInFlight) return;
    _audioFetchInFlight = true;
    final epoch = _audioEpoch;
    () async {
      try {
        final api = EngineService.instance.api;

        // Fetch one non-overlapping source range. Native preview PCM is
        // currently mixed at the fixed preview rate; no pitch-corrected
        // playback-rate conversion is claimed here.
        final samples = await api.mixAudioAtTime(
          startMs: BigInt.from(startMs),
          durationMs: BigInt.from(durationMs),
        );

        if (epoch != _audioEpoch) return;
        if (samples.isNotEmpty) {
          final floatSamples = Float32List.fromList(samples);
          await AudioPlayerService.instance.writeSamples(floatSamples);
          if (epoch == _audioEpoch) _audioPositionMs = startMs + durationMs;
        }
      } catch (e) {
        developer.log(
          'Audio feed failed at ${startMs}ms (speed=${speed}x): $e',
          name: 'AvSyncCoordinator',
        );
      } finally {
        if (epoch == _audioEpoch) _audioFetchInFlight = false;
      }
    }();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Drift Correction — Weighted Moving Average
  // ═══════════════════════════════════════════════════════════════════

  /// Compare against AudioTrack's played-frame cursor, never queued samples.
  /// Small differences are observed; only sustained large drift re-primes audio.
  Future<void> _correctDrift(int videoPositionMs, double speed) async {
    if (!_audioInitialized || _driftCheckInFlight || speed != 1.0) return;
    _driftCheckInFlight = true;
    final epoch = _audioEpoch;
    try {
      final audioPos =
          await AudioPlayerService.instance.refreshPlaybackPosition();
      if (audioPos == null || epoch != _audioEpoch || _playbackOrigin == null)
        return;
      final currentVideoMs = _computeCurrentPts(DateTime.now(), speed);
      final drift = (audioPos - currentVideoMs).toDouble();
      _smoothedDriftMs =
          _ewmaAlpha * drift + (1 - _ewmaAlpha) * _smoothedDriftMs;
      if (_smoothedDriftMs.abs() > _driftToleranceMs) _driftExceededCount++;
      if (_smoothedDriftMs.abs() > _driftHardLimitMs) {
        _totalDriftCorrectionMs += _smoothedDriftMs.abs().round();
        _smoothedDriftMs = 0;
        await seekTo(_snapToFrameBoundary(currentVideoMs));
      }
    } finally {
      _driftCheckInFlight = false;
    }
  }

  bool get _engineReady => EngineService.instance.isInitialized;
}

// ═══════════════════════════════════════════════════════════════════════════
// Diagnostics
// ═══════════════════════════════════════════════════════════════════════════

/// Diagnostics for the A/V sync system.
class AvSyncDiagnostics {
  const AvSyncDiagnostics({
    required this.syncTickCount,
    required this.driftExceededCount,
    required this.totalDriftCorrectionMs,
    required this.smoothedDriftMs,
    required this.audioInitialized,
    required this.detectedLatencyMs,
    required this.adaptiveBufferAheadMs,
    required this.adaptiveChunkMs,
    required this.frameRate,
  });
  final int syncTickCount;
  final int driftExceededCount;
  final int totalDriftCorrectionMs;
  final double smoothedDriftMs;
  final bool audioInitialized;
  final double detectedLatencyMs;
  final int adaptiveBufferAheadMs;
  final int adaptiveChunkMs;
  final double frameRate;

  double get driftExceededRatio =>
      syncTickCount > 0 ? driftExceededCount / syncTickCount : 0.0;

  double get avgCorrectionMs =>
      syncTickCount > 0 ? totalDriftCorrectionMs / syncTickCount : 0.0;

  /// Frame duration derived from the current frame rate.
  double get frameDurationMs => frameRate > 0 ? 1000.0 / frameRate : 0.0;

  @override
  String toString() =>
      'AvSyncDiagnostics(ticks=$syncTickCount, drift_exceeded=$driftExceededCount, '
      'ratio=${driftExceededRatio.toStringAsFixed(3)}, avg_correction=${avgCorrectionMs.toStringAsFixed(1)}ms, '
      'smoothed_drift=${smoothedDriftMs.toStringAsFixed(1)}ms, '
      'latency=${detectedLatencyMs.toStringAsFixed(1)}ms, '
      'buffer_ahead=${adaptiveBufferAheadMs}ms, chunk=${adaptiveChunkMs}ms, '
      'fps=$frameRate, audio=$audioInitialized)';
}

// ═══════════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the AV sync coordinator.
final avSyncCoordinatorProvider = Provider<AvSyncCoordinator>((ref) {
  final coordinator = AvSyncCoordinator(ref);

  ref.onDispose(() {
    coordinator.release();
  });

  return coordinator;
});
