import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Phase F.2: Safe Zones overlay.
///
/// Renders the title-safe (90% / 80% broadcast) and action-safe (80%)
/// overlays on the preview viewport. Plus a 4:3 and 9:16 reframing guide
/// for multi-platform delivery.
///
/// Toggleable from the editor toolbar. The overlay does NOT affect the
/// rendered output — it's a view-only guide.
///
/// See persona/skills/broadcast-legal/SKILL.md.
class SafeZonesOverlay extends StatelessWidget {
  /// Which overlays to show.
  final SafeZoneConfig config;

  /// Aspect ratio of the underlying preview (width / height).
  /// Used to compute the 9:16 and 4:3 reframing guides correctly.
  final double previewAspectRatio;

  const SafeZonesOverlay({
    super.key,
    required this.config,
    this.previewAspectRatio = 16 / 9,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _SafeZonesPainter(
          config: config,
          previewAspectRatio: previewAspectRatio,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class SafeZoneConfig {
  /// Title-safe area (90% for broadcast, 80% for social captions).
  final bool showTitleSafe;
  /// Action-safe area (80% for broadcast).
  final bool showActionSafe;
  /// Center crosshair.
  final bool showCenter;
  /// Rule-of-thirds grid.
  final bool showRuleOfThirds;
  /// 9:16 reframing guide (for vertical delivery).
  final bool showVertical9x16;
  /// 4:3 reframing guide (for legacy delivery).
  final bool showLegacy4x3;

  const SafeZoneConfig({
    this.showTitleSafe = false,
    this.showActionSafe = false,
    this.showCenter = false,
    this.showRuleOfThirds = false,
    this.showVertical9x16 = false,
    this.showLegacy4x3 = false,
  });

  SafeZoneConfig copyWith({
    bool? showTitleSafe,
    bool? showActionSafe,
    bool? showCenter,
    bool? showRuleOfThirds,
    bool? showVertical9x16,
    bool? showLegacy4x3,
  }) {
    return SafeZoneConfig(
      showTitleSafe: showTitleSafe ?? this.showTitleSafe,
      showActionSafe: showActionSafe ?? this.showActionSafe,
      showCenter: showCenter ?? this.showCenter,
      showRuleOfThirds: showRuleOfThirds ?? this.showRuleOfThirds,
      showVertical9x16: showVertical9x16 ?? this.showVertical9x16,
      showLegacy4x3: showLegacy4x3 ?? this.showLegacy4x3,
    );
  }

  /// Broadcast default — title-safe + action-safe + center.
  static const broadcast = SafeZoneConfig(
    showTitleSafe: true,
    showActionSafe: true,
    showCenter: true,
  );

  /// Social default — title-safe only (80% for captions).
  static const social = SafeZoneConfig(
    showTitleSafe: true,
    showCenter: true,
  );

  /// Composition default — rule-of-thirds + center.
  static const composition = SafeZoneConfig(
    showRuleOfThirds: true,
    showCenter: true,
  );

  /// All overlays on.
  static const all = SafeZoneConfig(
    showTitleSafe: true,
    showActionSafe: true,
    showCenter: true,
    showRuleOfThirds: true,
    showVertical9x16: true,
    showLegacy4x3: true,
  );

  /// None.
  static const none = SafeZoneConfig();
}

class _SafeZonesPainter extends CustomPainter {
  final SafeZoneConfig config;
  final double previewAspectRatio;

  _SafeZonesPainter({required this.config, required this.previewAspectRatio});

  @override
  void paint(Canvas canvas, Size size) {
    // Title-safe: 90% of frame (broadcast) — drawn at 90% if showTitleSafe.
    // For social, the title-safe is 80% (since phones clip edges).
    if (config.showTitleSafe) {
      _drawSafeRect(canvas, size, 0.90, Colors.white.withOpacity(0.7), dashed: true);
      _drawSafeRect(canvas, size, 0.80, Colors.yellow.withOpacity(0.5), dashed: true);
    }
    // Action-safe: 80%
    if (config.showActionSafe) {
      _drawSafeRect(canvas, size, 0.80, Colors.blue.withOpacity(0.5), dashed: true);
    }
    // Center crosshair
    if (config.showCenter) {
      _drawCenterCross(canvas, size);
    }
    // Rule of thirds
    if (config.showRuleOfThirds) {
      _drawRuleOfThirds(canvas, size);
    }
    // 9:16 reframing guide
    if (config.showVertical9x16) {
      _drawAspectGuide(canvas, size, 9 / 16, Colors.purple.withOpacity(0.5));
    }
    // 4:3 reframing guide
    if (config.showLegacy4x3) {
      _drawAspectGuide(canvas, size, 4 / 3, Colors.orange.withOpacity(0.5));
    }
  }

  void _drawSafeRect(Canvas canvas, Size size, double ratio, Color color, {bool dashed = false}) {
    final w = size.width * ratio;
    final h = size.height * ratio;
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    final rect = Rect.fromLTWH(left, top, w, h);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (dashed) {
      _drawDashedRect(canvas, rect, paint);
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dashLen = 8.0;
    const gapLen = 4.0;
    // Top
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint, dashLen, gapLen);
    // Bottom
    _drawDashedLine(canvas, rect.bottomLeft, rect.bottomRight, paint, dashLen, gapLen);
    // Left
    _drawDashedLine(canvas, rect.topLeft, rect.bottomLeft, paint, dashLen, gapLen);
    // Right
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint, dashLen, gapLen);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint, double dashLen, double gapLen) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final totalLen = math.sqrt(dx * dx + dy * dy);
    if (totalLen == 0) return;
    final ux = dx / totalLen;
    final uy = dy / totalLen;
    var pos = 0.0;
    while (pos < totalLen) {
      final segEnd = (pos + dashLen).clamp(0.0, totalLen);
      canvas.drawLine(
        Offset(start.dx + ux * pos, start.dy + uy * pos),
        Offset(start.dx + ux * segEnd, start.dy + uy * segEnd),
        paint,
      );
      pos += dashLen + gapLen;
    }
  }

  void _drawCenterCross(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(cx - 12, cy), Offset(cx + 12, cy), paint);
    canvas.drawLine(Offset(cx, cy - 12), Offset(cx, cy + 12), paint);
  }

  void _drawRuleOfThirds(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    // Vertical lines at 1/3 and 2/3
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(2 * size.width / 3, 0),
      Offset(2 * size.width / 3, size.height),
      paint,
    );
    // Horizontal lines at 1/3 and 2/3
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, 2 * size.height / 3),
      Offset(size.width, 2 * size.height / 3),
      paint,
    );
  }

  void _drawAspectGuide(Canvas canvas, Size size, double targetAspect, Color color) {
    // Fit the target aspect ratio inside the preview, centered.
    final previewAspect = size.width / size.height;
    double w, h;
    if (targetAspect > previewAspect) {
      // Target is wider — fit by width
      w = size.width;
      h = w / targetAspect;
    } else {
      // Target is taller — fit by height
      h = size.height;
      w = h * targetAspect;
    }
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    final rect = Rect.fromLTWH(left, top, w, h);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    _drawDashedRect(canvas, rect, paint);
  }

  @override
  bool shouldRepaint(covariant _SafeZonesPainter oldDelegate) =>
      config != oldDelegate.config || previewAspectRatio != oldDelegate.previewAspectRatio;
}
