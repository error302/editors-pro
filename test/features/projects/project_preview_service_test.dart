import 'dart:async';
import 'dart:io';

import 'package:editors_pro/core/services/project_preview_service.dart';
import 'package:editors_pro/data/models/project_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late File projectFile;
  late File source;
  late _Backend backend;
  late ProjectPreviewService service;
  late ProjectModel project;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('editors-preview-test-');
    await Directory(p.join(directory.path, 'projects')).create();
    projectFile = await File(p.join(directory.path, 'projects', 'project.epp'))
        .writeAsString('saved timeline A');
    source = await File(p.join(directory.path, 'source.png'))
        .writeAsString('source version A');
    backend = _Backend(source.path);
    service = ProjectPreviewService(
      backend: backend,
      documentsDirectory: () async => directory,
      cacheDirectory: () async => Directory(p.join(directory.path, 'cache')),
      pollInterval: const Duration(milliseconds: 1),
    );
    project = ProjectModel(
      id: 'project',
      name: 'Saved timeline',
      createdAt: 1,
      updatedAt: 1,
      width: 1920,
      height: 1080,
      fps: 30,
      eppFilePath: projectFile.path,
    );
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
      'cover then playable preview cache survives a fresh service; no source playback shortcut',
      () async {
    final cover = await service.ensure(project);
    expect(cover.coverPath, isNot(source.path));
    expect(cover.videoPath, isNull);
    final preview = await service.ensure(project, playable: true);
    expect(await File(preview.videoPath!).exists(), isTrue);
    expect(preview.durationMs, 23000);
    expect(preview.previewDurationMs, 10000);
    final restarted = ProjectPreviewService(
      backend: backend,
      documentsDirectory: () async => directory,
      cacheDirectory: () async => Directory(p.join(directory.path, 'cache')),
    );
    final replay = await restarted.ensure(project, playable: true);
    expect(replay.videoPath, preview.videoPath);
    expect(backend.started, 2);
  });

  test('timeline changes and source replacements invalidate cached previews',
      () async {
    final first = await service.ensure(project, playable: true);
    await projectFile.writeAsString('saved edited timeline B');
    final edited = await service.ensure(project, playable: true);
    expect(edited.key, isNot(first.key));
    await source.writeAsString('source version B');
    final replaced = await service.ensure(project, playable: true);
    expect(replaced.key, isNot(edited.key));
    expect(backend.started, 3);
  });

  test(
      'corrupt and missing cache files regenerate instead of being advertised as ready',
      () async {
    final first = await service.ensure(project, playable: true);
    await File(first.videoPath!).writeAsString('corrupted');
    await service.ensure(project, playable: true);
    expect(backend.started, 2);
    await File(first.coverPath!).delete();
    await service.ensure(project, playable: true);
    expect(backend.started, 3);
  });

  test('concurrent identical preview requests share one render job', () async {
    final results = await Future.wait(
      List.generate(4, (_) => service.ensure(project, playable: true)),
    );
    expect(results.map((item) => item.key).toSet(), hasLength(1));
    expect(backend.started, 1);
  });

  test(
      'missing or corrupt immutable cache input recovers from the durable project',
      () async {
    final first = await service.ensure(project, playable: true);
    final root = Directory(p.dirname(p.dirname(first.coverPath!)));
    final input = await root
            .list()
            .firstWhere((entry) => entry is File && entry.path.endsWith('.epp'))
        as File;
    await input.delete();
    await service.ensure(project, playable: true);
    expect(await input.readAsString(), await projectFile.readAsString());
    await input.writeAsString('corrupt cached snapshot');
    await service.ensure(project, playable: true);
    expect(await input.readAsString(), await projectFile.readAsString());
    expect(backend.started, 1);
  });

  test(
      'missing saved timeline or source fails visibly without creating an empty project',
      () async {
    await source.delete();
    await expectLater(service.ensure(project), throwsStateError);
    expect(backend.started, 0);
    await projectFile.delete();
    await expectLater(service.ensure(project), throwsStateError);
    expect(backend.started, 0);
  });

  test('empty projects have no misleading playable artifact', () async {
    backend.durationMs = 0;
    final preview = await service.ensure(project, playable: true);
    expect(preview.isEmpty, isTrue);
    expect(preview.videoPath, isNull);
    expect(backend.started, 0);
  });

  test(
      'save during rendering rejects obsolete results and retry uses new timeline',
      () async {
    backend.gate = Completer<void>();
    final rendering = service.ensure(project, playable: true);
    final failure = expectLater(rendering, throwsStateError);
    await backend.didStart.future;
    await projectFile.writeAsString('new saved timeline');
    service.invalidate(project.id);
    backend.gate!.complete();
    await failure;
    backend.gate = null;
    final current = await service.ensure(project, playable: true);
    expect(current.videoPath, isNotNull);
    expect(backend.started, 2);
  });
}

/// Verifies cache/job orchestration; real encoding is covered by native workflows.
class _Backend implements ProjectPreviewBackend {
  _Backend(this.source);
  final String source;
  int started = 0;
  int durationMs = 23000;
  Completer<void>? gate;
  final didStart = Completer<void>();
  @override
  Future<Map<String, dynamic>> inspect(String path) async => {
        'source_paths': [source],
        'duration_ms': durationMs,
        'width': 1920,
        'height': 1080,
      };
  @override
  Future<Map<String, dynamic>> start(
    String path,
    String cover,
    String? video,
  ) async {
    started++;
    await File(cover)
        .writeAsString('cover from ${await File(path).readAsString()}');
    if (video != null) {
      await File(video)
          .writeAsString('encoded timeline ${await File(path).readAsString()}');
    }
    if (!didStart.isCompleted) didStart.complete();
    return {
      'job_id': 'job-$started',
      'cover_ready': true,
      'video_ready': video != null,
      'finished': gate == null,
      'error': null,
    };
  }

  @override
  Future<Map<String, dynamic>> status(String jobId) async {
    await gate?.future;
    return {
      'job_id': jobId,
      'cover_ready': true,
      'video_ready': true,
      'finished': true,
      'error': null,
    };
  }

  @override
  Future<void> release(String jobId) async {}
}
