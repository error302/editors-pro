import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/project_model.dart';
import '../../projects/providers/project_provider.dart';

/// Real-time audio level meter bridge — a horizontal bar displayed at
/// the bottom of the editor showing per-track VU meters, a master stereo
/// meter (L/R), peak hold indicators, dB scale markings, and clip
/// indicators.
///
/// The meter uses a 50ms Timer for smooth animation. Audio levels are
/// simulated from the track volume levels (in a production app, these
/// would come from the engine's audio analysis pipeline).
///
/// Color zones:
/// - Green: -60 dB to -20 dB
/// - Yellow: -20 dB to -6 dB
/// - Red: -6 dB to +6 dB
///
/// Clip indicator stays lit (red dot) if the level exceeds 0 dB.
class AudioMeterBridge extends ConsumerStatefulWidget {
  const AudioMeterBridge({super.key});

  @override
  ConsumerState<AudioMeterBridge> createState() => _AudioMeterBridgeState();
}

class _AudioMeterBridgeState extends ConsumerState<AudioMeterBridge> {
  Timer? _updateTimer;

  /// Current level for each track, keyed by track ID.
  /// Value is in dB, typically -60 to +6.
  final Map<String, double> _trackLevels = {};

  /// Peak hold for each track (the thin line that falls slowly).
  final Map<String, double> _trackPeaks = {};

  /// Clip indicator state per track (true if level exceeded 0 dB).
  final Map<String, bool> _trackClipped = {};

  /// Master L/R channel levels in dB.
  double _masterL = -60.0;
  double _masterR = -60.0;

  /// Master L/R peak hold in dB.
  double _masterPeakL = -60.0;
  double _masterPeakR = -60.0;

  /// Master clip indicators.
  bool _masterClippedL = false;
  bool _masterClippedR = false;

  /// Peak hold decay rate in dB per tick (50ms).
  static const double _peakDecayRate = 1.5;

  /// The dB floor (silence).
  static const double _dbFloor = -60.0;

  /// The dB ceiling (max display).
  static const double _dbCeiling = 6.0;

