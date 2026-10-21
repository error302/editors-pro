import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_theme.dart';

// ─── EQ Band Model ────────────────────────────────────────────────────

class EqBand {
  // 0.5 to 8.0

  const EqBand({
    required this.label,
    required this.frequency,
    this.gain = 0.0,
    this.q = 1.0,
  });
  final String label;
  final double frequency; // Hz
  final double gain; // -12 to +12 dB
  final double q;

  EqBand copyWith({double? gain, double? q}) {
    return EqBand(
      label: label,
      frequency: frequency,
      gain: gain ?? this.gain,
      q: q ?? this.q,
    );
  }
}

// ─── Noise Reduction Model ────────────────────────────────────────────

enum NrFocus { broadband, low, mid, high }

class NoiseReductionState {
  const NoiseReductionState({
    this.enabled = false,
    this.strength = 50.0,
    this.focus = NrFocus.broadband,
  });
  final bool enabled;
  final double strength; // 0-100
  final NrFocus focus;

  NoiseReductionState copyWith({
    bool? enabled,
    double? strength,
    NrFocus? focus,
  }) {
    return NoiseReductionState(
      enabled: enabled ?? this.enabled,
      strength: strength ?? this.strength,
      focus: focus ?? this.focus,
    );
  }
}

// ─── Compressor Model ─────────────────────────────────────────────────

class CompressorState {
  // simulated real-time

  const CompressorState({
    this.threshold = -20.0,
    this.ratio = 4.0,
    this.attack = 10.0,
    this.release = 100.0,
    this.makeupGain = 0.0,
    this.gainReduction = 0.0,
  });
  final double threshold; // -60 to 0 dB
  final double ratio; // 1:1 to 20:1
  final double attack; // 0.1 to 100 ms
  final double release; // 10 to 1000 ms
  final double makeupGain; // 0 to 24 dB
  final double gainReduction;

  CompressorState copyWith({
    double? threshold,
    double? ratio,
    double? attack,
    double? release,
    double? makeupGain,
    double? gainReduction,
  }) {
    return CompressorState(
      threshold: threshold ?? this.threshold,
      ratio: ratio ?? this.ratio,
      attack: attack ?? this.attack,
      release: release ?? this.release,
      makeupGain: makeupGain ?? this.makeupGain,
      gainReduction: gainReduction ?? this.gainReduction,
    );
  }
}

// ─── Full EQ State ────────────────────────────────────────────────────

class AudioEqState {
  const AudioEqState({
    required this.bands,
    this.noiseReduction = const NoiseReductionState(),
    this.compressor = const CompressorState(),
    this.activePreset,
  });
  final List<EqBand> bands;
  final NoiseReductionState noiseReduction;
  final CompressorState compressor;
  final String? activePreset;

  AudioEqState copyWith({
    List<EqBand>? bands,
    NoiseReductionState? noiseReduction,
    CompressorState? compressor,
    String? activePreset,
    bool clearPreset = false,
  }) {
    return AudioEqState(
      bands: bands ?? this.bands,
      noiseReduction: noiseReduction ?? this.noiseReduction,
      compressor: compressor ?? this.compressor,
      activePreset: clearPreset ? null : (activePreset ?? this.activePreset),
    );
  }

  // Shared immutable neutral state; retain the existing getter API.
  // ignore: prefer_constructors_over_static_methods
  static AudioEqState get flat => const AudioEqState(
        bands: [
          EqBand(label: 'Low', frequency: 60),
          EqBand(label: 'Low-Mid', frequency: 250),
          EqBand(label: 'Mid', frequency: 1000),
          EqBand(label: 'High-Mid', frequency: 4000),
          EqBand(label: 'High', frequency: 16000),
        ],
      );
}

// ─── EQ Presets ───────────────────────────────────────────────────────

class EqPreset {
  const EqPreset({
    required this.id,
    required this.name,
    required this.gains,
    this.qs = const [1.0, 1.0, 1.0, 1.0, 1.0],
    this.noiseReduction,
    this.compressor,
  });
  final String id;
  final String name;
  final List<double> gains; // 5 bands, -12 to +12 dB
  final List<double> qs; // 5 bands, 0.5 to 8.0
  final NoiseReductionState? noiseReduction;
  final CompressorState? compressor;

