import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Service for synchronized audio playback alongside video preview.
///
/// On Android, this uses the platform's AudioTrack API via a method
/// channel to play PCM float32 samples received from the Rust engine.
/// The coordinator can compare its played-frame cursor with the video clock.
/// Actual device latency and synchronization accuracy require runtime testing.
class AudioPlayerService {
  AudioPlayerService._();
  static const _channel = MethodChannel('com.editorspro/audio');

  static final AudioPlayerService instance = AudioPlayerService._();

  bool _isPlaying = false;
  bool _isInitialized = false;
  int _currentPositionMs = 0;
  Timer? _playbackTimer;
  final Queue<_PendingAudio> _pending = Queue<_PendingAudio>();
  int _pendingSampleCount = 0;
  int _writeEpoch = 0;
  int _controlEpoch = 0;
  int? _pumpingEpoch;
  Timer? _writeRetry;
  bool _paused = false;
  int _sampleRate = 44100;
  int _channels = 2;
  int _positionOriginMs = 0;
  bool _hasPlaybackPosition = false;
  String? _lastWriteError;

  /// Queued samples are retained until Android acknowledges their exact count.
  int get pendingSampleCount => _pendingSampleCount;
  String? get lastWriteError => _lastWriteError;
  bool get hasPlaybackPosition => _hasPlaybackPosition;

  void _cancelWrites() {
    _writeEpoch++;
    _controlEpoch++;
    _writeRetry?.cancel();
    _writeRetry = null;
    _pending.clear();
    _pendingSampleCount = 0;
    _lastWriteError = null;
  }

  /// Whether the audio player is currently playing.
  bool get isPlaying => _isPlaying;

  /// Whether the audio player has been initialized.
  bool get isInitialized => _isInitialized;

  /// Current playback position in milliseconds.
  int get currentPositionMs => _currentPositionMs;

  /// Initialize the audio player.
  ///
  /// Sets up the Android AudioTrack with the project's sample rate
  /// and channel configuration. Must be called before playing audio.
  Future<bool> initialize({
    int sampleRate = 44100,
    int channels = 2,
  }) async {
    if (sampleRate <= 0 || (channels != 1 && channels != 2)) {
      throw ArgumentError(
          'Audio playback requires a positive rate and mono or stereo channels');
    }
    _cancelWrites();
    _isInitialized = false;
    _isPlaying = false;
    _paused = false;
    _hasPlaybackPosition = false;
    _currentPositionMs = 0;
    _positionOriginMs = 0;
    _sampleRate = sampleRate;
    _channels = channels;
    final epoch = _writeEpoch;
    try {
      final result = await _channel.invokeMethod<bool>('initialize', {
        'sampleRate': sampleRate,
        'channels': channels,
      });
      if (epoch != _writeEpoch) return false;
      _isInitialized = result ?? false;
      developer.log(
        'AudioPlayerService initialized: sampleRate=$sampleRate, channels=$channels',
        name: 'AudioPlayerService',
      );
      return _isInitialized;
    } on PlatformException catch (e) {
      developer.log(
        'Failed to initialize audio player: ${e.message}',
        name: 'AudioPlayerService',
        error: e,
      );
      return false;
    }
  }

  /// Admit PCM to a bounded FIFO. Completion acknowledges queue ownership,
  /// not playback: priming must finish even before AudioTrack.play() is called.
  /// Partial/zero native writes retain their tail and retry without blocking UI.
  Future<void> writeSamples(Float32List samples) async {
    if (!_isInitialized) return;
    if (_lastWriteError != null) throw StateError(_lastWriteError!);
    if (samples.length % _channels != 0 ||
        samples.any((sample) => !sample.isFinite)) {
      throw ArgumentError('PCM must contain complete, finite channel frames');
    }
    if (_pendingSampleCount + samples.length > _sampleRate * _channels * 3) {
      throw StateError(
          'Audio queue is full; retry after playback consumes samples');
    }
    if (samples.isEmpty) return;
    // Copy only this view, never unrelated bytes from its backing buffer.
    _pending.add(_PendingAudio(Float32List.fromList(samples)));
    _pendingSampleCount += samples.length;
    unawaited(_pumpWrites());
  }

