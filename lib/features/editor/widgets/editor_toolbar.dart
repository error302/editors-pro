import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../projects/providers/project_provider.dart';
import '../providers/editor_provider.dart';

/// Project actions stay separate from transport and clip operations.
class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(currentProjectProvider);
    final state = ref.watch(editorProvider);
    final editor = ref.read(editorProvider.notifier);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final fps = project?.fps ?? 30;
    final hasSelection = state.selectedClipId != null;

    return SafeArea(
      bottom: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Column(children: [
          SizedBox(
            height: 60,
            child: Row(children: [
              IconButton(
                tooltip: 'Back to projects',
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.arrow_back, size: 20),
              ),
              Expanded(
                  child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(project?.name ?? 'Untitled',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                      '${project?.width ?? 1920} × ${project?.height ?? 1080}  ·  ${fps.toStringAsFixed(fps % 1 == 0 ? 0 : 2)} fps',
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.textSecondary)),
                ],
              )),
              IconButton(
                tooltip: 'Save project',
                icon: const Icon(Icons.save_outlined, size: 20),
                onPressed: project == null
                    ? null
                    : () async {
                        final saved = await ref
                            .read(projectProvider.notifier)
                            .saveCurrentProject();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(saved
                                ? 'Project saved'
                                : 'Could not save project'),
                          ));
                        }
                      },
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  onPressed: project == null
                      ? null
                      : () => context.go('/export/${project.id}'),
                  icon: const Icon(Icons.ios_share, size: 16),
                  label: const Text('Export'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding:
                        EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ]),
          ),
          Container(
            height: 48,
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border))),
            child: Row(children: [
              IconButton(
                  tooltip: 'Undo',
                  onPressed: editor.undo,
                  icon: const Icon(Icons.undo, size: 19)),
              IconButton(
                  tooltip: 'Redo',
                  onPressed: editor.redo,
                  icon: const Icon(Icons.redo, size: 19)),
              const SizedBox(height: 20, child: VerticalDivider(width: 1)),
              IconButton(
                  tooltip: 'Split at playhead',
                  onPressed: hasSelection ? editor.splitAtPlayhead : null,
                  icon: const Icon(Icons.content_cut, size: 18)),
              IconButton(
                  tooltip: 'Delete selected',
                  onPressed: hasSelection ? editor.deleteSelected : null,
                  icon: const Icon(Icons.delete_outline, size: 19)),
              const Spacer(),
              if (!compact) ...[
                Text(_timecode(state.currentTimeMs, fps),
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                        color: AppTheme.textSecondary)),
                const SizedBox(width: 16),
              ],
              IconButton(
                  tooltip: 'Go to start',
                  onPressed: () => editor.seekTo(0),
                  icon: const Icon(Icons.skip_previous, size: 20)),
              IconButton.filledTonal(
                  tooltip: state.isPlaying ? 'Pause' : 'Play',
                  onPressed:
                      state.durationMs > 0 ? editor.togglePlayback : null,
                  icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 20)),
              IconButton(
                  tooltip: 'Go to end',
                  onPressed: () => editor.seekTo(state.durationMs),
                  icon: const Icon(Icons.skip_next, size: 20)),
              const SizedBox(width: 4),
            ]),
          ),
        ]),
      ),
    );
  }

  String _timecode(int milliseconds, double fps) {
    final duration = Duration(milliseconds: milliseconds);
    final frames = ((milliseconds % 1000) * fps / 1000).floor();
    return '${duration.inHours.toString().padLeft(2, '0')}:'
        '${(duration.inMinutes % 60).toString().padLeft(2, '0')}:'
        '${(duration.inSeconds % 60).toString().padLeft(2, '0')}:'
        '${frames.toString().padLeft(2, '0')}';
  }
}
