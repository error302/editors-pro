import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/project_model.dart';
import '../../projects/providers/project_provider.dart';
import '../providers/editor_provider.dart';

/// Project actions stay separate from transport and clip operations.
class EditorToolbar extends ConsumerWidget {
  const EditorToolbar(
      {this.onExit,
      this.onOpenTools,
      this.onImportMedia,
      this.onImportAudio,
      this.onInspector,
      super.key});
  final Future<void> Function()? onExit;
  final ValueChanged<LeftPanelTab>? onOpenTools;
  final VoidCallback? onImportMedia;
  final VoidCallback? onImportAudio;
  final VoidCallback? onInspector;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(currentProjectProvider);
    final state = ref.watch(editorProvider);
    final editor = ref.read(editorProvider.notifier);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final short = MediaQuery.sizeOf(context).height < 500;
    final fps = project?.fps ?? 30;
    ClipModel? selected;
    TrackModel? selectedTrack;
    for (final track in project?.tracks ?? <TrackModel>[]) {
      for (final clip in track.clips) {
        if (clip.id == state.selectedClipId) {
          selected = clip;
          selectedTrack = track;
        }
      }
    }
    final canEdit = selected != null &&
        !selected.locked &&
        selectedTrack?.locked == false &&
        !state.isImporting &&
        !state.isExporting;
    final canCut = canEdit &&
        state.currentTimeMs > selected.startMs &&
        state.currentTimeMs < selected.startMs + selected.durationMs;
    final clipMenu = PopupMenuButton<String>(
      tooltip: 'Clip tools',
      icon: const Icon(Icons.more_horiz, size: 20),
      onSelected: (action) {
        switch (action) {
          case 'in':
            editor.trimSelectedInAtPlayhead();
          case 'out':
            editor.trimSelectedOutAtPlayhead();
          case 'duplicate':
            editor.duplicateSelected();
          case 'delete':
            editor.deleteSelected();
          case 'ripple':
            editor.rippleDeleteSelected();
          case 'speed':
            onOpenTools?.call(LeftPanelTab.speed);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
            value: 'in',
            enabled: canCut,
            child: const Text('Trim start to playhead')),
        PopupMenuItem(
            value: 'out',
            enabled: canCut,
            child: const Text('Trim end to playhead')),
        PopupMenuItem(
            value: 'duplicate',
            enabled: canEdit,
            child: const Text('Duplicate clip')),
        if (onOpenTools != null)
          PopupMenuItem(
              value: 'speed',
              enabled: canEdit && selectedTrack?.trackType != TrackType.text,
              child: const Text('Clip speed')),
        const PopupMenuDivider(),
        PopupMenuItem(
            value: 'delete',
            enabled: canEdit,
            child: const Text('Delete clip')),
        PopupMenuItem(
            value: 'ripple',
            enabled: canEdit,
            child: const Text('Ripple delete')),
      ],
    );

