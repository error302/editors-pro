import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/editor_provider.dart';

/// Speed ramp preset data model.
///
/// Each preset defines a series of speed segments that describe how
/// playback speed changes across the clip. The [segments] list contains
/// tuples of (startSpeed, endSpeed, easingName) which are evenly divided
/// across the clip duration when applied.
class _RampPreset {
  final String name;
  final String description;
  final IconData icon;
  final List<(double, double, String)> segments;
  final Color accentColor;

  const _RampPreset({
    required this.name,
    required this.description,
    required this.icon,
    required this.segments,
    required this.accentColor,
  });
}

/// Speed ramp presets panel — displays 8 professional speed-ramp presets
/// plus a custom speed entry section.
///
/// Each preset shows:
/// - A name and description
/// - A small curve preview rendered via [CustomPaint]
/// - Tap to apply → calls `setClipSpeedCurve(clipId, segments)`
/// - Visual feedback via [SnackBar]
///
/// The custom entry section allows manual specification of start speed,
/// end speed, easing type, and what portion of the clip the ramp occupies.
class SpeedRampPresets extends ConsumerStatefulWidget {
  final String clipId;
  final int clipDurationMs;

  const SpeedRampPresets({
    super.key,
    required this.clipId,
    required this.clipDurationMs,
  });

  @override
  ConsumerState<SpeedRampPresets> createState() => _SpeedRampPresetsState();
}

class _SpeedRampPresetsState extends ConsumerState<SpeedRampPresets> {
  /// The 8 professional speed-ramp presets.
  static const List<_RampPreset> _presets = [
    _RampPreset(
      name: 'Smooth Slow-Mo',
      description: 'Ramp down to 0.25x and back to 1.0x',
      icon: Icons.motion_photos_on_outlined,
      segments: [
        (1.0, 0.25, 'ease_out'),
        (0.25, 1.0, 'ease_in'),
      ],
      accentColor: AppTheme.secondary,
    ),
    _RampPreset(
      name: 'Speed Ramp Up',
      description: 'Gradually increase from 1.0x to 4.0x',
      icon: Icons.trending_up,
      segments: [
        (1.0, 4.0, 'ease_in'),
      ],
      accentColor: AppTheme.primary,
    ),
    _RampPreset(
      name: 'Speed Ramp Down',
      description: 'Gradually decrease from 4.0x to 1.0x',
      icon: Icons.trending_down,
      segments: [
        (4.0, 1.0, 'ease_out'),
      ],
      accentColor: AppTheme.warning,
    ),
    _RampPreset(
      name: 'Reverse Ramp',
      description: '1.0x → -1.0x (reverse) → 1.0x',
      icon: Icons.replay_outlined,
      segments: [
        (1.0, -1.0, 'ease_in_out'),
        (-1.0, 1.0, 'ease_in_out'),
      ],
      accentColor: AppTheme.accent,
    ),
    _RampPreset(
      name: 'Bounce',
      description: '1.0x → 0.25x → 2.0x → 1.0x',
      icon: Icons.speed,
      segments: [
        (1.0, 0.25, 'ease_out'),
        (0.25, 2.0, 'ease_in'),
        (2.0, 1.0, 'ease_out'),
      ],
      accentColor: Color(0xFF55EFC4),
    ),
    _RampPreset(
      name: 'Flash',
      description: 'Instant jump to 8x for a brief moment',
      icon: Icons.flash_on_outlined,
      segments: [
        (1.0, 8.0, 'linear'),
        (8.0, 1.0, 'linear'),
      ],
      accentColor: Color(0xFFFFEAA7),
    ),
    _RampPreset(
      name: 'Smooth Cutoff',
      description: 'Smooth deceleration to a full stop',
      icon: Icons.stop_circle_outlined,
      segments: [
        (1.0, 0.0, 'ease_in_out'),
      ],
      accentColor: AppTheme.error,
    ),
    _RampPreset(
      name: 'Elastic',
      description: 'Overshoot with spring-back effect',
      icon: Icons.waves_outlined,
      segments: [
        (1.0, 2.5, 'ease_out'),
        (2.5, 0.5, 'ease_in_out'),
        (0.5, 1.2, 'ease_out'),
        (1.2, 1.0, 'ease_in'),
      ],
      accentColor: Color(0xFFA29BFE),
    ),
  ];

  // ─── Custom speed entry state ────────────────────────────────
  double _customStartSpeed = 1.0;
  double _customEndSpeed = 1.0;
  String _customEasing = 'ease_in_out';
  double _rampPortion = 1.0; // 0.0 to 1.0 (what % of clip)
  final _startSpeedController = TextEditingController(text: '1.0');
  final _endSpeedController = TextEditingController(text: '1.0');

  static const List<String> _easingTypes = [
    'linear',
    'ease_in',
    'ease_out',
    'ease_in_out',
    'cubic_bezier',
  ];

