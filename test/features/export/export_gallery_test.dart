import 'package:editors_pro/core/services/storage_service.dart';
import 'package:editors_pro/features/export/presentation/export_screen.dart';
import 'package:editors_pro/features/export/providers/export_provider.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.editorspro/storage');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps supported video extensions to Gallery MIME types', () {
    expect(
        StorageService.videoMimeTypeForPath('/export/clip.MP4'), 'video/mp4');
    expect(
      StorageService.videoMimeTypeForPath('/export/clip.mov'),
      'video/quicktime',
    );
    expect(
      StorageService.videoMimeTypeForPath('/export/clip.webm'),
      'video/webm',
    );
    expect(
      StorageService.videoMimeTypeForPath('/export/clip.avi'),
      'video/x-msvideo',
    );
    expect(StorageService.videoMimeTypeForPath('/export/clip.gif'), isNull);
  });

  testWidgets('saves completed Android export to MediaStore', (tester) async {
    const filePath = '/tmp/editors-pro-test.mp4';
    MethodCall? saveCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      saveCall = call;
      return 'content://media/external/video/42';
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exportProvider
              .overrideWith((ref) => _CompletedExportNotifier(filePath)),
          isAndroidPlatformProvider.overrideWithValue(true),
          currentProjectProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: ExportScreen(projectId: 'test')),
      ),
    );

    final saveButton = find.text('Save to Gallery');
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(saveButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(saveCall?.method, 'saveToMediaStore');
    expect(saveCall?.arguments, {
      'filePath': filePath,
      'displayName': 'editors-pro-test.mp4',
      'mimeType': 'video/mp4',
    });
    expect(find.text('Saved to Gallery'), findsOneWidget);
    expect(find.text('Video saved to Movies/EDITORS-PRO.'), findsOneWidget);
  });
}

class _CompletedExportNotifier extends ExportNotifier {
  _CompletedExportNotifier(String filePath) {
    state = ExportState(progress: 1, outputPath: filePath);
  }
}