    return SafeArea(
      bottom: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Column(
          children: [
            SizedBox(
              height: short ? 48 : 60,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to projects',
                    onPressed: onExit ??
                        () async {
                          if (await ref
                              .read(projectProvider.notifier)
                              .saveCurrentProject()) {
                            if (context.mounted) context.go('/');
                          } else if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not save project. Please try again before leaving.',
                                ),
                              ),
                            );
                          }
                        },
                    icon: const Icon(Icons.arrow_back, size: 20),
                  ),
                  if (short) ...[
                    IconButton.filledTonal(
                      tooltip: state.isPlaying ? 'Pause' : 'Play',
                      onPressed:
                          state.durationMs > 0 ? editor.togglePlayback : null,
                      icon: Icon(
                          state.isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 20),
                    ),
                    IconButton(
                      tooltip: 'Split at playhead',
                      onPressed: canCut ? editor.splitAtPlayhead : null,
                      icon: const Icon(Icons.content_cut, size: 18),
                    ),
                    clipMenu,
                    if (!compact)
                      IconButton(
                          tooltip: 'Undo',
                          onPressed: editor.undo,
                          icon: const Icon(Icons.undo, size: 19)),
                    if (onOpenTools != null)
                      PopupMenuButton<String>(
                        tooltip: 'Editing tools',
                        icon: const Icon(Icons.video_settings, size: 20),
                        onSelected: (value) {
                          if (value == 'import') {
                            onImportMedia?.call();
                            return;
                          }
                          if (value == 'audio') {
                            onImportAudio?.call();
                            return;
                          }
                          onOpenTools?.call(LeftPanelTab.values.byName(value));
                        },
                        itemBuilder: (_) => [
                          if (onImportMedia != null)
                            const PopupMenuItem(
                                value: 'import', child: Text('Add media')),
                          if (onImportAudio != null)
                            const PopupMenuItem(
                                value: 'audio', child: Text('Add audio')),
                          const PopupMenuItem(
                              value: 'media', child: Text('Media bin')),
                          const PopupMenuItem(
                              value: 'text', child: Text('Add text')),
                          const PopupMenuItem(
                              value: 'effects', child: Text('Effects')),
                          PopupMenuItem(
                              value: 'speed',
                              enabled: canEdit,
                              child: const Text('Clip speed')),
                        ],
                      ),
                    if (onInspector != null)
                      IconButton(
                          tooltip: 'Inspector',
                          onPressed: onInspector,
                          icon: const Icon(Icons.tune, size: 20)),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project?.name ?? 'Untitled',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!short) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${project?.width ?? 1920} × ${project?.height ?? 1080}  ·  ${fps.toStringAsFixed(fps % 1 == 0 ? 0 : 2)} fps',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        ],
                      ],
                    ),
                  ),
                  if (short)
                    PopupMenuButton<String>(
                      tooltip: 'Project actions',
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (value) async {
                        if (value == 'export' && project != null) {
                          context.go('/export/${project.id}');
                        } else if (value == 'save') {
                          final saved = await ref
                              .read(projectProvider.notifier)
                              .saveCurrentProject();
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(saved
                                    ? 'Project saved'
                                    : 'Could not save project')));
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'save',
                            enabled: project != null && !state.isImporting,
                            child: const Text('Save project')),
                        PopupMenuItem(
                            value: 'export',
                            enabled: project != null && !state.isImporting,
                            child: const Text('Export')),
                      ],
                    )
                  else ...[
                    IconButton(
                      tooltip: 'Save project',
                      icon: const Icon(Icons.save_outlined, size: 20),
                      onPressed: project == null || state.isImporting
                          ? null
                          : () async {
                              final saved = await ref
                                  .read(projectProvider.notifier)
                                  .saveCurrentProject();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      saved
                                          ? 'Project saved'
                                          : 'Could not save project',
                                    ),
                                  ),
                                );
                              }
                            },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: FilledButton.icon(
                        onPressed: project == null || state.isImporting
                            ? null
                            : () => context.go('/export/${project.id}'),
                        icon: const Icon(Icons.ios_share, size: 16),
                        label: const Text('Export'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                              horizontal: compact ? 12 : 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!short)
              Container(
                height: 48,
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Undo',
                      onPressed: editor.undo,
                      icon: const Icon(Icons.undo, size: 19),
                    ),
                    IconButton(
                      tooltip: 'Redo',
                      onPressed: editor.redo,
                      icon: const Icon(Icons.redo, size: 19),
                    ),
                    const SizedBox(
                        height: 20, child: VerticalDivider(width: 1)),
                    IconButton(
                      tooltip: 'Split at playhead',
                      onPressed: canCut ? editor.splitAtPlayhead : null,
                      icon: const Icon(Icons.content_cut, size: 18),
                    ),
                    clipMenu,
                    if (!compact)
                      IconButton(
                        tooltip: 'Delete selected',
                        onPressed: canEdit ? editor.deleteSelected : null,
                        icon: const Icon(Icons.delete_outline, size: 19),
                      ),
                    const Spacer(),
                    if (!compact) ...[
                      Text(
                        _timecode(state.currentTimeMs, fps),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()],
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    IconButton(
                      tooltip: 'Go to start',
                      onPressed: () => editor.seekTo(0),
                      icon: const Icon(Icons.skip_previous, size: 20),
                    ),
                    IconButton.filledTonal(
                      tooltip: state.isPlaying ? 'Pause' : 'Play',
                      onPressed:
                          state.durationMs > 0 ? editor.togglePlayback : null,
                      icon: Icon(
                        state.isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 20,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Go to end',
                      onPressed: () => editor.seekTo(state.durationMs),
                      icon: const Icon(Icons.skip_next, size: 20),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _timecode(int milliseconds, double fps) {
    final wholeFrameRate =
        fps.isFinite && fps > 0 && fps == fps.roundToDouble();
    final totalFrames =
        wholeFrameRate ? (milliseconds * fps / 1000).round() : 0;
    final duration = wholeFrameRate
        ? Duration(seconds: totalFrames ~/ fps.toInt())
        : Duration(milliseconds: milliseconds);
    final frames = wholeFrameRate
        ? totalFrames % fps.toInt()
        : ((milliseconds % 1000) * fps / 1000).floor();
    return '${duration.inHours.toString().padLeft(2, '0')}:'
        '${(duration.inMinutes % 60).toString().padLeft(2, '0')}:'
        '${(duration.inSeconds % 60).toString().padLeft(2, '0')}:'
        '${frames.toString().padLeft(2, '0')}';
  }
}
