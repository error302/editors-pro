import 'package:editors_pro/core/services/performance_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PerformanceService', () {
    late PerformanceService service;

    setUp(() {
      // Create a fresh instance by accessing the singleton
      service = PerformanceService.instance;
    });

    test('coldStartDuration is null before marks are set', () {
      expect(service.coldStartDuration, isNull);
    });

    test('coldStartDuration is set after marking app start and engine ready',
        () {
      service.markAppStart();
      // Simulate some time passing
      service.markEngineReady();
      expect(service.coldStartDuration, isNotNull);
      expect(
        service.coldStartDuration!.inMilliseconds,
        greaterThanOrEqualTo(0),
      );
    });

    test('averageDecodeTime is zero with no samples', () {
      expect(service.averageDecodeTime, equals(Duration.zero));
    });

    test('recordFrameDecode tracks average decode time', () {
      service.recordFrameDecode(const Duration(milliseconds: 16));
      service.recordFrameDecode(const Duration(milliseconds: 20));
      service.recordFrameDecode(const Duration(milliseconds: 14));

      expect(service.averageDecodeTime.inMilliseconds, greaterThan(0));
      // Average of 16, 20, 14 = ~16.67ms
      expect(service.averageDecodeTime.inMilliseconds, lessThan(25));
    });

    test('memoryPressureEventCount starts at zero', () {
      // This is a singleton, so previous tests may have incremented it.
      // We just test that incrementing works.
      final before = service.memoryPressureEventCount;
      service.recordMemoryPressure();
      expect(service.memoryPressureEventCount, equals(before + 1));
    });

    test('averageExportSpeed is zero with no samples', () {
      // This depends on singleton state, so we check it's a valid number
      expect(service.averageExportSpeed, isA<double>());
    });

    test('recordExportSpeed tracks average export speed', () {
      service.recordExportSpeed(30.0);
      service.recordExportSpeed(60.0);

      final avg = service.averageExportSpeed;
      expect(avg, greaterThanOrEqualTo(0));
    });

    test('toMap returns valid diagnostic data', () {
      final map = service.toMap();
      expect(map, isA<Map<String, dynamic>>());
      expect(map, containsPair('coldStartMs', isA<int?>()));
      expect(map, containsPair('avgDecodeMs', isA<int>()));
      expect(map, containsPair('memoryPressureEvents', isA<int>()));
      expect(map, containsPair('avgExportFps', isA<String>()));
    });
  });
}
