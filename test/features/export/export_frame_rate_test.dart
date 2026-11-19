import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/export/presentation/export_screen.dart';
import 'package:editors_pro/features/export/providers/export_provider.dart';
import 'package:editors_pro/features/onboarding/providers/onboarding_provider.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:editors_pro/features/settings/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('export defaults retain project dimensions and 120 fps', (tester) async {
    SharedPreferences.setMockInitialValues({'settings_default_codec': 'H.265'});
    final preferences = await SharedPreferences.getInstance();
    final exporting = _CaptureExportNotifier();
    const project = ProjectModel(id: '120', name: 'Fast motion', createdAt: 0,
        updatedAt: 0, width: 1280, height: 720, fps: 120);
    await tester.pumpWidget(ProviderScope(overrides: [
      currentProjectProvider.overrideWithValue(project),
      sharedPreferencesProvider.overrideWithValue(preferences),
      settingsProvider.overrideWith((ref) => SettingsNotifier(preferences)),
      exportProvider.overrideWith((ref) => exporting),
      isAndroidPlatformProvider.overrideWithValue(false),
    ], child: const MaterialApp(home: ExportScreen(projectId: '120'))));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pump();
    final summary = find.byKey(const ValueKey('export-summary'));
    expect(find.descendant(of: summary, matching: find.text('120 fps')), findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('1280 × 720')), findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('H.265')), findsOneWidget);
    final rate = find.byKey(const ValueKey('export-frame-rate'));
    await tester.ensureVisible(rate);
    await tester.pump();
    expect(find.textContaining('For TikTok, export at 60 fps or lower.'), findsOneWidget);
    await tester.tap(rate);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('50 fps').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('export-submit')), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('export-submit')));
    await tester.pump();
    expect(exporting.fps, 50);
    expect(exporting.dimensions, (1280, 720));
    expect(exporting.codec, 'H.265');
    await tester.pumpWidget(const SizedBox());
  });
}

class _CaptureExportNotifier extends ExportNotifier {
  double? fps;
  (int?, int?)? dimensions;
  String? codec;

  @override
  Future<void> startExport({required String preset, String? outputPath,
      String codec = 'H.264', String format = 'MP4', double fps = 30,
      int? customWidth, int? customHeight, int? customBitrate}) async {
    this.fps = fps;
    dimensions = (customWidth, customHeight);
    this.codec = codec;
  }
}
