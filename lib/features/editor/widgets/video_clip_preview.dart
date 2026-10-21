import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Android's platform decoder for a single source clip in the preview.
class VideoClipPreview extends StatefulWidget {
  const VideoClipPreview({
    required this.filePath,
    required this.fileName,
    required this.clipStartMs,
    required this.trimStartMs,
    required this.speed,
    required this.currentTimeMs,
    required this.isPlaying,
    super.key,
  });

  final String filePath;
  final String fileName;
  final int clipStartMs;
  final int trimStartMs;
  final double speed;
  final int currentTimeMs;
  final bool isPlaying;

  @override
  State<VideoClipPreview> createState() => _VideoClipPreviewState();
}

class _VideoClipPreviewState extends State<VideoClipPreview> {
  VideoPlayerController? _controller;
  Timer? _seekDebounce;
  int _generation = 0;
  bool _initializationFailed = false;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant VideoClipPreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.filePath != widget.filePath) {
      _replaceController();
      return;
    }

    if (oldWidget.speed != widget.speed) {
      unawaited(_setPlaybackSpeed());
      if (!widget.isPlaying) _scheduleSeek();
    }

    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        unawaited(_playFromPlayhead());
      } else {
        unawaited(_pauseAtPlayhead());
      }
    } else if (!widget.isPlaying &&
        (oldWidget.currentTimeMs != widget.currentTimeMs ||
            oldWidget.clipStartMs != widget.clipStartMs ||
            oldWidget.trimStartMs != widget.trimStartMs)) {
      _scheduleSeek();
    }
  }

  @override
  void dispose() {
    _seekDebounce?.cancel();
    _generation++;
    unawaited(_controller?.dispose());
    super.dispose();
  }

  void _createController() {
    final generation = ++_generation;
    final controller = VideoPlayerController.file(File(widget.filePath));
    _controller = controller;
    _initializationFailed = false;
    unawaited(_initialize(controller, generation));
  }

  Future<void> _initialize(
    VideoPlayerController controller,
    int generation,
  ) async {
    try {
      await controller.initialize();
      if (!_isCurrent(controller, generation)) return;
      await _setPlaybackSpeed(controller);
      await _seekToPlayhead(controller);
      if (widget.isPlaying && _isCurrent(controller, generation)) {
        await controller.play();
      }
    } catch (error, stackTrace) {
      developer.log(
        'Could not initialize video preview',
        name: 'VideoClipPreview',
        error: error,
        stackTrace: stackTrace,
      );
      if (_isCurrent(controller, generation) && mounted) {
        setState(() => _initializationFailed = true);
      }
    }
  }

  void _replaceController() {
    _seekDebounce?.cancel();
    final previous = _controller;
    _controller = null;
    _generation++;
    unawaited(previous?.dispose());
    _createController();
  }

  bool _isCurrent(VideoPlayerController controller, int generation) =>
      mounted &&
      generation == _generation &&
      identical(_controller, controller);

  double get _effectiveSpeed => widget.speed > 0 ? widget.speed : 1.0;

  Duration _sourcePosition(VideoPlayerController controller) {
    final clipOffsetMs = (widget.currentTimeMs - widget.clipStartMs).clamp(
      0,
      1 << 31,
    );
    final sourceOffsetMs = (clipOffsetMs * _effectiveSpeed).round();
    final requestedMs = widget.trimStartMs + sourceOffsetMs;
    final durationMs = controller.value.duration.inMilliseconds;
    return Duration(milliseconds: requestedMs.clamp(0, durationMs).toInt());
  }

  Future<void> _setPlaybackSpeed([VideoPlayerController? target]) async {
    final controller = target ?? _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setPlaybackSpeed(_effectiveSpeed);
    } catch (error) {
      developer.log(
        'Could not set video preview speed: $error',
        name: 'VideoClipPreview',
      );
    }
  }

  void _scheduleSeek() {
    _seekDebounce?.cancel();
    _seekDebounce = Timer(const Duration(milliseconds: 40), () {
      unawaited(_seekToPlayhead());
    });
  }

  Future<void> _seekToPlayhead([VideoPlayerController? target]) async {
    final controller = target ?? _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final position = _sourcePosition(controller);
      if ((controller.value.position - position).inMilliseconds.abs() > 70) {
        await controller.seekTo(position);
      }
    } catch (error) {
      developer.log(
        'Could not seek video preview: $error',
        name: 'VideoClipPreview',
      );
    }
  }

  Future<void> _playFromPlayhead() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await _setPlaybackSpeed(controller);
      await _seekToPlayhead(controller);
      await controller.play();
    } catch (error) {
      developer.log(
        'Could not start video preview: $error',
        name: 'VideoClipPreview',
      );
    }
  }

  Future<void> _pauseAtPlayhead() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.pause();
      await _seekToPlayhead(controller);
    } catch (error) {
      developer.log(
        'Could not pause video preview: $error',
        name: 'VideoClipPreview',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_initializationFailed) return _unavailable(context);
    if (controller == null) return _loading();

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        if (value.hasError) return _unavailable(context);
        if (!value.isInitialized) return _loading();

        final aspectRatio = value.aspectRatio.isFinite && value.aspectRatio > 0
            ? value.aspectRatio
            : 16 / 9;
        return Center(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: VideoPlayer(controller),
          ),
        );
      },
    );
  }

  Widget _loading() => const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );

  Widget _unavailable(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined, color: Colors.white54),
              const SizedBox(height: 8),
              Text(
                'Video unavailable',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 4),
              Text(
                widget.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
}
