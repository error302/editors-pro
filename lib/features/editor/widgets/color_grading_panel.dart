import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase E.16: Color grading panel with lift/gamma/gain wheels.
///
/// Professional color grading UI inspired by DaVinci Resolve:
/// - Three color wheels (Lift, Gamma, Gain) for shadows/midtones/highlights
/// - Each wheel adjusts hue (angle from center) and saturation (distance)
/// - Master slider for overall brightness per wheel
/// - Non-AI: pure CSS/canvas-based color math, no model inference
///
/// The wheel values map to a simple RGB offset/multiplier that's
/// applied as an effect via the existing `effects/color_space.rs`
/// infrastructure. Future enhancement: route through a proper LUT
/// pipeline when LUT support is added.
class ColorGradingPanel extends StatefulWidget {
  const ColorGradingPanel({
    required this.onChanged,
    super.key,
    this.initialValues = ColorGradeValues.neutral,
  });

  /// Called whenever any wheel value changes. The three values are
  /// RGB offsets in the range [-1.0, 1.0] for lift (additive),
  /// multipliers in [0.5, 2.0] for gamma (power), and multipliers
  /// in [0.0, 4.0] for gain (multiplicative).
  final void Function(ColorGradeValues values) onChanged;

  /// Initial values for the three wheels. Defaults to neutral
  /// (no color shift, no brightness change).
  final ColorGradeValues initialValues;

  @override
  State<ColorGradingPanel> createState() => _ColorGradingPanelState();
}

class _ColorGradingPanelState extends State<ColorGradingPanel> {
  late ColorGradeValues _values;

  @override
  void initState() {
    super.initState();
    _values = widget.initialValues;
  }

