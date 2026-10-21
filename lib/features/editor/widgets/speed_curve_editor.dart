import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/editor_provider.dart';

/// Speed segment data
class SpeedSegmentData {
  const SpeedSegmentData({
    required this.startMs,
    required this.endMs,
    required this.startSpeed,
    required this.endSpeed,
    required this.easingName,
  });
  final int startMs;
  final int endMs;
  final double startSpeed;
  final double endSpeed;
  final String easingName;

  SpeedSegmentData copyWith({
    int? startMs,
    int? endMs,
    double? startSpeed,
    double? endSpeed,
    String? easingName,
  }) {
    return SpeedSegmentData(
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      startSpeed: startSpeed ?? this.startSpeed,
      endSpeed: endSpeed ?? this.endSpeed,
      easingName: easingName ?? this.easingName,
    );
  }
}

/// Speed curve editor widget
class SpeedCurveEditor extends ConsumerStatefulWidget {
  const SpeedCurveEditor({
    required this.clipId,
    required this.clipDurationMs,
    super.key,
  });
  final String clipId;
  final int clipDurationMs;

  @override
  ConsumerState<SpeedCurveEditor> createState() => _SpeedCurveEditorState();
}

class _SpeedCurveEditorState extends ConsumerState<SpeedCurveEditor> {
  double _currentSpeed = 1.0;
  String _selectedEasing = 'linear';
  final List<SpeedSegmentData> _segments = [];
  int? _draggingSegmentIndex;
  bool _draggingStart = false; // true = start point, false = end point

  static const List<double> _speedPresets = [0.25, 0.5, 1.0, 2.0, 4.0];
  static const List<String> _easingTypes = [
    'linear',
    'ease_in',
    'ease_out',
    'ease_in_out',
    'cubic_bezier',
  ];