  AudioEqState toState() {
    final base = AudioEqState.flat;
    return base.copyWith(
      activePreset: id,
      bands: [
        base.bands[0].copyWith(gain: gains[0], q: qs[0]),
        base.bands[1].copyWith(gain: gains[1], q: qs[1]),
        base.bands[2].copyWith(gain: gains[2], q: qs[2]),
        base.bands[3].copyWith(gain: gains[3], q: qs[3]),
        base.bands[4].copyWith(gain: gains[4], q: qs[4]),
      ],
      noiseReduction: noiseReduction,
      compressor: compressor,
    );
  }
}

const _eqPresets = <EqPreset>[
  EqPreset(id: 'flat', name: 'Flat', gains: [0, 0, 0, 0, 0]),
  EqPreset(
    id: 'vocal_boost',
    name: 'Vocal Boost',
    gains: [-2, 2, 6, 4, -1],
    qs: [0.7, 1.2, 1.5, 1.2, 0.8],
  ),
  EqPreset(
    id: 'bass_boost',
    name: 'Bass Boost',
    gains: [8, 4, 0, -1, -2],
    qs: [0.8, 1.0, 1.0, 1.0, 1.0],
  ),
  EqPreset(
    id: 'treble_boost',
    name: 'Treble Boost',
    gains: [-2, -1, 1, 5, 8],
    qs: [1.0, 1.0, 1.0, 1.2, 0.8],
  ),
  EqPreset(
    id: 'loudness',
    name: 'Loudness',
    gains: [6, -2, -4, -2, 6],
    qs: [0.6, 1.0, 1.0, 1.0, 0.6],
  ),
  EqPreset(
    id: 'podcast',
    name: 'Podcast',
    gains: [-4, 1, 6, 4, -2],
    qs: [0.7, 1.2, 1.5, 1.3, 0.8],
    noiseReduction: NoiseReductionState(
      enabled: true,
      strength: 40.0,
      focus: NrFocus.broadband,
    ),
    compressor: CompressorState(
      threshold: -18,
      ratio: 3.0,
      attack: 10,
      release: 150,
      makeupGain: 4,
    ),
  ),
  EqPreset(
    id: 'music',
    name: 'Music',
    gains: [3, 0, -1, 2, 4],
    qs: [0.8, 1.0, 1.0, 1.2, 0.8],
  ),
  EqPreset(
    id: 'de_ess',
    name: 'De-Ess',
    gains: [0, 0, -2, -6, -2],
    qs: [1.0, 1.0, 2.0, 4.0, 2.0],
  ),
];

// ─── EQ State Provider per track ──────────────────────────────────────

final _eqStateProviders =
    StateNotifierProvider.family<AudioEqNotifier, AudioEqState, String>(
  (ref, trackId) => AudioEqNotifier(),
);

class AudioEqNotifier extends StateNotifier<AudioEqState> {
  AudioEqNotifier() : super(AudioEqState.flat);

  void setBandGain(int index, double gain) {
    final bands = List<EqBand>.from(state.bands);
    bands[index] = bands[index].copyWith(gain: gain);
    state = state.copyWith(bands: bands, clearPreset: true);
  }

  void setBandQ(int index, double q) {
    final bands = List<EqBand>.from(state.bands);
    bands[index] = bands[index].copyWith(q: q);
    state = state.copyWith(bands: bands, clearPreset: true);
  }

  void applyPreset(EqPreset preset) {
    state = preset.toState();
  }

  void resetToFlat() {
    state = AudioEqState.flat;
  }

  void updateNoiseReduction(NoiseReductionState nr) {
    state = state.copyWith(noiseReduction: nr, clearPreset: true);
  }

  void updateCompressor(CompressorState comp) {
    state = state.copyWith(compressor: comp, clearPreset: true);
  }

  void simulateGainReduction() {
    // Simulated gain reduction based on compressor threshold and ratio.
    final comp = state.compressor;
    // Assume a "virtual" input level of -6 dB for the simulation.
    const virtualInputDb = -6.0;
    final overDb = virtualInputDb - comp.threshold;
    final gr = overDb > 0 ? -overDb * (1.0 - 1.0 / comp.ratio) : 0.0;
    state = state.copyWith(
      compressor: comp.copyWith(gainReduction: gr.clamp(-30.0, 0.0)),
    );
  }
}

