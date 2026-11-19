import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:editors_pro/features/editor/widgets/editor_toolbar.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('120 fps timecode follows stepped frame index and second carry', (tester) async {
    const project = ProjectModel(id: '120', name: 'Fast motion', createdAt: 0,
        updatedAt: 0, width: 1280, height: 720, fps: 120);
    final container = ProviderContainer(overrides: [
      currentProjectProvider.overrideWithValue(project),
      editorProvider.overrideWith((ref) => _ToolbarEditorNotifier(ref)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: const MaterialApp(home: Scaffold(body: EditorToolbar()))));
    for (final (milliseconds, expected) in [
      (8, '00:00:00:01'), (17, '00:00:00:02'),
      (992, '00:00:00:119'), (1000, '00:00:01:00'),
      (59992, '00:00:59:119'), (60000, '00:01:00:00'),
    ]) {
      container.read(editorProvider.notifier).seekTo(milliseconds);
      await tester.pump();
      expect(find.text(expected), findsOneWidget, reason: 'at $milliseconds ms');
    }
    await tester.pumpWidget(const SizedBox());
  });
}

class _ToolbarEditorNotifier extends EditorNotifier {
  _ToolbarEditorNotifier(super.ref) {
    state = const EditorState(durationMs: 120000);
  }

  @override
  Future<void> initialize() async {}
}
