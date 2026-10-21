/// Chroma Key controls widget for the EDITORS-PRO editor.
///
/// Provides UI for configuring the chroma key (green/blue screen) effect:
/// - Color picker with green/blue preset buttons + custom color
/// - Tolerance sliders (hue, saturation)
/// - Edge softness slider
/// - Spill suppression slider
/// - Preview toggle (show/hide removed areas with red overlay)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/editor_provider.dart';

/// Chroma key controls panel — displayed in the inspector when
/// a Chroma Key effect is selected on the active clip.
class ChromaKeyControls extends ConsumerStatefulWidget {
  const ChromaKeyControls({
    required this.effectId,
    required this.clipId,
    super.key,
  });

  /// The effect ID for this chroma key instance
  final String effectId;

  /// The clip ID that owns this effect
  final String clipId;

  @override
  ConsumerState<ChromaKeyControls> createState() => _ChromaKeyControlsState();
}

class _ChromaKeyControlsState extends ConsumerState<ChromaKeyControls> {
  double _targetHue = 120.0;
  double _hueTolerance = 30.0;
  double _saturationTolerance = 0.4;
  double _softness = 0.15;
  double _spillSuppression = 0.5;
  bool _showMatteOverlay = false;

  Future<void> _updateParameter(String name, double value) async {
    final notifier = ref.read(editorProvider.notifier);
    await notifier.setEffectParameter(
      widget.effectId,
      name,
      value,
    );
  }

  void _applyPreset(ChromaKeyPreset preset) {
    setState(() {
      switch (preset) {
        case ChromaKeyPreset.green:
          _targetHue = 120.0;
          _hueTolerance = 30.0;
          _saturationTolerance = 0.4;
        case ChromaKeyPreset.blue:
          _targetHue = 240.0;
          _hueTolerance = 30.0;
          _saturationTolerance = 0.4;
      }
    });

    _updateParameter('target_hue', _targetHue);
    _updateParameter('hue_tolerance', _hueTolerance);
    _updateParameter('saturation_tolerance', _saturationTolerance);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Color Presets ──────────────────────────────────────
        Text(
          'COLOR PRESET',
          style: context.textTheme.labelSmall?.copyWith(
            color: AppTheme.textSecondary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _PresetButton(
              label: 'Green',
              color: Colors.green,
              isSelected: (_targetHue - 120.0).abs() < 5.0,
              onTap: () => _applyPreset(ChromaKeyPreset.green),
            ),
            const SizedBox(width: 8),
            _PresetButton(
              label: 'Blue',
              color: Colors.blue,
              isSelected: (_targetHue - 240.0).abs() < 5.0,
              onTap: () => _applyPreset(ChromaKeyPreset.blue),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CustomColorButton(
                currentHue: _targetHue,
                onHueSelected: (hue) {
                  setState(() => _targetHue = hue);
                  _updateParameter('target_hue', hue);
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ─── Target Hue ────────────────────────────────────────
        _ParameterSlider(
          label: 'Target Hue',
          value: _targetHue,
          min: 0,
          max: 360,
          divisions: 360,
          unit: '°',
          onChanged: (v) {
            setState(() => _targetHue = v);
            _updateParameter('target_hue', v);
          },
        ),

        const SizedBox(height: 12),

        // ─── Hue Tolerance ─────────────────────────────────────
        _ParameterSlider(
          label: 'Hue Tolerance',
          value: _hueTolerance,
          min: 0,
          max: 180,
          divisions: 180,
          unit: '°',
          onChanged: (v) {
            setState(() => _hueTolerance = v);
            _updateParameter('hue_tolerance', v);
          },
        ),

        const SizedBox(height: 12),

        // ─── Saturation Tolerance ──────────────────────────────
        _ParameterSlider(
          label: 'Saturation Tolerance',
          value: _saturationTolerance,
          min: 0,
          max: 1.0,
          divisions: 100,
          unit: '',
          displayValue: (_saturationTolerance * 100).round().toString(),
          onChanged: (v) {
            setState(() => _saturationTolerance = v);
            _updateParameter('saturation_tolerance', v);
          },
        ),

        const SizedBox(height: 12),

        // ─── Edge Softness ─────────────────────────────────────
        _ParameterSlider(
          label: 'Edge Softness',
          value: _softness,
          min: 0,
          max: 1.0,
          divisions: 100,
          unit: '',
          displayValue: (_softness * 100).round().toString(),
          onChanged: (v) {
            setState(() => _softness = v);
            _updateParameter('softness', v);
          },
        ),

        const SizedBox(height: 12),

        // ─── Spill Suppression ─────────────────────────────────
        _ParameterSlider(
          label: 'Spill Suppression',
          value: _spillSuppression,
          min: 0,
          max: 1.0,
          divisions: 100,
          unit: '',
          displayValue: (_spillSuppression * 100).round().toString(),
          onChanged: (v) {
            setState(() => _spillSuppression = v);
            _updateParameter('spill_suppression', v);
          },
        ),

        const SizedBox(height: 16),

        // ─── Preview Toggle ────────────────────────────────────
        SwitchListTile(
          title: Text(
            'Show Matte Overlay',
            style: context.textTheme.bodyMedium,
          ),
          subtitle: Text(
            'Highlight removed areas in red',
            style: context.textTheme.bodySmall,
          ),
          value: _showMatteOverlay,
          onChanged: (v) {
            setState(() => _showMatteOverlay = v);
            // In production, this would toggle a visual overlay on the
            // preview viewport showing which areas are keyed out.
          },
          activeThumbColor: AppTheme.primary,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ],
    );
  }
}

/// Chroma key preset types
enum ChromaKeyPreset { green, blue }

/// Preset button for green/blue screen selection
class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? color
                : AppTheme.textDisabled.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: isSelected ? color : AppTheme.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom color button that opens a hue picker dialog
class _CustomColorButton extends StatelessWidget {
  const _CustomColorButton({
    required this.currentHue,
    required this.onHueSelected,
  });
  final double currentHue;
  final ValueChanged<double> onHueSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showHuePicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppTheme.textDisabled.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.colorize, size: 16, color: _hueToColor(currentHue)),
            const SizedBox(width: 6),
            Text(
              'Custom',
              style: context.textTheme.bodySmall?.copyWith(
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _hueToColor(double hue) {
    return HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
  }

  void _showHuePicker(BuildContext context) {
    var selectedHue = currentHue;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Select Target Color'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: selectedHue,
                min: 0,
                max: 360,
                divisions: 360,
                activeColor: _hueToColor(selectedHue),
                onChanged: (v) {
                  setDialogState(() => selectedHue = v);
                },
              ),
              const SizedBox(height: 12),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _hueToColor(selectedHue),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white30),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                onHueSelected(selectedHue);
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Parameter slider widget for chroma key effect parameters
class _ParameterSlider extends StatelessWidget {
  const _ParameterSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.onChanged,
    this.displayValue,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final String? displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final display = displayValue ?? '$value$unit';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            Text(
              display,
              style: context.textTheme.bodySmall?.copyWith(
                color: AppTheme.primaryLight,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppTheme.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
