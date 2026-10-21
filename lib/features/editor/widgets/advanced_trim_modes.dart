import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase F: Advanced Trim Modes toolbar.
///
/// Exposes the four pro trim modes: Ripple, Roll, Slip, Slide.
/// Each mode is a toolbar button; the active mode colors the toolbar.
///
/// The amateur move is to do everything with regular trim + ripple-delete.
/// The pro move is to use the right trim mode for the job — ripple to
/// close gaps, roll for cut-point refinement, slip for reframing, slide
/// for nudging. See persona/skills/ripple-roll-trim/SKILL.md.
class AdvancedTrimModes extends StatefulWidget {
  // The delta applied per frame while scrubbing

  const AdvancedTrimModes({
    required this.activeMode,
    required this.onModeChanged,
    super.key,
    this.deltaMs = 100,
  });
  final AdvancedTrimMode activeMode;
  final void Function(AdvancedTrimMode mode) onModeChanged;
  final int deltaMs;

  @override
  State<AdvancedTrimModes> createState() => _AdvancedTrimModesState();
}

class _AdvancedTrimModesState extends State<AdvancedTrimModes> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing8,
        vertical: AppTheme.spacing4,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            'Trim mode:',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: AppTheme.spacing8),
          for (final mode in AdvancedTrimMode.values)
            Padding(
              padding: const EdgeInsets.only(right: AppTheme.spacing4),
              child: _ModeButton(
                mode: mode,
                isActive: mode == widget.activeMode,
                onTap: () => widget.onModeChanged(mode),
              ),
            ),
          const Spacer(),
          // Help icon
          IconButton(
            icon: const Icon(Icons.help_outline, size: 18),
            tooltip: 'Trim mode help',
            onPressed: () => _showHelp(context),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Advanced Trim Modes'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ripple',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Trim clip + shift subsequent clips to close the gap. '
                  'Total timeline duration changes.'),
              SizedBox(height: 8),
              Text(
                'Roll',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Trim two adjacent clips simultaneously — one shorter, '
                  'one longer. Total duration unchanged.'),
              SizedBox(height: 8),
              Text(
                'Slip',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Change in/out without changing duration or position. '
                  'You see different frames of the same shot.'),
              SizedBox(height: 8),
              Text(
                'Slide',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Move clip between neighbors — neighbors trimmed to '
                  'make room. Total duration unchanged; slid clip unchanged.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.mode,
    required this.isActive,
    required this.onTap,
  });
  final AdvancedTrimMode mode;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? Theme.of(context).colorScheme.primary
        : AppTheme.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          border:
              Border.all(color: color.withValues(alpha: isActive ? 0.7 : 0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(mode.icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(mode.label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

enum AdvancedTrimMode {
  ripple('Ripple', Icons.waves),
  roll('Roll', Icons.swap_horiz),
  slip('Slip', Icons.swap_calls),
  slide('Slide', Icons.compare_arrows);

  const AdvancedTrimMode(this.label, this.icon);
  final String label;
  final IconData icon;
}
