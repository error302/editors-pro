import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Service for synchronized audio playback alongside video preview.
///
/// On Android, this uses the platform's AudioTrack API via a method
/// channel to play PCM float32 samples received from the Rust engine.
/// The playback is synchronized with the video preview timer to keep
/// audio and video within ±50ms.
class AudioPlayerService {
  AudioPlayerService._();
  static const _channel = MethodChannel('com.editorspro/audio');

  static final AudioPlayerService instance = AudioPlayerService._();

  bool _isPlaying = false;
  bool _isInitialized = false;
  int _currentPositionMs = 0;
  Timer? _playbackTimer;

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
    try {
      final result = await _channel.invokeMethod<bool>('initialize', {
        'sampleRate': sampleRate,
        'channels': channels,
      });
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

  /// Write PCM float32 samples to the audio buffer for playback.
  ///
  /// The samples should be interleaved stereo (L R L R ...) at the
  /// configured sample rate. This method can be called repeatedly
  /// to stream audio data as it becomes available.
  Future<void> writeSamples(Float32List samples) async {
    if (!_isInitialized) return;
    try {
      // Convert Float32List to Uint8List for the platform channel
      final bytes = samples.buffer.asUint8List();
      await _channel.invokeMethod<void>('writeSamples', {
        'samples': bytes,
      });
    } on PlatformException catch (e) {
      developer.log(
        'Failed to write audio samples: ${e.message}',
        name: 'AudioPlayerService',
        error: e,
      );
    }
  }

  /// Start audio playback from the current position.
  Future<void> play() async {
    if (!_isInitialized || _isPlaying) return;
    try {
      await _channel.invokeMethod<void>('play');
      _isPlaying = true;
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
    if (!_isInitialized || !_isPlaying) return;
    try {
      await _channel.invokeMethod<void>('pause');
      _isPlaying = false;
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
    if (!_isInitialized) return;
    try {
      await _channel.invokeMethod<void>('stop');
      _isPlaying = false;
      _currentPositionMs = 0;
      _playbackTimer?.cancel();
      _playbackTimer = null;
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
    if (!_isInitialized) return;
    try {
      await _channel.invokeMethod<void>('seekTo', {
        'positionMs': positionMs,
      });
      _currentPositionMs = positionMs;
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

    stop();
    play();

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

      // Feed audio samples for the next chunk
      try {
        final samples = await sampleProvider(
          _currentPositionMs,
          chunkDurationMs,
        );
        if (samples.isNotEmpty) {
          await writeSamples(samples);
        }
      } catch (e) {
        developer.log(
          'Error feeding audio samples: $e',
          name: 'AudioPlayerService',
        );
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
