import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/project_preview_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../data/models/project_model.dart';

Future<void> showProjectPreview(BuildContext context, ProjectModel project) =>
    showDialog<void>(
      context: context,
      builder: (_) => ProjectPreviewDialog(project: project),
    );

/// Preview playback is independent of the editing providers and their native project.
class ProjectPreviewDialog extends ConsumerStatefulWidget {
  const ProjectPreviewDialog({required this.project, super.key});
  final ProjectModel project;
  @override
  ConsumerState<ProjectPreviewDialog> createState() =>
      _ProjectPreviewDialogState();
}

class _ProjectPreviewDialogState extends ConsumerState<ProjectPreviewDialog>
    with WidgetsBindingObserver {
  ProjectPreview? _preview;
  VideoPlayerController? _controller;
  Object? _error;
  bool _loading = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    VideoPlayerController? controller;
    try {
      final preview = await ref.read(projectPreviewServiceProvider).ensure(
        widget.project,
        playable: true,
        onCover: (cover) {
          if (mounted && request == _request) setState(() => _preview = cover);
        },
      );
      if (!mounted || request != _request) return;
      if (preview.videoPath != null) {
        final sdk = Platform.isAndroid
            ? await StorageService.androidSdkVersion()
            : null;
        if (!mounted || request != _request) return;
        controller = VideoPlayerController.file(
          File(preview.videoPath!),
          // SurfaceView avoids exposing the decoder's padded crop columns.
          // Retain textures below API 34 because of the plugin's documented
          // platform-view scrolling issue on older Android versions.
          viewType: sdk != null && sdk >= 34
              ? VideoViewType.platformView
              : VideoViewType.textureView,
        );
        await controller.initialize();
        await controller.setLooping(true);
      }
      if (!mounted || request != _request) {
        await controller?.dispose();
        return;
      }
      setState(() {
        _preview = preview;
        _controller = controller;
        _loading = false;
      });
      await controller?.play();
    } catch (error) {
      await controller?.dispose();
      if (mounted && request == _request) {
        setState(() {
          _controller = null;
          _error = error;
          _loading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_controller?.pause());
  }

  @override
  void dispose() {
    _request++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.project.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close preview',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: widget.project.width / widget.project.height,
                child: ColoredBox(
                  color: Colors.black,
                  child: controller != null
                      ? VideoPlayer(controller)
                      : _preview?.coverPath != null
                          ? Image.file(
                              File(_preview!.coverPath!),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.movie_outlined),
                            )
                          : const Center(
                              child: Icon(Icons.movie_outlined, size: 48),
                            ),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Preparing preview of the saved timeline…'),
              ] else if (_error != null) ...[
                Text('Could not play preview: $_error'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ),
              ] else if (_preview?.isEmpty == true)
                const Text(
                  'This project has an empty timeline. Add media in the editor to preview it.',
                )
              else if (controller != null)
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => Column(
                    children: [
                      VideoProgressIndicator(controller, allowScrubbing: true),
                      Row(
                        children: [
                          IconButton(
                            tooltip: value.isPlaying
                                ? 'Pause preview'
                                : 'Play preview',
                            icon: Icon(
                              value.isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                            onPressed: () => value.isPlaying
                                ? controller.pause()
                                : controller.play(),
                          ),
                          Expanded(
                            child: Text(
                              _preview!.durationMs > 10000
                                  ? 'First 10 seconds · ${_duration(_preview!.durationMs)} project'
                                  : '${_duration(_preview!.durationMs)} · saved timeline',
                            ),
                          ),
                          IconButton(
                            tooltip: value.volume == 0
                                ? 'Unmute preview'
                                : 'Mute preview',
                            icon: Icon(
                              value.volume == 0
                                  ? Icons.volume_off
                                  : Icons.volume_up,
                            ),
                            onPressed: () =>
                                controller.setVolume(value.volume == 0 ? 1 : 0),
                          ),
                        ],
                      ),
                      if (value.hasError)
                        Text('Playback failed: ${value.errorDescription}'),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _duration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class ProjectCover extends ConsumerStatefulWidget {
  const ProjectCover({required this.project, super.key});
  final ProjectModel project;
  @override
  ConsumerState<ProjectCover> createState() => _ProjectCoverState();
}

class _ProjectCoverState extends ConsumerState<ProjectCover> {
  late Future<ProjectPreview> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProjectCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project != widget.project) _load();
  }

  void _load() =>
      _future = ref.read(projectPreviewServiceProvider).ensure(widget.project);
  @override
  Widget build(BuildContext context) => FutureBuilder<ProjectPreview>(
        future: _future,
        builder: (context, snapshot) {
          final path = snapshot.data?.coverPath;
          if (path != null) {
            return Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _placeholder('Cover unavailable'),
            );
          }
          if (snapshot.hasError) return _placeholder('Preview unavailable');
          if (snapshot.data?.isEmpty == true) {
            return _placeholder('Empty timeline');
          }
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
  Widget _placeholder(String label) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_outlined, size: 28),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      );
}
