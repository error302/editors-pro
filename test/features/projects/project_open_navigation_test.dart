import 'dart:async';

import 'package:editors_pro/core/services/engine_service.dart';
import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/projects/presentation/project_home_screen.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _savedProject = ProjectModel(
  id: 'saved-project',
  name: 'Saved edit',
  createdAt: 1,
  updatedAt: 1,
  width: 1920,
  height: 1080,
  fps: 30,
  durationMs: 6000,
  eppFilePath: '/saved/project.epp',
);

void main() {
  testWidgets('Edit navigates after loading disposes the tapped project card', (tester) async {
    EngineService.instance.dispose();
    late _DelayedProjectNotifier notifier;
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ProjectHomeScreen()),
      GoRoute(path: '/editor/:projectId', builder: (_, state) => Scaffold(
        body: Text('Editor ${state.pathParameters['projectId']}'),
      )),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [projectProvider.overrideWith((ref) => notifier = _DelayedProjectNotifier(ref))],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pump();
    // The loading frame removes the LayoutBuilder/card BuildContext that
    // handled the tap, while the home screen's State remains mounted.
    expect(find.text('Saved edit'), findsNothing);
    expect(find.byType(ProjectHomeScreen), findsOneWidget);
    notifier.opened.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Editor saved-project'), findsOneWidget);
    expect(find.byType(ProjectHomeScreen), findsNothing);
  });
}

class _DelayedProjectNotifier extends ProjectNotifier {
  _DelayedProjectNotifier(super.ref) {
    state = const ProjectState(recentProjects: [_savedProject]);
  }
  final opened = Completer<bool>();
  @override
  Future<void> loadProjects() async {}
  @override
  Future<bool> openProject(ProjectModel project) async {
    state = state.copyWith(isLoading: true);
    final result = await opened.future;
    state = state.copyWith(isLoading: false, currentProject: result ? project : null);
    return result;
  }
}
