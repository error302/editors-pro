import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:editors_pro/core/services/engine_service.dart';
import 'package:editors_pro/core/services/project_repository.dart';
import 'package:editors_pro/data/database/app_database.dart';
import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:editors_pro/src/rust/frb_generated.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase db;
  late ProviderContainer container;
  late ProjectRepository repo;
  late _Engine engine;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('editors-save-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    EngineService.instance.dispose();
    RustLib.dispose();
    engine = _Engine();
    await RustLib.init(apiOverride: engine);
    expect(await EngineService.instance.initialize(), isTrue);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final provider =
        Provider<ProjectRepository>((ref) => ProjectRepository(db, ref));
    container = ProviderContainer();
    repo = container.read(provider);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    EngineService.instance.dispose();
    RustLib.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await directory.delete(recursive: true);
  });

  test(
      'missing previously saved timeline fails instead of opening an empty replacement',
      () async {
    final path = p.join(directory.path, 'projects', 'saved.epp');
    final saved = ProjectModel(
      id: 'saved',
      name: 'Important edits',
      createdAt: 1,
      updatedAt: 1,
      width: 1920,
      height: 1080,
      fps: 30,
      durationMs: 5000,
      eppFilePath: path,
    );
    await expectLater(repo.activateProjectInEngine(saved), throwsStateError);
    expect(engine.created, 0);
    expect(engine.saved, 0);
    expect(await File(path).exists(), isFalse);
  });

  test(
      'failed native save leaves existing database timeline metadata unchanged',
      () async {
    await db.upsertProject(
      ProjectEntriesCompanion.insert(
        id: 'saved',
        createdAt: 1,
        updatedAt: 3,
        durationMs: const Value(5000),
        eppFilePath: const Value('/original/saved.epp'),
      ),
    );
    const edited = ProjectModel(
      id: 'saved',
      name: 'Edited',
      createdAt: 1,
      updatedAt: 4,
      width: 1920,
      height: 1080,
      fps: 30,
      durationMs: 12000,
    );
    await expectLater(repo.saveProjectToEngine(edited), throwsStateError);
    final row = (await db.getProject('saved'))!;
    expect(row.durationMs, 5000);
    expect(row.updatedAt, 3);
    expect(row.eppFilePath, '/original/saved.epp');
    expect(engine.saved, 1);
  });
}

class _Engine extends EditorsProEngineApi {
  _Engine() : super.noOp();
  int created = 0;
  int saved = 0;
  @override
  bool get isEngineAvailable => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<ProjectInfo> createProject(
      {required String name, BridgeProjectSettings? settings,}) async {
    created++;
    return ProjectInfo(
        id: 'engine', name: name, width: 1920, height: 1080, fps: 30,);
  }

  @override
  Future<void> saveProject({required String filePath}) async {
    saved++;
    throw StateError('disk full');
  }
}
