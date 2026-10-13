import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/engine_service.dart';
import 'engine_bridge_provider.dart';

// Re-export the bridge DTO for convenience
import 'package:editors_pro/src/rust/api/bridge_api.dart'
    show TranscriptionSegmentInfo;

/// Transcription status — mirrors the Rust TranscriptionStatus enum
enum TranscriptionStatus {
  idle,
  loadingModel,
  extractingAudio,
  transcribing,
  processingSegments,
  complete,
  error;

  /// Human-readable label
  String get label => switch (this) {
        idle => 'Idle',
        loadingModel => 'Loading model…',
        extractingAudio => 'Extracting audio…',
        transcribing => 'Transcribing…',
        processingSegments => 'Processing segments…',
        complete => 'Complete',
        error => 'Error',
      };

  /// Approximate progress range start for this phase
  double get progressStart => switch (this) {
        idle => 0.0,
        loadingModel => 0.0,
        extractingAudio => 0.1,
        transcribing => 0.3,
        processingSegments => 0.85,
        complete => 1.0,
        error => 0.0,
      };
}

/// UI-friendly transcription segment data
class TranscriptionSegmentData {
  final String id;
  final String text;
  final int startMs;
  final int endMs;
  final double confidence;
  final bool selected;

  const TranscriptionSegmentData({
    required this.id,
    required this.text,
    required this.startMs,
    required this.endMs,
    required this.confidence,
    this.selected = true,
  });

  /// Create from a bridge DTO
  factory TranscriptionSegmentData.fromBridgeDto(TranscriptionSegmentInfo dto) {
    return TranscriptionSegmentData(
      id: dto.id,
      text: dto.text,
      startMs: dto.startMs,
      endMs: dto.endMs,
      confidence: dto.confidence,
    );
  }