// ─── Audio EQ Panel ───────────────────────────────────────────────────

class AudioEqPanel extends ConsumerStatefulWidget {
  const AudioEqPanel({required this.trackId, super.key});
  final String trackId;

  @override
  ConsumerState<AudioEqPanel> createState() => _AudioEqPanelState();
}

class _AudioEqPanelState extends ConsumerState<AudioEqPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing12,
            vertical: AppTheme.spacing8,
          ),
          child: Row(
            children: [
              Text('Audio EQ', style: context.textTheme.titleMedium),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.audioTrackColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Text(
                  widget.trackId.length > 8
                      ? widget.trackId.substring(0, 8)
                      : widget.trackId,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.audioTrackColor,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Tab bar ────────────────────────────────────────────────
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'EQ'),
            Tab(text: 'Noise Reduction'),
            Tab(text: 'Compressor'),
          ],
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textDisabled,
          indicatorColor: AppTheme.primary,
          labelStyle: context.textTheme.labelMedium,
          indicatorSize: TabBarIndicatorSize.label,
        ),

        // ── Tab content ────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _EqTab(trackId: widget.trackId),
              _NoiseReductionTab(trackId: widget.trackId),
              _CompressorTab(trackId: widget.trackId),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// EQ TAB
// ═══════════════════════════════════════════════════════════════════════

class _EqTab extends ConsumerWidget {
  const _EqTab({required this.trackId});
  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eqState = ref.watch(_eqStateProviders(trackId));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing12,
        vertical: AppTheme.spacing8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Preset selector ─────────────────────────────────────────
          Text('Presets', style: context.textTheme.labelMedium),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _eqPresets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final preset = _eqPresets[index];
                final isActive = eqState.activePreset == preset.id;
                return FilterChip(
                  label: Text(preset.name),
                  selected: isActive,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? Colors.white : AppTheme.textPrimary,
                  ),
                  backgroundColor: AppTheme.surfaceVariant,
                  selectedColor: AppTheme.primary,
                  side: BorderSide(
                    color: isActive
                        ? AppTheme.primary
                        : AppTheme.textDisabled.withValues(alpha: 0.2),
                  ),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    ref
                        .read(_eqStateProviders(trackId).notifier)
                        .applyPreset(preset);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: AppTheme.spacing12),

          // ── EQ Curve Visualization ──────────────────────────────────
          Text('Frequency Response', style: context.textTheme.labelMedium),
          const SizedBox(height: 4),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: CustomPaint(
              painter: _EqCurvePainter(bands: eqState.bands),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: AppTheme.spacing12),

          // ── Band controls ───────────────────────────────────────────
          ...List.generate(eqState.bands.length, (i) {
            final band = eqState.bands[i];
            return _BandControl(
              band: band,
              onGainChanged: (v) {
                ref.read(_eqStateProviders(trackId).notifier).setBandGain(i, v);
              },
              onQChanged: (v) {
                ref.read(_eqStateProviders(trackId).notifier).setBandQ(i, v);
              },
            );
          }),

          const SizedBox(height: AppTheme.spacing8),

          // ── Reset ───────────────────────────────────────────────────
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  ref.read(_eqStateProviders(trackId).notifier).resetToFlat();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reset to Flat'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Single Band Control ──────────────────────────────────────────────

