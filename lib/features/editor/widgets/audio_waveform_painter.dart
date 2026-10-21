import 'dart:math' as math;
import 'package:flutter/material.dart';

/// CustomPainter that draws an audio waveform visualization.
///
/// Renders peak values as vertical bars centered vertically within
/// the given size. The waveform is drawn with a gradient effect
/// and supports different color schemes for different track types.
class AudioWaveformPainter extends CustomPainter {
  const AudioWaveformPainter({
    required this.peaks,
    required this.color,
    this.rmsValues,
    this.showCenterLine = true,
    this.barWidthRatio = 0.7,
  });

  /// Peak amplitude values (0.0 to 1.0)
  final List<double> peaks;

  /// Color for the waveform bars
  final Color color;

  /// Whether to draw RMS values as a filled area behind the peaks
  final List<double>? rmsValues;

  /// Whether to show the center line
  final bool showCenterLine;

  /// Bar width ratio (0.0 to 1.0, where 1.0 means bars touch)
  final double barWidthRatio;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;

    // Draw center line
    if (showCenterLine) {
      final centerPaint = Paint()
        ..color = color.withValues(alpha: 0.15)
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        centerPaint,
      );
    }

    // Draw RMS fill area if provided
    if (rmsValues != null && rmsValues!.isNotEmpty) {
      final rmsPath = Path();
      final barWidth = size.width / peaks.length;
      final halfHeight = size.height / 2;

      rmsPath.moveTo(0, halfHeight);
      for (var i = 0; i < rmsValues!.length && i < peaks.length; i++) {
        final x = i * barWidth + barWidth / 2;
        final rmsHeight = (rmsValues![i] * halfHeight).clamp(0.0, halfHeight);
        rmsPath.lineTo(x, halfHeight - rmsHeight);
      }
      // Mirror back
      for (var i = math.min(rmsValues!.length, peaks.length) - 1; i >= 0; i--) {
        final x = i * barWidth + barWidth / 2;
        final rmsHeight = (rmsValues![i] * halfHeight).clamp(0.0, halfHeight);
        rmsPath.lineTo(x, halfHeight + rmsHeight);
      }
      rmsPath.close();

      paint.color = color.withValues(alpha: 0.2);
      canvas.drawPath(rmsPath, paint);
    }

    // Draw peak bars
    final barWidth = size.width / peaks.length;
    final actualBarWidth = barWidth * barWidthRatio;
    final halfHeight = size.height / 2;
    final gap = (barWidth - actualBarWidth) / 2;

    for (var i = 0; i < peaks.length; i++) {
      final peak = peaks[i].clamp(0.0, 1.0);
      if (peak < 0.001) continue; // Skip silent bars

      final barHeight = peak * halfHeight;
      final x = i * barWidth + gap;

      // Top half bar (mirrored waveform)
      final topRect = Rect.fromCenter(
        center: Offset(x + actualBarWidth / 2, halfHeight - barHeight / 2),
        width: actualBarWidth,
        height: barHeight,
      );

      // Bottom half bar (mirror)
      final bottomRect = Rect.fromCenter(
        center: Offset(x + actualBarWidth / 2, halfHeight + barHeight / 2),
        width: actualBarWidth,
        height: barHeight,
      );

      // Gradient effect: brighter at the center, dimmer at edges
      final alpha = 0.4 + peak * 0.5; // Louder = brighter
      paint.color = color.withValues(alpha: alpha.clamp(0.3, 0.9));

      // Draw rounded bars
      final radius = Radius.circular(actualBarWidth / 2);
      canvas.drawRRect(RRect.fromRectAndRadius(topRect, radius), paint);
      canvas.drawRRect(RRect.fromRectAndRadius(bottomRect, radius), paint);
    }
  }

  @override
  bool shouldRepaint(covariant AudioWaveformPainter oldDelegate) {
    return oldDelegate.peaks != peaks ||
        oldDelegate.color != color ||
        oldDelegate.rmsValues != rmsValues;
  }
}

/// A widget that displays an audio waveform.
///
/// This widget wraps [AudioWaveformPainter] in a [CustomPaint]
/// and provides a convenient interface for displaying waveforms
/// on audio clips in the timeline.
class AudioWaveformWidget extends StatelessWidget {
  const AudioWaveformWidget({
    required this.peaks,
    required this.color,
    required this.width,
    required this.height,
    super.key,
    this.rmsValues,
  });

  /// Peak amplitude values (0.0 to 1.0)
  final List<double> peaks;

  /// RMS energy values (0.0 to 1.0), optional
  final List<double>? rmsValues;

  /// Color for the waveform
  final Color color;

  /// Width of the widget
  final double width;

  /// Height of the widget
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: AudioWaveformPainter(
          peaks: peaks,
          color: color,
          rmsValues: rmsValues,
        ),
      ),
    );
  }
}
