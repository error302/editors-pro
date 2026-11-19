import 'package:editors_pro/core/services/engine_service.dart';
import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/editor/presentation/editor_screen.dart';
import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:editors_pro/features/editor/widgets/inspector_panel.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _project = ProjectModel(
  id: 'phone', name: 'Phone inspector', createdAt: 0, updatedAt: 0,
  width: 1920, height: 1080, fps: 30,
  tracks: [TrackModel(id: 'titles', name: 'Titles', trackType: TrackType.text, clips: [
    ClipModel(id: 'title', assetId: '__text__', startMs: 0, durationMs: 1000,
      properties: {'text_type': 'text_overlay', 'content': 'Phone title persisted',
        'font_family': 'Inter-Bold', 'font_size': 64.0, 'color_hex': '#FF0000'},
    ),
  ])],
);

void main() {
  for (final selection in ['text', 'track', 'empty']) {
    testWidgets('phone inspector sheet renders and scrolls $selection properties', (tester) async {
      EngineService.instance.dispose();
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _Editor editor;
      await tester.pumpWidget(ProviderScope(overrides: [
        currentProjectProvider.overrideWithValue(_project),
        editorProvider.overrideWith((ref) => editor = _Editor(ref, EditorState(
          selectedClipId: selection == 'text' ? 'title' : null,
          selectedTrackId: selection == 'track' ? 'titles' : null,
          showInspector: selection != 'empty',
        ))),
      ], child: const MaterialApp(home: EditorScreen(projectId: 'phone'))));
      await tester.pump();
      await tester.tap(find.byTooltip('Inspector'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final panel = find.byType(InspectorPanel);
      expect(panel, findsOneWidget);
      final scrollable = find.descendant(of: panel, matching: find.byType(Scrollable)).first;
      if (selection == 'text') {
        final content = find.byKey(const ValueKey('text-content'));
        await tester.scrollUntilVisible(content, 220, scrollable: scrollable);
        expect(tester.widget<TextField>(content).controller!.text, 'Phone title persisted');
        expect(tester.widget<Slider>(find.byKey(const ValueKey('text-Size'))).value, 64);
        final blue = find.byKey(const ValueKey('text-color-#0000FF'));
        await tester.scrollUntilVisible(blue, 100, scrollable: scrollable);
        await tester.tap(blue);
        await tester.pump();
        expect(editor.savedColor, '#0000FF');
        expect(editor.savedContent, 'Phone title persisted');
        expect(editor.savedSize, 64);
      } else if (selection == 'track') {
        expect(find.text('Track Inspector'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('VOLUME'), 100, scrollable: scrollable);
      } else {
        expect(find.text('Select a clip'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('GPU ACCELERATION'), 100, scrollable: scrollable);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _Editor extends EditorNotifier {
  _Editor(super.ref, EditorState initial) { state = initial; }
  String? savedColor;
  String? savedContent;
  double? savedSize;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> updateTextOverlay({required String clipId, String? content,
    String? fontFamily, double? fontSize, String? colorHex, double? positionX, double? positionY,
  }) async {
    savedColor = colorHex; savedContent = content; savedSize = fontSize;
    return true;
  }
}
