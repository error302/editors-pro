import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/editor_provider.dart';

// ─── Scope Tab Enum ──────────────────────────────────────────────────────────

enum ScopeTab { waveform, histogram, vectorscope }

enum ScopeRefreshRate { fps15, fps30, freeze }

// ─── Video Scopes Panel ──────────────────────────────────────────────────────

/// Professional video scopes panel for EDITORS-PRO.
///
/// Displays three scope views (Waveform Monitor, Histogram, Vectorscope)
/// switchable via tabs. Uses CustomPainter for GPU-efficient rendering
/// and simulates scope data from a time-based seed for realistic visuals.
class VideoScopesPanel extends ConsumerStatefulWidget {
  const VideoScopesPanel({super.key});

  @override
  ConsumerState<VideoScopesPanel> createState() => _VideoScopesPanelState();
}

class _VideoScopesPanelState extends ConsumerState<VideoScopesPanel>
    with SingleTickerProviderStateMixin {
  ScopeTab _currentTab = ScopeTab.waveform;
  ScopeRefreshRate _refreshRate = ScopeRefreshRate.fps30;
  double _gain = 1.0;

  int _seed = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _updateSeed();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _updateSeed() {
    _seed = DateTime.now().millisecondsSinceEpoch ~/ 33; // ~30fps granularity
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    if (_refreshRate == ScopeRefreshRate.freeze) return;

    final intervalMs = _refreshRate == ScopeRefreshRate.fps15 ? 67 : 33;
    _refreshTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (mounted) {
        _updateSeed();
        setState(() {});
      }
    });
  }

  void _onRefreshRateChanged(ScopeRefreshRate rate) {
    setState(() {
      _refreshRate = rate;
    });
    _startRefreshTimer();
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Tab Bar ───────────────────────────────────────────────
          _buildTabBar(),

          // ── Scope Display ─────────────────────────────────────────
          _buildScopeDisplay(editorState),

          // ── Controls Bar ──────────────────────────────────────────
          _buildControlsBar(),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xFF12121B),
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusMedium)),
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: Row(
        children: ScopeTab.values.map((tab) {
          final isActive = _currentTab == tab;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentTab = tab),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      isActive ? const Color(0xFF1a1a2e) : Colors.transparent,
                  border: isActive
                      ? const Border(
                          bottom: BorderSide(color: AppTheme.primary, width: 2),
                        )
                      : null,
                ),
                child: Text(
                  _tabLabel(tab),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _tabLabel(ScopeTab tab) {
    switch (tab) {
      case ScopeTab.waveform:
        return 'WAVEFORM';
      case ScopeTab.histogram:
        return 'HISTOGRAM';
      case ScopeTab.vectorscope:
        return 'VECTORSCOPE';
    }
  }

  Widget _buildScopeDisplay(EditorState editorState) {
    // Freeze seed when playback is paused for stable reference
    final effectiveSeed = editorState.isPlaying ? _seed : _seed;

    return SizedBox(
      width: 300,
      height: 200,
      child: CustomPaint(
        painter: _buildPainter(effectiveSeed),
      ),
    );
  }

  CustomPainter _buildPainter(int effectiveSeed) {
    switch (_currentTab) {
      case ScopeTab.waveform:
        return WaveformPainter(seed: effectiveSeed, gain: _gain);
      case ScopeTab.histogram:
        return HistogramPainter(seed: effectiveSeed, gain: _gain);
      case ScopeTab.vectorscope:
        return VectorscopePainter(seed: effectiveSeed, gain: _gain);
    }
  }

  Widget _buildControlsBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF12121B),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppTheme.radiusMedium),
        ),
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: Row(
        children: [
          // Refresh rate selector
          _buildRefreshRateSelector(),
          const SizedBox(width: 12),
          // Gain label
          const Text(
            'GAIN',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              fontFamily: 'Inter',
              letterSpacing: 0.5,
            ),
          ),
          // Gain slider
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: AppTheme.primary,
                thumbColor: AppTheme.primaryLight,
                inactiveTrackColor: AppTheme.border,
                trackHeight: 2,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: _gain,
                min: 0.2,
                max: 4.0,
                onChanged: (v) => setState(() => _gain = v),
              ),
            ),
          ),
          // Gain value readout
          SizedBox(
            width: 32,
            child: Text(
              '${_gain.toStringAsFixed(1)}x',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
                fontFamily: 'Inter',
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshRateSelector() {
    return PopupMenuButton<ScopeRefreshRate>(
      initialValue: _refreshRate,
      onSelected: _onRefreshRateChanged,
      constraints: const BoxConstraints(minWidth: 100),
      offset: const Offset(0, 28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.speed, size: 12, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              _refreshRateLabel(_refreshRate),
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const Icon(
              Icons.arrow_drop_down,
              size: 12,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => ScopeRefreshRate.values
          .map(
            (rate) => PopupMenuItem(
              value: rate,
              height: 28,
              child: Text(
                _refreshRateLabel(rate),
                style: const TextStyle(fontSize: 11, fontFamily: 'Inter'),
              ),
            ),
          )
          .toList(),
    );
  }

  String _refreshRateLabel(ScopeRefreshRate rate) {
    switch (rate) {
      case ScopeRefreshRate.fps15:
        return '15 fps';
      case ScopeRefreshRate.fps30:
        return '30 fps';
      case ScopeRefreshRate.freeze:
        return 'FREEZE';
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// WAVEFORM MONITOR PAINTER
// ═════════════════════════════════════════════════════════════════════════════

/// Paints a professional waveform monitor showing luma levels (0-100 IRE)
/// for each column of the frame. Classic green CRT trace on dark background
/// with IRE scale markings and graticule lines.
class WaveformPainter extends CustomPainter {
  WaveformPainter({required this.seed, required this.gain});
  final int seed;
  final double gain;

  @override
  void paint(Canvas canvas, Size size) {
    // ── Background ──────────────────────────────────────────────────
    final bgPaint = Paint()..color = const Color(0xFF0d0d1a);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // ── Graticule (grid) ────────────────────────────────────────────
    _drawGraticule(canvas, size);

    // ── IRE Scale Labels ────────────────────────────────────────────
    _drawIRELabels(canvas, size);

    // ── Waveform Trace ──────────────────────────────────────────────
    _drawWaveformTrace(canvas, size);
  }

  void _drawGraticule(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF2a2a3e)
      ..strokeWidth = 0.5;

    // Horizontal IRE lines at 0, 10, 25, 50, 75, 100
    final ireLines = [0.0, 10.0, 25.0, 50.0, 75.0, 100.0];
    for (final ire in ireLines) {
      final y = _ireToY(ire, size.height);
      final isMajor = ire == 0.0 || ire == 50.0 || ire == 100.0;
      canvas.drawLine(
        Offset(28, y),
        Offset(size.width, y),
        gridPaint
          ..color = isMajor ? const Color(0xFF3a3a52) : const Color(0xFF1e1e34),
      );
    }

    // Vertical column guides (every 60px)
    for (var x = 28.0 + 60.0; x < size.width; x += 60.0) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint..color = const Color(0xFF1e1e34),
      );
    }

    // Superblack / legal limit dashed line at 0 IRE and 100 IRE
    final legalPaint = Paint()
      ..color = const Color(0xFF5c3a3a)
      ..strokeWidth = 1.0;
    _drawDashedLine(
      canvas,
      Offset(28, _ireToY(0, size.height)),
      Offset(size.width, _ireToY(0, size.height)),
      legalPaint,
    );
    _drawDashedLine(
      canvas,
      Offset(28, _ireToY(100, size.height)),
      Offset(size.width, _ireToY(100, size.height)),
      legalPaint,
    );
  }

  void _drawIRELabels(Canvas canvas, Size size) {
    const labelStyle = TextStyle(
      color: Color(0xFF6a6a8a),
      fontSize: 8,
      fontFamily: 'Inter',
      fontWeight: FontWeight.w500,
    );

    final labels = {0: '0', 10: '10', 25: '25', 50: '50', 75: '75', 100: '100'};
    for (final entry in labels.entries) {
      final y = _ireToY(entry.key.toDouble(), size.height);
      final tp = TextPainter(
        text: TextSpan(text: entry.value, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }
  }

  void _drawWaveformTrace(Canvas canvas, Size size) {
    final random = Random(seed);
    final traceWidth = size.width - 28; // leave room for IRE labels
    const traceStartX = 28.0;
    final colCount = traceWidth.toInt();

    // Generate luma data per column — simulates a real video signal
    // with bright peaks, dark valleys, and midtone regions.
    final lumaData = List.generate(colCount, (col) {
      // Base signal: creates natural-looking waveform envelope
      final normalizedX = col / colCount;

      // Create a scene-like luma distribution:
      // Left side: midtones (interior shot)
      // Center: bright peak (sky/window)
      // Right: darker region (shadows)
      double base;
      if (normalizedX < 0.3) {
        base = 40 + 15 * sin(normalizedX * pi * 3); // interior midtones
      } else if (normalizedX < 0.6) {
        base = 70 + 10 * sin(normalizedX * pi * 5); // bright window
      } else {
        base = 30 + 20 * sin(normalizedX * pi * 4); // shadows
      }

      // Add per-column noise to simulate real pixel column variance
      final noise = (random.nextDouble() - 0.5) * 20 * gain;

      // Add fine detail — multiple frequency components
      final detail1 = sin(normalizedX * pi * 17 + seed * 0.001) * 5;
      final detail2 = cos(normalizedX * pi * 31 + seed * 0.002) * 3;
      final detail3 = sin(normalizedX * pi * 53 + seed * 0.003) * 2;

      return (base + noise + detail1 + detail2 + detail3).clamp(0.0, 100.0);
    });

    // Draw glow layer (wider, dimmer)
    final glowPaint = Paint()
      ..color = const Color(0xFF00ff41)
          .withValues(alpha: (0.12 * gain.clamp(0.2, 2.0)).clamp(0.0, 1.0))
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final glowPath = Path();
    for (var i = 0; i < colCount; i++) {
      final x = traceStartX + i.toDouble();
      final y = _ireToY(lumaData[i], size.height);
      if (i == 0) {
        glowPath.moveTo(x, y);
      } else {
        glowPath.lineTo(x, y);
      }
    }
    canvas.drawPath(glowPath, glowPaint);

    // Draw main trace line (bright green, CRT style)
    final tracePaint = Paint()
      ..color = const Color(0xFF00ff41)
          .withValues(alpha: (0.85 * gain.clamp(0.2, 2.0)).clamp(0.0, 1.0))
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final tracePath = Path();
    for (var i = 0; i < colCount; i++) {
      final x = traceStartX + i.toDouble();
      final y = _ireToY(lumaData[i], size.height);
      if (i == 0) {
        tracePath.moveTo(x, y);
      } else {
        tracePath.lineTo(x, y);
      }
    }
    canvas.drawPath(tracePath, tracePaint);

    // Draw brighter peak emphasis at high-IRE areas
    final peakPaint = Paint()
      ..color = const Color(0xFF66ff88)
          .withValues(alpha: (0.5 * gain.clamp(0.2, 2.0)).clamp(0.0, 1.0))
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final peakPath = Path();
    var peakStarted = false;
    for (var i = 0; i < colCount; i++) {
      if (lumaData[i] > 65 * gain.clamp(0.2, 2.0).clamp(0.0, 1.5)) {
        final x = traceStartX + i.toDouble();
        final y = _ireToY(lumaData[i], size.height);
        if (!peakStarted) {
          peakPath.moveTo(x, y);
          peakStarted = true;
        } else {
          peakPath.lineTo(x, y);
        }
      } else {
        peakStarted = false;
      }
    }
    canvas.drawPath(peakPath, peakPaint);
  }

  double _ireToY(double ire, double height) {
    // 0 IRE at bottom, 100 IRE at top, with small padding
    const topPad = 8.0;
    const bottomPad = 8.0;
    final drawHeight = height - topPad - bottomPad;
    return topPad + drawHeight * (1.0 - ire / 110.0); // 110 to give headroom
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLen = 6.0;
    const gapLen = 4.0;
    double current = 0;
    final totalLen = (end - start).distance;
    final dx = (end.dx - start.dx) / totalLen;
    final dy = (end.dy - start.dy) / totalLen;

    while (current < totalLen) {
      final segEnd = min(current + dashLen, totalLen);
      canvas.drawLine(
        Offset(start.dx + dx * current, start.dy + dy * current),
        Offset(start.dx + dx * segEnd, start.dy + dy * segEnd),
        paint,
      );
      current += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.seed != seed || oldDelegate.gain != gain;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HISTOGRAM PAINTER
// ═════════════════════════════════════════════════════════════════════════════

/// Paints a professional histogram showing the distribution of R, G, B,
/// and Luma channels. Each channel is rendered as a filled area with
/// semi-transparent color, overlapping to show channel interaction.
class HistogramPainter extends CustomPainter {
  HistogramPainter({required this.seed, required this.gain});
  final int seed;
  final double gain;

  @override
  void paint(Canvas canvas, Size size) {
    // ── Background ──────────────────────────────────────────────────
    final bgPaint = Paint()..color = const Color(0xFF0d0d1a);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // ── Grid ────────────────────────────────────────────────────────
    _drawGrid(canvas, size);

    // ── Generate histogram data for each channel ────────────────────
    final random = Random(seed);

    final lumaData = _generateChannel(random, _ChannelType.luma);
    final redData = _generateChannel(random, _ChannelType.red);
    final greenData = _generateChannel(random, _ChannelType.green);
    final blueData = _generateChannel(random, _ChannelType.blue);

    // ── Draw channels back-to-front: Luma, Blue, Green, Red ─────────
    _drawChannel(canvas, size, lumaData, const Color(0xFFcccccc), 0.25);
    _drawChannel(canvas, size, blueData, const Color(0xFF4488ff), 0.4);
    _drawChannel(canvas, size, greenData, const Color(0xFF44ff88), 0.4);
    _drawChannel(canvas, size, redData, const Color(0xFFff4466), 0.4);

    // ── Scale labels ────────────────────────────────────────────────
    _drawScaleLabels(canvas, size);

    // ── Channel legend ──────────────────────────────────────────────
    _drawLegend(canvas, size);
  }

  List<double> _generateChannel(Random random, _ChannelType type) {
    // 256 bins (0-255 luma values)
    const binCount = 256;
    final bins = List<double>.filled(binCount, 0);

    // Create realistic distribution: mixture of Gaussians
    // Different channels have different distributions to simulate real video
    final peaks = <List<double>>[];

    switch (type) {
      case _ChannelType.luma:
        // Typical luma: strong midtone peak, shoulder in highlights
        peaks.add([128, 40, 0.8]); // center, sigma, amplitude
        peaks.add([200, 25, 0.4]); // highlight shoulder
        peaks.add([30, 15, 0.2]); // shadow detail
        break;
      case _ChannelType.red:
        peaks.add([140, 35, 0.7]);
        peaks.add([210, 20, 0.5]); // skin tone red push
        peaks.add([45, 18, 0.15]);
        break;
      case _ChannelType.green:
        peaks.add([115, 30, 0.65]);
        peaks.add([180, 25, 0.35]);
        peaks.add([60, 20, 0.2]);
        break;
      case _ChannelType.blue:
        peaks.add([100, 35, 0.5]); // blue often lower
        peaks.add([160, 28, 0.3]);
        peaks.add([30, 12, 0.25]); // shadow blue
        break;
    }

    // Evaluate Gaussian mixture
    for (var i = 0; i < binCount; i++) {
      double val = 0;
      for (final peak in peaks) {
        final center = peak[0];
        final sigma = peak[1];
        final amplitude = peak[2];
        val += amplitude * exp(-pow(i - center, 2) / (2 * sigma * sigma));
      }
      bins[i] = val;
    }

    // Add noise for realism
    for (var i = 0; i < binCount; i++) {
      bins[i] += (random.nextDouble() - 0.5) * 0.03;
      bins[i] = bins[i].clamp(0.0, 1.0);
    }

    return bins;
  }

  void _drawChannel(
    Canvas canvas,
    Size size,
    List<double> data,
    Color color,
    double alpha,
  ) {
    const leftPad = 28.0;
    const topPad = 8.0;
    const bottomPad = 16.0;
    final drawWidth = size.width - leftPad - 4;
    final drawHeight = size.height - topPad - bottomPad;

    // Find peak for normalization (apply gain)
    double peak = 0;
    for (final v in data) {
      if (v > peak) peak = v;
    }
    final normFactor = peak > 0 ? 1.0 / (peak / gain.clamp(0.2, 4.0)) : 1.0;

    // Build filled path
    final path = Path();
    path.moveTo(leftPad, size.height - bottomPad);

    for (var i = 0; i < data.length; i++) {
      final x = leftPad + (i / (data.length - 1)) * drawWidth;
      final h = (data[i] * normFactor).clamp(0.0, 1.0) * drawHeight;
      final y = size.height - bottomPad - h;
      path.lineTo(x, y);
    }

    path.lineTo(leftPad + drawWidth, size.height - bottomPad);
    path.close();

    // Fill
    final fillPaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Stroke outline
    final strokePath = Path();
    for (var i = 0; i < data.length; i++) {
      final x = leftPad + (i / (data.length - 1)) * drawWidth;
      final h = (data[i] * normFactor).clamp(0.0, 1.0) * drawHeight;
      final y = size.height - bottomPad - h;
      if (i == 0) {
        strokePath.moveTo(x, y);
      } else {
        strokePath.lineTo(x, y);
      }
    }

    final strokePaint = Paint()
      ..color = color.withValues(alpha: alpha + 0.2)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(strokePath, strokePaint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    const leftPad = 28.0;
    const topPad = 8.0;
    const bottomPad = 16.0;
    final drawWidth = size.width - leftPad - 4;
    final drawHeight = size.height - topPad - bottomPad;

    final gridPaint = Paint()
      ..color = const Color(0xFF2a2a3e)
      ..strokeWidth = 0.5;

    // Horizontal lines
    for (var i = 0; i <= 4; i++) {
      final y = topPad + (drawHeight / 4) * i;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + drawWidth, y),
        gridPaint,
      );
    }

    // Vertical lines at 0, 64, 128, 192, 255
    for (final v in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final x = leftPad + v * drawWidth;
      canvas.drawLine(
        Offset(x, topPad),
        Offset(x, size.height - bottomPad),
        gridPaint,
      );
    }
  }

  void _drawScaleLabels(Canvas canvas, Size size) {
    const leftPad = 28.0;
    const bottomPad = 16.0;
    final drawWidth = size.width - leftPad - 4;

    const labelStyle = TextStyle(
      color: Color(0xFF6a6a8a),
      fontSize: 7,
      fontFamily: 'Inter',
      fontWeight: FontWeight.w500,
    );

    final values = {0: '0', 64: '64', 128: '128', 192: '192', 255: '255'};
    for (final entry in values.entries) {
      final x = leftPad + (entry.key / 255.0) * drawWidth;
      final tp = TextPainter(
        text: TextSpan(text: entry.value, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - bottomPad + 3));
    }

    // Y-axis label
    const yLabelStyle = TextStyle(
      color: Color(0xFF6a6a8a),
      fontSize: 7,
      fontFamily: 'Inter',
      fontWeight: FontWeight.w500,
    );
    final yTp = TextPainter(
      text: const TextSpan(text: '%', style: yLabelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    yTp.paint(canvas, const Offset(2, 4));
  }

  void _drawLegend(Canvas canvas, Size size) {
    const items = [
      ('L', Color(0xFFcccccc)),
      ('R', Color(0xFFff4466)),
      ('G', Color(0xFF44ff88)),
      ('B', Color(0xFF4488ff)),
    ];

    var x = size.width - 8;
    const y = 10.0;

    for (final item in items.reversed) {
      final tp = TextPainter(
        text: TextSpan(
          text: item.$1,
          style: TextStyle(
            color: item.$2,
            fontSize: 8,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      x -= tp.width;
      tp.paint(canvas, Offset(x, y));
      x -= 8;
      // Color dot
      canvas.drawCircle(Offset(x + 3, y + 4), 2.5, Paint()..color = item.$2);
      x -= 8;
    }
  }

  @override
  bool shouldRepaint(covariant HistogramPainter oldDelegate) {
    return oldDelegate.seed != seed || oldDelegate.gain != gain;
  }
}

enum _ChannelType { luma, red, green, blue }

// ═════════════════════════════════════════════════════════════════════════════
// VECTORSCOPE PAINTER
// ═════════════════════════════════════════════════════════════════════════════

/// Paints a professional vectorscope showing chrominance on the standard
/// U/V plot. Includes the reference color wheel, color target boxes for
/// primary/secondary colors, and the skin tone line.
class VectorscopePainter extends CustomPainter {
  VectorscopePainter({required this.seed, required this.gain});
  final int seed;
  final double gain;

  // Standard ITU-R BT.709 vectorscope target angles (degrees from +U axis):
  // Red:      104.9°  (V positive)
  // Green:    240.7°  (V negative)
  // Blue:     347.1°  (U negative)
  // Yellow:    61.7°  (between R and Y)
  // Cyan:     199.5°  (between G and B)
  // Magenta:  312.5°  (between B and R)
  static const _targetAngles = <String, double>{
    'R': 104.9,
    'G': 240.7,
    'B': 347.1,
    'Yl': 61.7,
    'Cy': 199.5,
    'Mg': 312.5,
  };

  static const _targetColors = <String, Color>{
    'R': Color(0xFFFF0000),
    'G': Color(0xFF00FF00),
    'B': Color(0xFF0000FF),
    'Yl': Color(0xFFFFFF00),
    'Cy': Color(0xFF00FFFF),
    'Mg': Color(0xFFFF00FF),
  };

  // Skin tone line angle (approximately 123° from +U axis, I-line)
  static const double _skinToneAngle = 123.0;

  @override
  void paint(Canvas canvas, Size size) {
    // ── Background ──────────────────────────────────────────────────
    final bgPaint = Paint()..color = const Color(0xFF0d0d1a);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (min(size.width, size.height) / 2 - 16)
        .clamp(0.0, double.infinity)
        .toDouble();

    // ── Color wheel (reference ring) ────────────────────────────────
    _drawColorWheel(canvas, cx, cy, radius);

    // ── Graticule circles ───────────────────────────────────────────
    _drawGraticule(canvas, cx, cy, radius);

    // ── Color target boxes ──────────────────────────────────────────
    _drawColorTargets(canvas, cx, cy, radius);

    // ── Skin tone line ──────────────────────────────────────────────
    _drawSkinToneLine(canvas, cx, cy, radius);

    // ── Chrominance data points ─────────────────────────────────────
    _drawChrominanceData(canvas, cx, cy, radius);

    // ── Labels ──────────────────────────────────────────────────────
    _drawLabels(canvas, cx, cy, radius, size);
  }

  void _drawColorWheel(Canvas canvas, double cx, double cy, double radius) {
    // Draw a subtle color wheel ring showing hue around the perimeter
    const segments = 360;
    for (var i = 0; i < segments; i++) {
      final angle1 = (i - 90) * pi / 180;
      final angle2 = (i + 1 - 90) * pi / 180;

      final hue = i.toDouble();
      final color = HSVColor.fromAHSV(0.15, hue / 360.0, 0.8, 1.0).toColor();

      final path = Path()
        ..moveTo(
          cx + cos(angle1) * (radius - 6),
          cy + sin(angle1) * (radius - 6),
        )
        ..lineTo(cx + cos(angle1) * radius, cy + sin(angle1) * radius)
        ..lineTo(cx + cos(angle2) * radius, cy + sin(angle2) * radius)
        ..lineTo(
          cx + cos(angle2) * (radius - 6),
          cy + sin(angle2) * (radius - 6),
        )
        ..close();

      canvas.drawPath(path, Paint()..color = color);
    }
  }

  void _drawGraticule(Canvas canvas, double cx, double cy, double radius) {
    final gridPaint = Paint()
      ..color = const Color(0xFF2a2a3e)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Concentric circles at 20%, 40%, 60%, 80%, 100%
    for (var r = 0.2; r <= 1.0; r += 0.2) {
      canvas.drawCircle(Offset(cx, cy), radius * r, gridPaint);
    }

    // Cross hairs (U and V axes)
    canvas.drawLine(
      Offset(cx - radius, cy),
      Offset(cx + radius, cy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cx, cy - radius),
      Offset(cx, cy + radius),
      gridPaint,
    );

    // Diagonal lines (connecting complementary color targets)
    final diagPaint = Paint()
      ..color = const Color(0xFF1e1e34)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // R-Cy diagonal
    _drawLineAtAngle(canvas, cx, cy, radius, 104.9, diagPaint);
    _drawLineAtAngle(canvas, cx, cy, radius, 284.9, diagPaint);
    // G-Mg diagonal
    _drawLineAtAngle(canvas, cx, cy, radius, 240.7, diagPaint);
    _drawLineAtAngle(canvas, cx, cy, radius, 60.7, diagPaint);
    // B-Yl diagonal
    _drawLineAtAngle(canvas, cx, cy, radius, 347.1, diagPaint);
    _drawLineAtAngle(canvas, cx, cy, radius, 167.1, diagPaint);
  }

  void _drawLineAtAngle(
    Canvas canvas,
    double cx,
    double cy,
    double radius,
    double angleDeg,
    Paint paint,
  ) {
    final angle = (angleDeg - 90) * pi / 180;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + cos(angle) * radius, cy + sin(angle) * radius),
      paint,
    );
  }

  void _drawColorTargets(Canvas canvas, double cx, double cy, double radius) {
    const targetSize = 8.0;

    for (final entry in _targetAngles.entries) {
      final angle = (entry.value - 90) * pi / 180;
      // Targets at 75% radius (standard 75% amplitude reference)
      final dist = radius * 0.75;
      final x = cx + cos(angle) * dist;
      final y = cy + sin(angle) * dist;

      final color = _targetColors[entry.key] ?? Colors.white;

      // Target box outline
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, y),
          width: targetSize,
          height: targetSize,
        ),
        Paint()
          ..color = color.withValues(alpha: 0.8)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );

      // Inner dot
      canvas.drawCircle(Offset(x, y), 1.5, Paint()..color = color);

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: entry.key,
          style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 7,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelX = cx + cos(angle) * (dist + 12) - tp.width / 2;
      final labelY = cy + sin(angle) * (dist + 12) - tp.height / 2;
      tp.paint(canvas, Offset(labelX, labelY));
    }
  }

  void _drawSkinToneLine(Canvas canvas, double cx, double cy, double radius) {
    const angle = (_skinToneAngle - 90) * pi / 180;
    final startDist = radius * 0.15;
    final endDist = radius * 0.65;

    final paint = Paint()
      ..color = const Color(0xFFcc8844)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(cx + cos(angle) * startDist, cy + sin(angle) * startDist),
      Offset(cx + cos(angle) * endDist, cy + sin(angle) * endDist),
      paint,
    );

    // "I" label for skin tone line (I-line in component analysis)
    final tp = TextPainter(
      text: const TextSpan(
        text: 'I',
        style: TextStyle(
          color: Color(0xFFcc8844),
          fontSize: 7,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelDist = endDist + 6;
    tp.paint(
      canvas,
      Offset(
        cx + cos(angle) * labelDist - tp.width / 2,
        cy + sin(angle) * labelDist - tp.height / 2,
      ),
    );
  }

  void _drawChrominanceData(
    Canvas canvas,
    double cx,
    double cy,
    double radius,
  ) {
    final random = Random(seed);

    // Generate clusters of chrominance data points
    // Simulates real video content: skin tones, primary colors, neutrals
    final clusters = <List<double>>[];

    // Skin tone cluster (most common in video)
    for (var i = 0; i < 40; i++) {
      final angle =
          (_skinToneAngle - 90) * pi / 180 + (random.nextDouble() - 0.5) * 0.4;
      final dist = (0.25 + random.nextDouble() * 0.3) * radius;
      clusters.add([cx + cos(angle) * dist, cy + sin(angle) * dist]);
    }

    // Neutral/white cluster (center)
    for (var i = 0; i < 20; i++) {
      final angle = random.nextDouble() * 2 * pi;
      final dist = random.nextDouble() * 0.12 * radius;
      clusters.add([cx + cos(angle) * dist, cy + sin(angle) * dist]);
    }

    // Red channel cluster
    for (var i = 0; i < 15; i++) {
      final angle = (104.9 - 90) * pi / 180 + (random.nextDouble() - 0.5) * 0.5;
      final dist = (0.3 + random.nextDouble() * 0.35) * radius;
      clusters.add([cx + cos(angle) * dist, cy + sin(angle) * dist]);
    }

    // Green channel cluster
    for (var i = 0; i < 12; i++) {
      final angle = (240.7 - 90) * pi / 180 + (random.nextDouble() - 0.5) * 0.5;
      final dist = (0.2 + random.nextDouble() * 0.3) * radius;
      clusters.add([cx + cos(angle) * dist, cy + sin(angle) * dist]);
    }

    // Blue channel cluster
    for (var i = 0; i < 10; i++) {
      final angle = (347.1 - 90) * pi / 180 + (random.nextDouble() - 0.5) * 0.5;
      final dist = (0.2 + random.nextDouble() * 0.25) * radius;
      clusters.add([cx + cos(angle) * dist, cy + sin(angle) * dist]);
    }

    // Scattered low-saturation points
    for (var i = 0; i < 30; i++) {
      final angle = random.nextDouble() * 2 * pi;
      final dist = random.nextDouble() * 0.5 * radius;
      clusters.add([cx + cos(angle) * dist, cy + sin(angle) * dist]);
    }

    // Draw glow layer first
    final glowPaint = Paint()
      ..color = const Color(0xFF00ff41)
          .withValues(alpha: (0.06 * gain.clamp(0.2, 2.0)).clamp(0.0, 1.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    for (final point in clusters) {
      canvas.drawCircle(Offset(point[0], point[1]), 5, glowPaint);
    }

    // Draw data points
    final dotPaint = Paint()
      ..color = const Color(0xFF00ff41)
          .withValues(alpha: (0.35 * gain.clamp(0.2, 2.0)).clamp(0.0, 1.0));

    for (final point in clusters) {
      canvas.drawCircle(Offset(point[0], point[1]), 1.8, dotPaint);
    }

    // Brighter core for dense clusters
    final corePaint = Paint()
      ..color = const Color(0xFF66ff88)
          .withValues(alpha: (0.5 * gain.clamp(0.2, 2.0)).clamp(0.0, 1.0));

    // Count nearby points to find density
    for (var i = 0; i < clusters.length; i++) {
      var neighbors = 0;
      for (var j = 0; j < clusters.length; j++) {
        if (i == j) continue;
        final dx = clusters[i][0] - clusters[j][0];
        final dy = clusters[i][1] - clusters[j][1];
        if (dx * dx + dy * dy < 100) neighbors++; // within 10px
      }
      if (neighbors > 3) {
        canvas.drawCircle(
          Offset(clusters[i][0], clusters[i][1]),
          1.2,
          corePaint,
        );
      }
    }
  }

  void _drawLabels(
    Canvas canvas,
    double cx,
    double cy,
    double radius,
    Size size,
  ) {
    const labelStyle = TextStyle(
      color: Color(0xFF6a6a8a),
      fontSize: 7,
      fontFamily: 'Inter',
      fontWeight: FontWeight.w500,
    );

    // U/V axis labels
    final uLabel = TextPainter(
      text: const TextSpan(text: 'U', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    uLabel.paint(canvas, Offset(cx + radius + 4, cy - uLabel.height / 2));

    final vLabel = TextPainter(
      text: const TextSpan(text: 'V', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    vLabel.paint(canvas, Offset(cx - vLabel.width / 2, cy - radius - 12));

    // Center dot
    canvas.drawCircle(
      Offset(cx, cy),
      1.5,
      Paint()..color = const Color(0xFF6a6a8a),
    );

    // 75% circle label
    final p75Label = TextPainter(
      text: const TextSpan(text: '75%', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    p75Label.paint(
      canvas,
      Offset(cx + radius * 0.75 - p75Label.width - 2, cy + 2),
    );

    // 100% circle label
    final p100Label = TextPainter(
      text: const TextSpan(text: '100%', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    p100Label.paint(canvas, Offset(cx + radius - p100Label.width - 2, cy + 2));
  }

  @override
  bool shouldRepaint(covariant VectorscopePainter oldDelegate) {
    return oldDelegate.seed != seed || oldDelegate.gain != gain;
  }
}
