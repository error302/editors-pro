import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends EditorsProEngineApi {
  _Api() : super.noOp();
  int splits = 0;
  @override
  Future<BigInt> getTimelineDuration() async => BigInt.from(5000);
  @override
  Future<(ClipInfo, ClipInfo)> splitClip({required String clipId, required BigInt timeMs}) async {
    splits++;
    return (
      const ClipInfo(id: 'left', trackId: 'v', assetId: 'asset', startMs: 1000, durationMs: 2000),
      const ClipInfo(id: 'right', trackId: 'v', assetId: 'asset', startMs: 3000, durationMs: 2000),
    );
  }
  @override
  Future<void> trimClip({required String clipId, required BigInt trimStartMs, required BigInt trimEndMs}) async {}
  @override
  Future<void> setFilterLook({required String clipId, required String presetId, double intensity = 1, bool enabled = true}) async {}
}

class _Projects extends ProjectNotifier {
  _Projects(super.ref, {bool locked = false}) {
    state = ProjectState(currentProject: ProjectModel(
      id: 'project', name: 'Editing', createdAt: 0, updatedAt: 0,
      width: 1280, height: 720, fps: 30,
      tracks: [TrackModel(id: 'v', name: 'Video', trackType: TrackType.video,
        orderIndex: 0, clips: [ClipModel(id: 'clip', assetId: 'asset',
          startMs: 1000, durationMs: 4000, locked: locked)])],
    ));
  }
  int syncs = 0;
  @override
  Future<void> syncFromEngine() async { syncs++; }
}

void main() {
  ({ProviderContainer container, EditorNotifier editor, _Api api, _Projects projects}) setup({bool locked = false}) {
    final api = _Api();
    late _Projects projects;
    final container = ProviderContainer(overrides: [
      projectProvider.overrideWith((ref) => projects = _Projects(ref, locked: locked)),
      editorProvider.overrideWith((ref) => EditorNotifier(ref, engineApi: api)),
    ]);
    container.read(projectProvider);
    final editor = container.read(editorProvider.notifier)..selectClip('clip')..setDuration(5000);
    addTearDown(container.dispose);
    return (container: container, editor: editor, api: api, projects: projects);
  }

  test('split selects the actual right-hand clip so subsequent effects have a valid target', () async {
    final h = setup();
    h.editor.seekTo(3000);
    await h.editor.splitAtPlayhead();
    expect(h.container.read(editorProvider).selectedClipId, 'right');
    expect(h.projects.syncs, 1);
    expect(h.container.read(editorProvider).renderRevision, greaterThan(0));
  });

  test('trim synchronizes the durable project model and invalidates the preview', () async {
    final h = setup();
    await h.editor.trimClip(clipId: 'clip', trimStartMs: 500, trimEndMs: 500);
    expect(h.projects.syncs, 1);
    expect(h.container.read(editorProvider).renderRevision, greaterThan(0));
  });

  test('applying a look brings an offscreen selected clip into the viewer', () async {
    final h = setup();
    expect(h.container.read(editorProvider).currentTimeMs, 0);
    expect(await h.editor.setFilterLook('warm'), isTrue);
    expect(h.container.read(editorProvider).currentTimeMs, 1000);
  });

  test('a locked clip cannot be split by invoking the action directly', () async {
    final h = setup(locked: true);
    h.editor.seekTo(3000);
    await h.editor.splitAtPlayhead();
    expect(h.api.splits, 0);
    expect(h.container.read(editorProvider).lastError, contains('locked'));
  });
}