  @override
  void initState() {
    super.initState();
    _updateTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      _updateLevels();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  /// Update audio levels from the project tracks.
  ///
  /// In a real implementation, these levels would come from the Rust
  /// engine's audio analysis pipeline via a stream. Here we simulate
  /// levels based on track volume with some randomness to demonstrate
  /// the meter UI.
  void _updateLevels() {
    final project = ref.read(currentProjectProvider);
    if (project == null) return;

    final random = math.Random();
    var anyChange = false;

    for (final track in project.tracks) {
      final trackId = track.id;

      if (!track.visible) {
        // Muted track — silence
        if (_trackLevels[trackId] != _dbFloor) {
          _trackLevels[trackId] = _dbFloor;
          anyChange = true;
        }
        continue;
      }

      // Simulate audio level based on track volume with some randomness.
      // A track at volume 1.0 might produce levels around -12 to -3 dB.
      // A track at volume 0.5 might produce levels around -24 to -12 dB.
      final baseLevel =
          20 * math.log(track.volume) / math.ln2; // dBFS approximation
      final noise = (random.nextDouble() - 0.5) * 12; // ±6 dB jitter
      final level = (baseLevel + noise).clamp(_dbFloor, _dbCeiling);

      final oldLevel = _trackLevels[trackId] ?? _dbFloor;
      // Smooth the level change (fast attack, slow release)
      final smoothed = level > oldLevel
          ? level // Fast attack
          : oldLevel - (oldLevel - level).clamp(0.0, 4.0); // Slow release

      _trackLevels[trackId] = smoothed.clamp(_dbFloor, _dbCeiling);

      // Update peak hold
      final oldPeak = _trackPeaks[trackId] ?? _dbFloor;
      if (smoothed > oldPeak) {
        _trackPeaks[trackId] = smoothed;
      } else {
        _trackPeaks[trackId] =
            (oldPeak - _peakDecayRate).clamp(_dbFloor, _dbCeiling);
      }

      // Update clip indicator
      if (smoothed >= 0.0) {
        _trackClipped[trackId] = true;
        anyChange = true;
      }

      anyChange = true;
    }

    // Update master levels (sum of all audio tracks)
    final audioTracks = project.tracks.where(
      (t) => t.trackType == TrackType.audio || t.trackType == TrackType.video,
    );

    if (audioTracks.isEmpty) {
      _masterL = _dbFloor;
      _masterR = _dbFloor;
    } else {
      // Sum of squares approximation for combined level
      double sumSquares = 0;
      for (final track in audioTracks) {
        final level = _trackLevels[track.id] ?? _dbFloor;
        if (level > _dbFloor) {
          sumSquares += math.pow(10, level / 10); // Power domain
        }
      }
      final masterLevel = sumSquares > 0
          ? (10 * math.log(sumSquares) / math.ln2).clamp(_dbFloor, _dbCeiling)
          : _dbFloor;

      // Slight stereo separation for visual interest
      final stereoSpread = (random.nextDouble() - 0.5) * 3;
      _masterL = (masterLevel + stereoSpread).clamp(_dbFloor, _dbCeiling);
      _masterR = (masterLevel - stereoSpread).clamp(_dbFloor, _dbCeiling);
    }

    // Update master peak hold
    if (_masterL > _masterPeakL) {
      _masterPeakL = _masterL;
    } else {
      _masterPeakL =
          (_masterPeakL - _peakDecayRate).clamp(_dbFloor, _dbCeiling);
    }

    if (_masterR > _masterPeakR) {
      _masterPeakR = _masterR;
    } else {
      _masterPeakR =
          (_masterPeakR - _peakDecayRate).clamp(_dbFloor, _dbCeiling);
    }

    // Update master clip indicators
    if (_masterL >= 0.0) _masterClippedL = true;
    if (_masterR >= 0.0) _masterClippedR = true;

    if (anyChange) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(currentProjectProvider);
    final tracks = project?.tracks ?? [];

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // dB scale markings
          _buildDbScale(),

          // Vertical divider
          Container(width: 1, color: AppTheme.border),

          // Per-track VU meters
          Expanded(
            child: tracks.isEmpty
                ? const Center(
                    child: Text(
                      'No tracks',
                      style: TextStyle(
                        color: AppTheme.textDisabled,
                        fontSize: 10,
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    itemCount: tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      final level = _trackLevels[track.id] ?? _dbFloor;
                      final peak = _trackPeaks[track.id] ?? _dbFloor;
                      final clipped = _trackClipped[track.id] ?? false;
                      return _TrackMeter(
                        trackName: track.name,
                        trackType: track.trackType,
                        level: level,
                        peak: peak,
                        clipped: clipped,
                        onClearClip: () {
                          setState(() {
                            _trackClipped[track.id] = false;
                          });
                        },
                      );
                    },
                  ),
          ),

          // Vertical divider
          Container(width: 1, color: AppTheme.border),

          // Master stereo meter (L/R)
          _buildMasterMeter(),
        ],
      ),
    );
  }

  /// Build the dB scale markings on the left side.
  Widget _buildDbScale() {
    const markings = [-60, -40, -20, -10, -6, -3, 0, 3, 6];

    return SizedBox(
      width: 36,
      child: CustomPaint(
        painter: _DbScalePainter(markings: markings),
        size: Size.infinite,
      ),
    );
  }

  /// Build the master stereo meter (L/R channels).
  Widget _buildMasterMeter() {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          // Label
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'M',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              // Clip reset button
              if (_masterClippedL || _masterClippedR)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _masterClippedL = false;
                      _masterClippedR = false;
                    });
                  },
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.border,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),

          // L channel
          _StereoChannelMeter(
            label: 'L',
            level: _masterL,
            peak: _masterPeakL,
            clipped: _masterClippedL,
          ),
          const SizedBox(width: 2),

          // R channel
          _StereoChannelMeter(
            label: 'R',
            level: _masterR,
            peak: _masterPeakR,
            clipped: _masterClippedR,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Per-track VU meter
// ═══════════════════════════════════════════════════════════════════════

/// A thin vertical VU meter for a single track.
///
/// Shows:
/// - A filled bar indicating the current level (color-coded by zone)
/// - A thin peak hold line that falls slowly
/// - A clip indicator (red dot) if the level exceeded 0 dB
/// - The track name abbreviated below
class _TrackMeter extends StatelessWidget {
  const _TrackMeter({
    required this.trackName,
    required this.trackType,
    required this.level,
    required this.peak,
    required this.clipped,
    required this.onClearClip,
  });
  final String trackName;
  final TrackType trackType;
  final double level; // in dB
  final double peak; // in dB
  final bool clipped;
  final VoidCallback onClearClip;

  @override
  Widget build(BuildContext context) {
    final trackColor = _trackTypeColor(trackType);

    return GestureDetector(
      onTap: clipped ? onClearClip : null,
      child: Column(
        children: [
          // Meter bar
          Expanded(
            child: CustomPaint(
              painter: _VuMeterPainter(
                level: level,
                peak: peak,
                clipped: clipped,
                trackColor: trackColor,
              ),
              size: const Size(12, double.infinity),
            ),
          ),
          const SizedBox(height: 2),

          // Track name (abbreviated)
          Text(
            trackName.length > 3 ? trackName.substring(0, 3) : trackName,
            style: TextStyle(
              color: trackColor.withValues(alpha: 0.7),
              fontSize: 7,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _trackTypeColor(TrackType type) {
    switch (type) {
      case TrackType.video:
        return AppTheme.videoTrackColor;
      case TrackType.audio:
        return AppTheme.audioTrackColor;
      case TrackType.text:
        return AppTheme.textTrackColor;
      case TrackType.effect:
        return AppTheme.effectTrackColor;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Stereo channel meter (L/R for master)
// ═══════════════════════════════════════════════════════════════════════

/// A single channel meter for the master stereo display.
class _StereoChannelMeter extends StatelessWidget {
  const _StereoChannelMeter({
    required this.label,
    required this.level,
    required this.peak,
    required this.clipped,
  });
  final String label;
  final double level; // in dB
  final double peak; // in dB
  final bool clipped;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Label
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textDisabled,
            fontSize: 7,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 1),

        // Meter bar
        Expanded(
          child: CustomPaint(
            painter: _VuMeterPainter(
              level: level,
              peak: peak,
              clipped: clipped,
              trackColor: AppTheme.primary,
            ),
            size: const Size(16, double.infinity),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// VU Meter Painter
// ═══════════════════════════════════════════════════════════════════════

/// Custom painter that renders a vertical VU meter bar with color zones,
/// peak hold indicator, and clip indicator.
///
/// Color zones:
/// - Green: -60 dB to -20 dB
/// - Yellow: -20 dB to -6 dB
/// - Red: -6 dB to +6 dB
class _VuMeterPainter extends CustomPainter {
  _VuMeterPainter({
    required this.level,
    required this.peak,
    required this.clipped,
    required this.trackColor,
  });
  final double level; // in dB
  final double peak; // in dB
  final bool clipped;
  final Color trackColor;

  static const double _dbFloor = -60.0;
  static const double _dbCeiling = 6.0;

  // Zone boundaries in dB
  static const double _greenYellow = -20.0;
  static const double _yellowRed = -6.0;

  // Zone colors
  static const Color _greenColor = Color(0xFF00D9A0);
  static const Color _yellowColor = Color(0xFFFFB84D);
  static const Color _redColor = Color(0xFFFF5C5C);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final width = size.width;
    final height = size.height;

    // Background
    final bgPaint = Paint()..color = const Color(0xFF0A0A14);
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      Radius.circular(width / 4),
    );
    canvas.drawRRect(bgRect, bgPaint);

    // Calculate level as a fraction of the total range
    final levelFraction = _dbToFraction(level);
    final peakFraction = _dbToFraction(peak);

    // Draw segmented meter bars
    final segmentCount = (height / 3).floor(); // 3px segments with 1px gaps
    const segmentHeight = 2.0;
    const gapHeight = 1.0;
    const totalSegmentSpace = segmentHeight + gapHeight;

    for (var i = 0; i < segmentCount; i++) {
      // i=0 is the top (highest dB), i=segmentCount-1 is the bottom (lowest dB)
      final segmentFraction = 1.0 - (i / segmentCount);

      // Only draw segments up to the current level
      if (segmentFraction > levelFraction) continue;

      final y = height - (i + 1) * totalSegmentSpace;
      if (y < 0) break;

      final segmentDb = _fractionToDb(segmentFraction);
      final color = _zoneColor(segmentDb);

      canvas.drawRect(
        Rect.fromLTWH(1, y, width - 2, segmentHeight),
        Paint()..color = color,
      );
    }

    // Draw peak hold indicator (a thin bright line)
    if (peak > _dbFloor + 1) {
      final peakY = height * (1 - peakFraction);
      final peakColor = _zoneColor(_fractionToDb(peakFraction));
      canvas.drawLine(
        Offset(0, peakY),
        Offset(width, peakY),
        Paint()
          ..color = peakColor
          ..strokeWidth = 1.5,
      );
    }

    // Draw clip indicator (red dot at the top)
    if (clipped) {
      canvas.drawCircle(
        Offset(width / 2, 3),
        2.5,
        Paint()..color = _redColor,
      );
    }
  }

  /// Convert a dB value to a fraction (0.0 = silence, 1.0 = max).
  double _dbToFraction(double db) {
    if (db <= _dbFloor) return 0.0;
    if (db >= _dbCeiling) return 1.0;
    return (db - _dbFloor) / (_dbCeiling - _dbFloor);
  }

  /// Convert a fraction back to dB.
  double _fractionToDb(double fraction) {
    return _dbFloor + fraction * (_dbCeiling - _dbFloor);
  }

  /// Get the color for a given dB level.
  Color _zoneColor(double db) {
    if (db >= _yellowRed) return _redColor;
    if (db >= _greenYellow) return _yellowColor;
    return _greenColor;
  }

  @override
  bool shouldRepaint(covariant _VuMeterPainter oldDelegate) =>
      level != oldDelegate.level ||
      peak != oldDelegate.peak ||
      clipped != oldDelegate.clipped;
}

// ═══════════════════════════════════════════════════════════════════════
// dB Scale Painter
// ═══════════════════════════════════════════════════════════════════════

/// Custom painter that renders dB scale markings on the left side of
/// the meter bridge.
class _DbScalePainter extends CustomPainter {
  _DbScalePainter({required this.markings});
  final List<int> markings;

  static const double _dbFloor = -60.0;
  static const double _dbCeiling = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Draw tick marks and labels
    for (final db in markings) {
      final fraction = (db - _dbFloor) / (_dbCeiling - _dbFloor);
      final y = size.height * (1 - fraction);

      // Tick mark
      canvas.drawLine(
        Offset(size.width - 4, y),
        Offset(size.width, y),
        Paint()
          ..color = AppTheme.textDisabled.withValues(alpha: 0.4)
          ..strokeWidth = 0.5,
      );

      // Label
      final label = db >= 0 ? '+$db' : '$db';
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: db >= 0
              ? AppTheme.error.withValues(alpha: 0.7)
              : AppTheme.textDisabled.withValues(alpha: 0.6),
          fontSize: 6,
          fontFamily: 'monospace',
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(size.width - 6 - textPainter.width, y - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DbScalePainter oldDelegate) =>
      markings != oldDelegate.markings;
}
