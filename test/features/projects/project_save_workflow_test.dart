import 'dart:async';

import 'package:editors_pro/core/services/project_repository.dart';
import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _project = ProjectModel(
  id: 'a',
  name: 'Edited A',
  createdAt: 1,
  updatedAt: 1,
  width: 1920,
  height: 1080,
  fps: 30,
  durationMs: 8000,
);

void main() {
  test(
      'failed save before New Project keeps the unsaved current project selected',
      () async {
    final repo = _Repository()..failSave = true;
    final container = ProviderContainer(
      overrides: [
        projectRepositoryProvider.overrideWithValue(repo),
        projectProvider.overrideWith((ref) => _Notifier(ref)),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(projectProvider.notifier) as _Notifier;
    notifier.select(_project);
    expect(await notifier.createProject('Another project'), isNull);
    expect(container.read(projectProvider).currentProject, _project);
    expect(repo.saves, 1);
  });

  test('failed durable save keeps prior metadata and reports failure',
      () async {
    final repo = _Repository()..failSave = true;
    final container = ProviderContainer(
      overrides: [
        projectRepositoryProvider.overrideWithValue(repo),
        projectProvider.overrideWith((ref) => _Notifier(ref)),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(projectProvider.notifier) as _Notifier;
    notifier.select(_project);
    expect(await notifier.saveCurrentProject(), isFalse);
    expect(repo.metadataWrites, 0);
    expect(container.read(projectProvider).currentProject!.updatedAt, 1);
    expect(container.read(projectProvider).error, contains('Could not save'));
  });

  test('successful save refreshes durable path and recent-project duration',
      () async {
    final repo = _Repository();
    final container = ProviderContainer(
      overrides: [
        projectRepositoryProvider.overrideWithValue(repo),
        projectProvider.overrideWith((ref) => _Notifier(ref)),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(projectProvider.notifier) as _Notifier;
    notifier.select(_project);
    expect(await notifier.saveCurrentProject(), isTrue);
    final state = container.read(projectProvider);
    expect(state.currentProject!.eppFilePath, '/saved/a.epp');
    expect(state.recentProjects.single.durationMs, 8000);
    notifier.closeProject();
    expect(container.read(projectProvider).currentProject, isNull);
  });

  test(
      'concurrent save requests cannot write a second timeline before the first finishes',
      () async {
    final repo = _Repository()..gate = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        projectRepositoryProvider.overrideWithValue(repo),
        projectProvider.overrideWith((ref) => _Notifier(ref)),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(projectProvider.notifier) as _Notifier;
    notifier.select(_project);
    final first = notifier.saveCurrentProject();
    final second = notifier.saveCurrentProject();
    await Future<void>.delayed(Duration.zero);
    expect(repo.saves, 1);
    repo.gate!.complete();
    expect(await Future.wait([first, second]), [true, true]);
    expect(repo.saves, 2);
    expect(repo.maximumWriters, 1);
  });
}

class _Notifier extends ProjectNotifier {
  _Notifier(super.ref);
  void select(ProjectModel project) =>
      state = ProjectState(currentProject: project);
}

class _Repository implements ProjectRepository {
  bool failSave = false;
  int metadataWrites = 0;
  int saves = 0;
  int writers = 0;
  int maximumWriters = 0;
  Completer<void>? gate;
  @override
  Future<void> updateProject(ProjectModel project) async {
    metadataWrites++;
  }

  @override
  Future<void> saveProjectToEngine(ProjectModel project) async {
    saves++;
    writers++;
    maximumWriters = writers > maximumWriters ? writers : maximumWriters;
    try {
      await gate?.future;
      if (failSave) throw StateError('disk full');
    } finally {
      writers--;
    }
  }

  @override
  Future<ProjectModel?> getProject(String id) async =>
      _project.copyWith(eppFilePath: '/saved/a.epp', updatedAt: 25);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
