import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:editors_pro/core/services/project_repository.dart';
import 'package:editors_pro/data/database/app_database.dart';
import 'package:editors_pro/data/models/project_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'duplicate inserts independent asset ownership only after native clone succeeds',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('editors-copy-test-');
    addTearDown(() => directory.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null,),
    );
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await Directory(p.join(directory.path, 'projects')).create();
    final originalPath = p.join(directory.path, 'projects', 'original.epp');
    await File(originalPath).writeAsString('original saved edited timeline');
    await db.upsertProject(
      ProjectEntriesCompanion.insert(
        id: 'original',
        createdAt: 1,
        updatedAt: 1,
        name: const Value('Original'),
        eppFilePath: Value(originalPath),
      ),
    );
    final sharedSourcePath = p.join(directory.path, 'shared.png');
    await File(sharedSourcePath).writeAsString('preserved source bytes');
    var shouldFail = true;
    final provider = Provider<ProjectRepository>(
      (ref) => ProjectRepository(
        db,
        ref,
        cloner: ({
          required String sourcePath,
          required String outputPath,
          required String projectId,
          required String name,
        }) async {
          if (shouldFail) throw StateError('clone failed');
          expect(await db.getProject(projectId), isNull);
          await File(outputPath).writeAsString('complete cloned timeline');
          return {
            'created_at': 2,
            'settings': {'width': 1920, 'height': 1080, 'fps': 30},
            'timeline': {'duration_ms': 6000},
            'media_assets': [
              {
                'id': 'copied-asset',
                'file_path': sharedSourcePath,
                'file_name': 'shared.png',
                'media_type': 'image',
                'file_size_bytes': 22,
              }
            ],
          };
        },
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repo = container.read(provider);
    await repo.addMediaAsset(
      'original',
      MediaAssetModel(
        id: 'original-asset',
        filePath: sharedSourcePath,
        fileName: 'shared.png',
        mediaType: MediaType.image,
      ),
    );
    await expectLater(repo.duplicateSavedProject('original'), throwsStateError);
    expect(await db.getAllProjects(), hasLength(1));
    shouldFail = false;
    final duplicate = await repo.duplicateSavedProject('original');
    expect(duplicate.durationMs, 6000);
    expect(duplicate.mediaAssets.single.id, 'copied-asset');
    expect((await repo.getProject('original'))!.mediaAssets.single.id,
        'original-asset',);
    expect((await repo.getProject('original'))!.mediaAssets.single.filePath,
        sharedSourcePath,);
    expect(await File(originalPath).readAsString(),
        'original saved edited timeline',);
    expect(
        await File(sharedSourcePath).readAsString(), 'preserved source bytes',);
  });
}
