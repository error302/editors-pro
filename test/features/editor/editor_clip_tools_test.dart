import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:editors_pro/features/editor/widgets/editor_toolbar.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<_Editor> pumpToolbar(
    WidgetTester tester, {
    String? selected = 'clip',
    int time = 5000,
    bool locked = false,
    bool trackLocked = false,
    bool importing = false,
  }) async {
    late _Editor editor;
    await tester.pumpWidget(ProviderScope(overrides: [
      currentProjectProvider.overrideWithValue(ProjectModel(
        id: 'tools',
        name: 'Clip tools',
        createdAt: 0,
        updatedAt: 0,
        width: 1920,
        height: 1080,
        fps: 30,
        tracks: [
          TrackModel(
              id: 'video',
              name: 'Video',
              trackType: TrackType.video,
              locked: trackLocked,
              clips: [
                ClipModel(
                    id: 'clip',
                    assetId: 'asset',
                    startMs: 1000,
                    durationMs: 9000,
                    locked: locked)
              ])
        ],
      )),
      editorProvider.overrideWith((ref) => editor = _Editor(
          ref,
          EditorState(
              selectedClipId: selected,
              currentTimeMs: time,
              durationMs: 10000,
              isImporting: importing))),
    ], child: const MaterialApp(home: Scaffold(body: EditorToolbar()))));
    return editor;
  }

  for (final scenario in [
    'none',
    'stale',
    'clip locked',
    'track locked',
    'importing'
  ]) {
    testWidgets('clip tools disable invalid selection: $scenario',
        (tester) async {
      await pumpToolbar(tester,
          selected: scenario == 'none'
              ? null
              : scenario == 'stale'
                  ? 'missing'
                  : 'clip',
          locked: scenario == 'clip locked',
          trackLocked: scenario == 'track locked',
          importing: scenario == 'importing');
      expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.content_cut))
              .onPressed,
          isNull);
      await tester.tap(find.byTooltip('Clip tools'));
      await tester.pumpAndSettle();
      for (final item in tester.widgetList<PopupMenuItem<String>>(
          find.byType(PopupMenuItem<String>))) {
        expect(item.enabled, isFalse);
      }
    });
  }

  for (final time in [1000, 10000]) {
    testWidgets('cut and trim disable at clip boundary $time', (tester) async {
      await pumpToolbar(tester, time: time);
      expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.content_cut))
              .onPressed,
          isNull);
      await tester.tap(find.byTooltip('Clip tools'));
      await tester.pumpAndSettle();
      for (final label in ['Trim start to playhead', 'Trim end to playhead']) {
        final item = find.ancestor(
            of: find.text(label), matching: find.byType(PopupMenuItem<String>));
        expect(tester.widget<PopupMenuItem<String>>(item).enabled, isFalse);
      }
    });
  }

  testWidgets('split and menu commands dispatch selected clip operations',
      (tester) async {
    final editor = await pumpToolbar(tester);
    await tester.tap(find.byTooltip('Split at playhead'));
    expect(editor.actions, ['split']);
    for (final (label, action) in [
      ('Trim start to playhead', 'in'),
      ('Trim end to playhead', 'out'),
      ('Duplicate clip', 'duplicate'),
      ('Delete clip', 'delete'),
      ('Ripple delete', 'ripple'),
    ]) {
      await tester.tap(find.byTooltip('Clip tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(editor.actions.last, action);
    }
  });
}

class _Editor extends EditorNotifier {
  _Editor(super.ref, EditorState initial) {
    state = initial;
  }
  final actions = <String>[];
  @override
  Future<void> initialize() async {}
  @override
  Future<void> splitAtPlayhead() async {
    actions.add('split');
  }

  @override
  Future<void> trimSelectedInAtPlayhead() async {
    actions.add('in');
  }

  @override
  Future<void> trimSelectedOutAtPlayhead() async {
    actions.add('out');
  }

  @override
  Future<void> duplicateSelected() async {
    actions.add('duplicate');
  }

  @override
  Future<void> deleteSelected() async {
    actions.add('delete');
  }

  @override
  Future<void> rippleDeleteSelected() async {
    actions.add('ripple');
  }
}
