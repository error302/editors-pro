import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/editor_provider.dart';

/// A small badge that shows GPU/CPU rendering status.
///
/// Displays:
/// - "GPU" in green with a dot when GPU acceleration is active
/// - "CPU" in grey when GPU is not available or disabled
/// - "HW" in blue during hardware-accelerated export
class GpuStatusBadge extends ConsumerWidget {
  const GpuStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(editorProvider);
    final isExporting = editorState.isExporting;
    final gpuAvailable = editorState.gpuAvailable;
    final gpuEnabled = editorState.gpuAccelerationEnabled;
    final hwEncoder = editorState.hardwareEncoderAvailable;

    // During hardware-accelerated export, show "HW" badge
    if (isExporting && gpuAvailable && gpuEnabled && hwEncoder) {
      return _buildBadge(
        label: 'HW',
        color: AppTheme.info,
        showDot: true,
      );
    }

    // GPU available and enabled
    if (gpuAvailable && gpuEnabled) {
      return _buildBadge(
        label: 'GPU',
        color: AppTheme.success,
        showDot: true,
      );
    }

    // CPU mode (GPU unavailable or disabled)
    return _buildBadge(
      label: 'CPU',
      color: AppTheme.textDisabled,
      showDot: false,
    );
  }

  Widget _buildBadge({
    required String label,
    required Color color,
    required bool showDot,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
