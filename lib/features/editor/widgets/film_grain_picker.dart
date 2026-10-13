import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase F: Film Grain picker.
///
/// Exposes the existing engine/src/effects/grain.rs module's 17 stock
/// presets plus VHS and halation.
///
/// The amateur move is to crank grain to 100% and call it "cinematic."
/// The pro move is to apply grain at 15–30% to break up digital
/// cleanliness, with the right stock for the look. See
/// persona/skills/film-grain-recipe/SKILL.md.
class FilmGrainPicker extends StatefulWidget {
  final void Function(FilmGrainValues values) onChanged;
  final FilmGrainValues initialValues;

  const FilmGrainPicker({
    super.key,
    required this.onChanged,
    this.initialValues = FilmGrainValues.neutral,
  });

  @override
  State<FilmGrainPicker> createState() => _FilmGrainPickerState();
}

class _FilmGrainPickerState extends State<FilmGrainPicker> {
  late FilmGrainValues _v;

  @override
  void initState() {
    super.initState();
    _v = widget.initialValues;
  }

  void _update(FilmGrainValues newV) {
    setState(() => _v = newV);
    widget.onChanged(_v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Film Grain', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppTheme.spacing4),
        Text(
          'Pick the right stock. 15–30% intensity is enough. '
          'Halation on highlights for film emulation.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Stock picker
        DropdownButton<String>(
          value: _v.stockPreset,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'none', child: Text('None')),
            DropdownMenuItem<String>(
              enabled: false,
              child: Divider(height: 1),
            ),
            DropdownMenuItem(value: 'kodak_5219_500T', child: Text('Kodak Vision3 500T (warm)')),
            DropdownMenuItem(value: 'kodak_5213_200T', child: Text('Kodak Vision3 200T')),
            DropdownMenuItem(value: 'kodak_5207_250D', child: Text('Kodak Vision3 250D (daylight)')),
            DropdownMenuItem(value: 'fuji_eterna_500T', child: Text('Fuji Eterna 500T (cool)')),
            DropdownMenuItem(value: 'fuji_8543_500T', child: Text('Fuji Eterna Vivid 500T')),
            DropdownMenuItem(value: 'ilford_hp5', child: Text('Ilford HP5 (B&W)')),
            DropdownMenuItem(value: 'ilford_delta_3200', child: Text('Ilford Delta 3200 (B&W push)')),
            DropdownMenuItem<String>(
              enabled: false,
              child: Divider(height: 1),
            ),
            DropdownMenuItem(value: 'vhs', child: Text('VHS (tape noise)')),
            DropdownMenuItem(value: 'halation', child: Text('Halation (red glow on highlights)')),
          ],
          onChanged: (v) {
            if (v != null) _update(_v.copyWith(stockPreset: v));
          },
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Intensity slider
        Text('Intensity', style: Theme.of(context).textTheme.bodyMedium),
        Slider(
          value: _v.intensity,
          min: 0.0, max: 1.0,
          divisions: 100,
          label: '${(_v.intensity * 100).round()}%',
          onChanged: (v) => _update(_v.copyWith(intensity: v)),
        ),
        Text(
          '15–30% is the pro range. Don\'t crank to 100% — looks like bad TV reception.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Grain size
        Text('Grain Size', style: Theme.of(context).textTheme.bodyMedium),
        Slider(
          value: _v.grainSize,
          min: 0.5, max: 4.0,
          divisions: 35,
          label: _v.grainSize.toStringAsFixed(1),
          onChanged: (v) => _update(_v.copyWith(grainSize: v)),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Halation
        SwitchListTile(
          title: const Text('Halation'),
          subtitle: const Text('Red glow around bright highlights'),
          value: _v.halation,
          onChanged: (b) => _update(_v.copyWith(halation: b)),
        ),
        if (_v.halation) ...[
          Text('Halation intensity', style: Theme.of(context).textTheme.bodyMedium),
          Slider(
            value: _v.halationIntensity,
            min: 0.0, max: 1.0,
            divisions: 100,
            label: '${(_v.halationIntensity * 100).round()}%',
            onChanged: (v) => _update(_v.copyWith(halationIntensity: v)),
          ),
        ],
      ],
    );
  }
}

class FilmGrainValues {
  final String stockPreset;
  final double intensity;
  final double grainSize;
  final bool halation;
  final double halationIntensity;

  const FilmGrainValues({
    this.stockPreset = 'none',
    this.intensity = 0.2,
    this.grainSize = 1.0,
    this.halation = false,
    this.halationIntensity = 0.3,
  });

  static const neutral = FilmGrainValues();

  FilmGrainValues copyWith({
    String? stockPreset,
    double? intensity,
    double? grainSize,
    bool? halation,
    double? halationIntensity,
  }) {
    return FilmGrainValues(
      stockPreset: stockPreset ?? this.stockPreset,
      intensity: intensity ?? this.intensity,
      grainSize: grainSize ?? this.grainSize,
      halation: halation ?? this.halation,
      halationIntensity: halationIntensity ?? this.halationIntensity,
    );
  }
}
