import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase F: Multicam Switcher.
///
/// Exposes the existing engine/src/effects/multicam.rs module. Renders a
/// grid of angle thumbnails; tap to switch to that angle in real time.
///
/// Workflow: (1) sync angles via audio cross-correlation or timecode,
/// (2) play back in real time, tapping angles to switch, (3) refine cuts
/// afterward.
///
/// The amateur move is to cut between angles with no rhythm and no audio
/// sync reference. The pro move is to sync via audio, live-switch with
/// the event's beat, refine cuts, hard cuts for energy, dissolves for
/// soft transitions. See persona/skills/multicam-editing/SKILL.md.
class MulticamSwitcher extends StatefulWidget {
  const MulticamSwitcher({
    required this.angles,
    required this.activeAngleIndex,
    required this.onSwitchAngle,
    required this.onResync,
    super.key,
    this.isSynced = false,
  });
  final List<MulticamAngle> angles;
  final int activeAngleIndex;
  final void Function(int angleIndex) onSwitchAngle;
  final VoidCallback onResync;
  final bool isSynced;

  @override
  State<MulticamSwitcher> createState() => _MulticamSwitcherState();
}

class _MulticamSwitcherState extends State<MulticamSwitcher> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Multicam Switcher',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            if (!widget.isSynced)
              ElevatedButton.icon(
                onPressed: widget.onResync,
                icon: const Icon(Icons.sync),
                label: const Text('Sync'),
              )
            else
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Synced',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing8),
        Text(
          'Tap an angle to switch in real time. Cut on the beat of the event.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Angle grid
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: AppTheme.spacing8,
              mainAxisSpacing: AppTheme.spacing8,
              childAspectRatio: 16 / 11,
            ),
            itemCount: widget.angles.length,
            itemBuilder: (context, i) {
              final angle = widget.angles[i];
              final isActive = i == widget.activeAngleIndex;
              return GestureDetector(
                onTap: () => widget.onSwitchAngle(i),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isActive
                          ? Colors.blue
                          : Colors.grey.withValues(alpha: 0.3),
                      width: isActive ? 3 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      // Thumbnail placeholder
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: angle.thumbnail != null
                            ? Image.memory(angle.thumbnail!, fit: BoxFit.cover)
                            : Center(
                                child: Icon(
                                  Icons.videocam,
                                  color: Colors.grey.withValues(alpha: 0.5),
                                ),
                              ),
                      ),
                      // Angle label
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            angle.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      // Active indicator
                      if (isActive)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.fiber_manual_record,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      // Audio source indicator
                      if (angle.isAudioSource)
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.graphic_eq,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppTheme.spacing8),
        // Tip
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
                  'Hard cuts for energy, dissolves for soft transitions. '
                  'Audio from the best angle (usually the board feed — green badge).',
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

class MulticamAngle {
  MulticamAngle({
    required this.label,
    required this.clipId,
    this.thumbnail,
    this.isAudioSource = false,
  });
  final String label;
  final String clipId;
  final Uint8List? thumbnail;
  final bool isAudioSource;
}
