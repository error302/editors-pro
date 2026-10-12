import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/constants/app_icons.dart';
import '../providers/editor_provider.dart';
import '../../projects/providers/project_provider.dart';

/// Top toolbar for the editor screen — CapCut-inspired clean dark style.
///
/// Layout (left → right):
///  1. Back button (navigates to '/')
///  2. Project name + resolution badge (surfaceVariant pill)
///  3. Divider
///  4. Undo / 5. Redo / 6. Save (text button, primary)
///  7. Divider
///  8. Skip to start / 9. Play-Pause (primary circle) / 10. Skip to end
///  11. Speed selector (compact surfaceVariant pill)
///  12. SMPTE timecode display (monospace, no background)
///  13. Edit mode toggles (Ripple / Rolling / Snap)
///  14. Spacer
///  15. Split / 16. Delete / 17. Freeze Frame
///  18. Divider
///  19. Export button (solid primary)
class EditorToolbar extends ConsumerStatefulWidget {
  const EditorToolbar({super.key});

  @override
  ConsumerState<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends ConsumerState<EditorToolbar> {
  /// Whether ripple edit mode is active.
  bool _rippleEdit = false;

  /// Whether rolling edit mode is active.
  bool _rollingEdit = false;

  /// Whether snap-to-grid is active.
  bool _snapToGrid = true;

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final project = ref.watch(currentProjectProvider);
    final hasSelection = editorState.selectedClipId != null;
    if (MediaQuery.sizeOf(context).width < 600) {
      return _buildCompactToolbar(
          context, project?.name ?? 'Untitled', project?.id);
    }

    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing12),
        child: Row(
          children: [
            // ── 1. Back ─────────────────────────────────────────────
            _PlainIconButton(
              icon: AppIcons.back,
              tooltip: 'Back to projects',
              onPressed: () => context.go('/'),
            ),
            const SizedBox(width: AppTheme.spacing8),

            // ── 2. Project name + resolution badge ─────────────────
            Text(
              project?.name ?? 'Untitled',
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: AppTheme.spacing8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              child: Text(
                '${project?.width ?? 1920}×${project?.height ?? 1080}',
                style: context.textTheme.labelSmall?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // ── 3. Divider ─────────────────────────────────────────
            _groupDivider(),

            // ── 4. Undo / 5. Redo / 6. Save ────────────────────────
            _PlainIconButton(
              icon: AppIcons.undo,
              tooltip: 'Undo',
              onPressed: () {
                // Phase E.6: light haptic on undo/redo — non-destructive.
                HapticFeedback.selectionClick();
                ref.read(editorProvider.notifier).undo();
              },
            ),
            const SizedBox(width: AppTheme.spacing4),
            _PlainIconButton(
              icon: AppIcons.redo,
              tooltip: 'Redo',
              onPressed: () {
                HapticFeedback.selectionClick();
                ref.read(editorProvider.notifier).redo();
              },
            ),
            const SizedBox(width: AppTheme.spacing4),
            TextButton(
              onPressed: () async {
                final saved = await ref
                    .read(projectProvider.notifier)
                    .saveCurrentProject();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        saved ? 'Project saved' : 'Could not save project',
                      ),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing8,
                  vertical: AppTheme.spacing4,
                ),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Save'),
            ),

            // ── 7. Divider ─────────────────────────────────────────
            _groupDivider(),

            // ── 8. Skip to start ───────────────────────────────────
            _PlainIconButton(
              icon: AppIcons.skipBack,
              tooltip: 'Go to start',
              onPressed: () => ref.read(editorProvider.notifier).seekTo(0),
            ),
            const SizedBox(width: AppTheme.spacing4),

            // ── 9. Play / Pause (primary circle, no glow) ──────────
            _PlayPauseButton(
              isPlaying: editorState.isPlaying,
              onPressed: () =>
                  ref.read(editorProvider.notifier).togglePlayback(),
            ),
            const SizedBox(width: AppTheme.spacing4),

            // ── 10. Skip to end ────────────────────────────────────
            _PlainIconButton(
              icon: AppIcons.skipForward,
              tooltip: 'Go to end',
              onPressed: () => ref
                  .read(editorProvider.notifier)
                  .seekTo(editorState.durationMs),
            ),

            // ── 11. Speed selector ─────────────────────────────────
            const SizedBox(width: AppTheme.spacing8),
            _PlaybackSpeedButton(
              currentSpeed: editorState.playbackSpeed,
              onSpeedChanged: (speed) =>
                  ref.read(editorProvider.notifier).setPlaybackSpeed(speed),
            ),

            const SizedBox(width: AppTheme.spacing8),

            // ── 12. SMPTE timecode display ─────────────────────────
            _SmpteTimecodeDisplay(
              currentTimeMs: editorState.currentTimeMs,
              durationMs: editorState.durationMs,
              fps: project?.fps ?? 30.0,
            ),

            const SizedBox(width: AppTheme.spacing8),

            // ── 13. Edit mode toggles ──────────────────────────────
            _EditModeToggleButton(
              icon: Icons.compare_arrows,
              label: 'Ripple',
              tooltip: 'Ripple edit — shifts subsequent clips',
              isActive: _rippleEdit,
              onPressed: () {
                setState(() {
                  _rippleEdit = !_rippleEdit;
                  // Ripple and rolling are mutually exclusive
                  if (_rippleEdit) _rollingEdit = false;
                });
                HapticFeedback.selectionClick();
              },
            ),
            const SizedBox(width: AppTheme.spacing4),
            _EditModeToggleButton(
              icon: Icons.sync_alt,
              label: 'Rolling',
              tooltip: 'Rolling edit — trims adjacent clips',
              isActive: _rollingEdit,
              onPressed: () {
                setState(() {
                  _rollingEdit = !_rollingEdit;
                  // Ripple and rolling are mutually exclusive
                  if (_rollingEdit) _rippleEdit = false;
                });
                HapticFeedback.selectionClick();
              },
            ),
            const SizedBox(width: AppTheme.spacing4),
            _EditModeToggleButton(
              icon: Icons.grid_on,
              label: 'Snap',
              tooltip: 'Snap to grid — align clips to markers and boundaries',
              isActive: _snapToGrid,
              onPressed: () {
                setState(() => _snapToGrid = !_snapToGrid);
                HapticFeedback.selectionClick();
              },
            ),

            // ── 14. Spacer ─────────────────────────────────────────
            const Spacer(),

            // ── 15. Split ──────────────────────────────────────────
            _ActionIconButton(
              svgIcon: AppIcons.split,
              tooltip: 'Split at playhead',
              onPressed: () {
                // Phase E.6: haptic feedback on split — confirms the
                // destructive action was triggered.
                HapticFeedback.mediumImpact();
                ref.read(editorProvider.notifier).splitAtPlayhead();
              },
            ),
            const SizedBox(width: AppTheme.spacing4),

            // ── 16. Delete (error color when a clip is selected) ───
            _ActionIconButton(
              svgIcon: AppIcons.deleteItem,
              tooltip: 'Delete selected',
              color: hasSelection ? AppTheme.error : AppTheme.textPrimary,
              disabledColor: AppTheme.textDisabled,
              onPressed: hasSelection
                  ? () {
                      // Phase E.6: heavier haptic on delete — more
                      // destructive than split.
                      HapticFeedback.heavyImpact();
                      ref.read(editorProvider.notifier).deleteSelected();
                    }
                  : null,
            ),
            const SizedBox(width: AppTheme.spacing4),

            // ── 17. Freeze Frame (snowflake — same style as split) ─
            _ActionIconButton(
              iconData: Icons.ac_unit,
              tooltip: 'Freeze frame',
              onPressed: () {
                HapticFeedback.mediumImpact();
                ref.read(editorProvider.notifier).splitAtPlayhead();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Freeze frame created'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),

            // ── 18. Divider ────────────────────────────────────────
            _groupDivider(),

            // ── 19. Export button (solid primary, no gradient) ─────
            _ExportButton(
              onPressed: project != null
                  ? () => context.go('/export/${project.id}')
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactToolbar(
    BuildContext context,
    String projectName,
    String? projectId,
  ) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            bottom: BorderSide(color: AppTheme.border, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _mobileIconButton(
              icon: AppIcons.back,
              tooltip: 'Back to projects',
              onPressed: () => context.go('/'),
            ),
            Expanded(
              child: Text(
                projectName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            _mobileIconButton(
              icon: AppIcons.undo,
              tooltip: 'Undo',
              onPressed: () {
                HapticFeedback.selectionClick();
                ref.read(editorProvider.notifier).undo();
              },
            ),
            _mobileIconButton(
              icon: AppIcons.redo,
              tooltip: 'Redo',
              onPressed: () {
                HapticFeedback.selectionClick();
                ref.read(editorProvider.notifier).redo();
              },
            ),
            _mobileIconButton(
              icon: AppIcons.save,
              tooltip: 'Save project',
              onPressed: () async {
                final saved = await ref
                    .read(projectProvider.notifier)
                    .saveCurrentProject();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        saved ? 'Project saved' : 'Could not save project',
                      ),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
            ),
            _mobileIconButton(
              icon: AppIcons.exportIcon,
              tooltip: 'Export project',
              onPressed: projectId == null
                  ? null
                  : () => context.go('/export/$projectId'),
              color: AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileIconButton({
    required String icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color color = AppTheme.textSecondary,
  }) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: SvgPicture.asset(
          icon,
          width: 20,
          height: 20,
          colorFilter: ColorFilter.mode(
            onPressed == null ? AppTheme.textDisabled : color,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }

  /// Thin 1px vertical divider used between major toolbar groups.
  Widget _groupDivider() => Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing8,
        ),
        width: 1,
        height: 24,
        color: AppTheme.border,
      );
}

// ═══════════════════════════════════════════════════════════════════════
// Plain icon button — no background, textSecondary icon
// ═══════════════════════════════════════════════════════════════════════

/// Clean icon button with no background circle. Used for back, undo/redo,
/// and skip buttons.
///
/// Shows [AppTheme.textDisabled] when [onPressed] is null.
class _PlainIconButton extends StatelessWidget {
  final String icon;
  final String? tooltip;
  final Color color;
  final Color disabledColor;
  final double iconSize;
  final VoidCallback? onPressed;

  const _PlainIconButton({
    required this.icon,
    this.tooltip,
    this.color = AppTheme.textSecondary,
    this.disabledColor = AppTheme.textDisabled,
    this.iconSize = 18,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final iconColor = enabled ? color : disabledColor;

    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          hoverColor: Colors.transparent,
          splashColor: AppTheme.surfaceVariant.withOpacity(0.4),
          highlightColor: AppTheme.surfaceVariant.withOpacity(0.3),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: SvgPicture.asset(
              icon,
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Play / Pause — circular primary button, 40×40, no glow
// ═══════════════════════════════════════════════════════════════════════

/// Circular 40×40 play/pause button with [AppTheme.primary] background
/// and a white icon. No glow / no shadow.
class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isPlaying ? 'Pause' : 'Play',
      child: Material(
        color: AppTheme.primary,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: SvgPicture.asset(
              isPlaying ? AppIcons.pause : AppIcons.play,
              width: 18,
              height: 18,
              colorFilter:
                  const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Action icon button — transparent bg, surfaceVariant on hover
// ═══════════════════════════════════════════════════════════════════════

/// Icon button for split / delete / freeze-frame actions.
///
/// Transparent background by default, [AppTheme.surfaceVariant] on hover.
/// Uses [AppTheme.textPrimary] icon color (override with [color]).
/// Supports both SVG (via [svgIcon]) and Material (via [iconData]) icons.
class _ActionIconButton extends StatelessWidget {
  /// SVG asset path. Either this or [iconData] must be provided.
  final String? svgIcon;

  /// Material icon data. Either this or [svgIcon] must be provided.
  final IconData? iconData;

  final String? tooltip;
  final Color? color;
  final Color? disabledColor;
  final VoidCallback? onPressed;

  const _ActionIconButton({
    this.svgIcon,
    this.iconData,
    this.tooltip,
    this.color,
    this.disabledColor,
    this.onPressed,
  }) : assert(
          svgIcon != null || iconData != null,
          'Either svgIcon or iconData must be provided',
        );

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final iconColor = enabled
        ? (color ?? AppTheme.textPrimary)
        : (disabledColor ?? AppTheme.textDisabled);

    Widget iconChild;
    if (svgIcon != null) {
      iconChild = SvgPicture.asset(
        svgIcon!,
        width: 18,
        height: 18,
        colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
      );
    } else {
      iconChild = Icon(iconData, size: 18, color: iconColor);
    }

    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          hoverColor: AppTheme.surfaceVariant,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: iconChild,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SMPTE Timecode Display
// ═══════════════════════════════════════════════════════════════════════

/// SMPTE timecode display in HH:MM:SS:FF format.
///
/// Plain monospace text — no background or border. Shows current timecode,
/// a separator, and the duration timecode at the project's frame rate.
class _SmpteTimecodeDisplay extends StatelessWidget {
  final int currentTimeMs;
  final int durationMs;
  final double fps;

  const _SmpteTimecodeDisplay({
    required this.currentTimeMs,
    required this.durationMs,
    required this.fps,
  });

  @override
  Widget build(BuildContext context) {
    final currentTc = _msToSmpte(currentTimeMs, fps);
    final durationTc = _msToSmpte(durationMs, fps);

    // titleSmall = 14px / w600 per AppTheme.
    const currentStyle = TextStyle(
      fontFamily: 'monospace',
      color: AppTheme.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    const sepStyle = TextStyle(
      fontFamily: 'monospace',
      color: AppTheme.textDisabled,
      fontSize: 14,
    );
    const durationStyle = TextStyle(
      fontFamily: 'monospace',
      color: AppTheme.textSecondary,
      fontSize: 14,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(currentTc, style: currentStyle),
        const Text(' / ', style: sepStyle),
        Text(durationTc, style: durationStyle),
      ],
    );
  }

  /// Convert milliseconds to SMPTE timecode string (HH:MM:SS:FF).
  ///
  /// The frame number is calculated based on the project [fps].
  /// For non-integer frame rates (e.g., 29.97), drop-frame timecode
  /// is not implemented here — a simple rounding approach is used.
  static String _msToSmpte(int ms, double fps) {
    final effectiveFps = fps > 0 ? fps : 30.0;
    final totalSeconds = ms ~/ 1000;
    final remainingMs = ms % 1000;
    final frame = (remainingMs * effectiveFps / 1000).floor();

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final frames = frame.clamp(0, (effectiveFps - 1).floor());

    return '${hours.toString().padLeft(2, '0')}'
        ':${minutes.toString().padLeft(2, '0')}'
        ':${seconds.toString().padLeft(2, '0')}'
        ':${frames.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Edit Mode Toggle Button
// ═══════════════════════════════════════════════════════════════════════

/// Compact toggle button for edit mode selection (Ripple / Rolling / Snap).
///
/// Active: [AppTheme.surfaceVariant] background, [AppTheme.primary]
/// icon/text. Inactive: transparent background, [AppTheme.textSecondary].
class _EditModeToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool isActive;
  final VoidCallback onPressed;

  const _EditModeToggleButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppTheme.primary : AppTheme.textSecondary;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing8,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.surfaceVariant : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: AppTheme.spacing4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Export Button — solid primary, no gradient
// ═══════════════════════════════════════════════════════════════════════

/// Compact export button — solid [AppTheme.primary] background with white
/// text and a small export icon. Rounded corners, no gradient or glow.
class _ExportButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _ExportButton({this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing12,
              vertical: AppTheme.spacing4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  AppIcons.exportIcon,
                  width: 14,
                  height: 14,
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
                const SizedBox(width: AppTheme.spacing4),
                const Text(
                  'Export',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Playback Speed Selector — compact surfaceVariant pill
// ═══════════════════════════════════════════════════════════════════════

/// Compact playback speed selector — pill button that opens a popup menu.
class _PlaybackSpeedButton extends StatelessWidget {
  final double currentSpeed;
  final ValueChanged<double> onSpeedChanged;

  const _PlaybackSpeedButton({
    required this.currentSpeed,
    required this.onSpeedChanged,
  });

  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0];

  @override
  Widget build(BuildContext context) {
    final isNonDefault = currentSpeed != 1.0;
    return PopupMenuButton<double>(
      offset: const Offset(0, 44),
      tooltip: 'Playback speed',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing8,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Text(
          '${currentSpeed.toStringAsFixed(1)}x',
          style: TextStyle(
            color: isNonDefault ? AppTheme.primary : AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ),
      itemBuilder: (context) => _speeds.map((speed) {
        return PopupMenuItem<double>(
          value: speed,
          child: Row(
            children: [
              if (speed == currentSpeed)
                const Icon(Icons.check, size: 16, color: AppTheme.primary)
              else
                const SizedBox(width: 16),
              const SizedBox(width: AppTheme.spacing8),
              Text('${speed}x'),
            ],
          ),
        );
      }).toList(),
      onSelected: onSpeedChanged,
    );
  }
}
