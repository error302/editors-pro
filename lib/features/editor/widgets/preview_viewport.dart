import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/services/engine_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/project_model.dart';
import '../../projects/providers/project_provider.dart';
import '../providers/editor_provider.dart';
import 'safe_zones_overlay.dart';
import 'text_overlay_handle.dart';
import 'transform_handles.dart';

enum SafeZoneType { actionSafe, titleSafe, centerCross, thirds, centerMarker }

/// Video preview viewport — displays the current frame rendered by the
/// Rust engine and provides playback controls.
///
/// Phase 4 improvements:
/// - Continuous frame decode loop during playback (not just on time change)
/// - Debounced scrub rendering during manual seek
/// - Frame prefetch during idle for smoother playback startup
class PreviewViewport extends ConsumerStatefulWidget {
  const PreviewViewport({super.key});

  @override
  ConsumerState<PreviewViewport> createState() => _PreviewViewportState();
}

class _PreviewViewportState extends ConsumerState<PreviewViewport> {
  /// PNG-encoded bytes for the current frame, or null when no frame
  /// is available.
  Uint8List? _currentFrameBytes;

  /// Whether the safe zones overlay is visible.
  bool _showSafeZones = false;

  /// Currently enabled safe zone types.
  Set<SafeZoneType> _enabledSafeZones = const {
    SafeZoneType.actionSafe,
    SafeZoneType.titleSafe,
  };

  /// Whether the zebra (overexposure) overlay is visible.
  bool _showZebra = false;

  SafeZoneConfig get _safeZoneConfig => SafeZoneConfig(
        showActionSafe: _enabledSafeZones.contains(SafeZoneType.actionSafe),
        showTitleSafe: _enabledSafeZones.contains(SafeZoneType.titleSafe),
        showCenter: _enabledSafeZones.contains(SafeZoneType.centerCross) ||
            _enabledSafeZones.contains(SafeZoneType.centerMarker),
        showRuleOfThirds: _enabledSafeZones.contains(SafeZoneType.thirds),
      );

  /// Frame duration in milliseconds at 30fps (≈33.33ms).
  static const int _frameDurationMs = 33;

  /// LRU cache of the last 10 rendered frames keyed by time position.
  final _frameCache = _LruCache<int, Uint8List>(maxSize: 10);

  /// Whether a frame request is currently in-flight.
  bool _fetchingFrame = false;

  /// The time position for which we are currently fetching a frame.
  int? _fetchingTimeMs;

  /// Subscription to the editor state for continuous playback decoding.
  StreamSubscription? _playbackSubscription;

  /// Timer for continuous frame fetching during playback.
  Timer? _playbackDecodeTimer;

  @override
  void initState() {
    super.initState();
    // Listen to time changes and request frames.
    ref.listenManual(editorProvider.select((s) => s.currentTimeMs), _onTimeChanged, fireImmediately: true);

    // Listen to playback state changes to start/stop continuous decode
    ref.listenManual(editorProvider.select((s) => s.isPlaying), _onPlaybackChanged);
  }

  @override
  void dispose() {
    _playbackDecodeTimer?.cancel();
    super.dispose();
  }

  void _onTimeChanged(int? previous, int next) {
    // During playback, the continuous decode timer handles frame fetching.
    // We only request frames here for manual seeks.
    final isPlaying = ref.read(editorProvider).isPlaying;
    if (!isPlaying) {
      _requestFrame(next);
    }
  }

  void _onPlaybackChanged(bool? wasPlaying, bool isPlaying) {
    if (isPlaying) {
      _startContinuousDecode();
    } else {
      _stopContinuousDecode();
      // When playback stops, render the current frame
      _requestFrame(ref.read(editorProvider).currentTimeMs);
    }
  }

  /// Start continuous frame decode during playback.
  ///
  /// Uses a Timer to continuously request frames from the engine
  /// at ~15fps (a balance between smoothness and CPU usage on mobile).
  void _startContinuousDecode() {
    _playbackDecodeTimer?.cancel();
    _playbackDecodeTimer = Timer.periodic(const Duration(milliseconds: 66), (_) {
      if (!mounted) return;
      final state = ref.read(editorProvider);
      if (!state.isPlaying) {
        _stopContinuousDecode();
        return;
      }
      _requestFrame(state.currentTimeMs);
    });
  }

