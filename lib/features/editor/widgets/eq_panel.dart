import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase F.2: Audio EQ panel.
///
/// 8-band parametric EQ for dialogue/music cleaning. Each band has
/// frequency, gain, and Q. Plus a high-pass filter for rumble removal
/// and a low-pass filter for hiss reduction.
///
/// The amateur move is to crank the highs for "clarity" and the lows
/// for "warmth" without listening on reference monitors. The pro move
/// is to cut before boosting, sweep the frequency to find the problem,
/// and use narrow Q for surgical fixes. See
/// persona/skills/dialogue-cleanup/SKILL.md.
class EqPanel extends StatefulWidget {
  final void Function(EqSettings settings) onChanged;
  final EqSettings initialSettings;

  EqPanel({
    super.key,
    required this.onChanged,
    EqSettings? initialSettings,
  }) : initialSettings = initialSettings ?? EqSettings.flat;

  @override
  State<EqPanel> createState() => _EqPanelState();
}

class _EqPanelState extends State<EqPanel> {
  late EqSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  void _update(EqSettings newSettings) {
    setState(() => _settings = newSettings);
    widget.onChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Equalizer',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            // Bypass switch
            Switch(
              value: _settings.enabled,
              onChanged: (v) => _update(_settings.copyWith(enabled: v)),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing4),
        Text(
          'Cut before boosting. Sweep the frequency to find the problem. '
          'Narrow Q for surgical fixes.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // High-pass filter
        _FilterRow(
          label: 'High-pass',
          frequency: _settings.highPassHz,
          minHz: 20,
          maxHz: 500,
          unit: 'Hz',
          onChanged: (v) => _update(_settings.copyWith(highPassHz: v)),
        ),
        const Divider(),
        // 8 parametric bands
        Text('Parametric Bands',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppTheme.spacing8),
        ...List.generate(8, (i) {
          final band = _settings.bands[i];
          return _BandEditor(
            bandIndex: i + 1,
            band: band,
            onChanged: (newBand) {
              final newBands = List<EqBand>.from(_settings.bands);
              newBands[i] = newBand;
              _update(_settings.copyWith(bands: newBands));
            },
          );
        }),
        const Divider(),
        // Low-pass filter
        _FilterRow(
          label: 'Low-pass',
          frequency: _settings.lowPassHz,
          minHz: 2000,
          maxHz: 20000,
          unit: 'Hz',
          onChanged: (v) => _update(_settings.copyWith(lowPassHz: v)),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Reset button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _update(EqSettings.flat.copyWith(
              enabled: _settings.enabled,
            )),
            icon: const Icon(Icons.refresh),
            label: const Text('Reset to flat'),
          ),
        ),
      ],
    );
  }
}

class _BandEditor extends StatelessWidget {
  final int bandIndex;
  final EqBand band;
  final ValueChanged<EqBand> onChanged;

  const _BandEditor({
    required this.bandIndex,
    required this.band,
    required this.onChanged,
  });

  String _frequencyLabel(double freq) {
    if (freq >= 1000) return '${(freq / 1000).toStringAsFixed(1)} kHz';
    return '${freq.round()} Hz';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 50,
                child: Text('Band $bandIndex',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              Expanded(
                child: Text(
                  _frequencyLabel(band.frequency),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  band.enabled ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 10,
                    color: band.enabled ? Colors.green : AppTheme.textDisabled,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              Switch(
                value: band.enabled,
                onChanged: (v) => onChanged(band.copyWith(enabled: v)),
              ),
            ],
          ),
          if (band.enabled) ...[
            // Gain (-18 to +18 dB)
            Text('Gain: ${band.gain.toStringAsFixed(1)} dB',
                style: const TextStyle(fontSize: 11)),
            Slider(
              value: band.gain,
              min: -18,
              max: 18,
              divisions: 72,
              label: '${band.gain.toStringAsFixed(1)} dB',
              onChanged: (v) => onChanged(band.copyWith(gain: v)),
            ),
            // Frequency (logarithmic-feeling, linear slider)
            Text('Frequency: ${_frequencyLabel(band.frequency)}',
                style: const TextStyle(fontSize: 11)),
            Slider(
              value: band.frequency,
              min: 20,
              max: 20000,
              divisions: 200,
              label: _frequencyLabel(band.frequency),
              onChanged: (v) => onChanged(band.copyWith(frequency: v)),
            ),
            // Q (0.1 to 6.0)
            Text('Q: ${band.q.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 11)),
            Slider(
              value: band.q,
              min: 0.1,
              max: 6.0,
              divisions: 59,
              label: band.q.toStringAsFixed(2),
              onChanged: (v) => onChanged(band.copyWith(q: v)),
            ),
            const SizedBox(height: AppTheme.spacing4),
          ],
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String label;
  final double frequency;
  final double minHz;
  final double maxHz;
  final String unit;
  final ValueChanged<double> onChanged;

  const _FilterRow({
    required this.label,
    required this.frequency,
    required this.minHz,
    required this.maxHz,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          Expanded(
            child: Slider(
              value: frequency,
              min: minHz,
              max: maxHz,
              divisions: 100,
              label: frequency.round().toString(),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${frequency.round()} $unit',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// EQ settings — high-pass, 8 parametric bands, low-pass.
class EqSettings {
  final bool enabled;
  final double highPassHz;
  final List<EqBand> bands;
  final double lowPassHz;

  const EqSettings({
    this.enabled = true,
    this.highPassHz = 80,
    required this.bands,
    this.lowPassHz = 20000,
  });

  /// Flat EQ — all bands at 0 dB, sensible default frequencies.
  static final flat = EqSettings(
    enabled: true,
    highPassHz: 80,
    lowPassHz: 20000,
    bands: [
      EqBand(frequency: 60, gain: 0, q: 1.0),
      EqBand(frequency: 120, gain: 0, q: 1.0),
      EqBand(frequency: 250, gain: 0, q: 1.0),
      EqBand(frequency: 500, gain: 0, q: 1.0),
      EqBand(frequency: 1000, gain: 0, q: 1.0),
      EqBand(frequency: 2500, gain: 0, q: 1.0),
      EqBand(frequency: 5000, gain: 0, q: 1.0),
      EqBand(frequency: 10000, gain: 0, q: 1.0),
    ],
  );

  EqSettings copyWith({
    bool? enabled,
    double? highPassHz,
    List<EqBand>? bands,
    double? lowPassHz,
  }) {
    return EqSettings(
      enabled: enabled ?? this.enabled,
      highPassHz: highPassHz ?? this.highPassHz,
      bands: bands ?? this.bands,
      lowPassHz: lowPassHz ?? this.lowPassHz,
    );
  }
}

/// A single parametric EQ band.
class EqBand {
  final double frequency;
  final double gain;
  final double q;
  final bool enabled;

  const EqBand({
    required this.frequency,
    required this.gain,
    required this.q,
    this.enabled = false,
  });

  EqBand copyWith({
    double? frequency,
    double? gain,
    double? q,
    bool? enabled,
  }) {
    return EqBand(
      frequency: frequency ?? this.frequency,
      gain: gain ?? this.gain,
      q: q ?? this.q,
      enabled: enabled ?? this.enabled,
    );
  }
}