  // Phase E.17: CapCut-style named velocity ramp presets.
  // Each preset defines a list of (startSpeed, endSpeed, easing) tuples
  // that are applied as consecutive segments across the clip's duration.
  // The presets are inspired by CapCut's "Velocity" templates.
  static const List<_VelocityPreset> _velocityPresets = [
    _VelocityPreset(
      name: 'Montage',
      icon: Icons.movie_filter_outlined,
      // Smooth ramp from 1x → 2x → 1x (typical montage beat-sync feel).
      segments: [
        (1.0, 2.0, 'ease_in_out'),
        (2.0, 1.0, 'ease_in_out'),
      ],
    ),
    _VelocityPreset(
      name: 'Hero',
      icon: Icons.flash_on_outlined,
      // Slow-motion hero entrance: 1x → 0.5x → 1x.
      segments: [
        (1.0, 0.5, 'ease_out'),
        (0.5, 1.0, 'ease_in'),
      ],
    ),
    _VelocityPreset(
      name: 'Bullet',
      icon: Icons.bolt_outlined,
      // Bullet-time effect: 1x → 0.25x → 4x → 1x.
      segments: [
        (1.0, 0.25, 'ease_out'),
        (0.25, 4.0, 'ease_in_out'),
        (4.0, 1.0, 'ease_in'),
      ],
    ),
    _VelocityPreset(
      name: 'Rollercoaster',
      icon: Icons.waves_outlined,
      // Wavy speed: 1x → 2x → 0.5x → 2x → 1x.
      segments: [
        (1.0, 2.0, 'ease_in_out'),
        (2.0, 0.5, 'ease_in_out'),
        (0.5, 2.0, 'ease_in_out'),
        (2.0, 1.0, 'ease_in_out'),
      ],
    ),
    _VelocityPreset(
      name: 'Flash',
      icon: Icons.timer_outlined,
      // Quick acceleration to 4x then snap back to 1x.
      segments: [
        (1.0, 4.0, 'ease_in'),
        (4.0, 1.0, 'linear'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _segments.add(
      SpeedSegmentData(
        startMs: 0,
        endMs: widget.clipDurationMs,
        startSpeed: 1.0,
        endSpeed: 1.0,
        easingName: 'linear',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.speed, color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Speed Curve',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${_currentSpeed.toStringAsFixed(2)}x',
                style: TextStyle(
                  color: _currentSpeed == 1.0
                      ? AppTheme.textSecondary
                      : AppTheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Speed curve canvas
          SizedBox(
            height: 120,
            child: GestureDetector(
              onPanStart: _onCanvasPanStart,
              onPanUpdate: _onCanvasPanUpdate,
              onPanEnd: _onCanvasPanEnd,
              child: CustomPaint(
                painter: _SpeedCurvePainter(
                  segments: _segments,
                  durationMs: widget.clipDurationMs,
                  currentSpeed: _currentSpeed,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Speed presets
          Wrap(
            spacing: 6,
            children: _speedPresets.map((speed) {
              final isSelected = (_currentSpeed - speed).abs() < 0.01;
              return ChoiceChip(
                label: Text('${speed}x'),
                selected: isSelected,
                onSelected: (_) => _setSpeed(speed),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : AppTheme.textPrimary,
                  fontSize: 11,
                ),
                selectedColor: AppTheme.primary,
                backgroundColor: AppTheme.surfaceVariant,
                side: const BorderSide(color: Color(0xFF2A2A3E)),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Phase E.17: CapCut-style velocity ramp presets.
          // These are named speed-ramp patterns that apply a multi-segment
          // curve to the clip. Tapping a preset calls _applyVelocityPreset
          // which constructs the appropriate SpeedSegmentData list.
          const Text(
            'Velocity Ramps',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _velocityPresets.map((preset) {
              return ActionChip(
                label: Text(preset.name),
                avatar: Icon(preset.icon, size: 16, color: AppTheme.primary),
                onPressed: () => _applyVelocityPreset(preset),
                labelStyle: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 11,
                ),
                backgroundColor: AppTheme.surfaceVariant,
                side: const BorderSide(color: Color(0xFF2A2A3E)),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          // Easing selector
          Row(
            children: [
              const Text(
                'Easing: ',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedEasing,
                      isDense: true,
                      isExpanded: true,
                      dropdownColor: AppTheme.surfaceVariant,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                      ),
                      items: _easingTypes.map((easing) {
                        return DropdownMenuItem(
                          value: easing,
                          child:
                              Text(easing.replaceAll('_', ' ').toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedEasing = value);
                          _applyCurve();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Custom speed slider
          Row(
            children: [
              const Text(
                'Custom: ',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: _currentSpeed,
                  min: 0.1,
                  max: 8.0,
                  divisions: 79,
                  activeColor: AppTheme.primary,
                  label: '${_currentSpeed.toStringAsFixed(1)}x',
                  onChanged: (value) {
                    setState(() => _currentSpeed = value);
                    _applyCurve();
                  },
                ),
              ),
            ],
          ),

          // Add ramp button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addRampSegment,
              icon: const Icon(Icons.trending_up, size: 16),
              label: const Text('Add Speed Ramp'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: Color(0xFF2A2A3E)),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Reset button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetToUniform,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reset to Uniform'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: const BorderSide(color: Color(0xFF2A2A3E)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _setSpeed(double speed) {
    setState(() {
      _currentSpeed = speed;
      _segments.clear();
      _segments.add(
        SpeedSegmentData(
          startMs: 0,
          endMs: widget.clipDurationMs,
          startSpeed: speed,
          endSpeed: speed,
          easingName: _selectedEasing,
        ),
      );
    });
    _applyCurve();
  }

  /// Phase E.17: apply a named velocity ramp preset to the clip.
  ///
  /// Divides the clip duration into N equal segments (where N is the
  /// preset's segment count) and assigns each segment the preset's
  /// (startSpeed, endSpeed, easing) values. The user can then fine-tune
  /// individual segments via the existing drag UI.
  void _applyVelocityPreset(_VelocityPreset preset) {
    setState(() {
      _segments.clear();
      final segCount = preset.segments.length;
      final segDuration = widget.clipDurationMs ~/ segCount;
      for (var i = 0; i < segCount; i++) {
        final (startSpeed, endSpeed, easing) = preset.segments[i];
        _segments.add(
          SpeedSegmentData(
            startMs: i * segDuration,
            endMs: (i == segCount - 1)
                ? widget.clipDurationMs
                : (i + 1) * segDuration,
            startSpeed: startSpeed,
            endSpeed: endSpeed,
            easingName: easing,
          ),
        );
      }
      // Set the current speed to the average of the preset's segment
      // speeds so the speed preset chips reflect the applied state.
      final avgSpeed = preset.segments
              .map((s) => (s.$1 + s.$2) / 2)
              .reduce((a, b) => a + b) /
          segCount;
      _currentSpeed = avgSpeed;
    });
    _applyCurve();
  }

  void _addRampSegment() {
    setState(() {
      final midPoint = widget.clipDurationMs ~/ 2;
      _segments.clear();
      _segments.addAll([
        SpeedSegmentData(
          startMs: 0,
          endMs: midPoint,
          startSpeed: _currentSpeed,
          endSpeed: _currentSpeed * 2.0,
          easingName: _selectedEasing,
        ),
        SpeedSegmentData(
          startMs: midPoint,
          endMs: widget.clipDurationMs,
          startSpeed: _currentSpeed * 2.0,
          endSpeed: _currentSpeed,
          easingName: _selectedEasing,
        ),
      ]);
    });
    _applyCurve();
  }

  void _resetToUniform() {
    setState(() {
      _segments.clear();
      _segments.add(
        SpeedSegmentData(
          startMs: 0,
          endMs: widget.clipDurationMs,
          startSpeed: _currentSpeed,
          endSpeed: _currentSpeed,
          easingName: 'linear',
        ),
      );
    });
    _applyCurve();
  }

  void _onCanvasPanStart(DragStartDetails details) {
    // Find the closest segment endpoint to the touch position
    final box = context.findRenderObject() as RenderBox;
    final localPos = details.localPosition;
    const canvasTop = 12.0 + 28.0; // padding + header height
    const canvasHeight = 120.0;
    final canvasWidth = box.size.width - 24; // minus horizontal padding

    // Check each segment's endpoints
    var closestDist = 30.0; // threshold in pixels
    _draggingSegmentIndex = null;

    for (var i = 0; i < _segments.length; i++) {
      final seg = _segments[i];

      // Start point
      final startX = (seg.startMs /
              (widget.clipDurationMs > 0 ? widget.clipDurationMs : 1)) *
          canvasWidth;
      final startSpeedY =
          canvasHeight - (seg.startSpeed / 8.0).clamp(0.0, 1.0) * canvasHeight;
      final startDist = math.sqrt(
        math.pow(localPos.dx - startX, 2) +
            math.pow(localPos.dy - canvasTop - startSpeedY, 2),
      );
      if (startDist < closestDist) {
        closestDist = startDist;
        _draggingSegmentIndex = i;
        _draggingStart = true;
      }

      // End point
      final endX = (seg.endMs /
              (widget.clipDurationMs > 0 ? widget.clipDurationMs : 1)) *
          canvasWidth;
      final endSpeedY =
          canvasHeight - (seg.endSpeed / 8.0).clamp(0.0, 1.0) * canvasHeight;
      final endDist = math.sqrt(
        math.pow(localPos.dx - endX, 2) +
            math.pow(localPos.dy - canvasTop - endSpeedY, 2),
      );
      if (endDist < closestDist) {
        closestDist = endDist;
        _draggingSegmentIndex = i;
        _draggingStart = false;
      }
    }
  }

  void _onCanvasPanUpdate(DragUpdateDetails details) {
    if (_draggingSegmentIndex == null) return;
    final box = context.findRenderObject() as RenderBox;
    final canvasWidth = box.size.width - 24;
    const canvasHeight = 120.0;

    final seg = _segments[_draggingSegmentIndex!];

    // Convert delta to speed change
    final speedDelta = -details.delta.dy / canvasHeight * 8.0;
    final timeDelta =
        (details.delta.dx / canvasWidth * widget.clipDurationMs).round();

    setState(() {
      if (_draggingStart) {
        final newSpeed = (seg.startSpeed + speedDelta).clamp(0.1, 8.0);
        final newTime = (seg.startMs + timeDelta).clamp(0, seg.endMs - 100);
        _segments[_draggingSegmentIndex!] = seg.copyWith(
          startSpeed: newSpeed,
          startMs: newTime,
        );
      } else {
        final newSpeed = (seg.endSpeed + speedDelta).clamp(0.1, 8.0);
        final newTime = (seg.endMs + timeDelta)
            .clamp(seg.startMs + 100, widget.clipDurationMs);
        _segments[_draggingSegmentIndex!] = seg.copyWith(
          endSpeed: newSpeed,
          endMs: newTime,
        );
      }
    });
    _applyCurve();
  }

  void _onCanvasPanEnd(DragEndDetails details) {
    _draggingSegmentIndex = null;
  }

  void _applyCurve() {
    ref
        .read(editorProvider.notifier)
        .setClipSpeed(widget.clipId, _currentSpeed);
    // Also update speed curve segments
    ref
        .read(editorProvider.notifier)
        .setClipSpeedCurve(widget.clipId, _segments);
  }
}

/// Custom painter for the speed curve visualization
class _SpeedCurvePainter extends CustomPainter {
  _SpeedCurvePainter({
    required this.segments,
    required this.durationMs,
    required this.currentSpeed,
  });
  final List<SpeedSegmentData> segments;
  final int durationMs;
  final double currentSpeed;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF2A2A3E).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw grid
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var i = 0; i <= 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Draw 1x reference line
    final oneXy = size.height * 0.5; // Middle = 1x (assuming max 2x view)
    final refPaint = Paint()
      ..color = AppTheme.textDisabled.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, oneXy), Offset(size.width, oneXy), refPaint);

    // Draw '1x' label
    const textSpan = TextSpan(
      text: '1x',
      style: TextStyle(color: AppTheme.textDisabled, fontSize: 9),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(2, oneXy - tp.height - 2));

    if (segments.isEmpty || durationMs == 0) return;

    // Draw speed curve
    final curvePaint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();
    const steps = 100;

    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final timeMs = (t * durationMs).round();

      // Find speed at this time
      var speed = 1.0;
      for (final seg in segments) {
        if (timeMs >= seg.startMs && timeMs <= seg.endMs) {
          final segT = (seg.endMs - seg.startMs) > 0
              ? (timeMs - seg.startMs) / (seg.endMs - seg.startMs)
              : 0.0;
          final easedT = _applyEasing(segT, seg.easingName);
          speed = seg.startSpeed + (seg.endSpeed - seg.startSpeed) * easedT;
          break;
        }
      }

      final x = t * size.width;
      // Map speed 0-8x to canvas height (inverted because Y goes down)
      final y = size.height - (speed / 8.0).clamp(0.0, 1.0) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Complete the fill path
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, curvePaint);

    // Draw segment endpoints
    for (final seg in segments) {
      for (final entry in [
        (timeMs: seg.startMs, speed: seg.startSpeed),
        (timeMs: seg.endMs, speed: seg.endSpeed),
      ]) {
        final t = entry.timeMs / durationMs;
        final x = t * size.width;
        final y =
            size.height - (entry.speed / 8.0).clamp(0.0, 1.0) * size.height;

        // Outer glow
        canvas.drawCircle(
          Offset(x, y),
          6,
          Paint()..color = AppTheme.primary.withValues(alpha: 0.3),
        );
        // Filled circle
        canvas.drawCircle(
          Offset(x, y),
          4,
          Paint()..color = AppTheme.primary,
        );
        // Border
        canvas.drawCircle(
          Offset(x, y),
          4,
          Paint()
            ..color = AppTheme.surface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // Draw speed labels on Y axis
    for (final speed in [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]) {
      final y = size.height - (speed / 8.0) * size.height;
      if (y >= 0 && y <= size.height) {
        final labelTp = TextPainter(
          text: TextSpan(
            text: '${speed}x',
            style: const TextStyle(color: AppTheme.textDisabled, fontSize: 8),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        labelTp.paint(
          canvas,
          Offset(size.width - labelTp.width - 2, y - labelTp.height / 2),
        );
      }
    }
  }

  double _applyEasing(double t, String easingName) {
    switch (easingName) {
      case 'ease_in':
        return t * t;
      case 'ease_out':
        return 1 - (1 - t) * (1 - t);
      case 'ease_in_out':
        return t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;
      case 'cubic_bezier':
        // Simplified cubic bezier approximation
        return t * t * (3 - 2 * t);
      case 'linear':
      default:
        return t;
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedCurvePainter oldDelegate) =>
      segments != oldDelegate.segments ||
      durationMs != oldDelegate.durationMs ||
      currentSpeed != oldDelegate.currentSpeed;
}

/// Phase E.17: a named velocity ramp preset (CapCut-style).
///
/// Each preset is a list of (startSpeed, endSpeed, easing) tuples that
/// are applied as consecutive segments across the clip's duration. The
/// segments divide the clip evenly — e.g., a 3-segment preset on a
/// 10-second clip gets segments of [0-3.33s, 3.33-6.67s, 6.67-10s].
class _VelocityPreset {
  const _VelocityPreset({
    required this.name,
    required this.icon,
    required this.segments,
  });
  final String name;
  final IconData icon;
  final List<(double, double, String)> segments;
}
