import 'package:editors_pro/core/services/engine_service.dart';
import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/editor/presentation/editor_screen.dart';
import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:editors_pro/features/editor/widgets/preview_viewport.dart';
import 'package:editors_pro/features/editor/widgets/timeline_panel.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _project = ProjectModel(
  id: 'adaptive',
  name: 'Adaptive editing',
  createdAt: 0,
  updatedAt: 0,
  width: 1920,
  height: 1080,
  fps: 30,
  tracks: [
    TrackModel(id: 'v1', name: 'Video', trackType: TrackType.video, clips: [
      ClipModel(id: 'clip', assetId: 'video', startMs: 0, durationMs: 10000)
    ]),
  ],
);

void main() {
  for (final size in [const Size(360, 640), const Size(640, 360)]) {
    for (final unavailable in [false, true]) {
      testWidgets(
          'effects dock retains preview at $size, unavailable $unavailable',
          (tester) async {
        EngineService.instance.dispose();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              currentProjectProvider.overrideWithValue(_project),
              editorProvider.overrideWith(
                  (ref) => _Editor(ref, unavailable: unavailable)),
            ],
            child: MaterialApp(
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(1.5)),
                    child: child!),
                home: const EditorScreen(projectId: 'adaptive'))));
        await tester.pump();
        if (size.height < 500) {
          await tester.tap(find.byTooltip('Editing tools'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Effects'));
        } else {
          await tester.ensureVisible(find.byTooltip('Effects'));
          await tester.tap(find.byTooltip('Effects'));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(PreviewViewport)).height,
            greaterThanOrEqualTo(150));
        expect(find.byTooltip('Close tools').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Close tools'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(TimelinePanel), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  for (final size in [
    const Size(360, 640),
    const Size(640, 360),
    const Size(1024, 768),
    const Size(1440, 900)
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
          'workspace preserves preview and timeline at $size, text $scale',
          (tester) async {
        EngineService.instance.dispose();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              currentProjectProvider.overrideWithValue(_project),
              editorProvider.overrideWith((ref) => _Editor(ref)),
            ],
            child: MaterialApp(
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      padding: scale == 1.5 && size.width < 1200
                        ? const EdgeInsets.symmetric(vertical: 24)
                        : EdgeInsets.zero,
                    ),
                    child: child!),
                home: const EditorScreen(projectId: 'adaptive'))));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(PreviewViewport)).height,
            greaterThanOrEqualTo(size.height < 500 ? 150 : 230));
        expect(tester.getSize(find.byType(TimelinePanel)).height,
            greaterThanOrEqualTo(96));
        expect(
            find.byTooltip('Split at playhead').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Inspector').hitTestable(),
            size.width < 1200 ? findsOneWidget : findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

class _Editor extends EditorNotifier {
  _Editor(super.ref, {this.unavailable = false}) {
    state = const EditorState(
        selectedClipId: 'clip', currentTimeMs: 5000, durationMs: 10000);
  }
  final bool unavailable;
  @override
  Future<void> initialize() async {}
  @override
  Future<List<FilterTypeInfo>> getFilterCatalog() async {
    if (unavailable) throw StateError('Test engine unavailable');
    return [
      FilterTypeInfo.fromJson({'name': 'Hue', 'icon': 'hue', 'parameters': []})
    ];
  }

  @override
  Future<List<FilterPresetInfo>> getFilterPresets() async => [
        FilterPresetInfo.fromJson(
            {'id': 'warm', 'name': 'Warm', 'description': 'Warm light'}),
      ];
  @override
  Future<List<EffectInfo>> getSelectedClipEffects() async => [];
}
