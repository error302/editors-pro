import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/transcription_provider.dart';

/// Available language options for transcription
const _languageOptions = [
  {'code': 'auto', 'name': 'Auto-detect'},
  {'code': 'en', 'name': 'English'},
  {'code': 'es', 'name': 'Spanish'},
  {'code': 'fr', 'name': 'French'},
  {'code': 'de', 'name': 'German'},
  {'code': 'it', 'name': 'Italian'},
  {'code': 'pt', 'name': 'Portuguese'},
  {'code': 'zh', 'name': 'Chinese'},
  {'code': 'ja', 'name': 'Japanese'},
  {'code': 'ko', 'name': 'Korean'},
  {'code': 'ar', 'name': 'Arabic'},
  {'code': 'hi', 'name': 'Hindi'},
  {'code': 'ru', 'name': 'Russian'},
];

/// Available model size options
const _modelOptions = [
  {'code': 'tiny', 'name': 'Tiny', 'desc': 'Fastest, least accurate (~39 MB)'},
  {'code': 'base', 'name': 'Base', 'desc': 'Good balance for mobile (~74 MB)'},
  {'code': 'small', 'name': 'Small', 'desc': 'Higher accuracy (~244 MB)'},
];

/// Auto Caption widget — provides transcription UI for creating subtitles
///
/// Displays:
/// - Language selector dropdown
/// - Model size selector dropdown
/// - Transcription progress indicator with status labels
/// - Preview of transcribed segments with editing
/// - Confidence color coding on segments
/// - Select All / Deselect All toggle
/// - Export SRT / Export VTT buttons
/// - "Add to Timeline" button
class AutoCaption extends ConsumerStatefulWidget {
  const AutoCaption({
    required this.assetId,
    required this.trackId,
    super.key,
  });

  /// The asset ID of the video/audio to transcribe
  final String assetId;

  /// The text track ID where subtitle clips will be added
  final String trackId;

  @override
  ConsumerState<AutoCaption> createState() => _AutoCaptionState();
}

class _AutoCaptionState extends ConsumerState<AutoCaption> {
  /// Segment ID currently being edited (null = none)
  String? _editingSegmentId;
  late TextEditingController _editController;
  late FocusNode _editFocusNode;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _editFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Phase B.7: hide the Auto Caption UI entirely unless the user has
    // opted in via Settings > Experimental > Auto Captions. The Rust
    // transcription engine is a simulation that produces placeholder
    // segments; exposing the UI without real Whisper integration would
    // mislead users. See AUDIT_REPORT.md §1.4.
    final autoCaptionsEnabled = ref.watch(
      settingsProvider.select((s) => s.experimentalAutoCaptions),
    );
    if (!autoCaptionsEnabled) {
      return const SizedBox.shrink();
    }

    final transcriptionState = ref.watch(transcriptionProvider);

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: AppTheme.textDisabled.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _buildHeader(transcriptionState),
          const SizedBox(height: AppTheme.spacing12),

          // Language selector
          _buildLanguageSelector(transcriptionState),
          const SizedBox(height: AppTheme.spacing8),

          // Model size selector
          _buildModelSelector(transcriptionState),
          const SizedBox(height: AppTheme.spacing12),

          // Transcription button or progress
          if (transcriptionState.isTranscribing)
            _buildProgressIndicator(transcriptionState)
          else
            _buildTranscribeButton(transcriptionState),

          // Error message
          if (transcriptionState.errorMessage != null) ...[
            const SizedBox(height: AppTheme.spacing8),
            _buildErrorMessage(transcriptionState),
          ],

