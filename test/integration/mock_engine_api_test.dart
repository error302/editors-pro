import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorsProEngineApi no-op mode', () {
    late EditorsProEngineApi api;

    setUp(() {
      api = EditorsProEngineApi.noOp();
    });

    test('reports that the native engine is unavailable', () {
      expect(api.isEngineAvailable, isFalse);
    });

    test('fails bridge calls explicitly when the native engine is absent',
        () async {
      await expectLater(
        api.initialize(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('does not return fabricated project data', () async {
      await expectLater(
        api.createProject(name: 'Test project'),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