class _BandControl extends StatelessWidget {
  const _BandControl({
    required this.band,
    required this.onGainChanged,
    required this.onQChanged,
  });
  final EqBand band;
  final ValueChanged<double> onGainChanged;
  final ValueChanged<double> onQChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing8),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacing8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Band header
            Row(
              children: [
                Text(
                  band.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${band.frequency >= 1000 ? '${(band.frequency / 1000).toStringAsFixed(band.frequency % 1000 == 0 ? 0 : 1)}k' : band.frequency.toStringAsFixed(0)}Hz',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.primary,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                // Gain readout
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: _gainColor(band.gain).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Text(
                    '${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(1)} dB',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _gainColor(band.gain),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Gain slider
            Row(
              children: [
                const SizedBox(
                  width: 36,
                  child: Text(
                    'Gain',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppTheme.textDisabled,
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: _gainColor(band.gain),
                      thumbColor: _gainColor(band.gain).withValues(alpha: 0.9),
                      inactiveTrackColor: AppTheme.border,
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: band.gain,
                      min: -12,
                      max: 12,
                      divisions: 48,
                      onChanged: onGainChanged,
                    ),
                  ),
                ),
              ],
            ),

            // Q slider
            Row(
              children: [
                const SizedBox(
                  width: 36,
                  child: Text(
                    'Q',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppTheme.textDisabled,
                    ),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: band.q,
                    min: 0.5,
                    max: 8.0,
                    divisions: 30,
                    label: 'Q ${band.q.toStringAsFixed(1)}',
                    onChanged: onQChanged,
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    band.q.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppTheme.textSecondary,
                      fontFamily: 'monospace',
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _gainColor(double gain) {
    if (gain.abs() < 0.5) return AppTheme.textSecondary;
    return gain > 0 ? AppTheme.success : AppTheme.error;
  }
}

// ─── EQ Curve Painter ─────────────────────────────────────────────────

class _EqCurvePainter extends CustomPainter {
  _EqCurvePainter({required this.bands});
  final List<EqBand> bands;

  @override
  void paint(Canvas canvas, Size size) {
    const padLeft = 32.0;
    const padRight = 8.0;
    const padTop = 8.0;
    const padBottom = 16.0;
    final plotW = size.width - padLeft - padRight;
    final plotH = size.height - padTop - padBottom;

    // ── Grid ────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = AppTheme.border
      ..strokeWidth = 0.5;

    // Horizontal center (0 dB)
    final cy = padTop + plotH / 2;
    canvas.drawLine(
      Offset(padLeft, cy),
      Offset(size.width - padRight, cy),
      gridPaint,
    );

    // Horizontal +6 / -6
    for (final db in [-6.0, 6.0]) {
      final y = padTop + plotH / 2 - (db / 12.0) * (plotH / 2);
      canvas.drawLine(
        Offset(padLeft, y),
        Offset(size.width - padRight, y),
        gridPaint,
      );
    }

    // Frequency gridlines: 60, 250, 1k, 4k, 16k
    final freqs = [60.0, 250.0, 1000.0, 4000.0, 16000.0];
    final freqLabels = ['60', '250', '1k', '4k', '16k'];
    final minLog = math.log(20);
    final maxLog = math.log(20000);

    for (var i = 0; i < freqs.length; i++) {
      final x =
          padLeft + (math.log(freqs[i]) - minLog) / (maxLog - minLog) * plotW;
      canvas.drawLine(Offset(x, padTop), Offset(x, padTop + plotH), gridPaint);

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: freqLabels[i],
          style: const TextStyle(
            color: AppTheme.textDisabled,
            fontSize: 8,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, padTop + plotH + 2));
    }

    // dB labels
    for (final db in [-12.0, -6.0, 0.0, 6.0, 12.0]) {
      final y = padTop + plotH / 2 - (db / 12.0) * (plotH / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: '${db > 0 ? '+' : ''}${db.round()}',
          style: const TextStyle(
            color: AppTheme.textDisabled,
            fontSize: 8,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    // ── Curve ───────────────────────────────────────────────────────
    final points = <Offset>[];
    const steps = 200;

    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final freq = math.exp(minLog + t * (maxLog - minLog));
      var totalGain = 0.0;

      // Sum contributions from all bands (simplified parametric response)
      for (final band in bands) {
        totalGain += _bandResponse(freq, band);
      }

      // Clamp
      totalGain = totalGain.clamp(-12.0, 12.0);

      final x = padLeft + t * plotW;
      final y = padTop + plotH / 2 - (totalGain / 12.0) * (plotH / 2);
      points.add(Offset(x, y));
    }

    // Fill under curve
    if (points.isNotEmpty) {
      final fillPath = Path();
      fillPath.moveTo(points[0].dx, cy);
      fillPath.lineTo(points[0].dx, points[0].dy);
      for (var i = 1; i < points.length; i++) {
        fillPath.lineTo(points[i].dx, points[i].dy);
      }
      fillPath.lineTo(points.last.dx, cy);
      fillPath.close();

      canvas.drawPath(
        fillPath,
        Paint()
          ..color = AppTheme.primary.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
    }

    // Draw curve line
    if (points.length > 1) {
      final linePath = Path();
      linePath.moveTo(points[0].dx, points[0].dy);
      for (var i = 1; i < points.length; i++) {
        linePath.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(
        linePath,
        Paint()
          ..color = AppTheme.primary
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // ── Band markers ────────────────────────────────────────────────
    for (final band in bands) {
      final t = (math.log(band.frequency) - minLog) / (maxLog - minLog);
      final x = padLeft + t * plotW;
      final y = padTop +
          plotH / 2 -
          (band.gain.clamp(-12.0, 12.0) / 12.0) * (plotH / 2);

      // Dot
      canvas.drawCircle(
        Offset(x, y),
        4,
        Paint()..color = AppTheme.primary,
      );
      canvas.drawCircle(
        Offset(x, y),
        4,
        Paint()
          ..color = AppTheme.cardColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  /// Simplified parametric EQ band response at a given frequency.
  /// Uses a second-order peak/dip filter approximation.
  double _bandResponse(double freq, EqBand band) {
    if (band.gain.abs() < 0.01) return 0.0;
    final ratio = freq / band.frequency;
    final q = band.q;
    // RBJ peak EQ approximation
    final a = math.pow(10.0, band.gain / 40.0);
    // Simplified: use a bell shape
    final x = (ratio - 1.0 / ratio) * q;
    final denom = 1.0 + x * x;
    final response = (a * a - 1.0) / denom + 1.0;
    return 20.0 * math.log(response) / math.ln10;
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter oldDelegate) {
    // Simple comparison — rebuild if any band differs.
    if (oldDelegate.bands.length != bands.length) return true;
    for (var i = 0; i < bands.length; i++) {
      if (oldDelegate.bands[i].gain != bands[i].gain ||
          oldDelegate.bands[i].q != bands[i].q) {
        return true;
      }
    }
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// NOISE REDUCTION TAB
// ═══════════════════════════════════════════════════════════════════════

class _NoiseReductionTab extends ConsumerWidget {
  const _NoiseReductionTab({required this.trackId});
  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eqState = ref.watch(_eqStateProviders(trackId));
    final nr = eqState.noiseReduction;
    final notifier = ref.read(_eqStateProviders(trackId).notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing12,
        vertical: AppTheme.spacing12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Enable toggle ───────────────────────────────────────────
          Row(
            children: [
              Switch(
                value: nr.enabled,
                activeThumbColor: AppTheme.audioTrackColor,
                onChanged: (v) {
                  notifier.updateNoiseReduction(
                    nr.copyWith(enabled: v),
                  );
                },
              ),
              const SizedBox(width: 8),
              Text(
                'Noise Reduction',
                style: context.textTheme.labelLarge,
              ),
              const Spacer(),
              if (nr.enabled)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.audioTrackColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.audioTrackColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing16),

          // ── Strength ────────────────────────────────────────────────
          Text('Strength', style: context.textTheme.labelMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: nr.strength,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${nr.strength.round()}%',
                  onChanged: nr.enabled
                      ? (v) {
                          notifier.updateNoiseReduction(
                            nr.copyWith(strength: v),
                          );
                        }
                      : null,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${nr.strength.round()}%',
                  style: context.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: nr.enabled
                        ? AppTheme.textPrimary
                        : AppTheme.textDisabled,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing16),

          // ── Frequency focus ─────────────────────────────────────────
          Text('Frequency Focus', style: context.textTheme.labelMedium),
          const SizedBox(height: 6),
          Row(
            children: NrFocus.values.map((focus) {
              final isActive = nr.focus == focus;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(_focusLabel(focus)),
                  selected: isActive,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? Colors.white
                        : (nr.enabled
                            ? AppTheme.textPrimary
                            : AppTheme.textDisabled),
                  ),
                  backgroundColor: AppTheme.surfaceVariant,
                  selectedColor: AppTheme.audioTrackColor,
                  side: BorderSide(
                    color: isActive
                        ? AppTheme.audioTrackColor
                        : AppTheme.textDisabled.withValues(alpha: 0.2),
                  ),
                  visualDensity: VisualDensity.compact,
                  onSelected: nr.enabled
                      ? (_) {
                          notifier.updateNoiseReduction(
                            nr.copyWith(focus: focus),
                          );
                        }
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppTheme.spacing16),

          // ── Info ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing12),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppTheme.textDisabled,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Noise reduction analyzes the audio signal and removes '
                    'unwanted background noise. Higher strength removes more '
                    'noise but may affect audio quality. Use the frequency '
                    'focus to target specific noise ranges.',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _focusLabel(NrFocus focus) {
    switch (focus) {
      case NrFocus.broadband:
        return 'Broadband';
      case NrFocus.low:
        return 'Low';
      case NrFocus.mid:
        return 'Mid';
      case NrFocus.high:
        return 'High';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// COMPRESSOR TAB
// ═══════════════════════════════════════════════════════════════════════

class _CompressorTab extends ConsumerStatefulWidget {
  const _CompressorTab({required this.trackId});
  final String trackId;

  @override
  ConsumerState<_CompressorTab> createState() => _CompressorTabState();
}

class _CompressorTabState extends ConsumerState<_CompressorTab> {
  @override
  void initState() {
    super.initState();
    // Simulate gain reduction updates
    Future.delayed(const Duration(milliseconds: 500), _simulateGr);
  }

  void _simulateGr() {
    if (!mounted) return;
    ref
        .read(_eqStateProviders(widget.trackId).notifier)
        .simulateGainReduction();
    Future.delayed(const Duration(milliseconds: 200), _simulateGr);
  }

  @override
  Widget build(BuildContext context) {
    final eqState = ref.watch(_eqStateProviders(widget.trackId));
    final comp = eqState.compressor;
    final notifier = ref.read(_eqStateProviders(widget.trackId).notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing12,
        vertical: AppTheme.spacing12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Gain Reduction Meter ────────────────────────────────────
          Text('Gain Reduction', style: context.textTheme.labelMedium),
          const SizedBox(height: 4),
          _GainReductionMeter(reductionDb: comp.gainReduction),
          const SizedBox(height: AppTheme.spacing16),

          // ── Threshold ───────────────────────────────────────────────
          _CompressorSlider(
            label: 'Threshold',
            value: comp.threshold,
            min: -60,
            max: 0,
            divisions: 60,
            unit: 'dB',
            onChanged: (v) {
              notifier.updateCompressor(comp.copyWith(threshold: v));
            },
          ),
          const SizedBox(height: AppTheme.spacing8),

          // ── Ratio ──────────────────────────────────────────────────
          _CompressorSlider(
            label: 'Ratio',
            value: comp.ratio,
            min: 1,
            max: 20,
            divisions: 19,
            unit: ':1',
            onChanged: (v) {
              notifier.updateCompressor(comp.copyWith(ratio: v));
            },
          ),
          const SizedBox(height: AppTheme.spacing8),

          // ── Attack ─────────────────────────────────────────────────
          _CompressorSlider(
            label: 'Attack',
            value: comp.attack,
            min: 0.1,
            max: 100,
            divisions: 100,
            unit: 'ms',
            onChanged: (v) {
              notifier.updateCompressor(comp.copyWith(attack: v));
            },
          ),
          const SizedBox(height: AppTheme.spacing8),

          // ── Release ────────────────────────────────────────────────
          _CompressorSlider(
            label: 'Release',
            value: comp.release,
            min: 10,
            max: 1000,
            divisions: 99,
            unit: 'ms',
            onChanged: (v) {
              notifier.updateCompressor(comp.copyWith(release: v));
            },
          ),
          const SizedBox(height: AppTheme.spacing8),

          // ── Makeup Gain ────────────────────────────────────────────
          _CompressorSlider(
            label: 'Makeup Gain',
            value: comp.makeupGain,
            min: 0,
            max: 24,
            divisions: 24,
            unit: 'dB',
            onChanged: (v) {
              notifier.updateCompressor(comp.copyWith(makeupGain: v));
            },
          ),
          const SizedBox(height: AppTheme.spacing12),

          // ── Compressor visualization ────────────────────────────────
          Text('Compression Curve', style: context.textTheme.labelMedium),
          const SizedBox(height: 4),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: CustomPaint(
              painter: _CompressionCurvePainter(
                threshold: comp.threshold,
                ratio: comp.ratio,
              ),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: AppTheme.spacing12),

          // ── Reset ──────────────────────────────────────────────────
          TextButton.icon(
            onPressed: () {
              notifier.updateCompressor(const CompressorState());
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reset Compressor'),
          ),
        ],
      ),
    );
  }
}

// ─── Compressor Slider Widget ─────────────────────────────────────────

class _CompressorSlider extends StatelessWidget {
  const _CompressorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: context.textTheme.labelMedium,
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)} $unit',
            style: context.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ─── Gain Reduction Meter ─────────────────────────────────────────────

class _GainReductionMeter extends StatelessWidget {
  // negative value, e.g. -6.0

  const _GainReductionMeter({required this.reductionDb});
  final double reductionDb;

  @override
  Widget build(BuildContext context) {
    final normalized = (reductionDb.abs() / 30.0).clamp(0.0, 1.0);

    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Stack(
        children: [
          // Background segments
          Row(
            children: List.generate(30, (i) {
              return Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: AppTheme.border,
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          // Active reduction bar (from right to left)
          if (normalized > 0)
            FractionallySizedBox(
              alignment: Alignment.centerRight,
              widthFactor: normalized,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(
                      normalized > 0.95 ? 0 : AppTheme.radiusSmall,
                    ),
                    right: const Radius.circular(AppTheme.radiusSmall),
                  ),
                  gradient: const LinearGradient(
                    colors: [
                      AppTheme.warning,
                      AppTheme.error,
                    ],
                  ),
                ),
              ),
            ),
          // Label
          Center(
            child: Text(
              '${reductionDb.toStringAsFixed(1)} dB',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: normalized > 0.5 ? Colors.white : AppTheme.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Compression Curve Painter ────────────────────────────────────────

class _CompressionCurvePainter extends CustomPainter {
  _CompressionCurvePainter({
    required this.threshold,
    required this.ratio,
  });
  final double threshold;
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 24.0;
    final plotW = size.width - pad * 2;
    final plotH = size.height - pad * 2;

    // Grid
    final gridPaint = Paint()
      ..color = AppTheme.border
      ..strokeWidth = 0.5;

    // 1:1 reference line (diagonal)
    canvas.drawLine(
      Offset(pad, pad + plotH),
      Offset(pad + plotW, pad),
      gridPaint,
    );

    // Axis labels
    const labelStyle = TextStyle(
      color: AppTheme.textDisabled,
      fontSize: 8,
      fontFamily: 'monospace',
    );

    // Input (x-axis) labels
    for (final db in [-60.0, -40.0, -20.0, 0.0]) {
      final x = pad + ((db + 60) / 60) * plotW;
      canvas.drawLine(Offset(x, pad), Offset(x, pad + plotH), gridPaint);
      _drawLabel(
        canvas,
        '${db.round()}',
        Offset(x, pad + plotH + 4),
        labelStyle,
      );
    }

    // Output (y-axis) labels
    for (final db in [-60.0, -40.0, -20.0, 0.0]) {
      final y = pad + plotH - ((db + 60) / 60) * plotH;
      canvas.drawLine(Offset(pad, y), Offset(pad + plotW, y), gridPaint);
      _drawLabel(canvas, '${db.round()}', Offset(2, y - 4), labelStyle);
    }

    // Compression curve
    final path = Path();
    for (var i = 0; i <= 100; i++) {
      final inputDb = -60.0 + (i / 100) * 60.0;
      double outputDb;
      if (inputDb <= threshold) {
        outputDb = inputDb;
      } else {
        outputDb = threshold + (inputDb - threshold) / ratio;
      }

      final x = pad + ((inputDb + 60) / 60) * plotW;
      final y = pad + plotH - ((outputDb + 60) / 60) * plotH;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.primary
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Threshold marker
    final tx = pad + ((threshold + 60) / 60) * plotW;
    final thresholdPaint = Paint()
      ..color = AppTheme.warning.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(tx, pad), Offset(tx, pad + plotH), thresholdPaint);
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _CompressionCurvePainter oldDelegate) {
    return oldDelegate.threshold != threshold || oldDelegate.ratio != ratio;
  }
}