          // Segments preview
          if (transcriptionState.hasSegments) ...[
            const SizedBox(height: AppTheme.spacing16),
            _buildSegmentControls(transcriptionState),
            const SizedBox(height: AppTheme.spacing8),
            _buildSegmentsPreview(transcriptionState),
            const SizedBox(height: AppTheme.spacing12),
            _buildExportButtons(transcriptionState),
            const SizedBox(height: AppTheme.spacing8),
            _buildAddToTimelineButton(transcriptionState),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(TranscriptionState state) {
    return Row(
      children: [
        const Icon(
          Icons.mic_outlined,
          size: 20,
          color: AppTheme.secondary,
        ),
        const SizedBox(width: 8),
        Text(
          'Auto Caption',
          style: context.textTheme.titleSmall?.copyWith(
            color: AppTheme.textPrimary,
          ),
        ),
        const Spacer(),
        if (state.hasSegments)
          Text(
            '${state.selectedCount}/${state.segments.length} segments',
            style: context.textTheme.bodySmall?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        if (state.status == TranscriptionStatus.complete) ...[
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppTheme.success,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLanguageSelector(TranscriptionState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LANGUAGE',
          style: context.textTheme.labelMedium?.copyWith(
            color: AppTheme.textDisabled,
            letterSpacing: 1,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: state.selectedLanguage,
              isExpanded: true,
              icon: const Icon(
                Icons.language,
                size: 18,
                color: AppTheme.textSecondary,
              ),
              style: context.textTheme.bodyMedium,
              dropdownColor: AppTheme.surfaceVariant,
              items: _languageOptions.map((lang) {
                return DropdownMenuItem<String>(
                  value: lang['code'],
                  child: Text(
                    lang['name']!,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                );
              }).toList(),
              onChanged: state.isTranscribing
                  ? null
                  : (value) {
                      if (value != null) {
                        ref
                            .read(transcriptionProvider.notifier)
                            .setLanguage(value);
                      }
                    },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModelSelector(TranscriptionState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MODEL SIZE',
          style: context.textTheme.labelMedium?.copyWith(
            color: AppTheme.textDisabled,
            letterSpacing: 1,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: state.selectedModel,
              isExpanded: true,
              icon: const Icon(
                Icons.memory,
                size: 18,
                color: AppTheme.textSecondary,
              ),
              style: context.textTheme.bodyMedium,
              dropdownColor: AppTheme.surfaceVariant,
              items: _modelOptions.map((model) {
                return DropdownMenuItem<String>(
                  value: model['code'],
                  child: Row(
                    children: [
                      Text(
                        model['name']!,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          model['desc']!,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: state.isTranscribing
                  ? null
                  : (value) {
                      if (value != null) {
                        ref
                            .read(transcriptionProvider.notifier)
                            .setModel(value);
                      }
                    },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTranscribeButton(TranscriptionState state) {
    final hadPreviousResult = state.hasSegments;
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: OutlinedButton.icon(
        onPressed: () {
          ref
              .read(transcriptionProvider.notifier)
              .startTranscription(widget.assetId);
        },
        icon: const Icon(Icons.auto_awesome, size: 16),
        label: Text(
          hadPreviousResult ? 'Re-transcribe Audio' : 'Transcribe Audio',
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.secondary,
          side: const BorderSide(color: AppTheme.secondary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(TranscriptionState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: state.progress,
                  backgroundColor: AppTheme.surfaceVariant,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppTheme.secondary,
                  ),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${(state.progress * 100).round()}%',
              style: context.textTheme.bodySmall?.copyWith(
                color: AppTheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          state.status.label,
          style: context.textTheme.bodySmall?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage(TranscriptionState state) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing8),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: AppTheme.error.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppTheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.errorMessage!,
              style: context.textTheme.bodySmall?.copyWith(
                color: AppTheme.error,
              ),
            ),
          ),
          InkWell(
            onTap: () {
              ref.read(transcriptionProvider.notifier).clearTranscription();
            },
            child: const Icon(Icons.close, size: 14, color: AppTheme.error),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentControls(TranscriptionState state) {
    return Row(
      children: [
        Text(
          'TRANSCRIBED SEGMENTS',
          style: context.textTheme.labelMedium?.copyWith(
            color: AppTheme.textDisabled,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        // Select All / Deselect All toggle
        _buildToggleAllButton(state),
      ],
    );
  }

  Widget _buildToggleAllButton(TranscriptionState state) {
    final allSelected = state.allSelected;
    return InkWell(
      onTap: () {
        ref.read(transcriptionProvider.notifier).toggleSelectAll();
      },
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: allSelected
              ? AppTheme.secondary.withValues(alpha: 0.1)
              : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: allSelected
                ? AppTheme.secondary.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              allSelected ? Icons.deselect : Icons.select_all,
              size: 14,
              color: allSelected ? AppTheme.secondary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              allSelected ? 'Deselect All' : 'Select All',
              style: context.textTheme.bodySmall?.copyWith(
                color:
                    allSelected ? AppTheme.secondary : AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentsPreview(TranscriptionState state) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(8),
        itemCount: state.segments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final seg = state.segments[index];
          return _SegmentPreviewItem(
            segment: seg,
            isEditing: _editingSegmentId == seg.id,
            editController: _editController,
            editFocusNode: _editFocusNode,
            onTap: () => _onSegmentTap(seg),
            onSelectionToggle: () {
              ref
                  .read(transcriptionProvider.notifier)
                  .toggleSegmentSelection(seg.id);
            },
            onEditSubmit: (newText) {
              ref
                  .read(transcriptionProvider.notifier)
                  .updateSegmentText(seg.id, newText);
              setState(() => _editingSegmentId = null);
            },
            onEditCancel: () {
              setState(() => _editingSegmentId = null);
            },
          );
        },
      ),
    );
  }

  void _onSegmentTap(TranscriptionSegmentData segment) {
    setState(() {
      _editingSegmentId = segment.id;
      _editController.text = segment.text;
    });
    // Focus the edit field after the frame rebuilds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
    });
  }

  Widget _buildExportButtons(TranscriptionState state) {
    final hasSelected = state.selectedCount > 0;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: hasSelected
                  ? () {
                      ref
                          .read(transcriptionProvider.notifier)
                          .exportSrt('subtitles.srt');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('SRT file exported'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.subtitles, size: 14),
              label: const Text('Export SRT', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.secondary,
                side: BorderSide(
                  color:
                      hasSelected ? AppTheme.secondary : AppTheme.textDisabled,
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: hasSelected
                  ? () {
                      ref
                          .read(transcriptionProvider.notifier)
                          .exportVtt('subtitles.vtt');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('VTT file exported'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.closed_caption, size: 14),
              label: const Text('Export VTT', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.secondary,
                side: BorderSide(
                  color:
                      hasSelected ? AppTheme.secondary : AppTheme.textDisabled,
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddToTimelineButton(TranscriptionState state) {
    final selectedCount = state.selectedCount;
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: ElevatedButton.icon(
        onPressed: selectedCount > 0 ? _addToTimeline : null,
        icon: const Icon(Icons.subtitles, size: 16),
        label: Text(
          'Add $selectedCount Subtitle${selectedCount == 1 ? '' : 's'} to Timeline',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.secondary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.textDisabled.withValues(alpha: 0.3),
          disabledForegroundColor: AppTheme.textDisabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
        ),
      ),
    );
  }

  Future<void> _addToTimeline() async {
    final clipIds = await ref
        .read(transcriptionProvider.notifier)
        .addSubtitlesToTimeline(widget.assetId, widget.trackId);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          clipIds.isNotEmpty
              ? 'Added ${clipIds.length} subtitle clips to timeline'
              : 'Subtitles prepared for timeline',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Individual segment preview item with editing and selection support
class _SegmentPreviewItem extends StatelessWidget {
  const _SegmentPreviewItem({
    required this.segment,
    required this.isEditing,
    required this.editController,
    required this.editFocusNode,
    required this.onTap,
    required this.onSelectionToggle,
    required this.onEditSubmit,
    required this.onEditCancel,
  });
  final TranscriptionSegmentData segment;
  final bool isEditing;
  final TextEditingController editController;
  final FocusNode editFocusNode;
  final VoidCallback onTap;
  final VoidCallback onSelectionToggle;
  final ValueChanged<String> onEditSubmit;
  final VoidCallback onEditCancel;

  /// Get the confidence color based on the score
  Color get _confidenceColor {
    if (segment.confidence > 0.8) return AppTheme.success;
    if (segment.confidence > 0.5) return AppTheme.warning;
    return AppTheme.error;
  }

  /// Get the background tint based on confidence
  Color get _confidenceBgColor {
    if (segment.confidence > 0.8) {
      return AppTheme.success.withValues(alpha: 0.05);
    }
    if (segment.confidence > 0.5) {
      return AppTheme.warning.withValues(alpha: 0.05);
    }
    return AppTheme.error.withValues(alpha: 0.05);
  }

  @override
  Widget build(BuildContext context) {
    final dimmed = !segment.selected && !isEditing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: dimmed
            ? AppTheme.cardColor.withValues(alpha: 0.5)
            : isEditing
                ? AppTheme.secondary.withValues(alpha: 0.08)
                : _confidenceBgColor,
        borderRadius: BorderRadius.circular(4),
        border: isEditing
            ? Border.all(
                color: AppTheme.secondary.withValues(alpha: 0.4),
                width: 1,
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selection checkbox
          GestureDetector(
            onTap: onSelectionToggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: Icon(
                segment.selected
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 16,
                color: segment.selected
                    ? AppTheme.secondary
                    : AppTheme.textDisabled,
              ),
            ),
          ),

          // Timestamp
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              segment.startTimeFormatted,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: dimmed ? AppTheme.textDisabled : AppTheme.secondary,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Text (editable or display)
          Expanded(
            child: isEditing
                ? TextField(
                    controller: editController,
                    focusNode: editFocusNode,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                    onSubmitted: onEditSubmit,
                  )
                : GestureDetector(
                    onTap: onTap,
                    child: Text(
                      segment.text,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: dimmed
                            ? AppTheme.textDisabled
                            : AppTheme.textPrimary,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),

          // Confidence indicator
          if (segment.confidence > 0 && !isEditing)
            Tooltip(
              message: '${(segment.confidence * 100).round()}% confidence',
              child: Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4, left: 4),
                decoration: BoxDecoration(
                  color: _confidenceColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),

          // Edit/Done icon when editing
          if (isEditing)
            GestureDetector(
              onTap: () => onEditSubmit(editController.text),
              child: const Padding(
                padding: EdgeInsets.only(top: 2, left: 4),
                child: Icon(
                  Icons.check,
                  size: 14,
                  color: AppTheme.secondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