  Future<void> _pumpWrites() async {
    final epoch = _writeEpoch;
    if (!_isInitialized ||
        _paused ||
        _lastWriteError != null ||
        _pumpingEpoch == epoch) return;
    _writeRetry?.cancel();
    _writeRetry = null;
    _pumpingEpoch = epoch;
    try {
      while (epoch == _writeEpoch && !_paused && _pending.isNotEmpty) {
        final pending = _pending.first;
        final end = (pending.offset + 4096).clamp(0, pending.samples.length);
        final view =
            Float32List.sublistView(pending.samples, pending.offset, end);
        final written = await _channel.invokeMethod<int>('writeSamples', {
          'samples':
              view.buffer.asUint8List(view.offsetInBytes, view.lengthInBytes),
        });
        if (epoch != _writeEpoch) return;
        if (written == null || written < 0 || written > view.length) {
          throw StateError(
              'Invalid AudioTrack accepted-sample count: $written');
        }
        if (written == 0) {
          if (!_paused) {
            _writeRetry?.cancel();
            _writeRetry = Timer(const Duration(milliseconds: 8), () {
              _writeRetry = null;
              if (epoch == _writeEpoch) unawaited(_pumpWrites());
            });
          }
          return;
        }
        pending.offset += written;
        _pendingSampleCount -= written;
        if (pending.offset == pending.samples.length) _pending.removeFirst();
      }
    } catch (error) {
      if (epoch == _writeEpoch) {
        _lastWriteError = 'Audio write failed: $error';
        developer.log(_lastWriteError!,
            name: 'AudioPlayerService', error: error);
      }
    } finally {
      if (_pumpingEpoch == epoch) _pumpingEpoch = null;
    }
  }

