import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Data model representing a text overlay's position and style on the preview.
class TextOverlayData {
  const TextOverlayData({
    required this.clipId,
    required this.text,
    this.positionX = 0.5,
    this.positionY = 0.5,
    this.width = 0.4,
    this.height = 0.1,
    this.fontFamily = 'Inter',
    this.fontSize = 36.0,
    this.colorHex = '#FFFFFF',
    this.isSelected = false,
  });
  final String clipId;
  final String text;
  final double positionX; // 0.0–1.0 relative to preview width
  final double positionY; // 0.0–1.0 relative to preview height
  final double width; // 0.0–1.0 relative to preview width
  final double height; // 0.0–1.0 relative to preview height
  final String fontFamily;
  final double fontSize;
  final String colorHex;
  final bool isSelected;

  TextOverlayData copyWith({
    String? clipId,
    String? text,
    double? positionX,
    double? positionY,
    double? width,
    double? height,
    String? fontFamily,
    double? fontSize,
    String? colorHex,
    bool? isSelected,
  }) {
    return TextOverlayData(
      clipId: clipId ?? this.clipId,
      text: text ?? this.text,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      width: width ?? this.width,
      height: height ?? this.height,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      colorHex: colorHex ?? this.colorHex,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

/// Callback signature for when a text overlay is repositioned.
typedef TextPositionChanged = void Function(
  String clipId,
  double positionX,
  double positionY,
);

/// Callback signature for when a text overlay is resized.
typedef TextSizeChanged = void Function(
  String clipId,
  double width,
  double height,
);

/// A draggable handle that appears on the preview viewport when a text
/// clip is selected. The native composed frame paints the text; this widget
/// only supplies selection geometry and commits a position when dragging ends.
class TextOverlayHandle extends StatefulWidget {
  const TextOverlayHandle({
    required this.data,
    required this.onPositionChanged,
    super.key,
    this.onSizeChanged,
    this.onTap,
  });
  final TextOverlayData data;
  final TextPositionChanged onPositionChanged;
  final TextSizeChanged? onSizeChanged;
  final VoidCallback? onTap;

  @override
  State<TextOverlayHandle> createState() => _TextOverlayHandleState();
}

class _TextOverlayHandleState extends State<TextOverlayHandle> {
  Offset? _dragStart;
  Offset? _startPosition;
  Offset? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
        return const SizedBox.shrink();
      }
      final center = _dragPosition ?? Offset(data.positionX, data.positionY);
      final boxWidth = (data.width * width).clamp(24.0, width);
      final boxHeight = (data.height * height).clamp(24.0, height);
      return Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: center.dx * width - boxWidth / 2,
          top: center.dy * height - boxHeight / 2,
          width: boxWidth,
          height: boxHeight,
          child: Semantics(
            label: 'Move text overlay',
            child: GestureDetector(
              key: const ValueKey('text-selection-geometry'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onPanStart: (details) {
                _dragStart = details.globalPosition;
                _startPosition = Offset(data.positionX, data.positionY);
                _dragPosition = _startPosition;
              },
              onPanUpdate: (details) {
                if (_dragStart == null || _startPosition == null) return;
                final delta = details.globalPosition - _dragStart!;
                setState(() => _dragPosition = Offset(
                      (_startPosition!.dx + delta.dx / width).clamp(0.0, 1.0),
                      (_startPosition!.dy + delta.dy / height).clamp(0.0, 1.0),
                    ));
              },
              onPanEnd: (_) {
                final position = _dragPosition;
                if (position != null) {
                  widget.onPositionChanged(
                      data.clipId, position.dx, position.dy);
                }
                _dragStart = null;
                _startPosition = null;
              },
              onPanCancel: () => setState(() {
                _dragStart = null;
                _startPosition = null;
                _dragPosition = null;
              }),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                  border: Border.all(
                      color: data.isSelected
                          ? AppTheme.primary
                          : AppTheme.textTrackColor,
                      width: 1.5),
                )),
              ),
            ),
          ),
        ),
      ]);
    });
  }

  @override
  void didUpdateWidget(covariant TextOverlayHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragStart == null) _dragPosition = null;
  }
}
