import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase F: Color Scopes panel.
///
/// Renders four broadcast-grade scopes from the current frame:
/// - Waveform (Y luma distribution per column)
/// - Vectorscope (Cb-Cr chroma plane)
/// - RGB Parade (three waveforms for R, G, B)
/// - Histogram (luma distribution)
///
/// Plus a "legal range" overlay showing the 16–235 luma band.
///
/// The amateur move is to grade by eye on an uncalibrated screen. The pro
/// move is to grade to the scopes. See persona/skills/color-scopes/SKILL.md.
class ColorScopesPanel extends StatefulWidget {
  const ColorScopesPanel({
    required this.onRequestRefresh,
    super.key,
    this.scopes,
  });

  /// Called when the user wants to refresh the scopes from the current frame.
  /// The parent should call `compute_scopes` via the bridge and pass the
  /// resulting `Scopes` data to this widget via `scopes`.
  final VoidCallback onRequestRefresh;

  /// Pre-computed scopes data (from `compute_scopes` bridge method).
  /// If null, the widget shows a placeholder prompting the user to refresh.
  final ScopesData? scopes;

  @override
  State<ColorScopesPanel> createState() => _ColorScopesPanelState();
}

class _ColorScopesPanelState extends State<ColorScopesPanel> {
  ScopeType _selected = ScopeType.waveform;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Color Scopes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: widget.onRequestRefresh,
              tooltip: 'Refresh from current frame',
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing8),
        // Scope type selector
        SegmentedButton<ScopeType>(
          segments: const [
            ButtonSegment(value: ScopeType.waveform, label: Text('Waveform')),
            ButtonSegment(
              value: ScopeType.vectorscope,
              label: Text('Vectorscope'),
            ),
            ButtonSegment(
              value: ScopeType.rgbParade,
              label: Text('RGB Parade'),
            ),
            ButtonSegment(value: ScopeType.histogram, label: Text('Histogram')),
          ],
          selected: {_selected},
          onSelectionChanged: (s) => setState(() => _selected = s.first),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Scope canvas
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(
                color: AppTheme.textSecondary.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: widget.scopes == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.analytics_outlined,
                          size: 48,
                          color: AppTheme.textSecondary,
                        ),
                        SizedBox(height: AppTheme.spacing8),
                        Text(
                          'Tap refresh to compute scopes',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  )
                : CustomPaint(
                    painter: _ScopePainter(
                      scopeType: _selected,
                      data: widget.scopes!,
                    ),
                    child: const SizedBox.expand(),
                  ),
          ),
        ),
        const SizedBox(height: AppTheme.spacing8),
        // Safety reminder
        if (_selected == ScopeType.waveform || _selected == ScopeType.rgbParade)
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: AppTheme.spacing8),
                Expanded(
                  child: Text(
                    'Blue lines = legal range (16–235 luma). '
                    'Pixels outside need a legalizer pass in full/ultra mode.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum ScopeType { waveform, vectorscope, rgbParade, histogram }

/// Plain-Dart representation of the scopes data (mirrors the Rust struct).
/// The bridge call returns JSON; the parent widget parses it into this.
class ScopesData {
  ScopesData({
    required this.waveform,
    required this.vectorscope,
    required this.rgbParade,
    required this.histogram,
  });
  final WaveformData waveform;
  final VectorscopeData vectorscope;
  final RgbParadeData rgbParade;
  final HistogramData histogram;
}

class WaveformData {
  // width × 256
  WaveformData({required this.width, required this.columns});
  final int width;
  final List<List<int>> columns;
}

class VectorscopeData {
  // size × size
  VectorscopeData({required this.size, required this.grid});
  final int size;
  final List<int> grid;
}

class RgbParadeData {
  RgbParadeData({
    required this.width,
    required this.red,
    required this.green,
    required this.blue,
  });
  final int width;
  final List<List<int>> red, green, blue;
}

class HistogramData {
  // 256
  HistogramData({required this.bins});
  final List<int> bins;
}

/// Paints the selected scope on a black canvas.
class _ScopePainter extends CustomPainter {
  _ScopePainter({required this.scopeType, required this.data});
  final ScopeType scopeType;
  final ScopesData data;

  @override
  void paint(Canvas canvas, Size size) {
    switch (scopeType) {
      case ScopeType.waveform:
        _paintWaveform(canvas, size, data.waveform);
        _paintLegalRangeOverlay(canvas, size);
        break;
      case ScopeType.vectorscope:
        _paintVectorscope(canvas, size, data.vectorscope);
        _paintVectorscopeOverlay(canvas, size);
        break;
      case ScopeType.rgbParade:
        _paintRgbParade(canvas, size, data.rgbParade);
        _paintLegalRangeOverlay(canvas, size);
        break;
      case ScopeType.histogram:
        _paintHistogram(canvas, size, data.histogram);
        _paintLegalRangeOverlay(canvas, size);
        break;
    }
  }

  void _paintWaveform(Canvas canvas, Size size, WaveformData wf) {
    final paint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;
    final maxCount = wf.columns
        .expand((c) => c)
        .fold(0, (a, b) => a > b ? a : b)
        .toDouble()
        .clamp(1.0, double.infinity);
    final colWidth = size.width / wf.width;
    final rowHeight = size.height / 256.0;
    for (var x = 0; x < wf.width; x++) {
      for (var y = 0; y < 256; y++) {
        final count = wf.columns[x][y];
        if (count == 0) continue;
        final alpha = (count / maxCount).clamp(0.0, 1.0);
        paint.color = Colors.green.withValues(alpha: alpha);
        canvas.drawRect(
          Rect.fromLTWH(
            x * colWidth,
            (255 - y) * rowHeight,
            colWidth + 1,
            rowHeight + 1,
          ),
          paint,
        );
      }
    }
  }

  void _paintVectorscope(Canvas canvas, Size size, VectorscopeData vs) {
    final paint = Paint()..style = PaintingStyle.fill;
    final maxCount = vs.grid
        .fold(0, (a, b) => a > b ? a : b)
        .toDouble()
        .clamp(1.0, double.infinity);
    final cellSize = size.shortestSide / vs.size;
    final offsetX = (size.width - cellSize * vs.size) / 2;
    final offsetY = (size.height - cellSize * vs.size) / 2;
    for (var y = 0; y < vs.size; y++) {
      for (var x = 0; x < vs.size; x++) {
        final count = vs.grid[y * vs.size + x];
        if (count == 0) continue;
        final alpha = (count / maxCount).clamp(0.0, 1.0);
        paint.color = Colors.green.withValues(alpha: alpha);
        canvas.drawRect(
          Rect.fromLTWH(
            offsetX + x * cellSize,
            offsetY + y * cellSize,
            cellSize + 1,
            cellSize + 1,
          ),
          paint,
        );
      }
    }
  }

  void _paintVectorscopeOverlay(Canvas canvas, Size size) {
    // Skin tone I-line at ~123° from R (between R and Y on the vectorscope).
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    const angle =
        (123.0 + 90.0) * math.pi / 180.0; // adjust for canvas orientation
    final paint = Paint()
      ..color = Colors.yellow.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(
      center,
      Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      ),
      paint,
    );
    // Center cross
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(center.dx - 10, center.dy),
      Offset(center.dx + 10, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 10),
      Offset(center.dx, center.dy + 10),
      crossPaint,
    );
  }

  void _paintRgbParade(Canvas canvas, Size size, RgbParadeData parade) {
    final third = size.width / 3;
    _paintSingleParade(
      canvas,
      Rect.fromLTWH(0, 0, third, size.height),
      parade.red,
      Colors.red,
    );
    _paintSingleParade(
      canvas,
      Rect.fromLTWH(third, 0, third, size.height),
      parade.green,
      Colors.green,
    );
    _paintSingleParade(
      canvas,
      Rect.fromLTWH(third * 2, 0, third, size.height),
      parade.blue,
      Colors.blue,
    );
  }

  void _paintSingleParade(
    Canvas canvas,
    Rect rect,
    List<List<int>> data,
    Color color,
  ) {
    final paint = Paint()..style = PaintingStyle.fill;
    final maxCount = data
        .expand((c) => c)
        .fold(0, (a, b) => a > b ? a : b)
        .toDouble()
        .clamp(1.0, double.infinity);
    final colWidth = rect.width / data.length;
    final rowHeight = rect.height / 256.0;
    for (var x = 0; x < data.length; x++) {
      for (var y = 0; y < 256; y++) {
        final count = data[x][y];
        if (count == 0) continue;
        final alpha = (count / maxCount).clamp(0.0, 1.0);
        paint.color = color.withValues(alpha: alpha);
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left + x * colWidth,
            rect.top + (255 - y) * rowHeight,
            colWidth + 1,
            rowHeight + 1,
          ),
          paint,
        );
      }
    }
  }

  void _paintHistogram(Canvas canvas, Size size, HistogramData hist) {
    final maxCount = hist.bins
        .fold(0, (a, b) => a > b ? a : b)
        .toDouble()
        .clamp(1.0, double.infinity);
    final paint = Paint()
      ..color = Colors.green.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    final barWidth = size.width / 256.0;
    for (var i = 0; i < 256; i++) {
      final h = (hist.bins[i] / maxCount) * size.height;
      canvas.drawRect(
        Rect.fromLTWH(i * barWidth, size.height - h, barWidth + 1, h),
        paint,
      );
    }
  }

  void _paintLegalRangeOverlay(Canvas canvas, Size size) {
    // 16/255 and 235/255 of height
    final top = size.height * (1.0 - 235 / 255.0);
    final bottom = size.height * (1.0 - 16 / 255.0);
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, top), Offset(size.width, top), paint);
    canvas.drawLine(Offset(0, bottom), Offset(size.width, bottom), paint);
  }

  @override
  bool shouldRepaint(covariant _ScopePainter oldDelegate) =>
      scopeType != oldDelegate.scopeType || data != oldDelegate.data;
}
