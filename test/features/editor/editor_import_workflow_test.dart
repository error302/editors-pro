import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:editors_pro/core/services/engine_service.dart';
import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/editor/presentation/editor_screen.dart';
import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:editors_pro/src/rust/frb_generated.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _initialProject = ProjectModel(
  id: 'imports',
  name: 'Import integration',
  createdAt: 0,
  updatedAt: 0,
  width: 1920,
  height: 1080,
  fps: 30,
  tracks: [TrackModel(id: 'audio', name: 'Audio', trackType: TrackType.audio)],
);

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'the pending picker/import should finish');
}

void main() {
  late Directory directory;
  late _Picker picker;
  late PathProviderPlatform previousPaths;
  FilePicker? previousPicker;

  setUp(() async {
    directory =
        Directory.systemTemp.createTempSync('editors-pro-import-workflow-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    try {
      previousPicker = FilePicker.platform;
    } catch (_) {
      previousPicker = null;
    }
    picker = _Picker();
    FilePicker.platform = picker;
    EngineService.instance.dispose();
    RustLib.dispose();
    await RustLib.init(apiOverride: _AvailableApi());
    expect(await EngineService.instance.initialize(), isTrue);
  });

  tearDown(() {
    EngineService.instance.dispose();
    RustLib.dispose();
    PathProviderPlatform.instance = previousPaths;
    if (previousPicker != null) FilePicker.platform = previousPicker!;
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<_Harness> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late _Projects projects;
    late _Editor editor;
    final router = GoRouter(initialLocation: '/editor', routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Projects home'))),
      GoRoute(
          path: '/editor',
          builder: (_, __) => const EditorScreen(projectId: 'imports')),
    ]);
    await tester.pumpWidget(ProviderScope(overrides: [
      projectProvider.overrideWith((ref) => projects = _Projects(ref)),
      editorProvider.overrideWith((ref) => editor = _Editor(ref)),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
    return _Harness(projects, editor);
  }

  testWidgets(
      'stream-only PlatformFile imports durable bytes and an audio timeline clip',
      (tester) async {
    final harness = await pumpEditor(tester);
    final bytes = List<int>.generate(80, (index) => index);
    await tester.tap(find.byTooltip('Add audio'));
    await tester.pump();
    expect(picker.withReadStreamRequested, isTrue);
    picker.result.complete(FilePickerResult([
      PlatformFile(
        name: 'Provider song.mp3',
        size: bytes.length,
        identifier: 'content://provider/audio/42',
        readStream: Stream.value(bytes),
      )
    ]));
    await _waitFor(tester, () => !harness.editor.state.isImporting);
    expect(harness.editor.importedBytes, [bytes]);
    final project = harness.projects.state.currentProject!;
    expect(project.mediaAssets.single.fileName, 'Provider song.mp3');
    expect(project.mediaAssets.single.filePath, startsWith(directory.path));
    expect(File(project.mediaAssets.single.filePath).readAsBytesSync(), bytes);
    expect(project.tracks.single.clips.single.assetId,
        project.mediaAssets.single.id);
    expect(harness.projects.savedProjects, hasLength(1));
    expect(harness.projects.savedProjects.single.tracks.single.clips,
        hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'back waits through picker and pending import before saving and leaving',
      (tester) async {
    final harness = await pumpEditor(tester);
    final importBarrier = Completer<void>();
    harness.editor.importBarrier = importBarrier;
    await tester.tap(find.byTooltip('Add audio'));
    await tester.pump();
    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pump();
    expect(harness.projects.savedProjects, isEmpty);
    expect(find.text('Projects home'), findsNothing);
    picker.result.complete(FilePickerResult([
      PlatformFile(
        name: 'Slow provider.wav',
        size: 4,
        readStream: Stream.value([1, 2, 3, 4]),
      )
    ]));
    await _waitFor(tester, () => harness.editor.importedBytes.isNotEmpty);
    expect(harness.projects.savedProjects, isEmpty);
    expect(find.text('Projects home'), findsNothing);
    importBarrier.complete();
    await _waitFor(
        tester, () => find.text('Projects home').evaluate().isNotEmpty);
    expect(harness.projects.savedProjects, isNotEmpty);
    expect(
        harness.projects.savedProjects.every((saved) =>
            saved.mediaAssets.length == 1 &&
            saved.tracks.single.clips.length == 1),
        isTrue,
        reason: 'back must never persist a prematurely empty project');
  });

  testWidgets('picker cancellation creates no media file, asset, clip, or save',
      (tester) async {
    final harness = await pumpEditor(tester);
    await tester.tap(find.byTooltip('Add audio'));
    await tester.pump();
    picker.result.complete(null);
    await _waitFor(tester, () => !harness.editor.state.isImporting);
    expect(harness.editor.importedBytes, isEmpty);
    expect(harness.projects.state.currentProject!.mediaAssets, isEmpty);
    expect(harness.projects.state.currentProject!.tracks.single.clips, isEmpty);
    expect(harness.projects.savedProjects, isEmpty);
    expect(directory.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  testWidgets(
      'a picker opened for another project cannot mutate the newly selected project',
      (tester) async {
    final harness = await pumpEditor(tester);
    await tester.tap(find.byTooltip('Add audio'));
    await tester.pump();
    harness.projects.switchProject('new-project');
    await tester.pump();
    picker.result.complete(FilePickerResult([
      PlatformFile(
        name: 'Late provider.mp3',
        size: 3,
        readStream: Stream.value([1, 2, 3]),
      )
    ]));
    await _waitFor(tester, () => !harness.editor.state.isImporting);
    expect(harness.editor.importedBytes, isEmpty);
    expect(harness.projects.state.currentProject!.id, 'new-project');
    expect(harness.projects.state.currentProject!.mediaAssets, isEmpty);
    expect(harness.projects.savedProjects, isEmpty);
    expect(directory.listSync(recursive: true).whereType<File>(), isEmpty);
  });
}

class _Harness {
  _Harness(this.projects, this.editor);
  final _Projects projects;
  final _Editor editor;
}

class _AvailableApi extends EditorsProEngineApi {
  _AvailableApi() : super.noOp();
  @override
  bool get isEngineAvailable => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<Uint8List> getFrame({required BigInt timeMs}) async => Uint8List(0);
  @override
  Future<List<double>> getWaveform(
          {required String assetId, required int numBins}) async =>
      [0.1, 0.2];
}

class _Editor extends EditorNotifier {
  _Editor(super.ref);
  final importedBytes = <List<int>>[];
  Completer<void>? importBarrier;
  @override
  Future<void> initialize() async {}
  @override
  Future<MediaAssetInfo?> importMedia(String filePath) async {
    final bytes = File(filePath).readAsBytesSync();
    importedBytes.add(bytes);
    await importBarrier?.future;
    return MediaAssetInfo(
        id: 'import-${importedBytes.length}',
        filePath: filePath,
        fileName: 'source',
        mediaType: 'Audio',
        durationMs: 1000,
        fileSizeBytes: bytes.length);
  }

  @override
  Future<ClipInfo?> addClipToTrack(
          {required String trackId,
          required String assetId,
          required int startMs,
          int durationMs = 0}) async =>
      ClipInfo(
        id: 'clip-$assetId',
        trackId: trackId,
        assetId: assetId,
        startMs: startMs,
        durationMs: durationMs,
      );
}

class _Projects extends ProjectNotifier {
  _Projects(super.ref) {
    state = const ProjectState(currentProject: _initialProject);
  }
  final savedProjects = <ProjectModel>[];
  void switchProject(String id) {
    state = ProjectState(currentProject: _initialProject.copyWith(id: id));
  }

  @override
  Future<bool> saveCurrentProject() async {
    savedProjects.add(state.currentProject!);
    return true;
  }

  @override
  Future<void> importMedia(
    String filePath,
    String fileName,
    MediaType mediaType, {
    required String assetId,
    int? durationMs,
    int? width,
    int? height,
    int fileSizeBytes = 0,
    String? codec,
    int? bitrate,
  }) async {
    final project = state.currentProject!;
    state = state.copyWith(
        currentProject: project.copyWith(mediaAssets: [
      ...project.mediaAssets,
      MediaAssetModel(
          id: assetId,
          filePath: filePath,
          fileName: fileName,
          mediaType: mediaType,
          durationMs: durationMs,
          width: width,
          height: height,
          fileSizeBytes: fileSizeBytes,
          codec: codec,
          bitrate: bitrate),
    ]));
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Picker extends FilePicker {
  final result = Completer<FilePickerResult?>();
  bool withReadStreamRequested = false;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) {
    withReadStreamRequested = withReadStream;
    return result.future;
  }
}
