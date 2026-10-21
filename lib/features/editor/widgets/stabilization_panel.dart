import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase F: Video Stabilization panel.
///
/// Exposes the new engine/src/effects/stabilization.rs module's 2D
/// deshake. Smoothing 30–60% and crop 8–12% are the pro defaults.
///
/// The amateur move is to crank smoothing to 100% and get jelly artifacts.
/// The pro move is to smooth just enough, crop to hide edges, and upgrade
/// to a 3D camera solve if motion is parallax-heavy. See
/// persona/skills/video-stabilization/SKILL.md.
class StabilizationPanel extends StatefulWidget {
  const StabilizationPanel({
    required this.onChanged,
    super.key,
    this.initialValues = StabilizationValues.defaults,
  });
  final void Function(StabilizationValues values) onChanged;
  final StabilizationValues initialValues;

  @override
  State<StabilizationPanel> createState() => _StabilizationPanelState();
}

class _StabilizationPanelState extends State<StabilizationPanel> {
  late StabilizationValues _v;

  @override
  void initState() {
    super.initState();
    _v = widget.initialValues;
  }

  void _update(StabilizationValues newV) {
    setState(() => _v = newV);
    widget.onChanged(_v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stabilization',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppTheme.spacing4),
        Text(
          '2D deshake via block matching. Smooth 30–60%, crop 8–12% to hide '
          'edge artifacts. Don\'t crank smoothing — jelly artifacts.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        SwitchListTile(
          title: const Text('Enable stabilization'),
          value: _v.enabled,
          onChanged: (b) => _update(_v.copyWith(enabled: b)),
        ),
        if (_v.enabled) ...[
          const SizedBox(height: AppTheme.spacing8),
          // Smoothing
          Text('Smoothing', style: Theme.of(context).textTheme.bodyMedium),
          Slider(
            value: _v.smoothing,
            min: 0.0,
            max: 1.0,
            divisions: 100,
            label: '${(_v.smoothing * 100).round()}%',
            onChanged: (v) => _update(_v.copyWith(smoothing: v)),
          ),
          Text(
            '30–60% is the pro range. 100% = jelly.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          const SizedBox(height: AppTheme.spacing16),
          // Crop
          Text('Crop', style: Theme.of(context).textTheme.bodyMedium),
          Slider(
            value: _v.crop,
            min: 0.0,
            max: 0.3,
            divisions: 60,
            label: '${(_v.crop * 100).round()}%',
            onChanged: (v) => _update(_v.copyWith(crop: v)),
          ),
          Text(
            '8–12% is the pro range. Hides edge artifacts from translation.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          const SizedBox(height: AppTheme.spacing16),
          // Motion mode
          Text('Motion mode', style: Theme.of(context).textTheme.bodyMedium),
          SegmentedButton<StabilizationMotionMode>(
            segments: const [
              ButtonSegment(
                value: StabilizationMotionMode.smooth,
                label: Text('Smooth'),
                tooltip: 'Keep the camera move, just smooth it out',
              ),
              ButtonSegment(
                value: StabilizationMotionMode.locked,
                label: Text('Locked'),
                tooltip:
                    'Lock the camera (no motion). Use for tripod emulation.',
              ),
            ],
            selected: {_v.motionMode},
            onSelectionChanged: (s) =>
                _update(_v.copyWith(motionMode: s.first)),
          ),
          const SizedBox(height: AppTheme.spacing16),
          // 3D upgrade notice
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                const SizedBox(width: AppTheme.spacing8),
                Expanded(
                  child: Text(
                    'If motion is parallax-heavy (foreground/background moving '
                    'differently), 2D will produce jelly artifacts. Upgrade '
                    'to a 3D camera solve — marked as `video:` debt.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

enum StabilizationMotionMode { smooth, locked }

class StabilizationValues {
  const StabilizationValues({
    this.enabled = false,
    this.smoothing = 0.5,
    this.crop = 0.1,
    this.motionMode = StabilizationMotionMode.smooth,
  });
  final bool enabled;
  final double smoothing;
  final double crop;
  final StabilizationMotionMode motionMode;

  static const defaults = StabilizationValues();

  StabilizationValues copyWith({
    bool? enabled,
    double? smoothing,
    double? crop,
    StabilizationMotionMode? motionMode,
  }) {
    return StabilizationValues(
      enabled: enabled ?? this.enabled,
      smoothing: smoothing ?? this.smoothing,
      crop: crop ?? this.crop,
      motionMode: motionMode ?? this.motionMode,
    );
  }
}
