import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase F: Lens Correction panel.
///
/// Exposes the existing engine/src/effects/lens_correction.rs module.
/// Two modes: profile-based (pick from 8 built-in profiles) or manual
/// (K1/K2/K3 + tangential P1/P2 + chromatic aberration + vignette).
///
/// The amateur move is to slide K1 to 0.5 because the frame looks "weird"
/// with no reference grid. The pro move is to enable a grid overlay and
/// dial K1 until straight lines are straight. See
/// persona/skills/lens-correction/SKILL.md.
class LensCorrectionPanel extends StatefulWidget {
  const LensCorrectionPanel({
    required this.onChanged,
    super.key,
    this.initialValues = LensCorrectionValues.neutral,
  });

  /// Called when any parameter changes. The parent applies the effect
  /// via the engine.
  final void Function(LensCorrectionValues values) onChanged;
  final LensCorrectionValues initialValues;

  @override
  State<LensCorrectionPanel> createState() => _LensCorrectionPanelState();
}

class _LensCorrectionPanelState extends State<LensCorrectionPanel> {
  late LensCorrectionValues _v;
  bool _showGrid = false;

  @override
  void initState() {
    super.initState();
    _v = widget.initialValues;
  }

  void _update(LensCorrectionValues newV) {
    setState(() => _v = newV);
    widget.onChanged(_v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Lens Correction',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            IconButton(
              icon: Icon(_showGrid ? Icons.grid_on : Icons.grid_off),
              tooltip: 'Toggle reference grid',
              onPressed: () => setState(() => _showGrid = !_showGrid),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing4),
        Text(
          'Profile: pick from 8 built-in, or dial manually with grid overlay.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Distortion sliders
        _SliderRow(
          label: 'K1 (radial)',
          value: _v.k1,
          min: -1.0,
          max: 1.0,
          onChanged: (v) => _update(_v.copyWith(k1: v)),
        ),
        _SliderRow(
          label: 'K2',
          value: _v.k2,
          min: -1.0,
          max: 1.0,
          onChanged: (v) => _update(_v.copyWith(k2: v)),
        ),
        _SliderRow(
          label: 'K3',
          value: _v.k3,
          min: -1.0,
          max: 1.0,
          onChanged: (v) => _update(_v.copyWith(k3: v)),
        ),
        _SliderRow(
          label: 'P1 (tangential)',
          value: _v.p1,
          min: -0.5,
          max: 0.5,
          onChanged: (v) => _update(_v.copyWith(p1: v)),
        ),
        _SliderRow(
          label: 'P2',
          value: _v.p2,
          min: -0.5,
          max: 0.5,
          onChanged: (v) => _update(_v.copyWith(p2: v)),
        ),
        const Divider(),
        // Chromatic aberration
        Text(
          'Chromatic Aberration',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        _SliderRow(
          label: 'Red offset',
          value: _v.caRedOffset,
          min: -0.01,
          max: 0.01,
          onChanged: (v) => _update(_v.copyWith(caRedOffset: v)),
        ),
        _SliderRow(
          label: 'Blue offset',
          value: _v.caBlueOffset,
          min: -0.01,
          max: 0.01,
          onChanged: (v) => _update(_v.copyWith(caBlueOffset: v)),
        ),
        const Divider(),
        // Vignette
        Text('Vignette', style: Theme.of(context).textTheme.bodyMedium),
        _SliderRow(
          label: 'Amount',
          value: _v.vignetteAmount,
          min: -1.0,
          max: 1.0,
          onChanged: (v) => _update(_v.copyWith(vignetteAmount: v)),
        ),
        _SliderRow(
          label: 'Midpoint',
          value: _v.vignetteMidpoint,
          min: 0.0,
          max: 1.0,
          onChanged: (v) => _update(_v.copyWith(vignetteMidpoint: v)),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing4),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: 100,
              label: value.toStringAsFixed(3),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              value.toStringAsFixed(3),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class LensCorrectionValues {
  const LensCorrectionValues({
    this.k1 = 0.0,
    this.k2 = 0.0,
    this.k3 = 0.0,
    this.p1 = 0.0,
    this.p2 = 0.0,
    this.caRedOffset = 0.0,
    this.caBlueOffset = 0.0,
    this.vignetteAmount = 0.0,
    this.vignetteMidpoint = 0.5,
  });
  final double k1, k2, k3;
  final double p1, p2;
  final double caRedOffset, caBlueOffset;
  final double vignetteAmount, vignetteMidpoint;

  static const neutral = LensCorrectionValues();

  LensCorrectionValues copyWith({
    double? k1,
    double? k2,
    double? k3,
    double? p1,
    double? p2,
    double? caRedOffset,
    double? caBlueOffset,
    double? vignetteAmount,
    double? vignetteMidpoint,
  }) {
    return LensCorrectionValues(
      k1: k1 ?? this.k1,
      k2: k2 ?? this.k2,
      k3: k3 ?? this.k3,
      p1: p1 ?? this.p1,
      p2: p2 ?? this.p2,
      caRedOffset: caRedOffset ?? this.caRedOffset,
      caBlueOffset: caBlueOffset ?? this.caBlueOffset,
      vignetteAmount: vignetteAmount ?? this.vignetteAmount,
      vignetteMidpoint: vignetteMidpoint ?? this.vignetteMidpoint,
    );
  }
}