  @override
  void dispose() {
    _startSpeedController.dispose();
    _endSpeedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.speed, color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Speed Ramp Presets',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${widget.clipDurationMs}ms',
                style: const TextStyle(
                  color: AppTheme.textDisabled,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Preset grid (2 columns)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.2,
            children: _presets.map((preset) {
              return _PresetCard(
                preset: preset,
                onTap: () => _applyPreset(preset),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Divider
          Container(
            height: 1,
            color: AppTheme.border,
          ),
          const SizedBox(height: 12),

          // Custom speed entry
          _buildCustomSpeedSection(),
        ],
      ),
    );
  }

  /// Build the custom speed entry section with start/end speed inputs,
  /// easing selector, and duration slider.
  Widget _buildCustomSpeedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            const Icon(Icons.tune, color: AppTheme.primaryLight, size: 16),
            const SizedBox(width: 6),
            const Text(
              'Custom Speed Curve',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Speed entry row
        Row(
          children: [
            // Start speed
            Expanded(
              child: _SpeedInputField(
                label: 'Start Speed',
                controller: _startSpeedController,
                onChanged: (value) {
                  final speed = double.tryParse(value) ?? 1.0;
                  setState(() => _customStartSpeed = speed.clamp(-8.0, 8.0));
                },
              ),
            ),
            const SizedBox(width: 8),

            // Arrow
            const Icon(Icons.arrow_forward, color: AppTheme.textDisabled, size: 18),
            const SizedBox(width: 8),

            // End speed
            Expanded(
              child: _SpeedInputField(
                label: 'End Speed',
                controller: _endSpeedController,
                onChanged: (value) {
                  final speed = double.tryParse(value) ?? 1.0;
                  setState(() => _customEndSpeed = speed.clamp(-8.0, 8.0));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Easing selector
        Row(
          children: [
            const Text(
              'Easing:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _customEasing,
                    isDense: true,
                    isExpanded: true,
                    dropdownColor: AppTheme.surfaceVariant,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                    ),
                    items: _easingTypes.map((easing) {
                      return DropdownMenuItem(
                        value: easing,
                        child: Text(
                          easing.replaceAll('_', ' ').toUpperCase(),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _customEasing = value);
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Ramp portion slider
        Row(
          children: [
            const Text(
              'Ramp Portion:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: _rampPortion,
                min: 0.05,
                max: 1.0,
                divisions: 95,
                activeColor: AppTheme.primary,
                label: '${(_rampPortion * 100).round()}%',
                onChanged: (value) {
                  setState(() => _rampPortion = value);
                },
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${(_rampPortion * 100).round()}%',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Curve preview for custom entry
        SizedBox(
          height: 50,
          child: CustomPaint(
            painter: _SpeedCurvePreviewPainter(
              segments: [
                (_customStartSpeed, _customEndSpeed, _customEasing),
              ],
              accentColor: AppTheme.primaryLight,
            ),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 8),

        // Apply custom button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _applyCustomSpeed,
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Apply Custom Curve'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Apply a named preset to the clip.
  void _applyPreset(_RampPreset preset) {
    final segCount = preset.segments.length;
    final totalRampMs = (widget.clipDurationMs * _rampPortion).round();
    final rampStartMs = (widget.clipDurationMs - totalRampMs) ~/ 2;
    final segDuration = totalRampMs ~/ segCount;

    final segments = <Map<String, dynamic>>[];

    for (int i = 0; i < segCount; i++) {
      final (startSpeed, endSpeed, easing) = preset.segments[i];
      segments.add({
        'start_ms': rampStartMs + i * segDuration,
        'end_ms': i == segCount - 1
            ? rampStartMs + totalRampMs
            : rampStartMs + (i + 1) * segDuration,
        'start_speed': startSpeed,
        'end_speed': endSpeed,
        'easing_name': easing,
      });
    }

    ref.read(editorProvider.notifier).setClipSpeedCurve(widget.clipId, segments);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied "${preset.name}" speed ramp'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Apply the custom speed curve to the clip.
  void _applyCustomSpeed() {
    final totalRampMs = (widget.clipDurationMs * _rampPortion).round();
    final rampStartMs = (widget.clipDurationMs - totalRampMs) ~/ 2;

    final segments = <Map<String, dynamic>>[
      {
        'start_ms': rampStartMs,
        'end_ms': rampStartMs + totalRampMs,
        'start_speed': _customStartSpeed,
        'end_speed': _customEndSpeed,
        'easing_name': _customEasing,
      },
    ];

    ref.read(editorProvider.notifier).setClipSpeedCurve(widget.clipId, segments);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Applied custom speed curve'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Preset Card widget
// ═══════════════════════════════════════════════════════════════════════

/// A single preset card showing a mini curve preview, name, and description.
class _PresetCard extends StatelessWidget {
  final _RampPreset preset;
  final VoidCallback onTap;

  const _PresetCard({
    required this.preset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceVariant,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: AppTheme.border, width: 0.5),
          ),
          child: Row(
            children: [
              // Mini curve preview
              SizedBox(
                width: 48,
                height: 40,
                child: CustomPaint(
                  painter: _SpeedCurvePreviewPainter(
                    segments: preset.segments,
                    accentColor: preset.accentColor,
                  ),
                  size: Size.infinite,
                ),
              ),
              const SizedBox(width: 8),

              // Name + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      preset.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.description,
                      style: const TextStyle(
                        color: AppTheme.textDisabled,
                        fontSize: 9,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Speed Curve Preview Painter
// ═══════════════════════════════════════════════════════════════════════

/// A compact painter that renders a speed curve as a line graph.
///
/// Given a list of (startSpeed, endSpeed, easing) tuples, this painter
/// divides the canvas width evenly among the segments and draws a smooth
/// curve from start to end speed for each.
class _SpeedCurvePreviewPainter extends CustomPainter {
  final List<(double, double, String)> segments;
  final Color accentColor;

  _SpeedCurvePreviewPainter({
    required this.segments,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty || size.isEmpty) return;

    // Draw subtle background grid
    final gridPaint = Paint()
      ..color = AppTheme.border.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Horizontal 1x reference line
    final oneXy = _speedToY(1.0, size.height);
    canvas.drawLine(
      Offset(0, oneXy),
      Offset(size.width, oneXy),
      gridPaint,
    );

    // Draw 0x baseline
    final zeroY = _speedToY(0.0, size.height);
    final baselinePaint = Paint()
      ..color = AppTheme.border.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      baselinePaint,
    );

    // Build the curve path
    final curvePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = accentColor.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();
    final stepsPerSegment = 20;
    final segWidth = size.width / segments.length;

    bool firstPoint = true;

    for (int s = 0; s < segments.length; s++) {
      final (startSpeed, endSpeed, easing) = segments[s];
      final segStartX = s * segWidth;

      for (int i = 0; i <= stepsPerSegment; i++) {
        final t = i / stepsPerSegment;
        final easedT = _applyEasing(t, easing);
        final speed = startSpeed + (endSpeed - startSpeed) * easedT;
        final x = segStartX + t * segWidth;
        final y = _speedToY(speed, size.height);

        if (firstPoint) {
          path.moveTo(x, y);
          fillPath.moveTo(x, size.height);
          fillPath.lineTo(x, y);
          firstPoint = false;
        } else {
          path.lineTo(x, y);
          fillPath.lineTo(x, y);
        }
      }
    }

    // Complete fill path
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, curvePaint);

    // Draw start and end dots
    if (segments.isNotEmpty) {
      final (firstStart, _, _) = segments.first;
      final (_, lastEnd, _) = segments.last;

      _drawDot(canvas, Offset(0, _speedToY(firstStart, size.height)), accentColor);
      _drawDot(
        canvas,
        Offset(size.width, _speedToY(lastEnd, size.height)),
        accentColor,
      );
    }
  }

  /// Convert a speed value to a Y coordinate.
  /// Maps speed range [-2, 8] to [height, 0].
  double _speedToY(double speed, double height) {
    const minSpeed = -2.0;
    const maxSpeed = 8.0;
    final normalized = (speed - minSpeed) / (maxSpeed - minSpeed);
    return height - normalized.clamp(0.0, 1.0) * height;
  }

  /// Draw a small dot at the given position.
  void _drawDot(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(
      center,
      3.0,
      Paint()..color = color,
    );
    canvas.drawCircle(
      center,
      3.0,
      Paint()
        ..color = AppTheme.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  /// Apply an easing function to the parameter [t] (0.0 to 1.0).
  double _applyEasing(double t, String easingName) {
    switch (easingName) {
      case 'ease_in':
        return t * t;
      case 'ease_out':
        return 1 - (1 - t) * (1 - t);
      case 'ease_in_out':
        return t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;
      case 'cubic_bezier':
        return t * t * (3 - 2 * t);
      case 'linear':
      default:
        return t;
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedCurvePreviewPainter oldDelegate) =>
      segments != oldDelegate.segments || accentColor != oldDelegate.accentColor;
}

// ═══════════════════════════════════════════════════════════════════════
// Speed Input Field
// ═══════════════════════════════════════════════════════════════════════

/// A compact text input field for entering speed values (supports negative).
class _SpeedInputField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SpeedInputField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textDisabled,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 32,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                borderSide: const BorderSide(color: AppTheme.primary, width: 1),
              ),
              suffixText: 'x',
              suffixStyle: const TextStyle(
                color: AppTheme.textDisabled,
                fontSize: 11,
              ),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}
