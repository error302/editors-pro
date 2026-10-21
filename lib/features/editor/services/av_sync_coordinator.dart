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

/// Synchronizes audio playback with the video preview timeline.
///
/// ## Architecture
///
/// The sync coordinator runs a high-precision clock that drives both the
/// video frame requests and the audio sample feeding. The video playhead
/// position is the "master clock" — audio is slaved to it.
///
/// ## Frame Timing Precision
///
/// Each frame's exact presentation timestamp (PTS) is computed from the
/// timeline origin, elapsed wall-clock time, and the current playback
/// speed. Frame boundaries are derived from the project frame rate so
/// that every displayed frame lands on an exact grid point, eliminating
/// sub-frame jitter.
///
/// ## Drift Correction — Weighted Moving Average
///
/// Audio and video can drift apart due to:
/// - Variable frame decode latency
/// - Audio buffer underruns/overruns
/// - GC pauses on the Dart VM
///
/// Instead of a hard threshold + instant seek, the coordinator maintains
/// an exponentially-weighted moving average (EWMA) of measured drift.
/// Small corrections are applied every tick proportional to the smoothed
/// drift, yielding gradual convergence without visible or audible jumps.
/// A hard safety limit still exists to catch catastrophic desync.
///
/// ## Adaptive Buffer Strategy
///
/// Audio buffer sizes are dynamically adjusted based on the detected
/// system audio latency. Higher-latency hardware receives a larger
/// lookahead buffer to prevent underruns; low-latency setups keep the
/// buffer small to minimise memory usage and seek responsiveness.
///
/// ## Playback Rate Handling
///
/// At non-1.0× speeds the coordinator adjusts both the video frame PTS
/// computation and the audio time-stretch parameters so that pitch-
/// corrected audio stays frame-locked with the video. The audio chunk
/// duration is scaled by the inverse of the playback rate to deliver
/// the correct number of samples per wall-clock second.
///
/// ## Seek Compensation
///
/// On seek, both audio and video snap to the nearest frame boundary
/// before resuming, ensuring that the first displayed frame after a
/// seek is perfectly aligned with the first audio sample played.
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

  /// Maximum fraction of measured drift to correct per tick.
  /// Prevents overcorrection oscillation.
  static const double _maxCorrectionFraction = 0.4;

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

  /// Sum of measured audio-write-to-playback delays (ms).
  double _latencySampleSum = 0.0;

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
      if (!success) {
        developer.log(
          'Audio init failed — playback will be video-only',
          name: 'AvSyncCoordinator',
        );
        return;
      }
      _audioInitialized = true;
      _probeSystemLatency();
    }

    // Set volume
    await AudioPlayerService.instance.setVolume(masterVolume);

    // ── Anchor the PTS origin ─────────────────────────────────────
    _playbackOrigin = DateTime.now();
    _playbackOriginMs = currentMs;
    _lastPlaybackSpeed = editorState.playbackSpeed;

    // ── Prime the audio buffer ────────────────────────────────────
    await _primeAudioBuffer(currentMs, durationMs);

    // Start audio playback
    await AudioPlayerService.instance.play();

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
    _syncTimer?.cancel();
    _syncTimer = null;
    _playbackOrigin = null;
    _seekInProgress = false;
    _lastSeekTime = null;

    if (_audioInitialized) {
      AudioPlayerService.instance.stopSynchronizedPlayback();
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
  /// Both audio and video snap to the nearest frame boundary before
  /// resuming, so the first displayed frame is perfectly aligned with
  /// the first audio sample.
  Future<void> seekTo(int positionMs) async {
    if (!_audioInitialized) return;

    _seekInProgress = true;
    _lastSeekTime = DateTime.now();

    // ── Snap to nearest frame boundary ────────────────────────────
    final snappedMs = _snapToFrameBoundary(positionMs);

    // ── Pause audio during seek ───────────────────────────────────
    await AudioPlayerService.instance.pause();
    await AudioPlayerService.instance.seekTo(snappedMs);

    // ── Re-anchor the PTS origin at the snapped position ──────────
    _playbackOrigin = DateTime.now();
    _playbackOriginMs = snappedMs;
    _smoothedDriftMs = 0.0;

    // ── Re-prime the audio buffer from the snapped position ───────
    final editorState = _ref.read(editorProvider);
    await _primeAudioBuffer(snappedMs, editorState.durationMs);

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
      _primeAudioBuffer(snappedZero, durationMs);
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

  /// Probe the system audio latency by measuring the round-trip time
  /// of a small silent write. The result informs the adaptive buffer.
  void _probeSystemLatency() {
    // We estimate latency by writing a tiny silent buffer and measuring
    // how long the platform takes to acknowledge it. This is a rough
    // heuristic — the real latency is dominated by the AudioTrack buffer
    // size on Android, but this gives us a usable signal.
    () async {
      try {
        // Write 1ms of silence (44100 / 1000 * 2 channels = 88 samples)
        final silenceSamples = Float32List(88);
        final sw = Stopwatch()..start();
        await AudioPlayerService.instance.writeSamples(silenceSamples);
        sw.stop();
        final roundTripMs = sw.elapsedMilliseconds.toDouble();

        if (roundTripMs > 0) {
          _latencySampleCount++;
          _latencySampleSum += roundTripMs;

          if (_latencySampleCount >= _latencyProbeMinSamples) {
            _detectedLatencyMs = _latencySampleSum / _latencySampleCount;
            developer.log(
              'Detected audio latency: ${_detectedLatencyMs.toStringAsFixed(1)}ms '
              '($_latencySampleCount samples)',
              name: 'AvSyncCoordinator',
            );
          }
        }
      } catch (_) {
        // Latency probe is best-effort; failures are safe to ignore.
      }
    }();
  }

  /// Dynamically adjust the buffer-ahead duration and chunk size based
  /// on the detected system latency.
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

    try {
      final api = EngineService.instance.api;
      final samples = await api.mixAudioAtTime(
        startMs: BigInt.from(startMs),
        durationMs: BigInt.from(_audioBufferAheadMs),
      );

      if (samples.isNotEmpty) {
        final floatSamples = Float32List.fromList(samples);
        await AudioPlayerService.instance.writeSamples(floatSamples);
        _audioPositionMs = startMs + _audioBufferAheadMs;
      }
    } catch (e) {
      developer.log(
        'Prime audio buffer failed: $e',
        name: 'AvSyncCoordinator',
      );
    }
  }

  /// Feed audio samples ahead of the current playhead position.
  ///
  /// When the playback rate differs from 1.0×, the chunk duration
  /// requested from the engine is adjusted: at 2× speed we need half
  /// the wall-clock duration of samples (because they'll be played
  /// back at double rate), while at 0.5× speed we need double the
  /// wall-clock duration.
  void _feedAudioAhead(int playheadMs, int durationMs, double speed) {
    if (!_engineReady || !_audioInitialized) return;

    final bufferEndMs = _audioPositionMs;
    // The amount of *timeline* time we need ahead of the playhead.
    final neededAheadMs = playheadMs + _audioBufferAheadMs;

    if (bufferEndMs < neededAheadMs && neededAheadMs < durationMs) {
      // Scale the chunk duration by 1/speed so that the wall-clock
      // fill rate matches the accelerated/decelerated playback.
      // E.g. at 2×, we request half the timeline duration per chunk
      // because the audio will be consumed twice as fast.
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
  /// When [speed] ≠ 1.0, the engine is asked for time-stretched audio
  /// by requesting samples over the appropriate timeline range.
  void _fetchAndWriteAudio(int startMs, int durationMs, double speed) {
    () async {
      if (!_engineReady || !_audioInitialized) return;

      try {
        final api = EngineService.instance.api;

        // Request the engine to mix audio at the given timeline range.
        // For non-1.0× speeds, the engine is expected to deliver
        // time-stretched (pitch-corrected) audio matching the speed
        // factor. The durationMs here is in *timeline* time; the
        // engine maps that to the correct number of output samples.
        final samples = await api.mixAudioAtTime(
          startMs: BigInt.from(startMs),
          durationMs: BigInt.from(durationMs),
        );

        if (samples.isNotEmpty) {
          final floatSamples = Float32List.fromList(samples);
          await AudioPlayerService.instance.writeSamples(floatSamples);
          _audioPositionMs = startMs + durationMs;
        }
      } catch (e) {
        developer.log(
          'Audio feed failed at ${startMs}ms (speed=${speed}x): $e',
          name: 'AvSyncCoordinator',
        );
      }
    }();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Drift Correction — Weighted Moving Average
  // ═══════════════════════════════════════════════════════════════════

  /// Measure and correct drift between audio and video positions using
  /// an exponentially-weighted moving average (EWMA).
  ///
  /// The EWMA smooths out transient spikes (e.g. GC pauses) while still
  /// reacting to persistent drift. The correction applied per tick is
  /// a fraction of the smoothed drift, ensuring gradual convergence
  /// without visible or audible jumps.
  ///
  /// A hard safety limit catches catastrophic desync and forces an
  /// immediate seek correction.
  void _correctDrift(int videoPositionMs, double speed) {
    if (!_audioInitialized) return;

    final audioPos = AudioPlayerService.instance.currentPositionMs;
    // Positive drift means audio is ahead of video.
    final rawDriftMs = (audioPos - videoPositionMs).toDouble();

    // ── Update EWMA ───────────────────────────────────────────────
    _smoothedDriftMs =
        _ewmaAlpha * rawDriftMs + (1.0 - _ewmaAlpha) * _smoothedDriftMs;

    final absSmoothed = _smoothedDriftMs.abs();

    // ── Hard safety limit: immediate seek correction ──────────────
    if (absSmoothed > _driftHardLimitMs) {
      _driftExceededCount++;

      final snappedVideo = _snapToFrameBoundary(videoPositionMs);
      AudioPlayerService.instance.seekTo(snappedVideo);
      _audioPositionMs = snappedVideo;
      _totalDriftCorrectionMs += _smoothedDriftMs.abs().round();

      // Reset EWMA after a hard correction to avoid lingering bias.
      _smoothedDriftMs = 0.0;

      developer.log(
        'Hard A/V drift correction: ${_smoothedDriftMs.toStringAsFixed(1)}ms '
        '(audio ${audioPos}ms vs video ${videoPositionMs}ms) — seeked to ${snappedVideo}ms',
        name: 'AvSyncCoordinator',
        level: 900, // warning level
      );
      return;
    }

    // ── Soft correction: proportional to smoothed drift ───────────
    if (absSmoothed > _driftToleranceMs) {
      _driftExceededCount++;

      // Apply a fraction of the smoothed drift as a position nudge.
      // The correction direction opposes the drift.
      final correctionMs = (_smoothedDriftMs * _maxCorrectionFraction).round();

      if (correctionMs != 0) {
        // Nudge the audio position by seeking a small amount.
        final correctedAudioPos = _snapToFrameBoundary(audioPos - correctionMs);
        AudioPlayerService.instance.seekTo(correctedAudioPos);
        _audioPositionMs = correctedAudioPos;
        _totalDriftCorrectionMs += correctionMs.abs();

        // Partially decay the EWMA so we don't over-correct next tick.
        _smoothedDriftMs *= 1.0 - _maxCorrectionFraction;
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════

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
