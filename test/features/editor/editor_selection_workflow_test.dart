import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('selecting a photo then opening Effects keeps the filter target selected', () {
    final editor = container.read(editorProvider.notifier);
    editor.selectClip('photo');
    editor.setLeftPanelTab(LeftPanelTab.effects);
    expect(container.read(editorProvider).selectedClipId, 'photo');
    expect(container.read(editorProvider).leftPanelTab, LeftPanelTab.effects);
    expect(container.read(editorProvider).showInspector, isTrue);
  });

  test('unrelated render, import, export and playback edits retain clip selection', () {
    final editor = container.read(editorProvider.notifier);
    editor.selectClip('photo');
    editor.setImporting(true);
    expect(container.read(editorProvider).selectedClipId, 'photo');
    editor.setImporting(false);
    editor.setExporting(true, progress: 0.5);
    editor.setExporting(false);
    editor.setDuration(1000);
    editor.seekTo(250);
    editor.setPlaybackSpeed(1.5);
    editor.notifyRenderChanged();
    editor.toggleInspector();
    editor.toggleSafeZones();
    expect(container.read(editorProvider).selectedClipId, 'photo');
    expect(container.read(editorProvider).selectedTrackId, isNull);
  });

  test('copyWith distinguishes omitted selection from an explicit null', () {
    const selected = EditorState(selectedClipId: 'photo', selectedTrackId: 'video');
    final playing = selected.copyWith(isPlaying: true, isAudioPlaying: true, isDecodingFrame: true);
    expect(playing.selectedClipId, 'photo');
    expect(playing.selectedTrackId, 'video');
    expect(selected.copyWith(selectedClipId: null).selectedClipId, isNull);
    expect(selected.copyWith(selectedClipId: null).selectedTrackId, 'video');
    expect(selected.copyWith(selectedTrackId: null).selectedClipId, 'photo');
    expect(selected.copyWith(selectedTrackId: null).selectedTrackId, isNull);
  });

  test('clip and track selection deliberately replace one another and can be cleared', () {
    final editor = container.read(editorProvider.notifier);
    editor.selectClip('photo');
    editor.selectTrack('audio');
    expect(container.read(editorProvider).selectedClipId, isNull);
    expect(container.read(editorProvider).selectedTrackId, 'audio');
    editor.setLeftPanelTab(LeftPanelTab.audio);
    expect(container.read(editorProvider).selectedTrackId, 'audio');
    editor.selectClip('title');
    expect(container.read(editorProvider).selectedClipId, 'title');
    expect(container.read(editorProvider).selectedTrackId, isNull);
    editor.selectClip(null);
    expect(container.read(editorProvider).selectedClipId, isNull);
    expect(container.read(editorProvider).selectedTrackId, isNull);
    expect(container.read(editorProvider).showInspector, isFalse);
    editor.selectTrack('video');
    editor.selectTrack(null);
    expect(container.read(editorProvider).selectedClipId, isNull);
    expect(container.read(editorProvider).selectedTrackId, isNull);
    expect(container.read(editorProvider).showInspector, isFalse);
  });
}