  /// A real hardware playback cursor, distinct from the queued-sample cursor.
  Future<int?> refreshPlaybackPosition() async {
    if (!_isInitialized) return null;
    final epoch = _writeEpoch;
    try {
      final frames =
          await _channel.invokeMethod<int>('getPlaybackPositionFrames');
      if (epoch != _writeEpoch || frames == null || frames < 0) return null;
      _currentPositionMs = _positionOriginMs + frames * 1000 ~/ _sampleRate;
      _hasPlaybackPosition = true;
      return _currentPositionMs;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Start audio playback from the current position.
  Future<void> play() async {
    if (!_isInitialized || _isPlaying) return;
    final control = ++_controlEpoch;
    try {
      await _channel.invokeMethod<void>('play');
      if (control != _controlEpoch) return;
      _isPlaying = true;
      _paused = false;
      unawaited(_pumpWrites());
      developer.log('Audio playback started', name: 'AudioPlayerService');
    } on PlatformException catch (e) {
      developer.log(
        'Failed to start audio playback: ${e.message}',
        name: 'AudioPlayerService',
        error: e,
      );
    }
  }

  /// Pause audio playback.
  Future<void> pause() async {
    if (!_isInitialized) return;
    _controlEpoch++;
    _paused = true;
    _isPlaying = false;
    _writeRetry?.cancel();
    _writeRetry = null;
    try {
      await _channel.invokeMethod<void>('pause');
      developer.log('Audio playback paused', name: 'AudioPlayerService');
    } on PlatformException catch (e) {
      developer.log(
        'Failed to pause audio playback: ${e.message}',
        name: 'AudioPlayerService',
        error: e,
      );
    }
  }

  /// Stop audio playback and reset position.
  Future<void> stop() async {
    _cancelWrites();
    _isPlaying = false;
    _paused = false;
    _currentPositionMs = 0;
    _positionOriginMs = 0;
    _hasPlaybackPosition = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    if (!_isInitialized) return;
    try {
      await _channel.invokeMethod<void>('stop');
      developer.log('Audio playback stopped', name: 'AudioPlayerService');
    } on PlatformException catch (e) {
      developer.log(
        'Failed to stop audio playback: ${e.message}',
        name: 'AudioPlayerService',
        error: e,
      );
    }
  }

  /// Seek to a specific position in milliseconds.
  ///
  /// Clears the audio buffer and rewrites samples from the new
  /// position. The caller is responsible for providing the
  /// correct samples after seeking.
  Future<void> seekTo(int positionMs) async {
    _cancelWrites();
    _paused = false;
    _positionOriginMs = positionMs;
    _currentPositionMs = positionMs;
    _hasPlaybackPosition = false;
    if (!_isInitialized) return;
    try {
      await _channel.invokeMethod<void>('seekTo', {
        'positionMs': positionMs,
      });
      developer.log(
        'Audio seeked to ${positionMs}ms',
        name: 'AudioPlayerService',
      );
    } on PlatformException catch (e) {
      developer.log(
        'Failed to seek audio: ${e.message}',
        name: 'AudioPlayerService',
        error: e,
      );
    }
  }

  /// Set the playback volume (0.0 to 1.0).
  Future<void> setVolume(double volume) async {
    if (!_isInitialized) return;
    try {
      await _channel.invokeMethod<void>('setVolume', {
        'volume': volume.clamp(0.0, 1.0),
      });
    } on PlatformException catch (e) {
      developer.log(
        'Failed to set audio volume: ${e.message}',
        name: 'AudioPlayerService',
        error: e,
      );
    }
  }

  /// Release audio resources.
  ///
  /// Must be called when the audio player is no longer needed
  /// to free native resources (AudioTrack on Android).
  Future<void> release() async {
    await stop();
    if (_isInitialized) {
      try {
        await _channel.invokeMethod<void>('release');
      } on PlatformException catch (_) {
        // Ignore release errors
      }
      _isInitialized = false;
    }
  }

  /// Start synchronized playback with the video preview.
  ///
  /// Uses a timer to feed audio samples in chunks, keeping the
  /// audio buffer filled and synchronized with the video frame
  /// timer in the EditorNotifier.
  void startSynchronizedPlayback({
    required Future<Float32List> Function(int startMs, int durationMs)
        sampleProvider,
    required void Function(int currentTimeMs) onTimeUpdate,
    int totalDurationMs = 0,
  }) {
    if (!_isInitialized) return;

    unawaited(
        _startLegacyPlayback(sampleProvider, onTimeUpdate, totalDurationMs));
  }

  Future<void> _startLegacyPlayback(
    Future<Float32List> Function(int startMs, int durationMs) sampleProvider,
    void Function(int currentTimeMs) onTimeUpdate,
    int totalDurationMs,
  ) async {
    await stop();
    await play();
    final epoch = _writeEpoch;
    var feeding = false;
    var nextAudioMs = 0;
    const chunkDurationMs = 100; // Feed 100ms of audio at a time
    const tickMs = 33; // ~30fps timer tick

    _playbackTimer =
        Timer.periodic(const Duration(milliseconds: tickMs), (timer) async {
      if (!_isPlaying) {
        timer.cancel();
        _playbackTimer = null;
        return;
      }

      _currentPositionMs += tickMs;

      if (totalDurationMs > 0 && _currentPositionMs >= totalDurationMs) {
        _currentPositionMs = 0;
        await stop();
        onTimeUpdate(0);
        return;
      }

      onTimeUpdate(_currentPositionMs);

      if (feeding ||
          epoch != _writeEpoch ||
          nextAudioMs > _currentPositionMs + chunkDurationMs) return;
      feeding = true;
      try {
        final samples = await sampleProvider(nextAudioMs, chunkDurationMs);
        if (epoch == _writeEpoch && samples.isNotEmpty) {
          await writeSamples(samples);
          nextAudioMs += chunkDurationMs;
        }
      } catch (e) {
        developer.log(
          'Error feeding audio samples: $e',
          name: 'AudioPlayerService',
        );
      } finally {
        feeding = false;
      }
    });
  }

  /// Stop synchronized playback.
  void stopSynchronizedPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    stop();
  }
}

class _PendingAudio {
  _PendingAudio(this.samples);
  final Float32List samples;
  int offset = 0;
}
