import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Transform handle type
enum HandleType {
  move,
  scaleTopLeft,
  scaleTopRight,
  scaleBottomLeft,
  scaleBottomRight,
  rotate,
}

/// Transform handles overlay for the preview viewport
class TransformHandles extends StatefulWidget {
  final Rect bounds;
  final double rotation;
  final ValueChanged<Offset>? onMove;
  final ValueChanged<HandleType>? onScaleStart;
  final ValueChanged<Offset>? onScaleUpdate;
  final ValueChanged<double>? onRotate;
  final bool isSelected;

  const TransformHandles({
    super.key,
    required this.bounds,
    this.rotation = 0.0,
    this.onMove,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onRotate,
    this.isSelected = true,
  });

  @override
  State<TransformHandles> createState() => _TransformHandlesState();
}

class _TransformHandlesState extends State<TransformHandles> {
  HandleType? _activeHandle;
  Offset? _lastPosition;

  @override
  Widget build(BuildContext context) {
    if (!widget.isSelected) return const SizedBox.shrink();

    final bounds = widget.bounds;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Bounding box outline
        Positioned.fromRect(
          rect: bounds,
          child: CustomPaint(
            painter: _TransformHandlesPainter(
              rotation: widget.rotation,
            ),
            size: bounds.size,
          ),
        ),

        // Rotation line from top center
        Positioned(
          left: bounds.topCenter.dx - 0.5,
          top: bounds.topCenter.dy - 30,
          child: Container(
            width: 1,
            height: 30,
            color: Colors.purple.withOpacity(0.6),
          ),
        ),

        // Rotation handle (above top center)
        _buildRotationHandle(
          Offset(bounds.topCenter.dx, bounds.topCenter.dy - 30),
        ),

        // Corner handles
        _buildHandle(bounds.topLeft, HandleType.scaleTopLeft),
        _buildHandle(bounds.topRight, HandleType.scaleTopRight),
        _buildHandle(bounds.bottomLeft, HandleType.scaleBottomLeft),
        _buildHandle(bounds.bottomRight, HandleType.scaleBottomRight),

        // Edge midpoint handles
        _buildEdgeHandle(bounds.topCenter, HandleType.scaleTopLeft), // top edge
        _buildEdgeHandle(bounds.bottomCenter, HandleType.scaleBottomLeft), // bottom edge
        _buildEdgeHandle(bounds.centerLeft, HandleType.scaleTopLeft), // left edge
        _buildEdgeHandle(bounds.centerRight, HandleType.scaleTopRight), // right edge

        // Move handle (entire area)
        Positioned.fromRect(
          rect: bounds.inflate(-8),
          child: GestureDetector(
            onPanStart: (details) {
              _activeHandle = HandleType.move;
              _lastPosition = details.globalPosition;
            },
            onPanUpdate: (details) {
              if (_activeHandle == HandleType.move && _lastPosition != null) {
                final delta = details.globalPosition - _lastPosition!;
                _lastPosition = details.globalPosition;
                widget.onMove?.call(delta);
              }
            },
            onPanEnd: (_) {
              _activeHandle = null;
              _lastPosition = null;
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHandle(Offset position, HandleType type) {
    final isActive = _activeHandle == type;
    final size = isActive ? 14.0 : 12.0;

    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size / 2,
      child: GestureDetector(
        onPanStart: (details) {
          _activeHandle = type;
          _lastPosition = details.globalPosition;
          widget.onScaleStart?.call(type);
        },
        onPanUpdate: (details) {
          if (_activeHandle == type && _lastPosition != null) {
            final delta = details.globalPosition - _lastPosition!;
            _lastPosition = details.globalPosition;
            widget.onScaleUpdate?.call(delta);
          }
        },
        onPanEnd: (_) {
          _activeHandle = null;
          _lastPosition = null;
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : AppTheme.primary,
            border: Border.all(color: Colors.white, width: 1.5),
            shape: BoxShape.rectangle,
          ),
        ),
      ),
    );
  }

  Widget _buildEdgeHandle(Offset position, HandleType type) {
    return Positioned(
      left: position.dx - 5,
      top: position.dy - 5,
      child: GestureDetector(
        onPanStart: (details) {
          _activeHandle = type;
          _lastPosition = details.globalPosition;
          widget.onScaleStart?.call(type);
        },
        onPanUpdate: (details) {
          if (_activeHandle == type && _lastPosition != null) {
            final delta = details.globalPosition - _lastPosition!;
            _lastPosition = details.globalPosition;
            widget.onScaleUpdate?.call(delta);
          }
        },
        onPanEnd: (_) {
          _activeHandle = null;
          _lastPosition = null;
        },
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.8),
            border: Border.all(color: Colors.white, width: 1),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildRotationHandle(Offset position) {
    return Positioned(
      left: position.dx - 10,
      top: position.dy - 10,
      child: GestureDetector(
        onPanStart: (details) {
          _activeHandle = HandleType.rotate;
          _lastPosition = details.globalPosition;
        },
        onPanUpdate: (details) {
          if (_activeHandle == HandleType.rotate && _lastPosition != null) {
            final center = Offset(
              widget.bounds.left + widget.bounds.width / 2,
              widget.bounds.top + widget.bounds.height / 2,
            );
            final prevAngle = math.atan2(
              _lastPosition!.dy - center.dy,
              _lastPosition!.dx - center.dx,
            );
            final currAngle = math.atan2(
              details.globalPosition.dy - center.dy,
              details.globalPosition.dx - center.dx,
            );
            final deltaAngle = currAngle - prevAngle;
            _lastPosition = details.globalPosition;
            widget.onRotate?.call(deltaAngle);
          }
        },
        onPanEnd: (_) {
          _activeHandle = null;
          _lastPosition = null;
        },
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.8),
            border: Border.all(color: Colors.white, width: 1.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.refresh,
            color: Colors.white,
            size: 12,
          ),
        ),
      ),
    );
  }
}

class _TransformHandlesPainter extends CustomPainter {
  final double rotation;

  _TransformHandlesPainter({required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw dashed bounding box
    final paint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw dashed line
    const dashWidth = 5.0;
    const dashSpace = 3.0;
    double startX = 0;

    // Top line
    while (startX < size.width) {
      final end = startX + dashWidth;
      canvas.drawLine(
        Offset(startX, 0),
        Offset(end.clamp(0, size.width), 0),
        paint,
      );
      startX = end + dashSpace;
    }

    // Bottom line
    startX = 0;
    while (startX < size.width) {
      final end = startX + dashWidth;
      canvas.drawLine(
        Offset(startX, size.height),
        Offset(end.clamp(0, size.width), size.height),
        paint,
      );
      startX = end + dashSpace;
    }

    // Left line
    double startY = 0;
    while (startY < size.height) {
      final end = startY + dashWidth;
      canvas.drawLine(
        Offset(0, startY),
        Offset(0, end.clamp(0, size.height)),
        paint,
      );
      startY = end + dashSpace;
    }

    // Right line
    startY = 0;
    while (startY < size.height) {
      final end = startY + dashWidth;
      canvas.drawLine(
        Offset(size.width, startY),
        Offset(size.width, end.clamp(0, size.height)),
        paint,
      );
      startY = end + dashSpace;
    }

    // Draw size indicator text
    if (size.width > 80 && size.height > 40) {
      final widthText = size.width.round().toString();
      final heightText = size.height.round().toString();
      final sizeText = '${widthText}×$heightText';

      final textSpan = TextSpan(
        text: sizeText,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 9,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final textX = (size.width - tp.width) / 2;
      final textY = (size.height - tp.height) / 2;

      // Background
      canvas.drawRect(
        Rect.fromLTWH(textX - 2, textY - 1, tp.width + 4, tp.height + 2),
        Paint()..color = AppTheme.background.withOpacity(0.7),
      );
      tp.paint(canvas, Offset(textX, textY));
    }

    // Draw rotation angle indicator
    if (rotation != 0.0) {
      final degrees = (rotation * 180 / math.pi).round();
      final rotText = '${degrees}°';
      final rotSpan = TextSpan(
        text: rotText,
        style: const TextStyle(
          color: Colors.purple,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
      final rotTp = TextPainter(
        text: rotSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      rotTp.paint(canvas, Offset(size.width / 2 - rotTp.width / 2, -20));
    }
  }

  @override
  bool shouldRepaint(covariant _TransformHandlesPainter oldDelegate) =>
      rotation != oldDelegate.rotation;
}
