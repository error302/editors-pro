import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase F: Audio Loudness Meter.
///
/// Renders a real-time loudness meter showing:
/// - Integrated LUFS (the program-average)
/// - Short-term LUFS (3-second window)
/// - Momentary LUFS (0.4-second window)
/// - True-peak (dBTP)
///
/// Plus target markers for the active delivery spec:
/// - EBU R128: −23 LUFS ±0.5, ≤ −1 dBTP (EU broadcast)
/// - ATSC A/85: −24 LKFS ±2, ≤ −2 dBTP (US broadcast)
/// - YouTube: −14 LUFS, ≤ −1 dBTP
/// - TikTok: −18 LUFS, ≤ −1 dBTP
///
/// The amateur move is to normalize to 0 dBFS peak and call it done.
/// The pro move is to mix to the target LUFS and verify true-peak. See
/// persona/skills/loudness-target/SKILL.md.
class AudioLoudnessMeter extends StatefulWidget {
  const AudioLoudnessMeter({
    required this.reading,
    super.key,
    this.target = LoudnessTarget.ebuR128,
  });
  final LoudnessReading reading;
  final LoudnessTarget target;

  @override
  State<AudioLoudnessMeter> createState() => _AudioLoudnessMeterState();
}

class _AudioLoudnessMeterState extends State<AudioLoudnessMeter> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Loudness Meter',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            // Target picker
            DropdownButton<LoudnessTarget>(
              value: widget.target,
              items: const [
                DropdownMenuItem(
                  value: LoudnessTarget.ebuR128,
                  child: Text('EBU R128 (−23 LUFS)'),
                ),
                DropdownMenuItem(
                  value: LoudnessTarget.atscA85,
                  child: Text('ATSC A/85 (−24 LKFS)'),
                ),
                DropdownMenuItem(
                  value: LoudnessTarget.youtube,
                  child: Text('YouTube (−14 LUFS)'),
                ),
                DropdownMenuItem(
                  value: LoudnessTarget.tiktok,
                  child: Text('TikTok (−18 LUFS)'),
                ),
                DropdownMenuItem(
                  value: LoudnessTarget.podcast,
                  child: Text('Podcast (−16 LUFS)'),
                ),
              ],
              onChanged: (_) {
                // Parent owns the target; we just display.
              },
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Integrated LUFS — large display
        _LoudnessDisplay(
          label: 'Integrated',
          value: widget.reading.integratedLufs,
          unit: 'LUFS',
          target: widget.target.integratedTarget,
          tolerance: widget.target.integratedTolerance,
          isPrimary: true,
        ),
        const SizedBox(height: AppTheme.spacing8),
        // Short-term + Momentary
        Row(
          children: [
            Expanded(
              child: _LoudnessDisplay(
                label: 'Short-term',
                value: widget.reading.shortTermLufs,
                unit: 'LUFS',
                target: widget.target.integratedTarget,
                tolerance: widget.target.integratedTolerance,
              ),
            ),
            const SizedBox(width: AppTheme.spacing8),
            Expanded(
              child: _LoudnessDisplay(
                label: 'Momentary',
                value: widget.reading.momentaryLufs,
                unit: 'LUFS',
                target: widget.target.integratedTarget,
                tolerance: widget.target.integratedTolerance,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing8),
        // True-peak
        _LoudnessDisplay(
          label: 'True-peak',
          value: widget.reading.truePeakDbtp,
          unit: 'dBTP',
          target: widget.target.truePeakCeiling,
          tolerance: 0.0,
          ceiling: true,
          isCompliance: true,
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Compliance status
        _ComplianceBadge(
          reading: widget.reading,
          target: widget.target,
        ),
      ],
    );
  }
}

class _LoudnessDisplay extends StatelessWidget {
  const _LoudnessDisplay({
    required this.label,
    required this.value,
    required this.unit,
    required this.target,
    required this.tolerance,
    this.isPrimary = false,
    this.ceiling = false,
    this.isCompliance = false,
  });
  final String label;
  final double value;
  final String unit;
  final double target;
  final double tolerance;
  final bool isPrimary;
  final bool ceiling;
  final bool isCompliance;

  @override
  Widget build(BuildContext context) {
    final isCompliant =
        ceiling ? value <= target : (value - target).abs() <= tolerance + 0.5;

    final color = isCompliant ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing8),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: isPrimary ? 14 : 12,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value.toStringAsFixed(1),
                style: TextStyle(
                  color: color,
                  fontSize: isPrimary ? 36 : 20,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  color: color,
                  fontSize: isPrimary ? 14 : 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            ceiling
                ? 'ceiling: ${target.toStringAsFixed(1)} $unit'
                : 'target: ${target.toStringAsFixed(1)} $unit (±${tolerance.toStringAsFixed(1)})',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComplianceBadge extends StatelessWidget {
  const _ComplianceBadge({required this.reading, required this.target});
  final LoudnessReading reading;
  final LoudnessTarget target;

  @override
  Widget build(BuildContext context) {
    final loudnessOk =
        (reading.integratedLufs - target.integratedTarget).abs() <=
            target.integratedTolerance + 0.5;
    final truePeakOk = reading.truePeakDbtp <= target.truePeakCeiling;
    final allOk = loudnessOk && truePeakOk;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing12),
      decoration: BoxDecoration(
        color: (allOk ? Colors.green : Colors.red).withValues(alpha: 0.1),
        border: Border.all(
          color: (allOk ? Colors.green : Colors.red).withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            allOk ? Icons.check_circle : Icons.warning,
            color: allOk ? Colors.green : Colors.red,
          ),
          const SizedBox(width: AppTheme.spacing8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allOk ? 'COMPLIANT' : 'NON-COMPLIANT',
                  style: TextStyle(
                    color: allOk ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!allOk) ...[
                  if (!loudnessOk)
                    Text(
                      'Loudness ${reading.integratedLufs.toStringAsFixed(1)} LUFS vs target ${target.integratedTarget.toStringAsFixed(1)} ±${target.integratedTolerance.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  if (!truePeakOk)
                    Text(
                      'True-peak ${reading.truePeakDbtp.toStringAsFixed(1)} dBTP exceeds ceiling ${target.truePeakCeiling.toStringAsFixed(1)} dBTP',
                      style: const TextStyle(fontSize: 11),
                    ),
                ] else
                  Text(
                    'Loudness and true-peak within ${target.label} spec.',
                    style: const TextStyle(fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Real-time loudness reading (from analysis/loudness.rs).
class LoudnessReading {
  const LoudnessReading({
    required this.integratedLufs,
    required this.shortTermLufs,
    required this.momentaryLufs,
    required this.truePeakDbtp,
  });
  final double integratedLufs;
  final double shortTermLufs;
  final double momentaryLufs;
  final double truePeakDbtp;

  static const silent = LoudnessReading(
    integratedLufs: -70.0,
    shortTermLufs: -70.0,
    momentaryLufs: -70.0,
    truePeakDbtp: -70.0,
  );

  /// Returns true if this reading represents silence (no audio analyzed).
  /// Used by the UI to show "—" instead of misleading -70 LUFS values.
  bool get isSilent => integratedLufs <= -69.0 && truePeakDbtp <= -69.0;
}

/// Delivery spec target.
enum LoudnessTarget {
  ebuR128('EBU R128 (EU broadcast)', -23.0, 0.5, -1.0),
  atscA85('ATSC A/85 (US broadcast)', -24.0, 2.0, -2.0),
  youtube('YouTube', -14.0, 1.0, -1.0),
  tiktok('TikTok', -18.0, 1.0, -1.0),
  podcast('Apple Podcasts', -16.0, 1.0, -1.0);

  const LoudnessTarget(
    this.label,
    this.integratedTarget,
    this.integratedTolerance,
    this.truePeakCeiling,
  );
  final String label;
  final double integratedTarget;
  final double integratedTolerance;
  final double truePeakCeiling;
}