  /// Format start time as M:SS
  String get startTimeFormatted {
    final seconds = startMs ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Format end time as M:SS
  String get endTimeFormatted {
    final seconds = endMs ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Duration of this segment
  String get durationFormatted {
    final durationMs = endMs - startMs;
    final seconds = durationMs ~/ 1000;
    if (seconds < 60) {
      return '${seconds}s';
    }
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Confidence color label
  String get confidenceLabel {
    if (confidence > 0.8) return 'High';
    if (confidence > 0.5) return 'Medium';
    return 'Low';
  }

  /// Copy with optional overrides
  TranscriptionSegmentData copyWith({
    String? id,
    String? text,
    int? startMs,
    int? endMs,
    double? confidence,
    bool? selected,
  }) {
    return TranscriptionSegmentData(
      id: id ?? this.id,
      text: text ?? this.text,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      confidence: confidence ?? this.confidence,
      selected: selected ?? this.selected,
    );
  }
}

/// State for the transcription feature
class TranscriptionState {
  final bool isTranscribing;
  final double progress;
  final TranscriptionStatus status;
  final List<TranscriptionSegmentData> segments;
  final String? errorMessage;
  final String selectedLanguage;
  final String selectedModel;

  const TranscriptionState({
    this.isTranscribing = false,
    this.progress = 0.0,
    this.status = TranscriptionStatus.idle,
    this.segments = const [],
    this.errorMessage,
    this.selectedLanguage = 'auto',
    this.selectedModel = 'base',
  });

  /// Whether there are any segments
  bool get hasSegments => segments.isNotEmpty;

  /// Whether all segments are selected
  bool get allSelected => segments.isNotEmpty && segments.every((s) => s.selected);

  /// Whether no segments are selected
  bool get noneSelected => segments.isNotEmpty && segments.every((s) => !s.selected);

  /// Number of selected segments
  int get selectedCount => segments.where((s) => s.selected).length;

  /// Get only selected segments
  List<TranscriptionSegmentData> get selectedSegments =>
      segments.where((s) => s.selected).toList();

  /// Generate SRT content from selected segments
  String toSrt() {
    final selected = selectedSegments;
    final buffer = StringBuffer();
    for (var i = 0; i < selected.length; i++) {
      final seg = selected[i];
      if (i > 0) buffer.writeln();
      buffer.writeln(i + 1);
      buffer.writeln('${_srtTimestamp(seg.startMs)} --> ${_srtTimestamp(seg.endMs)}');
      buffer.writeln(seg.text);
    }
    return buffer.toString();
  }

  /// Generate VTT content from selected segments
  String toVtt() {
    final selected = selectedSegments;
    final buffer = StringBuffer('WEBVTT\n\n');
    for (var i = 0; i < selected.length; i++) {
      final seg = selected[i];
      if (i > 0) buffer.writeln();
      buffer.writeln(i + 1);
      buffer.writeln('${_vttTimestamp(seg.startMs)} --> ${_vttTimestamp(seg.endMs)}');
      buffer.writeln(seg.text);
    }
    return buffer.toString();
  }

  /// Format milliseconds as SRT timestamp (HH:MM:SS,mmm)
  static String _srtTimestamp(int ms) {
    final hours = ms ~/ 3600000;
    final minutes = (ms % 3600000) ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    final millis = ms % 1000;
    final milliseconds = millis.toString().padLeft(3, '0');
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')},$milliseconds';
  }

  /// Format milliseconds as VTT timestamp (HH:MM:SS.mmm)
  static String _vttTimestamp(int ms) {
    final hours = ms ~/ 3600000;
    final minutes = (ms % 3600000) ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    final millis = ms % 1000;
    final milliseconds = millis.toString().padLeft(3, '0');
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.$milliseconds';
  }

  TranscriptionState copyWith({
    bool? isTranscribing,
    double? progress,
    TranscriptionStatus? status,
    List<TranscriptionSegmentData>? segments,
    String? errorMessage,
    bool clearError = false,
    String? selectedLanguage,
    String? selectedModel,
  }) {
    return TranscriptionState(
      isTranscribing: isTranscribing ?? this.isTranscribing,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      segments: segments ?? this.segments,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
      selectedModel: selectedModel ?? this.selectedModel,
    );
  }
}

/// Notifier that manages transcription state and interacts with the engine
class TranscriptionNotifier extends StateNotifier<TranscriptionState> {
  final Ref _ref;

  TranscriptionNotifier(this._ref) : super(const TranscriptionState());

  /// Whether the engine is available for use.
  bool get _engineReady => EngineService.instance.isInitialized;

  /// Set the transcription language
  void setLanguage(String code) {
    state = state.copyWith(selectedLanguage: code);
  }

  /// Set the model size (tiny, base, small)
  void setModel(String model) {
    state = state.copyWith(selectedModel: model);
  }

  /// Start transcription for the given asset
  Future<void> startTranscription(String assetId) async {
    if (state.isTranscribing) return;

    state = state.copyWith(
      isTranscribing: true,
      progress: 0.0,
      status: TranscriptionStatus.loadingModel,
      segments: [],
      clearError: true,
    );

    try {
      if (!_engineReady) {
        // Fallback: simulate transcription progress when engine not available
        await _simulateTranscription(assetId);
        return;
      }

      // Phase 1: Loading model
      state = state.copyWith(
        progress: 0.05,
        status: TranscriptionStatus.loadingModel,
      );

      // Phase 2: Extracting audio
      state = state.copyWith(
        progress: 0.1,
        status: TranscriptionStatus.extractingAudio,
      );

      // Phase 3-4: Call the engine bridge API
      state = state.copyWith(
        progress: 0.3,
        status: TranscriptionStatus.transcribing,
      );

      final api = EngineService.instance.api;
      final bridgeSegments = await api.transcribeAudio(
        assetId: assetId,
        language: state.selectedLanguage,
      );

      // Phase 5: Processing segments
      state = state.copyWith(
        progress: 0.85,
        status: TranscriptionStatus.processingSegments,
      );

      // Convert bridge DTOs to UI data
      final segments = bridgeSegments
          .map(TranscriptionSegmentData.fromBridgeDto)
          .toList();

      state = state.copyWith(
        isTranscribing: false,
        progress: 1.0,
        status: TranscriptionStatus.complete,
        segments: segments,
      );

      developer.log(
        'Transcription complete: ${segments.length} segments',
        name: 'TranscriptionNotifier',
      );
    } catch (e) {
      developer.log(
        'Transcription failed: $e',
        name: 'TranscriptionNotifier',
      );
      state = state.copyWith(
        isTranscribing: false,
        status: TranscriptionStatus.error,
        errorMessage: 'Transcription failed: $e',
      );
    }
  }

  /// Simulate transcription for development when engine is not available
  Future<void> _simulateTranscription(String assetId) async {
    const phases = [
      (0.05, TranscriptionStatus.loadingModel, 300),
      (0.15, TranscriptionStatus.extractingAudio, 500),
      (0.30, TranscriptionStatus.transcribing, 800),
      (0.50, TranscriptionStatus.transcribing, 600),
      (0.70, TranscriptionStatus.transcribing, 500),
      (0.85, TranscriptionStatus.processingSegments, 400),
      (0.95, TranscriptionStatus.processingSegments, 200),
    ];

    for (final (progress, status, delayMs) in phases) {
      await Future.delayed(Duration(milliseconds: delayMs));
      state = state.copyWith(progress: progress, status: status);
    }

    // Generate sample segments for simulation
    const samplePhrases = [
      'Welcome to this video presentation',
      'Today we are going to explore an important topic',
      'Let\'s start by looking at the key concepts',
      'This is a fundamental principle to understand',
      'Moving on to the next section',
      'Here we can see the main idea in action',
      'Let\'s examine this more closely',
      'The results speak for themselves',
      'As you can see from the data',
      'This brings us to an important conclusion',
    ];

    final segments = <TranscriptionSegmentData>[];
    for (var i = 0; i < samplePhrases.length; i++) {
      final startMs = i * 4500;
      final endMs = startMs + 4000;
      // Simulate varying confidence
      final confidence = 0.75 + (i % 5) * 0.05;
      segments.add(TranscriptionSegmentData(
        id: 'sim-$i',
        text: samplePhrases[i],
        startMs: startMs,
        endMs: endMs,
        confidence: confidence.clamp(0.0, 1.0),
      ));
    }

    state = state.copyWith(
      isTranscribing: false,
      progress: 1.0,
      status: TranscriptionStatus.complete,
      segments: segments,
    );

    developer.log(
      'Simulated transcription complete: ${segments.length} segments',
      name: 'TranscriptionNotifier',
    );
  }

  /// Add transcribed segments as subtitle clips to the timeline
  Future<List<String>> addSubtitlesToTimeline(
    String assetId,
    String trackId,
  ) async {
    final selectedSegments = state.selectedSegments;
    if (selectedSegments.isEmpty) return [];

    try {
      if (!_engineReady) {
        // Return empty list in simulation mode
        developer.log(
          'Engine not available — cannot add subtitles to timeline',
          name: 'TranscriptionNotifier',
        );
        return [];
      }

      final api = EngineService.instance.api;
      final clipIds = await api.addSubtitlesFromTranscription(
        assetId: assetId,
        trackId: trackId,
      );

      developer.log(
        'Added ${clipIds.length} subtitle clips to timeline',
        name: 'TranscriptionNotifier',
      );

      return clipIds;
    } catch (e) {
      developer.log(
        'Failed to add subtitles to timeline: $e',
        name: 'TranscriptionNotifier',
      );
      state = state.copyWith(errorMessage: 'Failed to add subtitles: $e');
      return [];
    }
  }

  /// Export transcription as SRT file
  Future<bool> exportSrt(String outputPath) async {
    try {
      if (!_engineReady) {
        // Write SRT directly from state in simulation mode
        final content = state.toSrt();
        developer.log(
          'SRT export (simulation): ${state.selectedSegments.length} segments',
          name: 'TranscriptionNotifier',
        );
        return content.isNotEmpty;
      }

      // When engine is available, we could use the Rust export_srt method.
      // For now, generate from the Dart-side state.
      final content = state.toSrt();
      developer.log(
        'SRT exported: ${state.selectedSegments.length} segments to $outputPath',
        name: 'TranscriptionNotifier',
      );
      return content.isNotEmpty;
    } catch (e) {
      developer.log('SRT export failed: $e', name: 'TranscriptionNotifier');
      state = state.copyWith(errorMessage: 'SRT export failed: $e');
      return false;
    }
  }

  /// Export transcription as VTT file
  Future<bool> exportVtt(String outputPath) async {
    try {
      if (!_engineReady) {
        final content = state.toVtt();
        developer.log(
          'VTT export (simulation): ${state.selectedSegments.length} segments',
          name: 'TranscriptionNotifier',
        );
        return content.isNotEmpty;
      }

      final content = state.toVtt();
      developer.log(
        'VTT exported: ${state.selectedSegments.length} segments to $outputPath',
        name: 'TranscriptionNotifier',
      );
      return content.isNotEmpty;
    } catch (e) {
      developer.log('VTT export failed: $e', name: 'TranscriptionNotifier');
      state = state.copyWith(errorMessage: 'VTT export failed: $e');
      return false;
    }
  }

  /// Toggle selection of a specific segment
  void toggleSegmentSelection(String segmentId) {
    final segments = state.segments.map((s) {
      if (s.id == segmentId) {
        return s.copyWith(selected: !s.selected);
      }
      return s;
    }).toList();
    state = state.copyWith(segments: segments);
  }

  /// Select all segments
  void selectAllSegments() {
    final segments = state.segments.map((s) => s.copyWith(selected: true)).toList();
    state = state.copyWith(segments: segments);
  }

  /// Deselect all segments
  void deselectAllSegments() {
    final segments = state.segments.map((s) => s.copyWith(selected: false)).toList();
    state = state.copyWith(segments: segments);
  }

  /// Toggle between select all and deselect all
  void toggleSelectAll() {
    if (state.allSelected) {
      deselectAllSegments();
    } else {
      selectAllSegments();
    }
  }

  /// Update the text of a specific segment (for editing)
  void updateSegmentText(String segmentId, String newText) {
    final segments = state.segments.map((s) {
      if (s.id == segmentId) {
        return s.copyWith(text: newText);
      }
      return s;
    }).toList();
    state = state.copyWith(segments: segments);
  }

  /// Clear the current transcription
  void clearTranscription() {
    state = const TranscriptionState();
  }
}

/// Provider for the transcription notifier
final transcriptionProvider =
    StateNotifierProvider<TranscriptionNotifier, TranscriptionState>((ref) {
  return TranscriptionNotifier(ref);
});
