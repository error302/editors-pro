import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

/// Reusable SVG icon widget with consistent sizing and coloring.
///
/// Usage:
///   AppIcon(AppIcons.play, size: 20, color: AppTheme.primary)
///   AppIcon(AppIcons.undo)  // defaults: 20px, textSecondary
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.onTap,
  });
  final String icon;
  final double? size;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveSize = size ?? 20;
    final effectiveColor = color ?? AppTheme.textSecondary;

    final child = SvgPicture.asset(
      icon,
      width: effectiveSize,
      height: effectiveSize,
      colorFilter: ColorFilter.mode(effectiveColor, BlendMode.srcIn),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.all((effectiveSize * 0.3).clamp(2, 8)),
          child: child,
        ),
      );
    }

    return child;
  }
}

/// Toolbar icon button using SVG icons — for the editor toolbar.
class SvgToolbarButton extends StatelessWidget {
  const SvgToolbarButton({
    required this.icon,
    super.key,
    this.tooltip,
    this.onPressed,
    this.color,
    this.iconSize = 18,
    this.isActive = false,
  });
  final String icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double iconSize;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: SvgPicture.asset(
                icon,
                width: iconSize,
                height: iconSize,
                colorFilter: ColorFilter.mode(
                  color ??
                      (isActive ? AppTheme.primary : AppTheme.textSecondary),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
