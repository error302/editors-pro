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
/// clip is selected. It shows a bounding box around the text overlay area,
/// supports drag to reposition, and shows resize handles at corners.
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
  double? _startPosX;
  double? _startPosY;
  _ResizeCorner? _activeCorner;
  double? _startWidth;
  double? _startHeight;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final selected = data.isSelected;

    // Use LayoutBuilder to get the actual parent (Stack) size for proper positioning
    return LayoutBuilder(
      builder: (context, constraints) {
        final parentWidth = constraints.maxWidth;
        final parentHeight = constraints.maxHeight;

        if (parentWidth <= 0 || parentHeight <= 0) {
          return const SizedBox.shrink();
        }

        // Calculate pixel positions from fractional values
        final left = (data.positionX - data.width / 2) * parentWidth;
        final top = (data.positionY - data.height / 2) * parentHeight;
        final boxWidth = data.width * parentWidth;
        final boxHeight = data.height * parentHeight;

        return Positioned(
          left: left,
          top: top,
          width: boxWidth,
          height: boxHeight,
          child: GestureDetector(
            onPanStart: _onDragStart,
            onPanUpdate: (details) =>
                _onDragUpdate(details, parentWidth, parentHeight),
            onPanEnd: _onDragEnd,
            onTap: widget.onTap,
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color:
                        selected ? AppTheme.primary : AppTheme.textTrackColor,
                    width: selected ? 2.0 : 1.0,
                  ),
                  color: selected
                      ? AppTheme.primary.withValues(alpha: 0.05)
                      : Colors.transparent,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Text preview
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          data.text,
                          style: TextStyle(
                            fontFamily: data.fontFamily,
                            fontSize: _scaledFontSize(data.fontSize, boxWidth),
                            color: _parseHexColor(data.colorHex),
                            overflow: TextOverflow.ellipsis,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                        ),
                      ),
                    ),

                    // Resize handles (only when selected)
                    if (selected) ...[
                      _buildResizeHandle(
                        _ResizeCorner.topLeft,
                        parentWidth,
                        parentHeight,
                      ),
                      _buildResizeHandle(
                        _ResizeCorner.topRight,
                        parentWidth,
                        parentHeight,
                      ),
                      _buildResizeHandle(
                        _ResizeCorner.bottomLeft,
                        parentWidth,
                        parentHeight,
                      ),
                      _buildResizeHandle(
                        _ResizeCorner.bottomRight,
                        parentWidth,
                        parentHeight,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResizeHandle(
    _ResizeCorner corner,
    double parentWidth,
    double parentHeight,
  ) {
    double? left, top, right, bottom;

    switch (corner) {
      case _ResizeCorner.topLeft:
        left = -5;
        top = -5;
        break;
      case _ResizeCorner.topRight:
        right = -5;
        top = -5;
        break;
      case _ResizeCorner.bottomLeft:
        left = -5;
        bottom = -5;
        break;
      case _ResizeCorner.bottomRight:
        right = -5;
        bottom = -5;
        break;
    }

    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: GestureDetector(
        onPanStart: (_) {
          _activeCorner = corner;
          _startWidth = widget.data.width;
          _startHeight = widget.data.height;
        },
        onPanUpdate: (details) {
          if (_activeCorner == null ||
              _startWidth == null ||
              _startHeight == null) {
            return;
          }

          final dx = details.delta.dx / parentWidth;
          final dy = details.delta.dy / parentHeight;

          var newWidth = _startWidth!;
          var newHeight = _startHeight!;

          switch (_activeCorner!) {
            case _ResizeCorner.topLeft:
              newWidth = (newWidth - dx * 2).clamp(0.05, 1.0);
              newHeight = (newHeight - dy * 2).clamp(0.03, 1.0);
              break;
            case _ResizeCorner.topRight:
              newWidth = (newWidth + dx * 2).clamp(0.05, 1.0);
              newHeight = (newHeight - dy * 2).clamp(0.03, 1.0);
              break;
            case _ResizeCorner.bottomLeft:
              newWidth = (newWidth - dx * 2).clamp(0.05, 1.0);
              newHeight = (newHeight + dy * 2).clamp(0.03, 1.0);
              break;
            case _ResizeCorner.bottomRight:
              newWidth = (newWidth + dx * 2).clamp(0.05, 1.0);
              newHeight = (newHeight + dy * 2).clamp(0.03, 1.0);
              break;
          }

          _startWidth = newWidth;
          _startHeight = newHeight;
          widget.onSizeChanged?.call(widget.data.clipId, newWidth, newHeight);
        },
        onPanEnd: (_) {
          _activeCorner = null;
          _startWidth = null;
          _startHeight = null;
        },
        child: MouseRegion(
          cursor: _cursorForCorner(corner),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              border: Border.all(
                color: AppTheme.primaryLight,
                width: 1,
              ),
              shape: BoxShape.rectangle,
            ),
          ),
        ),
      ),
    );
  }

  void _onDragStart(DragStartDetails details) {
    _dragStart = details.globalPosition;
    _startPosX = widget.data.positionX;
    _startPosY = widget.data.positionY;
  }

  void _onDragUpdate(
    DragUpdateDetails details,
    double parentWidth,
    double parentHeight,
  ) {
    if (_dragStart == null || _startPosX == null || _startPosY == null) return;

    final dx = details.globalPosition.dx - _dragStart!.dx;
    final dy = details.globalPosition.dy - _dragStart!.dy;

    final newPosX = (_startPosX! + dx / parentWidth).clamp(0.05, 0.95);
    final newPosY = (_startPosY! + dy / parentHeight).clamp(0.05, 0.95);

    widget.onPositionChanged(widget.data.clipId, newPosX, newPosY);
  }

  void _onDragEnd(DragEndDetails details) {
    // Finalize the position on drag end
    widget.onPositionChanged(
      widget.data.clipId,
      widget.data.positionX,
      widget.data.positionY,
    );
    _dragStart = null;
    _startPosX = null;
    _startPosY = null;
  }

  double _scaledFontSize(double baseFontSize, double boxWidth) {
    // Scale font size based on the overlay width relative to the preview
    if (boxWidth <= 0) return baseFontSize.clamp(8.0, 120.0);
    final scale =
        boxWidth / 400; // 400px is the reference width for baseFontSize
    return (baseFontSize * scale).clamp(8.0, 120.0);
  }

  Color _parseHexColor(String hex) {
    final hexStr = hex.replaceFirst('#', '');
    return Color(int.parse('FF$hexStr', radix: 16));
  }

  MouseCursor _cursorForCorner(_ResizeCorner corner) {
    switch (corner) {
      case _ResizeCorner.topLeft:
      case _ResizeCorner.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case _ResizeCorner.topRight:
      case _ResizeCorner.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
    }
  }
}

enum _ResizeCorner { topLeft, topRight, bottomLeft, bottomRight }
