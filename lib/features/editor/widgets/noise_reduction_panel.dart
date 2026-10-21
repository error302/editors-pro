import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase F: Noise Reduction panel.
///
/// Exposes the existing engine/src/effects/noise_reduction.rs module's
/// 4 methods: Bilateral, Wiener, NLM, Temporal.
///
/// The amateur move is to crank NR to 100% with NLM and get a wax-figure
/// look. The pro move is to NR just enough (30–50%), then add a tiny bit
/// of grain back to break up the plasticity. See
/// persona/skills/noise-reduction/SKILL.md.
class NoiseReductionPanel extends StatefulWidget {
  const NoiseReductionPanel({
    required this.onChanged,
    super.key,
    this.initialValues = NoiseReductionValues.neutral,
  });
  final void Function(NoiseReductionValues values) onChanged;
  final NoiseReductionValues initialValues;

  @override
  State<NoiseReductionPanel> createState() => _NoiseReductionPanelState();
}

class _NoiseReductionPanelState extends State<NoiseReductionPanel> {
  late NoiseReductionValues _v;

  @override
  void initState() {
    super.initState();
    _v = widget.initialValues;
  }

  void _update(NoiseReductionValues newV) {
    setState(() => _v = newV);
    widget.onChanged(_v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Noise Reduction',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppTheme.spacing4),
        Text(
          'Method by shot type. 30–50% is enough. Add a tiny bit of grain '
          'back to break up the plasticity.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Method picker
        SegmentedButton<NoiseReductionMethod>(
          segments: const [
            ButtonSegment(
              value: NoiseReductionMethod.bilateral,
              label: Text('Bilateral'),
              tooltip: 'Edge-preserving, fast. Good for motion shots.',
            ),
            ButtonSegment(
              value: NoiseReductionMethod.wiener,
              label: Text('Wiener'),
              tooltip: 'Frequency-domain. Good for fine noise.',
            ),
            ButtonSegment(
              value: NoiseReductionMethod.nlm,
              label: Text('NLM'),
              tooltip: 'Non-local means. Best quality, slow.',
            ),
            ButtonSegment(
              value: NoiseReductionMethod.temporal,
              label: Text('Temporal'),
              tooltip: 'Frame-to-frame coherence. Excellent for static shots.',
            ),
          ],
          selected: {_v.method},
          onSelectionChanged: (s) => _update(_v.copyWith(method: s.first)),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Strength slider
        Text('Strength', style: Theme.of(context).textTheme.bodyMedium),
        Slider(
          value: _v.strength,
          min: 0.0,
          max: 1.0,
          divisions: 100,
          label: '${(_v.strength * 100).round()}%',
          onChanged: (v) => _update(_v.copyWith(strength: v)),
        ),
        Text(
          '30–50% is the pro range. 100% = wax-figure skin. Don\'t.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Luma/chroma separation
        SwitchListTile(
          title: const Text('Luma/chroma separation'),
          subtitle: const Text(
            'NR on luma and chroma independently (better detail retention)',
          ),
          value: _v.lumaChromaSeparation,
          onChanged: (b) => _update(_v.copyWith(lumaChromaSeparation: b)),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Add grain back
        SwitchListTile(
          title: const Text('Add grain back (anti-plasticity)'),
          subtitle: const Text('Subtle film grain to break up NR plasticity'),
          value: _v.addGrainBack,
          onChanged: (b) => _update(_v.copyWith(addGrainBack: b)),
        ),
        if (_v.addGrainBack) ...[
          Text(
            'Grain intensity',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Slider(
            value: _v.grainIntensity,
            min: 0.0,
            max: 0.3,
            divisions: 30,
            label: '${(_v.grainIntensity * 100).round()}%',
            onChanged: (v) => _update(_v.copyWith(grainIntensity: v)),
          ),
        ],
      ],
    );
  }
}

enum NoiseReductionMethod { bilateral, wiener, nlm, temporal }

class NoiseReductionValues {
  const NoiseReductionValues({
    this.method = NoiseReductionMethod.bilateral,
    this.strength = 0.3,
    this.lumaChromaSeparation = true,
    this.addGrainBack = true,
    this.grainIntensity = 0.05,
  });
  final NoiseReductionMethod method;
  final double strength;
  final bool lumaChromaSeparation;
  final bool addGrainBack;
  final double grainIntensity;

  static const neutral = NoiseReductionValues();

  NoiseReductionValues copyWith({
    NoiseReductionMethod? method,
    double? strength,
    bool? lumaChromaSeparation,
    bool? addGrainBack,
    double? grainIntensity,
  }) {
    return NoiseReductionValues(
      method: method ?? this.method,
      strength: strength ?? this.strength,
      lumaChromaSeparation: lumaChromaSeparation ?? this.lumaChromaSeparation,
      addGrainBack: addGrainBack ?? this.addGrainBack,
      grainIntensity: grainIntensity ?? this.grainIntensity,
    );
  }
}
