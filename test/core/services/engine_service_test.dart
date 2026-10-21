import 'package:editors_pro/core/services/engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EngineService', () {
    setUp(() {
      // Start every test from a clean state.
      EngineService.instance.dispose();
    });

    tearDown(() {
      EngineService.instance.dispose();
    });

    test('singleton instance is consistent', () {
      final instance1 = EngineService.instance;
      final instance2 = EngineService.instance;

      expect(identical(instance1, instance2), isTrue);
    });

    test('initial state is not initialized', () {
      expect(EngineService.instance.isInitialized, isFalse);
    });

    test('api getter throws StateError when not initialized', () {
      EngineService.instance.dispose();

      expect(
        () => EngineService.instance.api,
        throwsA(isA<StateError>()),
      );
    });

    test('api StateError has descriptive message', () {
      EngineService.instance.dispose();

      try {
        EngineService.instance.api;
        fail('Expected StateError');
      } on StateError catch (e) {
        expect(e.message, contains('not initialized'));
        expect(e.message, contains('initialize()'));
      }
    });

    test('dispose resets initialization state', () {
      final service = EngineService.instance;

      // Even if never initialized, dispose should be safe to call.
      service.dispose();
      expect(service.isInitialized, isFalse);
    });

    test('dispose can be called multiple times safely', () {
      final service = EngineService.instance;

      service.dispose();
      service.dispose();
      service.dispose();

      expect(service.isInitialized, isFalse);
    });

    test('initialize returns false when native library unavailable', () async {
      // In the test environment the Rust native library is not compiled,
      // so RustLib.init() will throw. EngineService catches this and
      // returns false.
      final result = await EngineService.instance.initialize();

      expect(result, isFalse);
      expect(EngineService.instance.isInitialized, isFalse);
    });

    test('api still throws after failed initialization', () async {
      await EngineService.instance.initialize();

      expect(
        () => EngineService.instance.api,
        throwsA(isA<StateError>()),
      );
    });

    test('dispose after failed init resets cleanly', () async {
      await EngineService.instance.initialize();
      EngineService.instance.dispose();

      expect(EngineService.instance.isInitialized, isFalse);
      expect(
        () => EngineService.instance.api,
        throwsA(isA<StateError>()),
      );
    });

    test('calling initialize multiple times is safe', () async {
      // First call — will fail because the native library isn't compiled.
      final result1 = await EngineService.instance.initialize();
      expect(result1, isFalse);

      // Second call should also return false without throwing.
      final result2 = await EngineService.instance.initialize();
      expect(result2, isFalse);
    });

    test('isInitialized remains false when initialize fails', () async {
      await EngineService.instance.initialize();
      expect(EngineService.instance.isInitialized, isFalse);
    });
  });
}
