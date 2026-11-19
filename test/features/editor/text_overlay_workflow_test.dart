import 'dart:async';
import 'dart:typed_data';

import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:editors_pro/features/editor/widgets/inspector_panel.dart';
import 'package:editors_pro/features/editor/widgets/preview_viewport.dart';
import 'package:editors_pro/features/editor/widgets/text_overlay_handle.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _properties = {
  'text_type': 'text_overlay',
  'content': 'Saved red title',
  'font_family': 'Inter-Bold',
  'font_size': 72.0,
  'color_hex': '#FF0000',
  'position_x': 0.25,
  'position_y': 0.75,
};

const _project = ProjectModel(
  id: 'p',
  name: 'Text test',
  createdAt: 1,
  updatedAt: 1,
  width: 1920,
  height: 1080,
  fps: 30,
  tracks: [
    TrackModel(id: 'text', name: 'Titles', trackType: TrackType.text, clips: [
      ClipModel(
          id: 'a',
          assetId: '__text__',
          startMs: 0,
          durationMs: 1000,
          properties: _properties),
      ClipModel(
          id: 'b',
          assetId: '__text__',
          startMs: 1000,
          durationMs: 1000,
          properties: {
            'text_type': 'text_overlay',
            'content': 'Small blue note',
            'font_family': 'Inter',
            'font_size': 24.0,
            'color_hex': '#0000FF',
            'position_x': 0.8,
            'position_y': 0.2,
          }),
    ])
  ],
);

