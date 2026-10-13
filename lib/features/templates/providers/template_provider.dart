import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/engine_service.dart';
import '../../../src/rust/api/bridge_api.dart' show TemplateInfo;

/// Template data model for the UI
class TemplateData {
  final String id;
  final String name;
  final String description;
  final String category;
  final String previewPath;
  final int placeholderCount;
  final int durationMs;
  final String aspectRatio;
  final List<String> tags;

  const TemplateData({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.previewPath,
    required this.placeholderCount,
    required this.durationMs,
    required this.aspectRatio,
    required this.tags,
  });

  /// Format duration as M:SS
  String get durationFormatted {
    final seconds = durationMs ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Create from engine TemplateInfo
  factory TemplateData.fromTemplateInfo(TemplateInfo info) {
    return TemplateData(
      id: info.id,
      name: info.name,
      description: info.description,
      category: info.category,
      previewPath: info.previewPath,
      placeholderCount: info.placeholderCount,
      durationMs: info.durationMs,
      aspectRatio: info.aspectRatio,
      tags: info.tags,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateData && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Placeholder slot data
class PlaceholderSlotData {
  final String id;
  final String label;
  final String mediaType; // "video" or "image"
  final int startMs;
  final int expectedDurationMs;
  final bool isFilled;
  final String? assignedMediaPath;

  const PlaceholderSlotData({
    required this.id,
    required this.label,
    required this.mediaType,
    required this.startMs,
    required this.expectedDurationMs,
    this.isFilled = false,
    this.assignedMediaPath,
  });

  /// Format expected duration as M:SS
  String get expectedDurationFormatted {
    final seconds = expectedDurationMs ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  PlaceholderSlotData copyWith({
    bool? isFilled,
    String? assignedMediaPath,
  }) {
    return PlaceholderSlotData(
      id: id,
      label: label,
      mediaType: mediaType,
      startMs: startMs,
      expectedDurationMs: expectedDurationMs,
      isFilled: isFilled ?? this.isFilled,
      assignedMediaPath: assignedMediaPath ?? this.assignedMediaPath,
    );
  }
}

/// Template creation state
class TemplateCreationState {
  final TemplateData? selectedTemplate;
  final Map<String, String> mediaAssignments; // slotId -> mediaPath
  final bool isCreating;
  final String? errorMessage;
  final List<TemplateData> availableTemplates;
  final bool isLoadingTemplates;

  const TemplateCreationState({
    this.selectedTemplate,
    this.mediaAssignments = const {},
    this.isCreating = false,
    this.errorMessage,
    this.availableTemplates = const [],
    this.isLoadingTemplates = false,
  });

  /// Whether all video slots are filled (text slots are optional)
  bool get canCreate {
    if (selectedTemplate == null || isCreating) return false;
    // At least one media assignment is required
    return mediaAssignments.isNotEmpty;
  }

  /// Number of filled slots
  int get filledCount => mediaAssignments.length;

  /// Number of total slots
  int get totalSlotCount => selectedTemplate?.placeholderCount ?? 0;

  /// Progress as a fraction 0.0–1.0
  double get progress =>
      totalSlotCount == 0 ? 0.0 : filledCount / totalSlotCount;

  TemplateCreationState copyWith({
    TemplateData? selectedTemplate,
    bool clearTemplate = false,
    Map<String, String>? mediaAssignments,
    bool? isCreating,
    String? errorMessage,
    bool clearError = false,
    List<TemplateData>? availableTemplates,
    bool? isLoadingTemplates,
  }) {
    return TemplateCreationState(
      selectedTemplate:
          clearTemplate ? null : (selectedTemplate ?? this.selectedTemplate),
      mediaAssignments: mediaAssignments ?? this.mediaAssignments,
      isCreating: isCreating ?? this.isCreating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      availableTemplates:
          availableTemplates ?? this.availableTemplates,
      isLoadingTemplates:
          isLoadingTemplates ?? this.isLoadingTemplates,
    );
  }
}

/// Template notifier — manages template selection, media assignment,
/// and project creation from templates.
class TemplateNotifier extends StateNotifier<TemplateCreationState> {
  TemplateNotifier() : super(const TemplateCreationState());

  /// Load available templates from the engine.
  Future<void> loadTemplates() async {
    state = state.copyWith(isLoadingTemplates: true, clearError: true);
    try {
      final templates = await EngineService.instance.listTemplates();
      state = state.copyWith(
        availableTemplates:
            templates.map(TemplateData.fromTemplateInfo).toList(),
        isLoadingTemplates: false,
      );
    } catch (e) {
      developer.log('loadTemplates failed: $e', name: 'TemplateNotifier');
      state = state.copyWith(
        isLoadingTemplates: false,
        errorMessage: 'Failed to load templates: $e',
      );
    }
  }

  /// Select a template for project creation.
  void selectTemplate(TemplateData template) {
    state = state.copyWith(
      selectedTemplate: template,
      mediaAssignments: {},
      clearError: true,
    );
  }

  /// Assign media to a placeholder slot.
  void assignMedia(String slotId, String mediaPath) {
    final updated = Map<String, String>.from(state.mediaAssignments);
    updated[slotId] = mediaPath;
    state = state.copyWith(mediaAssignments: updated);
  }

  /// Remove media assignment from a slot.
  void unassignMedia(String slotId) {
    final updated = Map<String, String>.from(state.mediaAssignments);
    updated.remove(slotId);
    state = state.copyWith(mediaAssignments: updated);
  }

  /// Create a project from the selected template with current assignments.
  Future<String?> createProject() async {
    if (state.selectedTemplate == null) return null;

    state = state.copyWith(isCreating: true, clearError: true);

    try {
      final projectInfo = await EngineService.instance.instantiateTemplate(
        state.selectedTemplate!.id,
        state.mediaAssignments,
      );

      state = state.copyWith(isCreating: false);

      if (projectInfo != null) {
        developer.log(
          'Created project ${projectInfo.id} from template ${state.selectedTemplate!.id}',
          name: 'TemplateNotifier',
        );
        return projectInfo.id;
      } else {
        state = state.copyWith(
          isCreating: false,
          errorMessage: 'Failed to create project from template',
        );
        return null;
      }
    } catch (e) {
      developer.log('createProject failed: $e', name: 'TemplateNotifier');
      state = state.copyWith(
        isCreating: false,
        errorMessage: 'Failed to create project: $e',
      );
      return null;
    }
  }

  /// Clear the current selection and assignments.
  void clear() {
    state = const TemplateCreationState(
      availableTemplates: [],
    );
  }
}

/// Provider for template state management
final templateProvider =
    StateNotifierProvider<TemplateNotifier, TemplateCreationState>(
  (ref) => TemplateNotifier(),
);
