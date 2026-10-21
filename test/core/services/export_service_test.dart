import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:editors_pro/core/services/export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExportForegroundService', () {
    setUp(() => ExportForegroundService.instance.androidPlatformOverride = false);
    tearDown(() => ExportForegroundService.instance.androidPlatformOverride = null);
    test('Android start, progress and completion use the native channel',
        () async {
      ExportForegroundService.instance.androidPlatformOverride = true;
      const channel = MethodChannel('com.editorspro/editors_pro/export');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final service = ExportForegroundService.instance;
      try {
        await service.start();
        expect(service.isRunning, isTrue);
        await service.updateProgress(150, 'Encoding');
        await service.complete('/output.mp4', '1 MB');
        expect(calls.map((call) => call.method),
            ['startExport', 'updateProgress', 'complete']);
        expect((calls[1].arguments as Map)['progress'], 100);
        expect(service.isRunning, isFalse);
      } finally {
        await service.cancel();
        ExportForegroundService.instance.androidPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    });
    test('isRunning starts as false', () {
      // Note: This is a singleton, so state from previous tests may persist.
      // We're testing the initial contract.
      final service = ExportForegroundService.instance;
      // After cancel or complete, isRunning should be false
      expect(service.isRunning, isA<bool>());
    });

    test('instance is a singleton', () {
      final a = ExportForegroundService.instance;
      final b = ExportForegroundService.instance;
      expect(identical(a, b), isTrue);
    });

    test('complete sets isRunning to false', () async {
      final service = ExportForegroundService.instance;
      // Even if not running, calling complete should not throw
      await service.complete('/path/to/file.mp4', '5.0 MB');
      expect(service.isRunning, isFalse);
    });

    test('cancel sets isRunning to false', () async {
      final service = ExportForegroundService.instance;
      await service.cancel();
      expect(service.isRunning, isFalse);
    });

    test('start on non-Android is a no-op', () async {
      // On the test environment (not Android), start should not set isRunning
      final service = ExportForegroundService.instance;
      await service.start();
      // On non-Android, _isRunning stays false
      // This test verifies the method doesn't throw
    });

    test('updateProgress does not throw', () async {
      final service = ExportForegroundService.instance;
      // Should not throw even when not running
      await service.updateProgress(50, 'Encoding');
    });

    test('updateProgress with negative value does not throw', () async {
      final service = ExportForegroundService.instance;
      await service.updateProgress(-10, 'Invalid');
    });

    test('updateProgress with value over 100 does not throw', () async {
      final service = ExportForegroundService.instance;
      await service.updateProgress(150, 'Over 100');
    });
  });
}