void main() {
  test('clip bridge and model preserve text and complete effect parameters',
      () {
    final json = {
      'id': 'a',
      'track_id': 'text',
      'asset_id': '__text__',
      'start_ms': 0,
      'duration_ms': 1000,
      'properties': _properties,
      'effects': [
        {
          'id': 'fx',
          'name': 'Brightness',
          'effect_type': 'Filter',
          'enabled': false,
          'order': 3,
          'parameters': [
            {
              'name': 'value',
              'display_name': 'Value',
              'value': 0.3,
              'min_value': -1,
              'max_value': 1,
              'default_value': 0,
              'step': 0.05
            }
          ],
        }
      ],
    };
    final info = ClipInfo.fromJson(json);
    final state = ClipStateInfo.fromJson(json);
    expect(info.properties, _properties);
    expect(state.properties, _properties);
    expect(state.effects.single.enabled, isFalse);
    expect(state.effects.single.order, 3);
    expect(state.effects.single.parameters.single.step, 0.05);
    final copied = _project.tracks.single.clips.first.copyWith(startMs: 50);
    expect(copied.properties, _properties);
    expect(copied.textProperties.content, 'Saved red title');
    expect(ClipStateInfo.fromJson({...json, 'properties': null}).properties,
        isEmpty);
    expect(
        const EditorState(renderRevision: 3)
            .copyWith(zoomLevel: 2)
            .renderRevision,
        3);
  });

  testWidgets(
      'inspector hydrates each selected clip and preserves other style fields',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late _RecordingEditor editor;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          currentProjectProvider.overrideWith((ref) => _project),
          editorProvider.overrideWith((ref) => editor = _RecordingEditor(ref,
              const EditorState(selectedClipId: 'a', showInspector: true))),
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: SizedBox(width: 360, child: InspectorPanel())))));
    await tester.pumpAndSettle();
    final content = find.byKey(const ValueKey('text-content'));
    await tester.ensureVisible(content);
    expect(
        tester.widget<TextField>(content).controller!.text, 'Saved red title');
    expect(tester.widget<Slider>(find.byKey(const ValueKey('text-Size'))).value,
        72);
    expect(
        tester
            .widget<DropdownButton<String>>(
                find.byKey(const ValueKey('text-font')))
            .value,
        'Inter-Bold');
    await tester.tap(find.byKey(const ValueKey('text-color-#00FF00')));
    await tester.pump();
    expect(editor.updates.last, containsPair('content', 'Saved red title'));
    expect(editor.updates.last, containsPair('fontSize', 72.0));
    expect(editor.updates.last, containsPair('colorHex', '#00FF00'));
    await tester.enterText(content, 'Changed café');
    await tester.pump();
    expect(editor.updates.last, containsPair('content', 'Changed café'));
    editor.selectClip('b');
    await tester.pumpAndSettle();
    await tester.ensureVisible(content);
    expect(
        tester.widget<TextField>(content).controller!.text, 'Small blue note');
    expect(tester.widget<Slider>(find.byKey(const ValueKey('text-Size'))).value,
        24);
    expect(
        tester.widget<Slider>(find.byKey(const ValueKey('text-Pos X'))).value,
        0.8);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'paused preview invalidates cached frames on text render revision',
      (tester) async {
    late _RecordingEditor editor;
    final requests = <int>[];
    await tester.pumpWidget(ProviderScope(
        overrides: [
          currentProjectProvider.overrideWith((ref) => _project),
          editorProvider.overrideWith(
              (ref) => editor = _RecordingEditor(ref, const EditorState())),
        ],
        child: MaterialApp(
            home: Scaffold(body: PreviewViewport(frameLoader: (time) async {
          requests.add(time);
          return Uint8List(0);
        })))));
    await tester.pumpAndSettle();
    expect(requests, [0]);
    editor.notifyRenderChanged();
    await tester.pumpAndSettle();
    expect(requests, [0, 0]);
    editor.seekTo(500);
    await tester.pumpAndSettle();
    editor.seekTo(0);
    await tester.pumpAndSettle();
    expect(requests, [0, 0, 500]);
    editor.notifyRenderChanged();
    await tester.pumpAndSettle();
    expect(requests, [0, 0, 500, 0]);
  });

  testWidgets(
      'mutation during an in-flight preview discards the stale completion',
      (tester) async {
    late _RecordingEditor editor;
    final frames = <Completer<Uint8List>>[];
    await tester.pumpWidget(ProviderScope(
        overrides: [
          currentProjectProvider.overrideWith((ref) => _project),
          editorProvider.overrideWith(
              (ref) => editor = _RecordingEditor(ref, const EditorState())),
        ],
        child:
            MaterialApp(home: Scaffold(body: PreviewViewport(frameLoader: (_) {
          final frame = Completer<Uint8List>();
          frames.add(frame);
          return frame.future;
        })))));
    expect(frames, hasLength(1));
    editor.notifyRenderChanged();
    frames.first.complete(Uint8List(0));
    await tester.pump();
    expect(frames, hasLength(2));
    frames.last.complete(Uint8List(0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'preview handles use saved text geometry only while the clip is active',
      (tester) async {
    late _RecordingEditor editor;
    await tester.pumpWidget(ProviderScope(overrides: [
      currentProjectProvider.overrideWith((ref) => _project),
      editorProvider.overrideWith((ref) => editor = _RecordingEditor(
          ref, const EditorState(selectedClipId: 'a', showInspector: true))),
    ], child: const MaterialApp(home: Scaffold(body: PreviewViewport()))));
    final handle =
        tester.widget<TextOverlayHandle>(find.byType(TextOverlayHandle));
    expect(handle.data.positionX, 0.25);
    expect(handle.data.positionY, 0.75);
    expect(handle.data.fontSize, 72);
    expect(find.text('Saved red title'), findsNothing);
    editor.seekTo(1000);
    await tester.pumpAndSettle();
    expect(find.byType(TextOverlayHandle), findsNothing);
  });
}

class _RecordingEditor extends EditorNotifier {
  _RecordingEditor(super.ref, EditorState initial) {
    state = initial;
  }
  final updates = <Map<String, dynamic>>[];

  @override
  void seekTo(int timeMs) {
    state = state.copyWith(
        currentTimeMs: timeMs,
        selectedClipId: state.selectedClipId,
        selectedTrackId: state.selectedTrackId);
  }

  @override
  Future<bool> updateTextOverlay(
      {required String clipId,
      String? content,
      String? fontFamily,
      double? fontSize,
      String? colorHex,
      double? positionX,
      double? positionY}) async {
    updates.add({
      'clipId': clipId,
      'content': content,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'colorHex': colorHex,
      'positionX': positionX,
      'positionY': positionY
    });
    return true;
  }
}
