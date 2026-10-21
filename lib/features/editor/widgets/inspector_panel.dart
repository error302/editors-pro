import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/services/engine_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/project_model.dart';
import '../../projects/providers/project_provider.dart';
import '../providers/editor_provider.dart';
import 'chroma_key_controls.dart';
import 'color_grading_panel.dart';
import 'keyframe_graph_editor.dart';
import 'transition_picker.dart';

/// Inspector panel - Shows properties of the selected clip or track
class InspectorPanel extends ConsumerWidget {
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(editorProvider);
    final project = ref.watch(currentProjectProvider);

    // Find the selected clip
    ClipModel? selectedClip;
    TrackModel? selectedTrack;
    if (editorState.selectedClipId != null && project != null) {
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
    }

    // If a track is selected (but no clip), show track properties
    if (selectedClip == null &&
        editorState.selectedTrackId != null &&
        project != null) {
      for (final track in project.tracks) {
        if (track.id == editorState.selectedTrackId) {
          return _buildTrackInspector(context, ref, track);
        }
      }
    }

    if (!editorState.showInspector || selectedClip == null) {
      return _buildEmptyInspector(context);
    }

    final clip = selectedClip;
    final track = selectedTrack;

    return Container(
      color: AppTheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Row(
            children: [
              Text('Inspector', style: context.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                onPressed: () =>
                    ref.read(editorProvider.notifier).selectClip(null),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Clip type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color:
                  _trackColor(selectedTrack?.trackType).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _trackTypeName(selectedTrack?.trackType),
              style: context.textTheme.labelMedium?.copyWith(
                color: _trackColor(selectedTrack?.trackType),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Timing section
          const _SectionHeader(title: 'Timing'),
          const SizedBox(height: 8),
          _PropertyRow(
            label: 'Start',
            value: Duration(milliseconds: clip.startMs).formatted,
          ),
          _PropertyRow(
            label: 'Duration',
            value: Duration(milliseconds: clip.durationMs).formatted,
          ),
          _PropertyRow(label: 'Trim Start', value: '${clip.trimStartMs}ms'),
          _PropertyRow(label: 'Trim End', value: '${clip.trimEndMs}ms'),
          const SizedBox(height: 16),

          // Speed section (enhanced with presets and curve editor link)
          const _SectionHeader(title: 'Speed'),
          const SizedBox(height: 8),
          _SpeedSection(
            clipId: clip.id,
            speed: clip.speed,
            durationMs: clip.durationMs,
            onSpeedChanged: (value) {
              ref.read(editorProvider.notifier).setClipSpeed(clip.id, value);
            },
            onOpenCurveEditor: () {
              ref
                  .read(editorProvider.notifier)
                  .setLeftPanelTab(LeftPanelTab.speed);
            },
          ),
          const SizedBox(height: 16),

          // Opacity control
          const _SectionHeader(title: 'Opacity'),
          const SizedBox(height: 8),
          _OpacityControl(
            opacity: clip.opacity,
            onChanged: (value) {
              ref.read(editorProvider.notifier).addKeyframe(
                    clip.id,
                    'opacity',
                    ref.read(editorProvider).currentTimeMs,
                    value,
                    'Linear',
                  );
            },
          ),
          const SizedBox(height: 16),

          // Keyframe section
          const _SectionHeader(title: 'Keyframes'),
          const SizedBox(height: 8),
          _KeyframeSection(
            clipId: clip.id,
            durationMs: clip.durationMs,
            onOpenGraphEditor: () {
              ref
                  .read(editorProvider.notifier)
                  .setLeftPanelTab(LeftPanelTab.keyframes);
            },
          ),
          const SizedBox(height: 16),

          // Track volume (show for audio and video tracks)
          if (track != null) ...[
            const _SectionHeader(title: 'Track Volume'),
            const SizedBox(height: 8),
            _VolumeControl(
              volume: track.volume,
              isMuted: !track.visible,
              onVolumeChanged: (value) {
                ref
                    .read(editorProvider.notifier)
                    .setTrackVolume(track.id, value);
              },
              onMuteToggled: () {
                ref
                    .read(editorProvider.notifier)
                    .toggleTrackVisibility(track.id);
              },
            ),
            const SizedBox(height: 16),

            // Audio ducking (show for audio tracks)
            if (track.trackType == TrackType.audio) ...[
              const _SectionHeader(title: 'Audio Ducking'),
              const SizedBox(height: 8),
              _DuckingControl(
                enabled: false,
                duckLevel: 0.3,
                onEnabledChanged: (enabled) {
                  ref.read(editorProvider.notifier).setDucking(
                        track.id,
                        enabled: enabled,
                        duckLevel: 0.3,
                      );
                },
                onLevelChanged: (level) {
                  ref.read(editorProvider.notifier).setDucking(
                        track.id,
                        enabled: true,
                        duckLevel: level,
                      );
                },
              ),
              const SizedBox(height: 16),
            ],
          ],

          // Effects section
          const _SectionHeader(title: 'Effects'),
          const SizedBox(height: 8),
          _EffectsSection(clipId: clip.id, initialEffects: clip.effects),
          const SizedBox(height: 16),

          // Color Grading section
          const _SectionHeader(
            title: 'Color Grading',
            icon: Icons.palette,
            iconColor: Colors.amber,
          ),
          const SizedBox(height: 8),
          _ColorGradingSection(clipId: clip.id),
          const SizedBox(height: 16),

          // Crop & Transform section
          const _SectionHeader(
            title: 'Crop & Transform',
            icon: Icons.crop_rotate,
            iconColor: Colors.teal,
          ),
          const SizedBox(height: 8),
          _CropTransformSection(clipId: clip.id),
          const SizedBox(height: 16),

          // Chroma Key section (show when a ChromaKey effect is applied to the clip)
          Builder(
            builder: (context) {
              // Check if the clip has a ChromaKey effect
              final chromaKeyEffects = clip.effects.where(
                (e) => e.effectType == 'chroma_key' || e.name == 'Chroma Key',
              );
              if (chromaKeyEffects.isNotEmpty) {
                final chromaKeyEffect = chromaKeyEffects.first;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader(
                      title: 'Chroma Key',
                      icon: Icons.filter_vintage,
                      iconColor: Colors.green,
                    ),
                    const SizedBox(height: 8),
                    ChromaKeyControls(
                      effectId: chromaKeyEffect.id,
                      clipId: clip.id,
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),

          // Transitions section
          const _SectionHeader(title: 'Transitions'),
          const SizedBox(height: 8),
          _TransitionsSection(clipId: clip.id),

          // Text properties section (show for text track clips)
          if (track?.trackType == TrackType.text) ...[
            const SizedBox(height: 16),
            const _SectionHeader(title: 'Text Properties'),
            const SizedBox(height: 8),
            _TextPropertiesSection(
              clipId: clip.id,
              assetId: clip.assetId,
            ),
          ],
        ],
      ),
    );
  }

  /// Build inspector for a selected track (no clip selected)
  Widget _buildTrackInspector(
    BuildContext context,
    WidgetRef ref,
    TrackModel track,
  ) {
    return Container(
      color: AppTheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Row(
            children: [
              Text('Track Inspector', style: context.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                onPressed: () =>
                    ref.read(editorProvider.notifier).selectTrack(null),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Track type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _trackColor(track.trackType).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _trackInspectorTypeName(track.trackType),
              style: context.textTheme.labelMedium?.copyWith(
                color: _trackColor(track.trackType),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Track name
          const _SectionHeader(title: 'Name'),
          const SizedBox(height: 8),
          Text(track.name, style: context.textTheme.bodyMedium),
          const SizedBox(height: 16),

          // Clip count
          _PropertyRow(label: 'Clips', value: '${track.clips.length}'),
          _PropertyRow(label: 'Locked', value: track.locked ? 'Yes' : 'No'),
          _PropertyRow(label: 'Visible', value: track.visible ? 'Yes' : 'No'),
          const SizedBox(height: 16),

          // Volume control
          const _SectionHeader(title: 'Volume'),
          const SizedBox(height: 8),
          _VolumeControl(
            volume: track.volume,
            isMuted: !track.visible,
            onVolumeChanged: (value) {
              ref.read(editorProvider.notifier).setTrackVolume(track.id, value);
            },
            onMuteToggled: () {
              ref.read(editorProvider.notifier).toggleTrackVisibility(track.id);
            },
          ),
          const SizedBox(height: 16),

          // Audio ducking (for audio tracks)
          if (track.trackType == TrackType.audio) ...[
            const _SectionHeader(title: 'Audio Ducking'),
            const SizedBox(height: 8),
            _DuckingControl(
              enabled: false,
              duckLevel: 0.3,
              onEnabledChanged: (enabled) {
                ref.read(editorProvider.notifier).setDucking(
                      track.id,
                      enabled: enabled,
                      duckLevel: 0.3,
                    );
              },
              onLevelChanged: (level) {
                ref.read(editorProvider.notifier).setDucking(
                      track.id,
                      enabled: true,
                      duckLevel: level,
                    );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyInspector(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 32),
          // Empty state message
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.touch_app,
                  size: 48,
                  color: AppTheme.textDisabled,
                ),
                const SizedBox(height: 16),
                Text(
                  'Select a clip',
                  style: context.textTheme.titleSmall?.copyWith(
                    color: AppTheme.textDisabled,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap any clip on the timeline\nto view its properties',
                  style: context.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // GPU Acceleration settings section
          _buildGpuSettingsSection(context),
        ],
      ),
    );
  }

  /// Build the GPU acceleration settings section shown in the empty
  /// inspector panel. Allows users to toggle GPU acceleration and
  /// see GPU adapter info.
  Widget _buildGpuSettingsSection(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final editorState = ref.watch(editorProvider);
        final gpuAvailable = editorState.gpuAvailable;
        final gpuEnabled = editorState.gpuAccelerationEnabled;
        final gpuInfo = editorState.gpuInfo;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'GPU Acceleration'),
            const SizedBox(height: 12),

            // GPU toggle switch
            _SettingsRow(
              label: 'Enable GPU',
              child: Switch(
                value: gpuAvailable && gpuEnabled,
                onChanged: gpuAvailable
                    ? (value) {
                        ref
                            .read(editorProvider.notifier)
                            .toggleGpuAcceleration(value);
                      }
                    : null,
                activeThumbColor: AppTheme.success,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),

            const SizedBox(height: 8),

            // GPU info rows
            if (gpuInfo != null && gpuInfo.available) ...[
              _SettingsRow(
                label: 'Adapter',
                value: gpuInfo.adapterName.isNotEmpty
                    ? gpuInfo.adapterName
                    : 'Unknown',
              ),
              _SettingsRow(
                label: 'Backend',
                value: gpuInfo.backend.isNotEmpty ? gpuInfo.backend : 'Unknown',
              ),
              _SettingsRow(
                label: 'VRAM',
                value: gpuInfo.vramFormatted,
              ),
              _SettingsRow(
                label: 'HW Encoder',
                value: gpuInfo.isHardwareEncoderAvailable
                    ? 'Available'
                    : 'Not available',
              ),
              if (gpuInfo.supportedEffects.isNotEmpty)
                _SettingsRow(
                  label: 'GPU Effects',
                  value: '${gpuInfo.supportedEffects.length} supported',
                ),
            ] else ...[
              const _SettingsRow(
                label: 'Status',
                value: 'No GPU detected',
                valueColor: AppTheme.textDisabled,
              ),
            ],
          ],
        );
      },
    );
  }

  Color _trackColor(TrackType? type) {
    switch (type) {
      case TrackType.video:
        return AppTheme.videoTrackColor;
      case TrackType.audio:
        return AppTheme.audioTrackColor;
      case TrackType.text:
        return AppTheme.textTrackColor;
      case TrackType.effect:
        return AppTheme.effectTrackColor;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _trackTypeName(TrackType? type) {
    switch (type) {
      case TrackType.video:
        return 'VIDEO CLIP';
      case TrackType.audio:
        return 'AUDIO CLIP';
      case TrackType.text:
        return 'TEXT CLIP';
      case TrackType.effect:
        return 'EFFECT';
      default:
        return 'CLIP';
    }
  }

  String _trackInspectorTypeName(TrackType? type) {
    switch (type) {
      case TrackType.video:
        return 'VIDEO TRACK';
      case TrackType.audio:
        return 'AUDIO TRACK';
      case TrackType.text:
        return 'TEXT TRACK';
      case TrackType.effect:
        return 'EFFECT TRACK';
      default:
        return 'TRACK';
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.icon, this.iconColor});
  final String title;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        if (icon != null)
          Icon(icon, size: 14, color: iconColor ?? AppTheme.textDisabled),
        Text(
          title.toUpperCase(),
          softWrap: true,
          style: context.textTheme.labelMedium?.copyWith(
            color: AppTheme.textDisabled,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: context.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A settings row that can display a label with either a text value
/// or a custom child widget (e.g., a switch). Used in the GPU settings
/// section of the inspector.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    this.value,
    this.valueColor,
    this.child,
  });
  final String label;
  final String? value;
  final Color? valueColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          if (child != null)
            child!
          else
            Flexible(
              child: Text(
                value ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: context.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: valueColor ?? AppTheme.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OpacityControl extends StatelessWidget {
  const _OpacityControl({required this.opacity, required this.onChanged});
  final double opacity;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(opacity * 100).round()}%',
              style: context.textTheme.titleSmall,
            ),
          ],
        ),
        Slider(
          value: opacity,
          min: 0.0,
          max: 1.0,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Volume control widget with mute toggle
class _VolumeControl extends StatelessWidget {
  const _VolumeControl({
    required this.volume,
    required this.isMuted,
    required this.onVolumeChanged,
    required this.onMuteToggled,
  });
  final double volume;
  final bool isMuted;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onMuteToggled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onMuteToggled,
              icon: Icon(
                isMuted ? Icons.volume_off : Icons.volume_up,
                size: 20,
                color: isMuted ? AppTheme.error : AppTheme.textSecondary,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: volume,
                min: 0.0,
                max: 2.0,
                divisions: 20,
                onChanged: onVolumeChanged,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              child: Text(
                isMuted ? 'MUTE' : '${(volume * 100).round()}%',
                style: context.textTheme.labelSmall?.copyWith(
                  color: isMuted ? AppTheme.error : AppTheme.textSecondary,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Ducking control widget
class _DuckingControl extends StatelessWidget {
  const _DuckingControl({
    required this.enabled,
    required this.duckLevel,
    required this.onEnabledChanged,
    required this.onLevelChanged,
  });
  final bool enabled;
  final double duckLevel;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<double> onLevelChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Switch(
              value: enabled,
              onChanged: onEnabledChanged,
              activeThumbColor: AppTheme.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                enabled ? 'Ducking Active' : 'Enable Ducking',
                style: context.textTheme.bodySmall?.copyWith(
                  color: enabled ? AppTheme.primary : AppTheme.textDisabled,
                ),
              ),
            ),
          ],
        ),
        if (enabled) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.volume_down,
                size: 16,
                color: AppTheme.textDisabled,
              ),
              Expanded(
                child: Slider(
                  value: duckLevel,
                  min: 0.0,
                  max: 0.8,
                  divisions: 8,
                  onChanged: onLevelChanged,
                ),
              ),
              const Icon(
                Icons.volume_up,
                size: 16,
                color: AppTheme.textDisabled,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  '${(duckLevel * 100).round()}%',
                  style: context.textTheme.labelSmall
                      ?.copyWith(fontFamily: 'monospace'),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Effects section — shows applied effects with parameter sliders
class _EffectsSection extends ConsumerStatefulWidget {
  const _EffectsSection({required this.clipId, required this.initialEffects});
  final String clipId;
  final List<EffectModel> initialEffects;

  @override
  ConsumerState<_EffectsSection> createState() => _EffectsSectionState();
}

class _EffectsSectionState extends ConsumerState<_EffectsSection> {
  late List<Map<String, dynamic>> _effects = _effectsFromModels(
    widget.initialEffects,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_updateEffectsFromTimeline());
  }

  @override
  void didUpdateWidget(covariant _EffectsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clipId != widget.clipId) {
      _effects = _effectsFromModels(widget.initialEffects);
      unawaited(_updateEffectsFromTimeline());
    }
  }

  Future<void> _updateEffectsFromTimeline() async {
    if (!EngineService.instance.isInitialized) return;
    final clipId = widget.clipId;
    try {
      final api = EngineService.instance.api;
      final effects = await api.getClipEffects(clipId: clipId);
      if (mounted && widget.clipId == clipId && effects.isNotEmpty) {
        setState(() {
          _effects = effects
              .map(
                (e) => <String, dynamic>{
                  'id': e.id,
                  'name': e.name,
                  'effect_type': e.effectType,
                  'enabled': e.enabled,
                  'parameters': e.parameters
                      .map(
                        (p) => <String, dynamic>{
                          'name': p.name,
                          'display_name': p.displayName,
                          'value': p.value,
                          'min_value': p.minValue,
                          'max_value': p.maxValue,
                        },
                      )
                      .toList(),
                },
              )
              .toList();
        });
      }
    } catch (e) {
      // Preserve effects restored from the project model if the engine is
      // unavailable; those remain editable in the inspector.
    }
  }

  List<Map<String, dynamic>> _effectsFromModels(List<EffectModel> effects) =>
      effects
          .map(
            (effect) => <String, dynamic>{
              'id': effect.id,
              'name': effect.name,
              'effect_type': effect.effectType,
              'enabled': effect.enabled,
              'parameters': effect.parameters
                  .map(
                    (parameter) => <String, dynamic>{
                      'name': parameter.name,
                      'display_name': parameter.displayName,
                      'value': parameter.value,
                      'min_value': parameter.minValue,
                      'max_value': parameter.maxValue,
                      'step': parameter.step,
                    },
                  )
                  .toList(),
            },
          )
          .toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_effects.isEmpty) ...[
          // Phase E.10: improved empty state with icon and guidance.
          // Previously just showed "No effects applied" with no further
          // direction. Now the user sees what to do next.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing24),
            child: Column(
              children: [
                const Icon(
                  Icons.auto_fix_high_outlined,
                  size: 48,
                  color: AppTheme.textDisabled,
                ),
                const SizedBox(height: AppTheme.spacing12),
                Text(
                  'No effects applied',
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing4),
                Text(
                  'Open the Effects tab in the left panel\nto browse filters, transitions, and more.',
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: AppTheme.textDisabled,
                  ),
                ),
              ],
            ),
          ),
        ],

        // Applied effects list
        ..._effects.map(
          (effect) => _AppliedEffectCard(
            effect: effect,
            onParameterChanged: (paramName, value) async {
              final effectId = effect['id'] as String? ?? '';
              await ref.read(editorProvider.notifier).setEffectParameter(
                    effectId,
                    paramName,
                    value,
                  );
            },
            onToggleEnabled: () async {
              final effectId = effect['id'] as String? ?? '';
              setState(() {
                effect['enabled'] = !(effect['enabled'] as bool? ?? true);
              });
              await ref.read(editorProvider.notifier).toggleEffect(effectId);
              await _updateEffectsFromTimeline();
            },
            onRemove: () async {
              final effectId = effect['id'] as String? ?? '';
              setState(() {
                _effects.removeWhere((item) => item['id'] == effectId);
              });
              await ref.read(editorProvider.notifier).removeEffect(effectId);
              await _updateEffectsFromTimeline();
            },
          ),
        ),

        const SizedBox(height: 8),

        // Add Effect button
        OutlinedButton.icon(
          onPressed: () {
            ref
                .read(editorProvider.notifier)
                .setLeftPanelTab(LeftPanelTab.effects);
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Effect'),
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(36)),
        ),
      ],
    );
  }
}

/// Card showing an applied effect with its parameter sliders
class _AppliedEffectCard extends StatelessWidget {
  const _AppliedEffectCard({
    required this.effect,
    required this.onParameterChanged,
    required this.onToggleEnabled,
    required this.onRemove,
  });
  final Map<String, dynamic> effect;
  final void Function(String paramName, double value) onParameterChanged;
  final VoidCallback onToggleEnabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name = effect['name'] as String? ?? 'Unknown';
    final effectType = effect['effect_type'] as String? ?? '';
    final enabled = effect['enabled'] as bool? ?? true;
    final parameters = effect['parameters'] as List<dynamic>? ?? [];
    final effectId = effect['id'] as String? ?? '';
    final isChromaKey = effectType == 'chroma_key' ||
        effectType == 'ChromaKey' ||
        name == 'Chroma Key';

    return Card(
      key: ValueKey('effect-$effectId'),
      color: AppTheme.surfaceVariant,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Effect header
            Row(
              children: [
                Icon(
                  isChromaKey ? Icons.colorize : Icons.auto_fix_high,
                  size: 16,
                  color: enabled ? AppTheme.primary : AppTheme.textDisabled,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: enabled
                          ? AppTheme.textPrimary
                          : AppTheme.textDisabled,
                    ),
                  ),
                ),
                // Toggle enabled
                IconButton(
                  onPressed: onToggleEnabled,
                  icon: Icon(
                    enabled ? Icons.visibility : Icons.visibility_off,
                    size: 16,
                    color: enabled
                        ? AppTheme.textSecondary
                        : AppTheme.textDisabled,
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
                // Remove
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: AppTheme.error.withValues(alpha: 0.7),
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),

            // Parameter sliders (or ChromaKey controls)
            if (enabled && parameters.isNotEmpty) ...[
              const SizedBox(height: 4),
              if (isChromaKey) ...[
                // Use dedicated ChromaKey controls widget
                Consumer(
                  builder: (context, ref, _) {
                    // Find the clip ID from the editor state
                    final editorState = ref.watch(editorProvider);
                    final clipId = editorState.selectedClipId ?? '';
                    return ChromaKeyControls(
                      effectId: effectId,
                      clipId: clipId,
                    );
                  },
                ),
              ] else ...[
                ...parameters.map((param) {
                  final p = param as Map<dynamic, dynamic>;
                  final paramName = p['name'] as String? ?? '';
                  final displayName = p['display_name'] as String? ?? paramName;
                  final value = (p['value'] as num?)?.toDouble() ?? 0.0;
                  final minVal = (p['min_value'] as num?)?.toDouble() ?? 0.0;
                  final maxVal = (p['max_value'] as num?)?.toDouble() ?? 1.0;
                  final step = (p['step'] as num?)?.toDouble() ?? 0.01;

                  return _EffectParameterSlider(
                    name: displayName,
                    value: value,
                    min: minVal,
                    max: maxVal,
                    step: step,
                    onChanged: (v) => onParameterChanged(paramName, v),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Single parameter slider for an effect
class _EffectParameterSlider extends StatelessWidget {
  const _EffectParameterSlider({
    required this.name,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });
  final String name;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    // Format display value
    String displayValue;
    if (step >= 1.0) {
      displayValue = value.round().toString();
    } else if (step >= 0.1) {
      displayValue = value.toStringAsFixed(1);
    } else {
      displayValue = value.toStringAsFixed(2);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              name,
              style: context.textTheme.labelSmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              displayValue,
              style: context.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: AppTheme.textPrimary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// Transitions section — shows applied transitions and add button
class _TransitionsSection extends ConsumerWidget {
  const _TransitionsSection({required this.clipId});
  final String clipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            'Add transitions between clips',
            style: context.textTheme.bodySmall?.copyWith(
              color: AppTheme.textDisabled,
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            _showTransitionPicker(context, ref);
          },
          icon: const Icon(Icons.swap_horiz, size: 16),
          label: const Text('Add Transition'),
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(36)),
        ),
      ],
    );
  }

  void _showTransitionPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('Transitions', style: context.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Transition picker content
            const Expanded(
              child: TransitionPicker(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text properties section — shows text content editor, font picker, font size
/// slider, color picker, animation dropdown, and position X/Y fields when a
/// text clip is selected.
class _TextPropertiesSection extends ConsumerStatefulWidget {
  const _TextPropertiesSection({
    required this.clipId,
    required this.assetId,
  });
  final String clipId;
  final String assetId;

  @override
  ConsumerState<_TextPropertiesSection> createState() =>
      _TextPropertiesSectionState();
}

class _TextPropertiesSectionState
    extends ConsumerState<_TextPropertiesSection> {
  late TextEditingController _textController;
  String _selectedFont = 'Inter';
  double _fontSize = 36.0;
  String _selectedColor = '#FFFFFF';
  String _selectedAnimation = 'None';
  double _positionX = 0.5;
  double _positionY = 0.5;
  List<Map<String, String>> _availableFonts = [];

  static const List<Map<String, String>> _defaultFonts = [
    {'name': 'Inter', 'family': 'Inter', 'style': 'Regular'},
    {'name': 'Roboto', 'family': 'Roboto', 'style': 'Regular'},
    {'name': 'Open Sans', 'family': 'Open Sans', 'style': 'Regular'},
    {'name': 'Lato', 'family': 'Lato', 'style': 'Regular'},
    {'name': 'Montserrat', 'family': 'Montserrat', 'style': 'Regular'},
    {
      'name': 'Playfair Display',
      'family': 'Playfair Display',
      'style': 'Regular',
    },
  ];

  static const List<String> _animations = [
    'None',
    'Fade In',
    'Fade Out',
    'Typewriter',
    'Slide In',
    'Pop In',
  ];

  static const List<Map<String, String>> _presetColors = [
    {'name': 'White', 'hex': '#FFFFFF'},
    {'name': 'Black', 'hex': '#000000'},
    {'name': 'Red', 'hex': '#FF0000'},
    {'name': 'Green', 'hex': '#00FF00'},
    {'name': 'Blue', 'hex': '#0000FF'},
    {'name': 'Yellow', 'hex': '#FFFF00'},
    {'name': 'Cyan', 'hex': '#00FFFF'},
    {'name': 'Magenta', 'hex': '#FF00FF'},
    {'name': 'Orange', 'hex': '#FF8800'},
    {'name': 'Purple', 'hex': '#8800FF'},
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.assetId.startsWith('text_') ? 'Your Text' : '',
    );
    _loadFonts();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadFonts() async {
    try {
      final fonts = await ref.read(editorProvider.notifier).getAvailableFonts();
      if (mounted && fonts.isNotEmpty) {
        setState(() {
          _availableFonts = fonts
              .map(
                (f) => {
                  'name': f.name,
                  'family': f.family,
                  'style': f.style,
                },
              )
              .toList();
          if (_availableFonts.isNotEmpty) {
            _selectedFont = _availableFonts.first['family']!;
          }
        });
      } else {
        setState(() {
          _availableFonts = _defaultFonts;
        });
      }
    } catch (_) {
      setState(() {
        _availableFonts = _defaultFonts;
      });
    }
  }

  Future<void> _updateTextStyle() async {
    await ref.read(editorProvider.notifier).updateTextStyle(
          clipId: widget.clipId,
          fontFamily: _selectedFont,
          fontSize: _fontSize,
          colorHex: _selectedColor,
        );
  }

  Future<void> _updateTextPosition() async {
    await ref.read(editorProvider.notifier).updateTextPosition(
          clipId: widget.clipId,
          positionX: _positionX,
          positionY: _positionY,
        );
  }

  Color _parseHexColor(String hex) {
    final hexStr = hex.replaceFirst('#', '');
    return Color(int.parse('FF$hexStr', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text content editor
        TextField(
          controller: _textController,
          maxLines: 2,
          minLines: 1,
          style: context.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Text content...',
            hintStyle: const TextStyle(color: AppTheme.textDisabled),
            filled: true,
            fillColor: AppTheme.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(10),
          ),
          onChanged: (_) => _updateTextStyle(),
        ),
        const SizedBox(height: 10),

        // Font picker dropdown
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('Font', style: context.textTheme.bodySmall),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedFont,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    style: context.textTheme.bodySmall,
                    dropdownColor: AppTheme.surfaceVariant,
                    items: _availableFonts.map((font) {
                      return DropdownMenuItem<String>(
                        value: font['family'],
                        child: Text(
                          font['name']!,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedFont = value);
                        _updateTextStyle();
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Font size slider
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('Size', style: context.textTheme.bodySmall),
            ),
            Expanded(
              child: Slider(
                value: _fontSize,
                min: 8.0,
                max: 120.0,
                divisions: 56,
                onChanged: (value) {
                  setState(() => _fontSize = value);
                  _updateTextStyle();
                },
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                _fontSize.round().toString(),
                style: context.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Color picker (simple preset colors)
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('Color', style: context.textTheme.bodySmall),
            ),
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _presetColors.map((color) {
                  final hex = color['hex']!;
                  final isSelected = _selectedColor == hex;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedColor = hex);
                      _updateTextStyle();
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _parseHexColor(hex),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : const Color(0xFF2A2A3E),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Animation dropdown
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('Animate', style: context.textTheme.bodySmall),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedAnimation,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.animation,
                      size: 14,
                      color: AppTheme.textSecondary,
                    ),
                    style: context.textTheme.bodySmall,
                    dropdownColor: AppTheme.surfaceVariant,
                    items: _animations.map((anim) {
                      return DropdownMenuItem<String>(
                        value: anim,
                        child: Text(
                          anim,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedAnimation = value);
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Position X/Y fields
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('Pos X', style: context.textTheme.bodySmall),
            ),
            Expanded(
              child: Slider(
                value: _positionX,
                min: 0.0,
                max: 1.0,
                divisions: 100,
                onChanged: (value) {
                  setState(() => _positionX = value);
                },
                onChangeEnd: (_) => _updateTextPosition(),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                _positionX.toStringAsFixed(2),
                style: context.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('Pos Y', style: context.textTheme.bodySmall),
            ),
            Expanded(
              child: Slider(
                value: _positionY,
                min: 0.0,
                max: 1.0,
                divisions: 100,
                onChanged: (value) {
                  setState(() => _positionY = value);
                },
                onChangeEnd: (_) => _updateTextPosition(),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                _positionY.toStringAsFixed(2),
                style: context.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Speed section — shows current speed, presets, and link to curve editor
class _SpeedSection extends ConsumerStatefulWidget {
  const _SpeedSection({
    required this.clipId,
    required this.speed,
    required this.durationMs,
    required this.onSpeedChanged,
    required this.onOpenCurveEditor,
  });
  final String clipId;
  final double speed;
  final int durationMs;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onOpenCurveEditor;

  @override
  ConsumerState<_SpeedSection> createState() => _SpeedSectionState();
}

class _SpeedSectionState extends ConsumerState<_SpeedSection> {
  late double _speed;

  static const List<double> _speedPresets = [0.25, 0.5, 1.0, 2.0, 4.0];

  @override
  void initState() {
    super.initState();
    _speed = widget.speed;
  }

  @override
  void didUpdateWidget(covariant _SpeedSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) {
      _speed = widget.speed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current speed display + presets
        Row(
          children: [
            Text(
              '${_speed.toStringAsFixed(1)}x',
              style: context.textTheme.titleSmall?.copyWith(
                color: _speed == 1.0 ? AppTheme.textPrimary : AppTheme.primary,
              ),
            ),
            // Speed presets
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                runSpacing: 2,
                children: _speedPresets.map((s) {
                  final isSelected = (_speed - s).abs() < 0.01;
                  return ChoiceChip(
                    label: Text('${s}x', style: const TextStyle(fontSize: 9)),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _speed = s);
                      widget.onSpeedChanged(s);
                    },
                    visualDensity: VisualDensity.compact,
                    selectedColor: AppTheme.primary,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Speed slider
        Slider(
          value: _speed,
          min: 0.1,
          max: 8.0,
          divisions: 79,
          onChanged: (value) {
            setState(() => _speed = value);
          },
          onChangeEnd: (value) {
            widget.onSpeedChanged(value);
          },
        ),

        // Open Speed Curve Editor button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onOpenCurveEditor,
            icon: const Icon(Icons.show_chart, size: 14),
            label: const Text(
              'Speed Curve Editor',
              style: TextStyle(fontSize: 11),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: const BorderSide(color: Color(0xFF2A2A3E)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ),

        const SizedBox(height: 6),
      ],
    );
  }

  /// Show a dialog explaining the Freeze Frame feature and optionally
  /// perform the split + speed change.

  /// Apply freeze frame: split at playhead and set the second clip's
  /// speed to a very high value.
}

/// Keyframe section — shows keyframe indicators and graph editor link
class _KeyframeSection extends ConsumerStatefulWidget {
  const _KeyframeSection({
    required this.clipId,
    required this.durationMs,
    required this.onOpenGraphEditor,
  });
  final String clipId;
  final int durationMs;
  final VoidCallback onOpenGraphEditor;

  @override
  ConsumerState<_KeyframeSection> createState() => _KeyframeSectionState();
}

class _KeyframeSectionState extends ConsumerState<_KeyframeSection> {
  String _selectedProperty = 'position_x';
  final Map<String, List<KeyframePoint>> _keyframeData = {};
  String? _selectedKeyframeId;

  static const Map<String, _KeyframePropertyConfig> _propertyConfigs = {
    'position_x': _KeyframePropertyConfig(label: 'Pos X', color: Colors.blue),
    'position_y': _KeyframePropertyConfig(label: 'Pos Y', color: Colors.green),
    'scale': _KeyframePropertyConfig(label: 'Scale', color: Colors.orange),
    'rotation':
        _KeyframePropertyConfig(label: 'Rotation', color: Colors.purple),
    'opacity': _KeyframePropertyConfig(label: 'Opacity', color: Colors.red),
  };

  static const List<String> _easingTypes = [
    'linear',
    'ease_in',
    'ease_out',
    'ease_in_out',
  ];

  @override
  void initState() {
    super.initState();
    for (final prop in _propertyConfigs.keys) {
      _keyframeData[prop] = [];
    }
    _loadKeyframesFromEngine();
  }

  void _loadKeyframesFromEngine() async {
    if (!EngineService.instance.isInitialized) return;
    try {
      final api = EngineService.instance.api;
      final loaded = <String, List<KeyframePoint>>{};
      for (final prop in _propertyConfigs.keys) {
        final keyframes = await api.getKeyframes(
          clipId: widget.clipId,
          property: prop,
        );
        loaded[prop] = keyframes
            .map(
              (k) => KeyframePoint(
                id: k.id,
                timeMs: k.timeMs,
                value: k.value,
                easingName: k.easingName,
              ),
            )
            .toList();
      }
      if (mounted) {
        setState(() {
          for (final prop in _propertyConfigs.keys) {
            _keyframeData[prop] = loaded[prop] ?? [];
          }
        });
      }
    } catch (e) {
      // Engine not ready or clip has no keyframes yet
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyframes = _keyframeData[_selectedProperty] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Property selector
        Row(
          children: [
            const Text(
              'Property: ',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedProperty,
                    isDense: true,
                    isExpanded: true,
                    dropdownColor: AppTheme.surfaceVariant,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 11,
                    ),
                    items: _propertyConfigs.entries.map((entry) {
                      return DropdownMenuItem(
                        value: entry.key,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: entry.value.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(entry.value.label),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedProperty = value);
                        _loadKeyframesFromEngine();
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Add keyframe button
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addKeyframeAtPlayhead,
                icon: const Icon(Icons.add_circle_outline, size: 14),
                label:
                    const Text('Add Keyframe', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: Color(0xFF2A2A3E)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _deleteSelectedKeyframe,
              icon: Icon(
                Icons.remove_circle_outline,
                size: 18,
                color: _selectedKeyframeId != null
                    ? Colors.redAccent
                    : AppTheme.textDisabled,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Delete keyframe',
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Keyframe list
        if (keyframes.isNotEmpty) ...[
          Container(
            constraints: const BoxConstraints(maxHeight: 120),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: keyframes.length,
              itemBuilder: (context, index) {
                final kf = keyframes[index];
                final isSelected = kf.id == _selectedKeyframeId;
                final config = _propertyConfigs[_selectedProperty]!;

                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedKeyframeId = kf.id);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: isSelected
                          ? Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Diamond icon
                        Icon(
                          Icons.diamond,
                          size: 10,
                          color: config.color,
                        ),
                        const SizedBox(width: 6),
                        // Time
                        Text(
                          '${(kf.timeMs / 1000.0).toStringAsFixed(2)}s',
                          style: TextStyle(
                            color: isSelected
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Value
                        Expanded(
                          child: Text(
                            kf.value.toStringAsFixed(1),
                            style: TextStyle(
                              color: config.color,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        // Easing indicator
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            kf.easingName.replaceAll('_', ' ').toUpperCase(),
                            style: const TextStyle(
                              color: AppTheme.textDisabled,
                              fontSize: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ] else ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No keyframes yet',
                style: context.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textDisabled,
                ),
              ),
            ),
          ),
        ],

        // Easing selector for selected keyframe
        if (_selectedKeyframeId != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Text(
                'Easing: ',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 10),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _getSelectedKeyframe()?.easingName ?? 'linear',
                      isDense: true,
                      isExpanded: true,
                      dropdownColor: AppTheme.surfaceVariant,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 10,
                      ),
                      items: _easingTypes.map((easing) {
                        return DropdownMenuItem(
                          value: easing,
                          child:
                              Text(easing.replaceAll('_', ' ').toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          _updateKeyframeEasing(value);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 6),

        // Open Graph Editor button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onOpenGraphEditor,
            icon: const Icon(Icons.timeline, size: 14),
            label:
                const Text('Open Graph Editor', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: const BorderSide(color: Color(0xFF2A2A3E)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ),
      ],
    );
  }

  KeyframePoint? _getSelectedKeyframe() {
    if (_selectedKeyframeId == null) return null;
    final keyframes = _keyframeData[_selectedProperty] ?? [];
    return keyframes.where((kf) => kf.id == _selectedKeyframeId).firstOrNull;
  }

  void _addKeyframeAtPlayhead() {
    final timeMs = ref.read(editorProvider).currentTimeMs;
    final newId = 'kf_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _keyframeData[_selectedProperty]!.add(
        KeyframePoint(
          id: newId,
          timeMs: timeMs,
          value: 0.0,
          easingName: 'linear',
        ),
      );
      _keyframeData[_selectedProperty]!
          .sort((a, b) => a.timeMs.compareTo(b.timeMs));
      _selectedKeyframeId = newId;
    });

    ref.read(editorProvider.notifier).addKeyframe(
          widget.clipId,
          _selectedProperty,
          timeMs,
          0.0,
          'linear',
        );
  }

  void _deleteSelectedKeyframe() {
    if (_selectedKeyframeId == null) return;
    final keyframes = _keyframeData[_selectedProperty];
    if (keyframes == null) return;

    final toRemove =
        keyframes.where((kf) => kf.id == _selectedKeyframeId).firstOrNull;
    if (toRemove != null) {
      setState(() {
        keyframes.remove(toRemove);
        _selectedKeyframeId = null;
      });
      ref.read(editorProvider.notifier).removeKeyframe(
            widget.clipId,
            _selectedProperty,
            toRemove.id,
          );
    }
  }

  void _updateKeyframeEasing(String easingName) {
    if (_selectedKeyframeId == null) return;
    final keyframes = _keyframeData[_selectedProperty];
    if (keyframes == null) return;

    final idx = keyframes.indexWhere((kf) => kf.id == _selectedKeyframeId);
    if (idx < 0) return;

    setState(() {
      keyframes[idx] = keyframes[idx].copyWith(easingName: easingName);
    });

    ref.read(editorProvider.notifier).updateKeyframe(
          widget.clipId,
          _selectedProperty,
          _selectedKeyframeId!,
          value: keyframes[idx].value,
          easing: easingName,
        );
  }
}

/// Configuration for a keyframe property in the inspector
class _KeyframePropertyConfig {
  const _KeyframePropertyConfig({
    required this.label,
    required this.color,
  });
  final String label;
  final Color color;
}

// ─── Color Grading Section ──────────────────────────────────────────────

/// Inspector section for color grading (lift/gamma/gain wheels).
///
/// When the user adjusts any wheel, the values are applied as effects
/// to the selected clip:
/// - Lift R/G/B → "color_lift" effect parameters
/// - Gamma R/G/B → "color_gamma" effect parameters
/// - Gain R/G/B → "color_gain" effect parameters
///
/// Since the engine may not have dedicated "color_lift"/"color_gamma"/
/// "color_gain" filter types, we fall back to using "Brightness" for
/// the master adjustment and "Temperature" for the color tint of each
/// wheel. The effect IDs are cached so we only add them once.
class _ColorGradingSection extends ConsumerStatefulWidget {
  const _ColorGradingSection({required this.clipId});
  final String clipId;

  @override
  ConsumerState<_ColorGradingSection> createState() =>
      _ColorGradingSectionState();
}

class _ColorGradingSectionState extends ConsumerState<_ColorGradingSection> {
  ColorGradeValues _values = ColorGradeValues.neutral;

  // Cached effect IDs for the three color grading wheels.
  // Null means the effect hasn't been added yet.
  String? _liftEffectId;
  String? _gammaEffectId;
  String? _gainEffectId;

  @override
  Widget build(BuildContext context) {
    return ColorGradingPanel(
      initialValues: _values,
      onChanged: _onColorGradeChanged,
    );
  }

  /// Called when the user adjusts any color grading wheel.
  void _onColorGradeChanged(ColorGradeValues newValues) {
    setState(() => _values = newValues);
    _applyColorGradeToEngine(newValues);
  }

  /// Apply the color grade values to the engine as effects.
  ///
  /// For each wheel (lift, gamma, gain):
  /// - The master value maps to a "Brightness" effect parameter.
  /// - The hue/saturation tint maps to a "Temperature" effect parameter.
  ///
  /// We try to add a "color_lift"/"color_gamma"/"color_gain" effect first.
  /// If those filter types don't exist in the engine, we fall back to
  /// using "Brightness" and "Temperature" effects.
  Future<void> _applyColorGradeToEngine(ColorGradeValues values) async {
    final rgbOffsets = values.toRgbOffsets();

    // ── Lift ──
    await _ensureEffect(
      effectIdGetter: () => _liftEffectId,
      effectIdSetter: (id) => _liftEffectId = id,
      preferredName: 'color_lift',
      fallbackName: 'Brightness',
      parameters: {
        'lift_r': rgbOffsets['lift']![0],
        'lift_g': rgbOffsets['lift']![1],
        'lift_b': rgbOffsets['lift']![2],
        'brightness': values.liftMaster,
      },
    );

    // ── Gamma ──
    await _ensureEffect(
      effectIdGetter: () => _gammaEffectId,
      effectIdSetter: (id) => _gammaEffectId = id,
      preferredName: 'color_gamma',
      fallbackName: 'Contrast',
      parameters: {
        'gamma_r': rgbOffsets['gamma']![0],
        'gamma_g': rgbOffsets['gamma']![1],
        'gamma_b': rgbOffsets['gamma']![2],
        'contrast': values.gammaMaster,
      },
    );

    // ── Gain ──
    await _ensureEffect(
      effectIdGetter: () => _gainEffectId,
      effectIdSetter: (id) => _gainEffectId = id,
      preferredName: 'color_gain',
      fallbackName: 'Saturation',
      parameters: {
        'gain_r': rgbOffsets['gain']![0],
        'gain_g': rgbOffsets['gain']![1],
        'gain_b': rgbOffsets['gain']![2],
        'saturation': 1.0 + values.gainMaster,
      },
    );
  }

  /// Ensure an effect exists on the clip, adding it if needed.
  /// Then set all [parameters] on it.
  Future<void> _ensureEffect({
    required String? Function() effectIdGetter,
    required void Function(String) effectIdSetter,
    required String preferredName,
    required String fallbackName,
    required Map<String, double> parameters,
  }) async {
    var effectId = effectIdGetter();

    // Add the effect if it doesn't exist yet.
    if (effectId == null) {
      // Try preferred name first (e.g. "color_lift").
      var id = await ref.read(editorProvider.notifier).addEffect(preferredName);
      id ??= await ref.read(editorProvider.notifier).addEffect(fallbackName);
      if (id != null) {
        effectIdSetter(id);
        effectId = id;
      }
    }

    // Set parameters on the effect.
    if (effectId != null) {
      for (final entry in parameters.entries) {
        // The provider's setEffectParameter catches errors internally,
        // so we don't need try/catch here. If a parameter name doesn't
        // exist on the effect type (e.g. "lift_r" on a Brightness
        // effect), the engine will log an error but won't crash.
        await ref.read(editorProvider.notifier).setEffectParameter(
              effectId,
              entry.key,
              entry.value,
            );
      }
    }
  }
}

// ─── Crop & Transform Section ───────────────────────────────────────────

/// Inspector section for crop and transform operations.
///
/// Provides buttons for rotation, flipping, and resetting transforms.
/// Each operation applies a keyframe at the current playhead time so
/// the transform can be animated over time.
class _CropTransformSection extends ConsumerStatefulWidget {
  const _CropTransformSection({required this.clipId});
  final String clipId;

  @override
  ConsumerState<_CropTransformSection> createState() =>
      _CropTransformSectionState();
}

class _CropTransformSectionState extends ConsumerState<_CropTransformSection> {
  /// Current cumulative rotation in degrees (tracks state for UI display).
  double _rotation = 0.0;

  /// Flip state: -1.0 = flipped, 1.0 = normal.
  double _scaleX = 1.0;
  double _scaleY = 1.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current transform summary
        Text(
          'Rotation: ${_rotation.round()}°   '
          'Flip H: ${_scaleX < 0 ? "Yes" : "No"}   '
          'Flip V: ${_scaleY < 0 ? "Yes" : "No"}',
          style: context.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),

        // Transform buttons grid
        Row(
          children: [
            Expanded(
              child: _TransformButton(
                icon: Icons.rotate_left,
                label: 'Rotate Left',
                onTap: _rotateLeft,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _TransformButton(
                icon: Icons.rotate_right,
                label: 'Rotate Right',
                onTap: _rotateRight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _TransformButton(
                icon: Icons.flip,
                label: 'Flip Horiz',
                onTap: _flipHorizontal,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _TransformButton(
                icon: Icons.flip,
                label: 'Flip Vert',
                onTap: _flipVertical,
                rotation: 90,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Reset transform button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _resetTransform,
            icon: const Icon(Icons.refresh, size: 14),
            label:
                const Text('Reset Transform', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: Color(0xFF2A2A3E)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ),
      ],
    );
  }

  void _rotateLeft() {
    setState(() => _rotation -= 90);
    final timeMs = ref.read(editorProvider).currentTimeMs;
    ref.read(editorProvider.notifier).addKeyframe(
          widget.clipId,
          'rotation',
          timeMs,
          _rotation,
          'linear',
        );
  }

  void _rotateRight() {
    setState(() => _rotation += 90);
    final timeMs = ref.read(editorProvider).currentTimeMs;
    ref.read(editorProvider.notifier).addKeyframe(
          widget.clipId,
          'rotation',
          timeMs,
          _rotation,
          'linear',
        );
  }

  void _flipHorizontal() {
    setState(() => _scaleX *= -1);
    final timeMs = ref.read(editorProvider).currentTimeMs;
    ref.read(editorProvider.notifier).addKeyframe(
          widget.clipId,
          'scale_x',
          timeMs,
          _scaleX,
          'linear',
        );
  }

  void _flipVertical() {
    setState(() => _scaleY *= -1);
    final timeMs = ref.read(editorProvider).currentTimeMs;
    ref.read(editorProvider.notifier).addKeyframe(
          widget.clipId,
          'scale_y',
          timeMs,
          _scaleY,
          'linear',
        );
  }

  void _resetTransform() {
    setState(() {
      _rotation = 0.0;
      _scaleX = 1.0;
      _scaleY = 1.0;
    });
    final timeMs = ref.read(editorProvider).currentTimeMs;
    ref.read(editorProvider.notifier).addKeyframe(
          widget.clipId,
          'rotation',
          timeMs,
          0.0,
          'linear',
        );
    ref.read(editorProvider.notifier).addKeyframe(
          widget.clipId,
          'scale_x',
          timeMs,
          1.0,
          'linear',
        );
    ref.read(editorProvider.notifier).addKeyframe(
          widget.clipId,
          'scale_y',
          timeMs,
          1.0,
          'linear',
        );
  }
}

/// A small button used in the Crop & Transform section.
class _TransformButton extends StatelessWidget {
  const _TransformButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.rotation = 0,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textPrimary,
        side: const BorderSide(color: Color(0xFF2A2A3E)),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotatedBox(
            quarterTurns: (rotation / 90).round(),
            child: Icon(icon, size: 18, color: Colors.teal),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 9)),
        ],
      ),
    );
  }
}