  void _update(ColorGradeValues newValues) {
    setState(() => _values = newValues);
    widget.onChanged(_values);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Color Grading',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppTheme.spacing4),
        Text(
          'Adjust shadows, midtones, and highlights independently.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        _ColorWheel(
          label: 'Lift',
          subtitle: 'Shadows',
          hue: _values.liftHue,
          saturation: _values.liftSaturation,
          master: _values.liftMaster,
          // Lift is an additive offset — the wheel color tints the
          // shadows. Hue 0 = red, 120 = green, 240 = blue.
          onHueChanged: (h) => _update(
            _values.copyWith(liftHue: h),
          ),
          onSaturationChanged: (s) => _update(
            _values.copyWith(liftSaturation: s),
          ),
          onMasterChanged: (m) => _update(
            _values.copyWith(liftMaster: m),
          ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        _ColorWheel(
          label: 'Gamma',
          subtitle: 'Midtones',
          hue: _values.gammaHue,
          saturation: _values.gammaSaturation,
          master: _values.gammaMaster,
          onHueChanged: (h) => _update(
            _values.copyWith(gammaHue: h),
          ),
          onSaturationChanged: (s) => _update(
            _values.copyWith(gammaSaturation: s),
          ),
          onMasterChanged: (m) => _update(
            _values.copyWith(gammaMaster: m),
          ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        _ColorWheel(
          label: 'Gain',
          subtitle: 'Highlights',
          hue: _values.gainHue,
          saturation: _values.gainSaturation,
          master: _values.gainMaster,
          onHueChanged: (h) => _update(
            _values.copyWith(gainHue: h),
          ),
          onSaturationChanged: (s) => _update(
            _values.copyWith(gainSaturation: s),
          ),
          onMasterChanged: (m) => _update(
            _values.copyWith(gainMaster: m),
          ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Reset button
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _update(ColorGradeValues.neutral),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reset'),
            ),
            const Spacer(),
            // Show a textual summary of the current values for debugging.
            Text(
              'L:${(_values.liftMaster * 100).round()}% '
              'G:${(_values.gammaMaster * 100).round()}% '
              'H:${(_values.gainMaster * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textDisabled,
                    fontFamily: 'monospace',
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A single color wheel with hue/saturation dial and master slider.
class _ColorWheel extends StatelessWidget {
  const _ColorWheel({
    required this.label,
    required this.subtitle,
    required this.hue,
    required this.saturation,
    required this.master,
    required this.onHueChanged,
    required this.onSaturationChanged,
    required this.onMasterChanged,
  });
  final String label;
  final String subtitle;
  final double hue; // 0-360 degrees
  final double saturation; // 0.0-1.0
  final double master; // -1.0 to 1.0 (0 = neutral)
  final ValueChanged<double> onHueChanged;
  final ValueChanged<double> onSaturationChanged;
  final ValueChanged<double> onMasterChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Color wheel dial
        SizedBox(
          width: 80,
          height: 80,
          child: GestureDetector(
            onPanUpdate: (details) {
              // Convert the drag delta into hue/saturation changes.
              // Hue rotates around the center; saturation is the
              // distance from center.
              final dx = details.localPosition.dx - 40;
              final dy = details.localPosition.dy - 40;
              final distance = math.sqrt(dx * dx + dy * dy);
              final newSat = (distance / 40).clamp(0.0, 1.0);
              final newHue = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
              onHueChanged(newHue);
              onSaturationChanged(newSat);
            },
            child: CustomPaint(
              painter: _ColorWheelPainter(
                hue: hue,
                saturation: saturation,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppTheme.spacing16),
        // Label + master slider
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Master',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textDisabled,
                ),
              ),
              Slider(
                value: master,
                min: -1.0,
                max: 1.0,
                divisions: 200,
                label: '${(master * 100).round()}%',
                onChanged: onMasterChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Paints a circular color wheel with a draggable indicator at the
/// current hue/saturation position.
class _ColorWheelPainter extends CustomPainter {
  _ColorWheelPainter({required this.hue, required this.saturation});
  final double hue;
  final double saturation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw the hue ring as 360 segments.
    for (var i = 0; i < 360; i++) {
      final paint = Paint()
        ..color = HSLColor.fromAHSL(1.0, i.toDouble(), 1.0, 0.5).toColor()
        ..style = PaintingStyle.fill;
      final startAngle = (i - 90) * math.pi / 180;
      const sweepAngle = math.pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
    }

    // Draw a darker center for the saturation gradient.
    canvas.drawCircle(
      center,
      radius * 0.7,
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );

    // Draw the position indicator (small circle at hue/saturation).
    final angle = (hue - 90) * math.pi / 180;
    final distance = saturation * radius;
    final indicatorPos = Offset(
      center.dx + distance * math.cos(angle),
      center.dy + distance * math.sin(angle),
    );
    canvas.drawCircle(
      indicatorPos,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      indicatorPos,
      6,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) {
    return oldDelegate.hue != hue || oldDelegate.saturation != saturation;
  }
}

/// Phase E.16: color grading values for the three wheels.
///
/// Each wheel has:
/// - `hue` (0-360 degrees): the color tint direction.
/// - `saturation` (0.0-1.0): how strong the tint is (0 = no tint).
/// - `master` (-1.0 to 1.0): overall brightness adjustment for this
///   tonal range (0 = neutral, +1 = +1 stop, -1 = -1 stop).
@immutable
class ColorGradeValues {
  const ColorGradeValues({
    this.liftHue = 0,
    this.liftSaturation = 0,
    this.liftMaster = 0,
    this.gammaHue = 0,
    this.gammaSaturation = 0,
    this.gammaMaster = 0,
    this.gainHue = 0,
    this.gainSaturation = 0,
    this.gainMaster = 0,
  });
  final double liftHue;
  final double liftSaturation;
  final double liftMaster;
  final double gammaHue;
  final double gammaSaturation;
  final double gammaMaster;
  final double gainHue;
  final double gainSaturation;
  final double gainMaster;

  static const neutral = ColorGradeValues();

  ColorGradeValues copyWith({
    double? liftHue,
    double? liftSaturation,
    double? liftMaster,
    double? gammaHue,
    double? gammaSaturation,
    double? gammaMaster,
    double? gainHue,
    double? gainSaturation,
    double? gainMaster,
  }) {
    return ColorGradeValues(
      liftHue: liftHue ?? this.liftHue,
      liftSaturation: liftSaturation ?? this.liftSaturation,
      liftMaster: liftMaster ?? this.liftMaster,
      gammaHue: gammaHue ?? this.gammaHue,
      gammaSaturation: gammaSaturation ?? this.gammaSaturation,
      gammaMaster: gammaMaster ?? this.gammaMaster,
      gainHue: gainHue ?? this.gainHue,
      gainSaturation: gainSaturation ?? this.gainSaturation,
      gainMaster: gainMaster ?? this.gainMaster,
    );
  }

  /// Convert the wheel values to an RGB tint color for each tonal range.
  /// Useful for previewing the effect or applying it as a shader uniform.
  Map<String, List<double>> toRgbOffsets() {
    return {
      'lift': _hslToRgbOffset(liftHue, liftSaturation, liftMaster),
      'gamma': _hslToRgbOffset(gammaHue, gammaSaturation, gammaMaster),
      'gain': _hslToRgbOffset(gainHue, gainSaturation, gainMaster),
    };
  }

  static List<double> _hslToRgbOffset(
    double hue,
    double saturation,
    double master,
  ) {
    final color = HSLColor.fromAHSL(1.0, hue, saturation, 0.5).toColor();
    return [
      (color.r - 0.5) * saturation + master,
      (color.g - 0.5) * saturation + master,
      (color.b - 0.5) * saturation + master,
    ];
  }
}
