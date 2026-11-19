import 'dart:async';

import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/editor/widgets/editor_toolbar.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('Back waits for save and keeps the editor open when saving fails',
      (tester) async {
    late _Notifier notifier;
    final router = GoRouter(
      initialLocation: '/editor',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Project list')),
        ),
        GoRoute(
          path: '/editor',
          builder: (_, __) => const Scaffold(body: EditorToolbar()),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectProvider.overrideWith((ref) => notifier = _Notifier(ref)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pump();
    expect(find.byType(EditorToolbar), findsOneWidget);
    expect(find.text('Project list'), findsNothing);
    notifier.save.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(EditorToolbar), findsOneWidget);
    expect(find.textContaining('Could not save project'), findsOneWidget);

    notifier.save = Completer<bool>();
    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pump();
    notifier.save.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Project list'), findsOneWidget);
    expect(find.byType(EditorToolbar), findsNothing);
  });
}

class _Notifier extends ProjectNotifier {
  _Notifier(super.ref) {
    state = const ProjectState(
      currentProject: ProjectModel(
        id: 'a',
        name: 'Unsaved edit',
        createdAt: 1,
        updatedAt: 1,
        width: 1920,
        height: 1080,
        fps: 30,
      ),
    );
  }
  Completer<bool> save = Completer<bool>();
  @override
  Future<bool> saveCurrentProject() => save.future;
}
