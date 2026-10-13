import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editors_pro/core/services/engine_service.dart';
import 'package:editors_pro/core/services/project_repository.dart';
import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:editors_pro/features/editor/widgets/inspector_panel.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InspectorPanel', () {
    setUp(() {
      EngineService.instance.dispose();
    });

    tearDown(() {
      EngineService.instance.dispose();
    });

    /// Helper to pump the InspectorPanel with controlled providers.
    Future<void> pumpInspector(
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
            if (project != null)
              currentProjectProvider.overrideWith((ref) => project),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const Scaffold(
              body: SizedBox(
                width: 400,
                height: 800,
                child: InspectorPanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    // ─── Empty state ────────────────────────────────────────────────

    testWidgets('renders without crashing', (tester) async {
      await pumpInspector(tester);
      expect(find.byType(InspectorPanel), findsOneWidget);
    });

    testWidgets('shows empty state when no clip selected', (tester) async {
      await pumpInspector(tester);

      // The empty state shows "Select a clip" text.
      expect(find.text('Select a clip'), findsOneWidget);
    });

    testWidgets('empty state shows touch icon', (tester) async {
      await pumpInspector(tester);

      expect(find.byIcon(Icons.touch_app), findsOneWidget);
    });

    testWidgets('empty state shows helper text', (tester) async {
      await pumpInspector(tester);

      expect(
        find.text('Tap any clip on the timeline\nto view its properties'),
        findsOneWidget,
      );
    });

    // ─── Clip selected ──────────────────────────────────────────────

    testWidgets('shows clip properties when a clip is selected',
        (tester) async {
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
                speed: 1.0,
                opacity: 1.0,
              ),
            ],
            orderIndex: 0,
          ),
        ],
      );

      await pumpInspector(
        tester,
        editorState: const EditorState(
          selectedClipId: 'clip1',
          showInspector: true,
        ),
        project: project,
      );

      // Header should say "Inspector"
      expect(find.text('Inspector'), findsOneWidget);
      // The selected clip inspector is a scrollable phone-friendly panel.
      expect(find.text('TIMING'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('SPEED'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('SPEED'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('OPACITY'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('OPACITY'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('EFFECTS'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('EFFECTS'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('TRANSITIONS'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('TRANSITIONS'), findsOneWidget);
    });

    testWidgets('shows video clip type badge', (tester) async {
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
              ClipModel(id: 'clip1', assetId: 'a1', startMs: 0, durationMs: 5000),
            ],
            orderIndex: 0,
          ),
        ],
      );

      await pumpInspector(
        tester,
        editorState: const EditorState(
          selectedClipId: 'clip1',
          showInspector: true,
        ),
        project: project,
      );

      expect(find.text('VIDEO CLIP'), findsOneWidget);
    });

    testWidgets('shows audio clip type badge', (tester) async {
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
            clips: [
              ClipModel(id: 'clip1', assetId: 'a1', startMs: 0, durationMs: 5000),
            ],
            orderIndex: 0,
          ),
        ],
      );

      await pumpInspector(
        tester,
        editorState: const EditorState(
          selectedClipId: 'clip1',
          showInspector: true,
        ),
        project: project,
      );

      expect(find.text('AUDIO CLIP'), findsOneWidget);
    });

    testWidgets('shows timing properties for selected clip', (tester) async {
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
                assetId: 'a1',
                startMs: 1000,
                durationMs: 5000,
                trimStartMs: 200,
                trimEndMs: 100,
              ),
            ],
            orderIndex: 0,
          ),
        ],
      );

      await pumpInspector(
        tester,
        editorState: const EditorState(
          selectedClipId: 'clip1',
          showInspector: true,
        ),
        project: project,
      );

      // Property rows for timing
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Trim Start'), findsOneWidget);
      expect(find.text('Trim End'), findsOneWidget);
      // Trim values are displayed as "200ms" and "100ms"
      expect(find.text('200ms'), findsOneWidget);
      expect(find.text('100ms'), findsOneWidget);
    });

    testWidgets('shows effects section for selected clip', (tester) async {
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
                assetId: 'a1',
                startMs: 0,
                durationMs: 5000,
                effects: [
                  EffectModel(
                    id: 'fx1',
                    name: 'Brightness',
                    effectType: 'brightness',
                    parameters: [
                      EffectParameterModel(
                        name: 'value',
                        displayName: 'Brightness',
                        value: 0.5,
                        minValue: -1.0,
                        maxValue: 1.0,
                        defaultValue: 0.0,
                        step: 0.01,
                      ),
                    ],
                  ),
                ],
              ),
            ],
            orderIndex: 0,
          ),
        ],
      );

      await pumpInspector(
        tester,
        editorState: const EditorState(
          selectedClipId: 'clip1',
          showInspector: true,
        ),
        project: project,
      );

      await tester.scrollUntilVisible(
        find.text('Brightness').first,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Brightness'), findsNWidgets(2));
    });

    testWidgets('close button deselects clip', (tester) async {
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
              ClipModel(id: 'clip1', assetId: 'a1', startMs: 0, durationMs: 5000),
            ],
            orderIndex: 0,
          ),
        ],
      );

      await pumpInspector(
        tester,
        editorState: const EditorState(
          selectedClipId: 'clip1',
          showInspector: true,
        ),
        project: project,
      );

      // Close button in the inspector header
      final closeButton = find.byIcon(Icons.close);
      expect(closeButton, findsOneWidget);

      await tester.tap(closeButton);
      await tester.pump();
    });

    // ─── Track selected ─────────────────────────────────────────────

    testWidgets('shows track properties when a track is selected',
        (tester) async {
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
            volume: 0.8,
            visible: true,
            clips: [],
            orderIndex: 0,
          ),
        ],
      );

      await pumpInspector(
        tester,
        editorState: const EditorState(
          selectedTrackId: 'a1',
          showInspector: true,
        ),
        project: project,
      );

      // Track inspector header
      expect(find.text('Track Inspector'), findsOneWidget);
      // Track type badge
      expect(find.text('AUDIO TRACK'), findsOneWidget);
      // Track name
      expect(find.text('Audio 1'), findsOneWidget);
      // Properties
      expect(find.text('Clips'), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Visible'), findsOneWidget);
      // Volume section
      expect(find.text('VOLUME'), findsOneWidget);
    });

    testWidgets('track inspector shows clip count', (tester) async {
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
              ClipModel(id: 'c1', assetId: 'a1', startMs: 0, durationMs: 5000),
              ClipModel(id: 'c2', assetId: 'a2', startMs: 5000, durationMs: 3000),
            ],
            orderIndex: 0,
          ),
        ],
      );

      await pumpInspector(
        tester,
        editorState: const EditorState(
          selectedTrackId: 'v1',
          showInspector: true,
        ),
        project: project,
      );

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('shows audio ducking section for audio tracks', (tester) async {
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
            clips: [],
            orderIndex: 0,
          ),
        ],
      );

      await pumpInspector(
        tester,
        editorState: const EditorState(
          selectedTrackId: 'a1',
          showInspector: true,
        ),
        project: project,
      );

      expect(find.text('AUDIO DUCKING'), findsOneWidget);
    });

    testWidgets('does not show audio ducking for video tracks', (tester) async {
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
            clips: [],
            orderIndex: 0,
          ),
        ],
      );

      await pumpInspector(
        tester,
        editorState: const EditorState(
          selectedTrackId: 'v1',
          showInspector: true,
        ),
        project: project,
      );

      expect(find.text('AUDIO DUCKING'), findsNothing);
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
    state = state.copyWith(
      selectedTrackId: trackId,
      showInspector: trackId != null,
    );
  }

  void toggleInspector() {
    state = state.copyWith(showInspector: !state.showInspector);
  }

  void zoomIn() {
    final newZoom = (state.zoomLevel * 1.2).clamp(0.1, 10.0);
    state = state.copyWith(zoomLevel: newZoom);
  }

  void zoomOut() {
    final newZoom = (state.zoomLevel / 1.2).clamp(0.1, 10.0);
    state = state.copyWith(zoomLevel: newZoom);
  }
}

/// A lightweight fake repository.
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
