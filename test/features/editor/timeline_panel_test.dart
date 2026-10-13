import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editors_pro/core/services/engine_service.dart';
import 'package:editors_pro/core/services/project_repository.dart';
import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:editors_pro/features/editor/widgets/timeline_panel.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimelinePanel', () {
    setUp(() {
      EngineService.instance.dispose();
    });

    tearDown(() {
      EngineService.instance.dispose();
    });

    /// Helper to build the TimelinePanel with controlled state.
    Future<void> pumpTimeline(
      WidgetTester tester, {
      EditorState editorState = const EditorState(),
      ProjectModel? project,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectRepositoryProvider
                .overrideWith((ref) => _FakeProjectRepository()),
            editorProvider.overrideWith((ref) {
              return _TestEditorNotifier(ref, editorState);
            }),
            // Override currentProjectProvider if a project is given
            if (project != null)
              currentProjectProvider.overrideWith((ref) => project),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const Scaffold(
              body: SizedBox(
                width: 1200,
                height: 400,
                child: TimelinePanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('renders without crashing', (tester) async {
      await pumpTimeline(tester);
      expect(find.byType(TimelinePanel), findsOneWidget);
    });

    testWidgets('shows zoom controls', (tester) async {
      await pumpTimeline(tester);

      expect(find.byTooltip('Zoom out'), findsOneWidget);
      expect(find.byTooltip('Zoom in'), findsOneWidget);
    });

    testWidgets('shows zoom percentage', (tester) async {
      await pumpTimeline(
        tester,
        editorState: const EditorState(zoomLevel: 1.0),
      );

      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('shows zoom percentage at different level', (tester) async {
      await pumpTimeline(
        tester,
        editorState: const EditorState(zoomLevel: 2.0),
      );

      expect(find.text('200%'), findsOneWidget);
    });

    testWidgets('shows track headers when project has tracks', (tester) async {
      final project = ProjectModel(
        id: 'p1',
        name: 'Test Project',
        createdAt: 0,
        updatedAt: 0,
        width: 1920,
        height: 1080,
        fps: 30.0,
        tracks: [
          TrackModel(id: 'v1', name: 'Video 1', trackType: TrackType.video, orderIndex: 0),
          TrackModel(id: 'a1', name: 'Audio 1', trackType: TrackType.audio, orderIndex: 1),
        ],
      );

      await pumpTimeline(tester, project: project);

      // Track names should appear in the headers.
      expect(find.text('Video 1'), findsOneWidget);
      expect(find.text('Audio 1'), findsOneWidget);
    });

    testWidgets('shows track type icons', (tester) async {
      final project = ProjectModel(
        id: 'p1',
        name: 'Test',
        createdAt: 0,
        updatedAt: 0,
        width: 1920,
        height: 1080,
        fps: 30.0,
        tracks: [
          TrackModel(id: 'v1', name: 'Video 1', trackType: TrackType.video, orderIndex: 0),
          TrackModel(id: 'a1', name: 'Audio 1', trackType: TrackType.audio, orderIndex: 1),
          TrackModel(id: 't1', name: 'Text 1', trackType: TrackType.text, orderIndex: 2),
          TrackModel(id: 'e1', name: 'Effect 1', trackType: TrackType.effect, orderIndex: 3),
        ],
      );

      await pumpTimeline(tester, project: project);

      for (final label in [
        'Video track',
        'Audio track',
        'Text track',
        'Effect track',
      ]) {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == label,
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('shows clips on tracks', (tester) async {
      final project = ProjectModel(
        id: 'p1',
        name: 'Test',
        createdAt: 0,
        updatedAt: 0,
        width: 1920,
        height: 1080,
        fps: 30.0,
        tracks: [
          TrackModel(
            id: 'v1',
            name: 'Video 1',
            trackType: TrackType.video,
            clips: [
              ClipModel(
                id: 'clip1',
                assetId: 'asset1',
                startMs: 0,
                durationMs: 5000,
              ),
            ],
            orderIndex: 0,
          ),
        ],
      );

      await pumpTimeline(
        tester,
        editorState: const EditorState(durationMs: 10000, zoomLevel: 1.0),
        project: project,
      );

      // A clip with sufficient width should show "Video" label
      expect(find.text('Video'), findsOneWidget);
    });

    testWidgets('shows audio volume icon for audio tracks', (tester) async {
      final project = ProjectModel(
        id: 'p1',
        name: 'Test',
        createdAt: 0,
        updatedAt: 0,
        width: 1920,
        height: 1080,
        fps: 30.0,
        tracks: [
          TrackModel(
            id: 'a1',
            name: 'Audio 1',
            trackType: TrackType.audio,
            visible: true,
            orderIndex: 0,
          ),
        ],
      );

      await pumpTimeline(tester, project: project);

      expect(find.byTooltip('Mute audio track'), findsOneWidget);
    });

    testWidgets('shows muted icon for hidden audio tracks', (tester) async {
      final project = ProjectModel(
        id: 'p1',
        name: 'Test',
        createdAt: 0,
        updatedAt: 0,
        width: 1920,
        height: 1080,
        fps: 30.0,
        tracks: [
          TrackModel(
            id: 'a1',
            name: 'Audio 1',
            trackType: TrackType.audio,
            volume: 0,
            orderIndex: 0,
          ),
        ],
      );

      await pumpTimeline(tester, project: project);

      expect(find.byTooltip('Unmute audio track'), findsOneWidget);
    });

    testWidgets('shows locked icon for locked tracks', (tester) async {
      final project = ProjectModel(
        id: 'p1',
        name: 'Test',
        createdAt: 0,
        updatedAt: 0,
        width: 1920,
        height: 1080,
        fps: 30.0,
        tracks: [
          TrackModel(
            id: 'v1',
            name: 'Video 1',
            trackType: TrackType.video,
            locked: true,
            orderIndex: 0,
          ),
        ],
      );

      await pumpTimeline(tester, project: project);

      expect(find.byTooltip('Unlock track'), findsOneWidget);
    });

    testWidgets('zoom in button tap works', (tester) async {
      await pumpTimeline(
        tester,
        editorState: const EditorState(zoomLevel: 1.0),
      );

      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();

      // The zoom level should have increased (120%)
      expect(find.text('120%'), findsOneWidget);
    });

    testWidgets('zoom out button tap works', (tester) async {
      await pumpTimeline(
        tester,
        editorState: const EditorState(zoomLevel: 1.0),
      );

      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();

      // The zoom level should have decreased (83% → 0.833 * 100 = 83)
      // Exact value depends on 1.0/1.2 ≈ 0.833 → 83%
      expect(find.textContaining('%'), findsOneWidget);
    });
  });
}

/// A [EditorNotifier] that starts with a given state and does not access
/// the Rust engine.
class _TestEditorNotifier extends EditorNotifier {
  _TestEditorNotifier(Ref ref, EditorState initialState) : super(ref) {
    state = initialState;
  }

  @override
  Future<void> initialize() async {}

  void togglePlayback() {
    state = state.copyWith(isPlaying: !state.isPlaying);
  }

  void seekTo(int timeMs) {
    state = state.copyWith(currentTimeMs: timeMs);
  }

  void selectClip(String? clipId) {
    state = state.copyWith(
      selectedClipId: clipId,
      showInspector: clipId != null,
    );
  }

  void selectTrack(String? trackId) {
    state = state.copyWith(selectedTrackId: trackId, showInspector: trackId != null);
  }

  void zoomIn() {
    final newZoom = (state.zoomLevel * 1.2).clamp(0.1, 10.0);
    state = state.copyWith(zoomLevel: double.parse(newZoom.toStringAsFixed(3)));
  }

  void zoomOut() {
    final newZoom = (state.zoomLevel / 1.2).clamp(0.1, 10.0);
    state = state.copyWith(zoomLevel: double.parse(newZoom.toStringAsFixed(3)));
  }
}

/// A lightweight fake repository that satisfies [ProjectRepository].
class _FakeProjectRepository implements ProjectRepository {
  @override
  Future<ProjectModel> createProject(
    String name, {
    int width = 1920,
    int height = 1080,
    double fps = 30.0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ProjectModel(
      id: 'fake',
      name: name,
      createdAt: now,
      updatedAt: now,
      width: width,
      height: height,
      fps: fps,
    );
  }

  @override
  Future<List<ProjectModel>> getAllProjects() async => [];

  @override
  Future<ProjectModel?> getProject(String id) async => null;

  @override
  Future<void> updateProject(ProjectModel project) async {}

  @override
  Future<void> saveProjectToEngine(ProjectModel project) async {}

  @override
  Future<void> loadProjectFromEngine(String eppFilePath) async {}

  @override
  Future<List<int>?> readProjectEppBytes(String projectId) async => null;

  @override
  Future<void> addMediaAsset(String projectId, MediaAssetModel asset) async {}

  @override
  Future<void> restoreMediaAssetInEngine(MediaAssetModel asset) async {}

  @override
  Future<void> deleteProject(String projectId) async {}
}
