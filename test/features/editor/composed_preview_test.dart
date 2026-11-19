import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:editors_pro/features/editor/widgets/preview_viewport.dart';
import 'package:editors_pro/features/editor/widgets/video_clip_preview.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Distinct 4x4 RGBA PNG fixtures: raw source red, composed engine output green.
const _redPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR4nGP4z8DwHxkzkC4AADxAH+HggXe0AAAAAElFTkSuQmCC';
const _greenPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAD0lEQVR4nGNg+I8GSRcAACxQH+H81I9XAAAAAElFTkSuQmCC';

ProjectModel _project(String source, MediaType type) => ProjectModel(
      id: 'composed',
      name: 'Edited media',
      createdAt: 1,
      updatedAt: 1,
      width: 1920,
      height: 1080,
      fps: 30,
      mediaAssets: [
        MediaAssetModel(
          id: 'source',
          filePath: source,
          fileName: 'source',
          mediaType: type,
        )
      ],
      tracks: const [
        TrackModel(
            id: 'video',
            name: 'Media',
            trackType: TrackType.video,
            clips: [
              ClipModel(
                id: 'clip',
                assetId: 'source',
                startMs: 0,
                durationMs: 1000,
                effects: [
                  EffectModel(
                      id: 'effect', name: 'Brightness', effectType: 'Filter')
                ],
              ),
            ]),
        TrackModel(
            id: 'text',
            name: 'Title',
            trackType: TrackType.text,
            clips: [
              ClipModel(
                id: 'title',
                assetId: '__text__',
                startMs: 0,
                durationMs: 1000,
                properties: {
                  'text_type': 'text_overlay',
                  'content': 'Native overlay'
                },
              ),
            ]),
      ],
    );

void main() {
  testWidgets(
      'same-project edits reject an older in-flight frame before it can refill the cache',
      (tester) async {
    final initial = _project('/unused.png', MediaType.image);
    final projectState = StateProvider<ProjectModel>((ref) => initial);
    final firstFrame = Completer<Uint8List>();
    final editedFrame = base64Decode(_greenPng);
    final requestedTimes = <int>[];
    await tester.pumpWidget(ProviderScope(
        overrides: [
          currentProjectProvider.overrideWith((ref) => ref.watch(projectState)),
          editorProvider.overrideWith((ref) => _PausedEditor(ref)),
        ],
        child: MaterialApp(
            home: Scaffold(body: PreviewViewport(frameLoader: (time) {
          requestedTimes.add(time);
          return requestedTimes.length == 1
              ? firstFrame.future
              : Future.value(editedFrame);
        })))));
    final container = ProviderScope.containerOf(
        tester.element(find.byType(PreviewViewport)),
        listen: false);
    container.read(projectState.notifier).state = initial.copyWith(tracks: [
      initial.tracks.first.copyWith(visible: false),
      initial.tracks.last,
    ]);
    await tester.pump();
    firstFrame.complete(base64Decode(_redPng));
    await tester.pumpAndSettle();
    expect(requestedTimes, [0, 0],
        reason:
            'an old same-project response must not fill the new composition cache');
    final image = tester.widget<Image>(find.descendant(
        of: find.byType(PreviewViewport), matching: find.byType(Image)));
    expect((image.image as MemoryImage).bytes, editedFrame);
  });

  for (final change in ['clip addition', 'track visibility']) {
    testWidgets(
        'paused cache refreshes after same-project $change at the same playhead',
        (tester) async {
      const clip = ClipModel(
          id: 'photo-clip', assetId: 'photo', startMs: 0, durationMs: 1000);
      final initial = ProjectModel(
        id: 'same-project',
        name: 'Paused edits',
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
            clips: change == 'clip addition' ? const [] : const [clip],
          )
        ],
      );
      final projectState = StateProvider<ProjectModel>((ref) => initial);
      final requestedTimes = <int>[];
      final originalFrame = base64Decode(_redPng);
      final editedFrame = base64Decode(_greenPng);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            currentProjectProvider
                .overrideWith((ref) => ref.watch(projectState)),
            editorProvider.overrideWith((ref) => _PausedEditor(ref)),
          ],
          child: MaterialApp(
              home: Scaffold(body: PreviewViewport(frameLoader: (time) async {
            requestedTimes.add(time);
            return requestedTimes.length == 1 ? originalFrame : editedFrame;
          })))));
      await tester.pumpAndSettle();
      expect(requestedTimes, [0]);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(PreviewViewport)),
          listen: false);
      final changedTrack = change == 'clip addition'
          ? initial.tracks.single.copyWith(clips: const [clip])
          : initial.tracks.single.copyWith(visible: false);
      container.read(projectState.notifier).state =
          initial.copyWith(tracks: [changedTrack]);
      await tester.pumpAndSettle();
      expect(container.read(editorProvider).currentTimeMs, 0);
      expect(container.read(editorProvider).renderRevision, 0,
          reason:
              'project synchronization must refresh frames even without an editor revision update');
      expect(requestedTimes, [0, 0],
          reason:
              'a same-ID immutable project replacement must invalidate the composed frame cache');
      final image = tester.widget<Image>(find.descendant(
          of: find.byType(PreviewViewport), matching: find.byType(Image)));
      expect((image.image as MemoryImage).bytes, editedFrame);
    });
  }

  for (final type in [MediaType.image, MediaType.video]) {
    testWidgets(
        'active ${type.name} displays the composed native frame instead of its raw source',
        (tester) async {
      final composed = base64Decode(_greenPng);
      final directory =
          Directory.systemTemp.createTempSync('editors-pro-composed-preview-');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        directory.deleteSync(recursive: true);
      });
      final source = File(
          '${directory.path}/source.${type == MediaType.image ? 'png' : 'mp4'}');
      source.writeAsBytesSync(base64Decode(_redPng));
      final project = _project(source.path, type);
      var nativeRequests = 0;
      await tester.pumpWidget(ProviderScope(
          overrides: [
            currentProjectProvider.overrideWith((ref) => project),
            editorProvider.overrideWith((ref) => _PausedEditor(ref)),
          ],
          child: MaterialApp(
              home: Scaffold(body: PreviewViewport(frameLoader: (_) async {
            nativeRequests++;
            return composed;
          })))));
      await tester.pumpAndSettle();
      expect(nativeRequests, 1, reason: 'the engine supplied a composed frame');
      expect(find.byType(VideoClipPreview), findsNothing,
          reason:
              'the Android source player cannot show native effects and text');
      final image = tester.widget<Image>(find.descendant(
        of: find.byType(PreviewViewport),
        matching: find.byType(Image),
      ));
      expect(image.image, isA<MemoryImage>(),
          reason:
              'raw FileImage/ResizeImage source shortcuts bypass text, effects and canvas composition');
      expect((image.image as MemoryImage).bytes, composed);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}

class _PausedEditor extends EditorNotifier {
  _PausedEditor(super.ref);
}
