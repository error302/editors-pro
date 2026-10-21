import 'package:editors_pro/core/services/audio_player_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioPlayerService', () {
    late AudioPlayerService service;
    late List<MethodCall> methodCalls;

    setUp(() {
      methodCalls = [];

      // Set up a handler for the platform channel so that method calls
      // are recorded instead of throwing MissingPluginException.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.editorspro/audio'),
        (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          // Return appropriate values for each method
          switch (methodCall.method) {
            case 'initialize':
              return true;
            case 'play':
              return null;
            case 'pause':
              return null;
            case 'stop':
              return null;
            case 'seekTo':
              return null;
            case 'setVolume':
              return null;
            case 'writeSamples':
              return null;
            case 'release':
              return null;
            default:
              return null;
          }
        },
      );

      service = AudioPlayerService.instance;
    });

    tearDown(() {
      // Clean up the mock handler
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.editorspro/audio'),
        null,
      );
    });

    // ─── Singleton ──────────────────────────────────────────────────

    test('singleton instance is consistent', () {
      final instance1 = AudioPlayerService.instance;
      final instance2 = AudioPlayerService.instance;

      expect(identical(instance1, instance2), isTrue);
    });

    // ─── Initial state ──────────────────────────────────────────────

    test('isPlaying returns a bool', () {
      expect(service.isPlaying, isA<bool>());
    });

    test('currentPositionMs returns an int', () {
      expect(service.currentPositionMs, isA<int>());
    });

    test('isInitialized returns a bool', () {
      expect(service.isInitialized, isA<bool>());
    });

    // ─── Initialization ─────────────────────────────────────────────

    test('initialize sets isInitialized to true on success', () async {
      final result = await service.initialize(sampleRate: 44100, channels: 2);

      expect(result, isTrue);
      expect(service.isInitialized, isTrue);
    });

    test('initialize sends correct parameters to platform', () async {
      methodCalls.clear();
      await service.initialize(sampleRate: 48000, channels: 1);

      expect(methodCalls, isNotEmpty);
      expect(methodCalls.first.method, equals('initialize'));
      expect(methodCalls.first.arguments['sampleRate'], equals(48000));
      expect(methodCalls.first.arguments['channels'], equals(1));
    });

    test('initialize with default parameters', () async {
      methodCalls.clear();
      await service.initialize();

      expect(methodCalls.first.arguments['sampleRate'], equals(44100));
      expect(methodCalls.first.arguments['channels'], equals(2));
    });

    // ─── Playback state transitions ─────────────────────────────────

    test('play sets isPlaying to true after initialization', () async {
      await service.initialize();
      await service.play();

      expect(service.isPlaying, isTrue);
    });

    test('play does nothing when not initialized', () async {
      // Create a fresh service by releasing first (ensures uninitialized)
      await service.release();
      // Reset mock handler to throw for initialize (simulating not initialized)
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.editorspro/audio'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'initialize') {
            throw PlatformException(code: 'ERROR', message: 'Not available');
          }
          return null;
        },
      );

      // Try to initialize — will fail
      await service.initialize();
      expect(service.isInitialized, isFalse);

      // Play should do nothing
      await service.play();
      expect(service.isPlaying, isFalse);

      // Restore mock handler
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.editorspro/audio'),
        (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          switch (methodCall.method) {
            case 'initialize':
              return true;
            default:
              return null;
          }
        },
      );
    });

    test('pause sets isPlaying to false', () async {
      await service.initialize();
      await service.play();
      expect(service.isPlaying, isTrue);

      await service.pause();
      expect(service.isPlaying, isFalse);
    });

    test('stop resets isPlaying and position', () async {
      await service.initialize();
      await service.play();
      expect(service.isPlaying, isTrue);

      await service.stop();
      expect(service.isPlaying, isFalse);
      expect(service.currentPositionMs, equals(0));
    });

    test('full state transition sequence works', () async {
      // initialize
      await service.initialize();
      expect(service.isInitialized, isTrue);
      expect(service.isPlaying, isFalse);

      // play
      await service.play();
      expect(service.isPlaying, isTrue);

      // pause
      await service.pause();
      expect(service.isPlaying, isFalse);

      // play again
      await service.play();
      expect(service.isPlaying, isTrue);

      // stop
      await service.stop();
      expect(service.isPlaying, isFalse);
      expect(service.currentPositionMs, equals(0));
    });

    // ─── Seek ───────────────────────────────────────────────────────

    test('seekTo updates currentPositionMs', () async {
      await service.initialize();
      await service.seekTo(5000);

      expect(service.currentPositionMs, equals(5000));
    });

    test('seekTo sends correct parameters to platform', () async {
      await service.initialize();
      methodCalls.clear();

      await service.seekTo(3000);

      final seekCalls = methodCalls.where((c) => c.method == 'seekTo').toList();
      expect(seekCalls.length, equals(1));
      expect(seekCalls.first.arguments['positionMs'], equals(3000));
    });

    // ─── Volume ─────────────────────────────────────────────────────

    test('setVolume sends value to platform', () async {
      await service.initialize();
      methodCalls.clear();

      await service.setVolume(0.5);

      final volumeCalls =
          methodCalls.where((c) => c.method == 'setVolume').toList();
      expect(volumeCalls.length, equals(1));
      expect(volumeCalls.first.arguments['volume'], equals(0.5));
    });

    test('setVolume clamps value above 1.0', () async {
      await service.initialize();
      methodCalls.clear();

      await service.setVolume(2.5);

      final volumeCalls =
          methodCalls.where((c) => c.method == 'setVolume').toList();
      expect(volumeCalls.length, equals(1));
      expect(volumeCalls.first.arguments['volume'], equals(1.0));
    });

    test('setVolume clamps value below 0.0', () async {
      await service.initialize();
      methodCalls.clear();

      await service.setVolume(-0.5);

      final volumeCalls =
          methodCalls.where((c) => c.method == 'setVolume').toList();
      expect(volumeCalls.length, equals(1));
      expect(volumeCalls.first.arguments['volume'], equals(0.0));
    });

    // ─── Release ────────────────────────────────────────────────────

    test('release sets isInitialized to false', () async {
      await service.initialize();
      expect(service.isInitialized, isTrue);

      await service.release();
      expect(service.isInitialized, isFalse);
    });

    test('release also stops playback', () async {
      await service.initialize();
      await service.play();
      expect(service.isPlaying, isTrue);

      await service.release();
      expect(service.isPlaying, isFalse);
      expect(service.isInitialized, isFalse);
    });

    test('release resets position', () async {
      await service.initialize();
      await service.seekTo(5000);
      expect(service.currentPositionMs, equals(5000));

      await service.release();
      expect(service.currentPositionMs, equals(0));
    });

    // ─── Platform exception handling ─────────────────────────────────

    test('initialize handles PlatformException gracefully', () async {
      // Override handler to throw PlatformException
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.editorspro/audio'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'ERROR', message: 'Audio init failed');
        },
      );

      final result = await service.initialize();

      expect(result, isFalse);
      expect(service.isInitialized, isFalse);
    });
  });
}