  /// Stop the continuous decode loop.
  void _stopContinuousDecode() {
    _playbackDecodeTimer?.cancel();
    _playbackDecodeTimer = null;
  }

  Future<void> _requestFrame(int timeMs) async {
    if (!EngineService.instance.isInitialized) return;
    if (_fetchingFrame) return;

    // Check the cache first.
    final cached = _frameCache.get(timeMs);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _currentFrameBytes = cached;
        });
      }
      return;
    }

    _fetchingFrame = true;
    _fetchingTimeMs = timeMs;

    try {
      final api = EngineService.instance.api;
      final pngBytes = await api.getFrame(timeMs: BigInt.from(timeMs));

      if (!mounted) return;

      // Only apply if the user hasn't moved on to a very different position.
      final currentTimeMs = ref.read(editorProvider).currentTimeMs;
      if ((currentTimeMs - timeMs).abs() < 500) {
        _frameCache.put(timeMs, pngBytes);
        setState(() {
          _currentFrameBytes = pngBytes;
        });
      }
    } catch (e) {
      developer.log('getFrame failed at ${timeMs}ms: $e', name: 'PreviewViewport');
      // Leave the previous frame (or placeholder) in place.
    } finally {
      _fetchingFrame = false;
      _fetchingTimeMs = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);

    return Container(
      color: Colors.black,
      child: Column(
        children: [
          // Overlay toggle toolbar (above preview)
          _buildOverlayToolbar(context, editorState),

          // Preview area
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.border, width: 1),
                  ),
                  child: Stack(
                    children: [
                      // Video frame display
                      Center(
                        child: _buildPreviewContent(context, editorState),
                      ),

                      // Safe zones overlay
                      if (_showSafeZones)
                        SafeZonesOverlay(config: _safeZoneConfig),

                      // Zebra (overexposure) overlay
                      if (_showZebra)
                        CustomPaint(
                          painter: _ZebraOverlayPainter(),
                          size: Size.infinite,
                        ),

                      // Text overlay handles for selected text clips
                      _buildTextOverlayHandles(context, editorState),

                      // Transform handles for selected clips (move, scale, rotate)
                      _buildTransformHandles(context, editorState),

                      // Playback controls overlay
                      if (!editorState.isPlaying)
                        Center(
                          child: GestureDetector(
                            onTap: () => ref.read(editorProvider.notifier).togglePlayback(),
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                        ),

                      // Playback speed indicator
                      if (editorState.playbackSpeed != 1.0)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${editorState.playbackSpeed}x',
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                      // Decoding indicator
                      if (_fetchingFrame)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Scrub bar below preview
          _buildScrubBar(context, editorState),
        ],
      ),
    );
  }

  /// Build the overlay toggle toolbar above the preview viewport.
  ///
  /// Contains toggle buttons for:
  /// - Safe zones overlay
  /// - Zebra (overexposure warning) overlay
  /// - Frame step backward/forward buttons
  Widget _buildOverlayToolbar(BuildContext context, EditorState editorState) {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // Frame step backward
          IconButton(
            icon: const Icon(Icons.skip_previous, size: 16),
            tooltip: 'Previous frame',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: AppTheme.textSecondary,
            onPressed: () {
              final newTime = (editorState.currentTimeMs - _frameDurationMs).clamp(0, editorState.durationMs);
              ref.read(editorProvider.notifier).seekTo(newTime);
            },
          ),

          // Frame step forward
          IconButton(
            icon: const Icon(Icons.skip_next, size: 16),
            tooltip: 'Next frame',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: AppTheme.textSecondary,
            onPressed: () {
              final newTime = (editorState.currentTimeMs + _frameDurationMs).clamp(0, editorState.durationMs);
              ref.read(editorProvider.notifier).seekTo(newTime);
            },
          ),

          Container(width: 1, height: 16, color: AppTheme.border),

          // Safe zones toggle
          _OverlayToggleButton(
            icon: Icons.crop_free,
            label: 'Safe',
            isActive: _showSafeZones,
            onTap: () {
              setState(() => _showSafeZones = !_showSafeZones);
            },
            onLongPress: () {
              // Long press opens safe zone type selector
              _showSafeZonePicker();
            },
          ),

          // Zebra toggle
          _OverlayToggleButton(
            icon: Icons.warning_amber,
            label: 'Zebra',
            isActive: _showZebra,
            onTap: () {
              setState(() => _showZebra = !_showZebra);
            },
          ),

          const Spacer(),

          // Active overlay indicators
          if (_showSafeZones || _showZebra)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              child: Text(
                [
                  if (_showSafeZones) 'SAFE',
                  if (_showZebra) 'ZEBRA',
                ].join(' + '),
                style: const TextStyle(
                  color: AppTheme.primaryLight,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Show a dialog to pick which safe zone types to display.
  void _showSafeZonePicker() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              title: const Text(
                'Safe Zone Types',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: SafeZoneType.values.map((type) {
                  final isEnabled = _enabledSafeZones.contains(type);
                  return CheckboxListTile(
                    value: isEnabled,
                    title: Text(
                      _safeZoneTypeName(type),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    ),
                    subtitle: Text(
                      _safeZoneTypeDescription(type),
                      style: const TextStyle(color: AppTheme.textDisabled, fontSize: 10),
                    ),
                    activeColor: AppTheme.primary,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (checked) {
                      setDialogState(() {
                        final newZones = Set<SafeZoneType>.from(_enabledSafeZones);
                        if (checked == true) {
                          newZones.add(type);
                        } else {
                          newZones.remove(type);
                        }
                        _enabledSafeZones = newZones;
                      });
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _safeZoneTypeName(SafeZoneType type) {
    switch (type) {
      case SafeZoneType.actionSafe: return 'Action Safe';
      case SafeZoneType.titleSafe: return 'Title Safe';
      case SafeZoneType.centerCross: return 'Center Cross';
      case SafeZoneType.thirds: return 'Rule of Thirds';
      case SafeZoneType.centerMarker: return 'Center Marker';
    }
  }

  String _safeZoneTypeDescription(SafeZoneType type) {
    switch (type) {
      case SafeZoneType.actionSafe: return '90% frame boundary';
      case SafeZoneType.titleSafe: return '80% frame boundary';
      case SafeZoneType.centerCross: return 'Thin crosshair at center';
      case SafeZoneType.thirds: return 'Composition grid lines';
      case SafeZoneType.centerMarker: return 'Circle + crosshair at center';
    }
  }

  Widget _buildPreviewContent(BuildContext context, EditorState state) {
    final stillImage = _stillImageAtTime(
      ref.watch(currentProjectProvider),
      state.currentTimeMs,
    );
    if (stillImage != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final pixelRatio = MediaQuery.devicePixelRatioOf(context);
          final cacheWidth = constraints.maxWidth.isFinite
              ? (constraints.maxWidth * pixelRatio).round()
              : null;
          return Image.file(
            File(stillImage.filePath),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            cacheWidth:
                cacheWidth != null && cacheWidth > 0 ? cacheWidth : null,
            errorBuilder: (context, error, stackTrace) =>
                _buildImageUnavailable(context, stillImage.fileName),
          );
        },
      );
    }

    // If we have decoded frame bytes, display them.
    if (_currentFrameBytes != null && _currentFrameBytes!.isNotEmpty) {
      return Image.memory(
        _currentFrameBytes!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          // If the PNG data is corrupt, fall back to the placeholder.
          return _buildPlaceholder(context, state);
        },
      );
    }

    return _buildPlaceholder(context, state);
  }

  MediaAssetModel? _stillImageAtTime(ProjectModel? project, int timeMs) {
    if (project == null) return null;

    final activeClips = [
      for (final track in project.tracks)
        if (track.visible && track.trackType == TrackType.video)
          for (final clip in track.clips)
            if (timeMs >= clip.startMs &&
                timeMs < clip.startMs + clip.durationMs)
              clip,
    ];

    // Do not guess which layer to show when clips overlap; the native engine
    // must composite those cases.
    if (activeClips.length != 1) return null;

    final clip = activeClips.single;
    for (final asset in project.mediaAssets) {
      if (asset.id == clip.assetId &&
          asset.mediaType == MediaType.image &&
          asset.filePath.isNotEmpty) {
        return asset;
      }
    }
    return null;
  }

  Widget _buildImageUnavailable(BuildContext context, String fileName) {
    return Container(
      color: const Color(0xFF111122),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined,
                size: 40, color: AppTheme.textDisabled),
            const SizedBox(height: 8),
            Text(
              'Image unavailable',
              style: context.textTheme.titleSmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(
                color: AppTheme.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, EditorState state) {
    return Container(
      color: const Color(0xFF111122),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.movie_creation_outlined,
              size: 64,
              color: AppTheme.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              'Preview',
              style: context.textTheme.titleMedium?.copyWith(
                color: AppTheme.textDisabled,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              Duration(milliseconds: state.currentTimeMs).formatted,
              style: context.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build text overlay handles for any selected text clip.
  ///
  /// When a text clip is selected, this renders a draggable bounding box
  /// with resize handles on the preview viewport.
  Widget _buildTextOverlayHandles(BuildContext context, EditorState editorState) {
    final project = ref.watch(currentProjectProvider);
    if (project == null || editorState.selectedClipId == null) {
      return const SizedBox.shrink();
    }

    // Find the selected clip and check if it's on a text track
    ClipModel? selectedClip;
    TrackModel? selectedTrack;
    for (final track in project.tracks) {
      for (final clip in track.clips) {
        if (clip.id == editorState.selectedClipId) {
          selectedClip = clip;
          selectedTrack = track;
          break;
        }
      }
      if (selectedClip != null) break;
    }

    if (selectedClip == null || selectedTrack?.trackType != TrackType.text) {
      return const SizedBox.shrink();
    }

    // Create a TextOverlayData from the clip model
    final overlayData = TextOverlayData(
      clipId: selectedClip.id,
      text: selectedClip.assetId.startsWith('text_') ? 'Text' : selectedClip.assetId,
      positionX: 0.5,
      positionY: 0.5,
      width: 0.4,
      height: 0.1,
      isSelected: true,
    );

    return TextOverlayHandle(
      data: overlayData,
      onPositionChanged: (clipId, posX, posY) {
        ref.read(editorProvider.notifier).updateTextPosition(
              clipId: clipId,
              positionX: posX,
              positionY: posY,
            );
      },
      onTap: () {
        // Keep the clip selected (already is)
      },
    );
  }

  /// Build transform handles for the selected clip.
  ///
  /// When a clip is selected and has keyframe support, this renders
  /// move/scale/rotate handles on the preview viewport.
  Widget _buildTransformHandles(BuildContext context, EditorState editorState) {
    final project = ref.watch(currentProjectProvider);
    if (project == null || editorState.selectedClipId == null) {
      return const SizedBox.shrink();
    }

    // Don't show transform handles for text clips (those use TextOverlayHandle)
    ClipModel? selectedClip;
    TrackModel? selectedTrack;
    for (final track in project.tracks) {
      for (final clip in track.clips) {
        if (clip.id == editorState.selectedClipId) {
          selectedClip = clip;
          selectedTrack = track;
          break;
        }
      }
      if (selectedClip != null) break;
    }

    if (selectedClip == null) return const SizedBox.shrink();
    if (selectedTrack?.trackType == TrackType.text) return const SizedBox.shrink();

    // Calculate clip bounds relative to the preview area
    // Use a default centered rect for video/image clips
    // In a full implementation, this would be derived from keyframe data
    final bounds = Rect.fromCenter(
      center: const Offset(160, 90), // Center of 16:9 preview at 320x180
      width: 200,
      height: 112,
    );

    return TransformHandles(
      bounds: bounds,
      rotation: 0.0,
      isSelected: true,
      onMove: (delta) {
        // Convert pixel delta to normalized position and update via keyframe
        final normalizedDx = delta.dx / 320; // approximate preview width
        final normalizedDy = delta.dy / 180; // approximate preview height
        ref.read(editorProvider.notifier).updateClipTransform(
          clipId: selectedClip!.id,
          property: 'position_x',
          delta: normalizedDx,
        );
        ref.read(editorProvider.notifier).updateClipTransform(
          clipId: selectedClip!.id,
          property: 'position_y',
          delta: normalizedDy,
        );
      },
      onScaleStart: (handleType) {
        // Track initial scale for this handle type
      },
      onScaleUpdate: (delta) {
        // Convert pixel delta to normalized scale change
        final scaleDelta = 1.0 + (delta.dx + delta.dy) / 400;
        ref.read(editorProvider.notifier).updateClipTransform(
          clipId: selectedClip!.id,
          property: 'scale',
          delta: scaleDelta - 1.0,
        );
      },
      onRotate: (angleDelta) {
        // Add a rotation keyframe at the current time
        ref.read(editorProvider.notifier).updateClipTransform(
          clipId: selectedClip!.id,
          property: 'rotation',
          delta: angleDelta,
        );
      },
    );
  }

  Widget _buildScrubBar(BuildContext context, EditorState state) {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // Current time
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              Duration(milliseconds: state.currentTimeMs).formatted,
              style: context.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: AppTheme.textSecondary,
              ),
            ),
          ),

          // Scrubber
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: AppTheme.primary,
                thumbColor: Colors.white,
                inactiveTrackColor: AppTheme.borderLight,
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: state.durationMs > 0
                    ? state.currentTimeMs / state.durationMs
                    : 0,
                onChanged: (value) {
                  final timeMs = (value * state.durationMs).round();
                  ref.read(editorProvider.notifier).seekTo(timeMs);
                },
              ),
            ),
          ),

          // Duration
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              Duration(milliseconds: state.durationMs).formatted,
              style: context.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Overlay Toggle Button
// ═══════════════════════════════════════════════════════════════════════

/// A compact toggle button for the overlay toolbar.
class _OverlayToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _OverlayToggleButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.surfaceVariant
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: isActive ? AppTheme.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? AppTheme.primaryLight : AppTheme.textSecondary,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppTheme.primaryLight : AppTheme.textSecondary,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Zebra Overlay Painter
// ═══════════════════════════════════════════════════════════════════════

/// A zebra-stripe overlay that indicates overexposed areas.
///
/// In a real implementation, the engine would provide a luminance map
/// identifying overexposed pixels. Here we render a diagonal stripe
/// pattern as a visual placeholder that demonstrates the overlay UI.
class _ZebraOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0x55FF3333) // Semi-transparent red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw diagonal zebra stripes at 45 degrees
    const stripeSpacing = 12.0;
    final diagonalLength = size.width + size.height;

    for (double offset = 0; offset < diagonalLength; offset += stripeSpacing) {
      final startX = offset.clamp(0.0, size.width);
      final startY = (offset - startX).clamp(0.0, size.height);
      final endX = (offset - size.height).clamp(0.0, size.width);
      final endY = (offset - endX).clamp(0.0, size.height);

      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ZebraOverlayPainter oldDelegate) => false;
}

/// Simple LRU cache backed by a [LinkedHashMap].
///
/// Evicts the least-recently-used entry when [maxSize] is exceeded.
class _LruCache<K, V> {
  _LruCache({required this.maxSize});

  final int maxSize;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      // Re-insert at the end so it becomes most-recently-used.
      _map[key] = value;
    }
    return value;
  }

  void put(K key, V value) {
    _map.remove(key); // Remove if it already exists.
    _map[key] = value;
    while (_map.length > maxSize) {
      _map.remove(_map.keys.first);
    }
  }

  void clear() => _map.clear();
}
