import 'package:editors_pro/core/theme/app_theme.dart';
import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/editor/presentation/editor_screen.dart';
import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      final text = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      // Widget tests have no platform monospace font; keep review timecodes readable.
      final numerals = FontLoader('monospace')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
      await Future.wait([text.load(), icons.load(), numerals.load()]);
    }
  });
  for (final size in [
    const Size(393, 852),
    const Size(1440, 900),
    const Size(852, 393)
  ]) {
    testWidgets('editor tools fit ${size.width} x ${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final project = ProjectModel(
          id: 'visual',
          name: 'Coastal study',
          createdAt: 0,
          updatedAt: 0,
          width: 1080,
          height: 1920,
          fps: 24);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentProjectProvider.overrideWithValue(project),
          editorProvider.overrideWith((ref) => _Editor(ref)),
        ],
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const EditorScreen(projectId: 'visual')),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('1080 × 1920  ·  24 fps'), findsOneWidget);
      if (size.width < 900) {
        await tester.tap(find.byTooltip('Editing tools'));
        await tester.pumpAndSettle();
        expect(find.text('Effects'), findsOneWidget);
        expect(find.text('Text'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close tools'));
        await tester.pumpAndSettle();
      }
      // Opt-in snapshots are design review artifacts, not portable pixel baselines.
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await expectLater(
            find.byType(EditorScreen),
            matchesGoldenFile(
                'review/editor-${size.width.toInt()}x${size.height.toInt()}.png'));
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _Editor extends EditorNotifier {
  _Editor(super.ref);
  @override
  Future<void> initialize() async {}
}
