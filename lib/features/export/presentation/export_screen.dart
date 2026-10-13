import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/app_icons.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/models/project_model.dart';
import '../../projects/providers/project_provider.dart';
import '../providers/export_provider.dart';

/// Export screen — Configure and export the final video.
///
/// Premium export dialog inspired by CapCut / Premiere Pro:
/// - 16:9 preview card with accent resolution badge
/// - Resolution preset grid (720p, 1080p, 4K, Social Vertical, Social Square)
/// - Codec selection (H.264, H.265, VP9) via SegmentedButton
/// - Format selection (MP4, WebM, MOV) via SegmentedButton
/// - Live export summary card with dividers
/// - Gradient export button with subtle pulse
/// - 3-stage progress indicator (Prepare → Encode → Finalize)
/// - Complete and error states with status iconography + glow
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({required this.projectId, super.key});

  final String projectId;

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen>
    with TickerProviderStateMixin {
  String _selectedPreset = '1080p';
  String _selectedCodec = 'H.264';
  String _selectedFormat = 'MP4';
  bool _isSavingToGallery = false;
  bool _savedToGallery = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(currentProjectProvider);
    final exportState = ref.watch(exportProvider);
    final isAndroid = ref.watch(isAndroidPlatformProvider);
    final presets = ref.watch(exportPresetsProvider);

    return PopScope(
      canPop: !exportState.isExporting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && exportState.isExporting) {
          _showCancelDialog(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Export Video'),
          leading: IconButton(
            onPressed: exportState.isExporting
                ? null
                : () => context.go('/editor/${widget.projectId}'),
            icon: SvgPicture.asset(
              AppIcons.back,
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(
                exportState.isExporting
                    ? AppTheme.textDisabled
                    : AppTheme.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
          actions: [
            if (exportState.isExporting)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    exportState.progressText,
                    style: context.textTheme.titleSmall?.copyWith(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Preview card ─────────────────────────────────────────
            _buildPreviewCard(context, project),
            const SizedBox(height: 24),

            // ── Configuration (hidden while exporting / complete) ────
            if (!exportState.isExporting && !exportState.isComplete) ...[
              _buildSectionHeading(context, 'Resolution'),
              const SizedBox(height: 12),
              _buildPresetSelector(context, presets),
              const SizedBox(height: 24),

              _buildSectionHeading(context, 'Codec'),
              const SizedBox(height: 12),
              _buildCodecSelector(),
              const SizedBox(height: 24),

              _buildSectionHeading(context, 'Format'),
              const SizedBox(height: 12),
              _buildFormatSelector(),
              const SizedBox(height: 24),

              _buildExportSummary(context),
              const SizedBox(height: 28),
            ],

            // ── Status section ───────────────────────────────────────
            if (exportState.isExporting)
              _buildExportProgress(context, exportState)
            else if (exportState.isComplete)
              _buildExportComplete(context, exportState, isAndroid)
            else if (exportState.hasError)
              _buildExportError(context, exportState)
            else
              _buildExportButton(context),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Section heading ─────────────────────────────────────────────

  Widget _buildSectionHeading(BuildContext context, String text) {
    return Text(
      text,
      style: context.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }

  // ── Preview Card ────────────────────────────────────────────────

  Widget _buildPreviewCard(BuildContext context, ProjectModel? project) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Centered film icon + project name + resolution info
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppIcon(
                    AppIcons.film,
                    size: 48,
                    color: AppTheme.textDisabled,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    project?.name ?? 'Untitled',
                    style: context.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (project != null)
                    Text(
                      '${project.width} × ${project.height}  ·  '
                      '${project.fps.toStringAsFixed(0)} fps',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),

            // Subtle gradient overlay from bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 80,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(AppTheme.radiusLarge),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Top-right resolution badge
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: AppTheme.accentGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  boxShadow: AppTheme.accentGlow(),
                ),
                child: Text(
                  _selectedPreset,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Preset Selector ─────────────────────────────────────────────

  Widget _buildPresetSelector(
    BuildContext context,
    List<ExportPreset> presets,
  ) {
    final cardWidth = (MediaQuery.of(context).size.width - 40 - 10) / 2;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: presets.map((preset) {
        final isSelected = _selectedPreset == preset.name;
        return GestureDetector(
          onTap: () => setState(() => _selectedPreset = preset.name),
          child: Container(
            width: cardWidth,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.accent.withOpacity(0.12)
                  : AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                color: isSelected ? AppTheme.accent : AppTheme.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${preset.width} × ${preset.height}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (isSelected)
                  const Positioned(
                    top: 0,
                    right: 0,
                    child: AppIcon(
                      AppIcons.check,
                      size: 16,
                      color: AppTheme.accent,
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Codec Selector ──────────────────────────────────────────────

  Widget _buildCodecSelector() {
    return SegmentedButton<String>(
      style: _segmentedButtonStyle(),
      segments: const [
        ButtonSegment(
          value: 'H.264',
          label: Text('H.264'),
          tooltip: 'Best compatibility',
        ),
        ButtonSegment(
          value: 'H.265',
          label: Text('H.265'),
          tooltip: 'Better compression',
        ),
        ButtonSegment(
          value: 'VP9',
          label: Text('VP9'),
          tooltip: 'Web optimized',
        ),
      ],
      selected: {_selectedCodec},
      onSelectionChanged: (sel) => setState(() => _selectedCodec = sel.first),
    );
  }

  // ── Format Selector ─────────────────────────────────────────────

  Widget _buildFormatSelector() {
    return SegmentedButton<String>(
      style: _segmentedButtonStyle(),
      segments: const [
        ButtonSegment(value: 'MP4', label: Text('MP4')),
        ButtonSegment(value: 'WebM', label: Text('WebM')),
        ButtonSegment(value: 'MOV', label: Text('MOV')),
      ],
      selected: {_selectedFormat},
      onSelectionChanged: (sel) => setState(() => _selectedFormat = sel.first),
    );
  }

  ButtonStyle _segmentedButtonStyle() {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return AppTheme.primary;
        }
        return AppTheme.surfaceVariant;
      }),
      foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return AppTheme.textSecondary;
      }),
      side: WidgetStateProperty.all(
        const BorderSide(color: AppTheme.border, width: 1),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
    );
  }

  // ── Export Summary ──────────────────────────────────────────────

  Widget _buildExportSummary(BuildContext context) {
    final presetMap = {
      '720p': (1280, 720, 5000),
      '1080p': (1920, 1080, 10000),
      '4K': (3840, 2160, 40000),
      'Social Vertical': (1080, 1920, 8000),
      'Social Square': (1080, 1080, 6000),
    };
    final (w, h, bitrate) = presetMap[_selectedPreset] ?? (1920, 1080, 10000);
    final estimatedSizeMb = (bitrate * 60 / 8 / 1024).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Export Summary',
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              const AppIcon(
                AppIcons.info,
                size: 16,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SummaryRow(label: 'Resolution', value: '$w × $h'),
          const _SummaryDivider(),
          _SummaryRow(label: 'Codec', value: _selectedCodec),
          const _SummaryDivider(),
          _SummaryRow(label: 'Format', value: _selectedFormat),
          const _SummaryDivider(),
          _SummaryRow(label: 'Bitrate', value: '$bitrate kbps'),
          const _SummaryDivider(),
          _SummaryRow(
            label: 'Est. size (1 min)',
            value: '~$estimatedSizeMb MB',
          ),
        ],
      ),
    );
  }

  // ── Export Button (initial state) ───────────────────────────────

  Widget _buildExportButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.accentGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          boxShadow: AppTheme.accentGlow(),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _startExport,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.exportIcon,
                    size: 22,
                    color: Colors.white,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Export Video',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    )
        .animate(
          onPlay: (c) => c.repeat(reverse: true),
        )
        .scaleXY(
          begin: 1.0,
          end: 1.02,
          duration: 1500.ms,
          curve: Curves.easeInOut,
        );
  }

  // ── Export Progress (when exporting) ────────────────────────────

  Widget _buildExportProgress(BuildContext context, ExportState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 3-stage indicator: Prepare → Encode → Finalize
          Row(
            children: [
              _buildStageIndicator('Prepare', 'Preparing', state.stageName),
              _buildStageConnector('Preparing', state.stageName),
              _buildStageIndicator('Encode', 'Encoding', state.stageName),
              _buildStageConnector('Encoding', state.stageName),
              _buildStageIndicator('Finalize', 'Finalizing', state.stageName),
            ],
          ),
          const SizedBox(height: 24),

          // Large progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            child: LinearProgressIndicator(
              value: state.totalFrames == 0 && state.isExporting
                  ? null
                  : state.progress,
              backgroundColor: AppTheme.border,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.accent),
              minHeight: 12,
            ),
          ),
          const SizedBox(height: 14),

          // Progress percentage + estimated time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                state.progressText,
                style: context.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (state.estimatedTimeText.isNotEmpty)
                Text(
                  state.estimatedTimeText,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Frame progress text
          if (state.frameProgressText.isNotEmpty)
            Text(
              state.frameProgressText,
              style: context.textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),

          const SizedBox(height: 16),

          // Pulsing dot + stage name
          Row(
            children: [
              FadeTransition(
                opacity: _pulseController,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppTheme.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${state.stageName}…',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Warning box (orange tinted)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const AppIcon(
                  AppIcons.warning,
                  size: 18,
                  color: AppTheme.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Do not close the app during export',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: AppTheme.warning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Cancel button (outlined, red)
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _showCancelDialog(context),
              icon: const AppIcon(
                AppIcons.close,
                size: 16,
                color: AppTheme.error,
              ),
              label: const Text('Cancel Export'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error, width: 1.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageIndicator(
    String label,
    String stageKey,
    String currentStage,
  ) {
    final status = _stageStatus(stageKey, currentStage);
    const size = 32.0;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: status == 'pending' ? AppTheme.surfaceVariant : AppTheme.accent,
              border: Border.all(
                color: status == 'pending' ? AppTheme.border : AppTheme.accent,
                width: 2,
              ),
              boxShadow: status == 'active' ? AppTheme.accentGlow() : const [],
            ),
            child: _buildStageIcon(status),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: status == 'pending'
                  ? AppTheme.textDisabled
                  : AppTheme.accent,
              fontWeight: status == 'pending'
                  ? FontWeight.w500
                  : FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildStageIcon(String status) {
    if (status == 'completed') {
      return const Center(
        child: AppIcon(
          AppIcons.check,
          size: 16,
          color: Colors.white,
        ),
      );
    }
    if (status == 'active') {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }
    return null;
  }

  Widget _buildStageConnector(String stageKey, String currentStage) {
    final completed = _stageStatus(stageKey, currentStage) == 'completed';
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        width: 20,
        height: 2,
        color: completed ? AppTheme.accent : AppTheme.border,
      ),
    );
  }

  /// Returns `'completed'`, `'active'`, or `'pending'` for the given stage.
  String _stageStatus(String stage, String currentStage) {
    const order = ['Preparing', 'Encoding', 'Finalizing', 'Complete'];
    final currentIndex = order.indexOf(currentStage);
    final stageIndex = order.indexOf(stage);
    if (currentIndex < 0 || stageIndex < 0) return 'pending';
    if (stageIndex < currentIndex) return 'completed';
    if (stageIndex == currentIndex) return 'active';
    return 'pending';
  }

  // ── Export Complete ─────────────────────────────────────────────

  Widget _buildExportComplete(
    BuildContext context,
    ExportState state,
    bool isAndroid,
  ) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        children: [
          // Large check circle with success glow
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.success.withOpacity(0.15),
              border: Border.all(color: AppTheme.success, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.success.withOpacity(0.4),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Center(
              child: AppIcon(
                AppIcons.check,
                size: 32,
                color: AppTheme.success,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Export Complete!',
            style: context.textTheme.headlineSmall?.copyWith(
              color: AppTheme.success,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (state.fileSizeHuman != null)
            Text(
              'File size: ${state.fileSizeHuman}',
              style: context.textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          const SizedBox(height: 24),

          if (isAndroid &&
              state.outputPath != null &&
              StorageService.videoMimeTypeForPath(state.outputPath!) !=
                  null) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _isSavingToGallery || _savedToGallery
                    ? null
                    : () => _saveToGallery(state.outputPath!),
                icon: _isSavingToGallery
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _savedToGallery
                            ? Icons.check_circle_outline
                            : Icons.photo_library_outlined,
                        size: 20,
                      ),
                label: Text(
                  _isSavingToGallery
                      ? 'Saving to Gallery...'
                      : _savedToGallery
                          ? 'Saved to Gallery'
                          : 'Save to Gallery',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _savedToGallery ? AppTheme.success : AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Share Video button (accent gradient, full width)
          _buildGradientButton(
            onTap: () =>
                ref.read(exportProvider.notifier).shareExportedFile(),
            icon: AppIcons.share,
            label: 'Share Video',
          ),
          const SizedBox(height: 12),

          // Export Again button (outlined, full width)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _isSavingToGallery = false;
                  _savedToGallery = false;
                });
                ref.read(exportProvider.notifier).reset();
              },
              icon: const Icon(Icons.refresh, size: 20, color: AppTheme.textPrimary),
              label: const Text('Export Again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.borderLight, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Export Error ────────────────────────────────────────────────

  Widget _buildExportError(BuildContext context, ExportState state) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        children: [
          // Error icon (64px, error color)
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.error.withOpacity(0.15),
              border: Border.all(color: AppTheme.error, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.error.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: AppIcon(
                AppIcons.error,
                size: 32,
                color: AppTheme.error,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Export Failed',
            style: context.textTheme.headlineSmall?.copyWith(
              color: AppTheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            state.error ?? 'Unknown error',
            style: context.textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Try Again button (accent gradient)
          _buildGradientButton(
            onTap: () => ref.read(exportProvider.notifier).reset(),
            icon: AppIcons.exportIcon,
            label: 'Try Again',
          ),
        ],
      ),
    );
  }

  // ── Shared gradient button (Share / Try Again) ──────────────────

  Widget _buildGradientButton({
    required VoidCallback onTap,
    required String icon,
    required String label,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.accentGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          boxShadow: AppTheme.accentGlow(),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(icon, size: 20, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────

  void _startExport() {
    setState(() {
      _isSavingToGallery = false;
      _savedToGallery = false;
    });
    ref.read(exportProvider.notifier).startExport(
          preset: _selectedPreset,
          codec: _selectedCodec,
          format: _selectedFormat,
        );
  }

  Future<void> _saveToGallery(String filePath) async {
    final mimeType = StorageService.videoMimeTypeForPath(filePath);
    if (mimeType == null || _isSavingToGallery || _savedToGallery) return;

    setState(() => _isSavingToGallery = true);
    String? savedUri;
    try {
      savedUri = await StorageService.saveToMediaStore(
        filePath: filePath,
        displayName: p.basename(filePath),
        mimeType: mimeType,
      );
    } catch (_) {
      // Show a stable, user-facing message without exposing platform details.
    }

    if (!mounted) return;
    setState(() {
      _isSavingToGallery = false;
      _savedToGallery = savedUri != null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            savedUri == null
                ? 'Could not save the video. Check available storage and try again.'
                : 'Video saved to Movies/EDITORS-PRO.',
          ),
        ),
      );
  }

  Future<void> _showCancelDialog(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Export?'),
        content: const Text(
          'The current export will be stopped and the partial file will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continue Export'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel Export'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      unawaited(ref.read(exportProvider.notifier).cancelExport());
    }
  }
}

// ── Summary Row Widget ─────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(color: AppTheme.border, thickness: 1, height: 1);
  }
}
