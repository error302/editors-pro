import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/engine_service.dart';
import '../../../core/services/export_service.dart';
import '../../../src/rust/api/bridge_api.dart';

/// Export state that tracks the current status, progress, and result.
class ExportState {
  const ExportState({
    this.isExporting = false,
    this.progress = 0,
    this.stageName = '',
    this.currentFrame = 0,
    this.totalFrames = 0,
    this.estimatedSecondsRemaining = 0,
    this.outputPath,
    this.fileSizeHuman,
    this.error,
  });
  final bool isExporting;
  final double progress;
  final String stageName;
  final int currentFrame;
  final int totalFrames;
  final int estimatedSecondsRemaining;
  final String? outputPath;
  final String? fileSizeHuman;
  final String? error;

  ExportState copyWith({
    bool? isExporting,
    double? progress,
    String? stageName,
    int? currentFrame,
    int? totalFrames,
    int? estimatedSecondsRemaining,
    String? outputPath,
    String? fileSizeHuman,
    String? error,
    bool clearError = false,
  }) {
    return ExportState(
      isExporting: isExporting ?? this.isExporting,
      progress: progress ?? this.progress,
      stageName: stageName ?? this.stageName,
      currentFrame: currentFrame ?? this.currentFrame,
      totalFrames: totalFrames ?? this.totalFrames,
      estimatedSecondsRemaining:
          estimatedSecondsRemaining ?? this.estimatedSecondsRemaining,
      outputPath: outputPath ?? this.outputPath,
      fileSizeHuman: fileSizeHuman ?? this.fileSizeHuman,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// Whether the export has completed successfully.
  bool get isComplete =>
      !isExporting && progress >= 1.0 && outputPath != null && error == null;

  /// Whether the export failed.
  bool get hasError => error != null && !isExporting;

  /// Formatted progress string (e.g. "45%").
  String get progressText => '${(progress * 100).round()}%';

  /// Formatted remaining time (e.g. "~2m 30s").
  String get estimatedTimeText {
    final secs = estimatedSecondsRemaining;
    if (secs <= 0) return '';
    if (secs < 60) return '~${secs}s remaining';
    final mins = secs ~/ 60;
    final remSecs = secs % 60;
    return '~${mins}m ${remSecs}s remaining';
  }

  /// Formatted frame progress (e.g. "150 / 300 frames").
  String get frameProgressText {
    if (totalFrames <= 0) return '';
    return '$currentFrame / $totalFrames frames';
  }
}

/// State notifier that manages the export pipeline.
///
/// Provides methods to:
/// - Start an export with configurable settings
/// - Cancel an in-progress export
/// - Share the exported file
/// - Track progress in real-time
class ExportNotifier extends StateNotifier<ExportState> {
  ExportNotifier({EditorsProEngineApi? engineApi})
      : _engineApi = engineApi,
        super(const ExportState());

  final EditorsProEngineApi? _engineApi;
  Timer? _progressTimer;
  bool _cancelRequested = false;

  EditorsProEngineApi get _api => _engineApi ?? EngineService.instance.api;

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  /// Start exporting the project with the given settings.
  ///
  /// The export runs on the native dispatch isolate; progress is read from
  /// the lock-free status snapshot while the UI isolate remains responsive.
  Future<void> startExport({
    required String preset,
    String? outputPath,
    String codec = 'H.264',
    String format = 'MP4',
    int? customWidth,
    int? customHeight,
    int? customBitrate,
  }) async {
    if (state.isExporting) return;
    _cancelRequested = false;

    // Reset state
    state = const ExportState(
      isExporting: true,
      stageName: 'Preparing',
    );

    try {
      final api = _api;
      api.prepareExport();

      // Start the Android foreground service so export continues
      // when the app is minimized.
      await ExportForegroundService.instance.start();

      // Determine output path
      final outPath = outputPath ?? await _defaultOutputPath(format);

      // Build export settings
      final settings = _buildSettings(
        preset: preset,
        codec: codec,
        format: format,
        customWidth: customWidth,
        customHeight: customHeight,
        customBitrate: customBitrate,
      );

      _startProgressPolling(api);
      final result = await api.exportVideoWithCallback(
        outputPath: outPath,
        settings: settings,
      );

      if (result.success) {
        _progressTimer?.cancel();
        // Stop foreground service and show completion notification
        await ExportForegroundService.instance.complete(
          result.outputPath,
          result.fileSizeHuman,
        );
        state = ExportState(
          isExporting: false,
          progress: 1.0,
          stageName: 'Complete',
          outputPath: result.outputPath,
          fileSizeHuman: result.fileSizeHuman,
        );
      } else {
        _progressTimer?.cancel();
        await ExportForegroundService.instance.cancel();
        state = ExportState(
          isExporting: false,
          error: _cancelRequested
              ? 'Export canceled'
              : result.errorMessage ?? 'Export failed',
        );
      }
    } catch (e) {
      _progressTimer?.cancel();
      await ExportForegroundService.instance.cancel();
      state = ExportState(
        isExporting: false,
        error: _cancelRequested ? 'Export canceled' : 'Export error: $e',
      );
    } finally {
      _cancelRequested = false;
    }
  }

  /// Cancel an in-progress export.
  Future<void> cancelExport() async {
    if (!state.isExporting) return;

    _cancelRequested = true;
    try {
      await _api.cancelExport();
      state = state.copyWith(stageName: 'Canceling');
    } catch (e) {
      _cancelRequested = false;
      state = state.copyWith(error: 'Cancel request failed: $e');
    }
  }

  void _startProgressPolling(EditorsProEngineApi api) {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!state.isExporting) return;
      try {
        final progress = api.getExportProgress();
        state = state.copyWith(
          progress: progress.progress,
          currentFrame: progress.currentFrame,
          totalFrames: progress.totalFrames,
          estimatedSecondsRemaining: progress.estimatedSecondsRemaining,
          stageName: _cancelRequested ? 'Canceling' : progress.stageName,
        );
      } catch (_) {
        // Keep the export running if the optional status symbol is missing.
      }
    });
  }

  /// Share the exported video file using the Android share sheet.
  Future<void> shareExportedFile() async {
    final path = state.outputPath;
    if (path == null) return;

    final file = File(path);
    if (!await file.exists()) return;

    await Share.shareXFiles(
      [XFile(path)],
      text: 'Video exported from EDITORS-PRO',
      subject: 'EDITORS-PRO Export',
    );
  }

  /// Reset the export state.
  void reset() {
    state = const ExportState();
  }

  // ─── Internal helpers ────────────────────────────────────────

  /// Generate a default output path for the export.
  Future<String> _defaultOutputPath(String format) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${dir.path}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = _formatExtension(format);
    return '${exportsDir.path}/export_$timestamp$ext';
  }

  /// Get the file extension for a format name.
  String _formatExtension(String format) {
    switch (format.toUpperCase()) {
      case 'WEBM':
        return '.webm';
      case 'MOV':
        return '.mov';
      case 'AVI':
        return '.avi';
      case 'GIF':
        return '.gif';
      case 'MP4':
      default:
        return '.mp4';
    }
  }

  /// Build BridgeExportSettings from the UI parameters.
  BridgeExportSettings _buildSettings({
    required String preset,
    required String codec,
    required String format,
    int? customWidth,
    int? customHeight,
    int? customBitrate,
  }) {
    // Get the preset values
    final presetMap = {
      '720p': (1280, 720, 5000),
      '1080p': (1920, 1080, 10000),
      '4K': (3840, 2160, 40000),
      'Social Vertical': (1080, 1920, 8000),
      'Social Square': (1080, 1080, 6000),
    };

    final (width, height, bitrate) = presetMap[preset] ?? (1920, 1080, 10000);

    return BridgeExportSettings(
      width: customWidth ?? width,
      height: customHeight ?? height,
      fps: 30.0,
      bitrateKbps: customBitrate ?? bitrate,
      codec: codec,
      format: format,
      audioBitrateKbps: 128,
      audioSampleRate: 44100,
      audioChannels: 2,
      includeAudio: true,
      twoPass: false,
    );
  }
}

/// Provider for export state
final exportProvider =
    StateNotifierProvider<ExportNotifier, ExportState>((ref) {
  return ExportNotifier();
});

final isAndroidPlatformProvider = Provider<bool>((ref) => Platform.isAndroid);

/// Provider for the list of available export presets
final exportPresetsProvider = Provider<List<ExportPreset>>((ref) {
  return ExportPreset.all;
});

/// A single export preset with display info
class ExportPreset {
  const ExportPreset({
    required this.name,
    required this.width,
    required this.height,
    required this.bitrateKbps,
    required this.description,
  });
  final String name;
  final int width;
  final int height;
  final int bitrateKbps;
  final String description;

  static const all = [
    ExportPreset(
      name: '720p',
      width: 1280,
      height: 720,
      bitrateKbps: 5000,
      description: 'HD 720p — Small file, fast export',
    ),
    ExportPreset(
      name: '1080p',
      width: 1920,
      height: 1080,
      bitrateKbps: 10000,
      description: 'Full HD — Best balance of quality and size',
    ),
    ExportPreset(
      name: '4K',
      width: 3840,
      height: 2160,
      bitrateKbps: 40000,
      description: 'Ultra HD — Maximum quality, large file',
    ),
    ExportPreset(
      name: 'Social Vertical',
      width: 1080,
      height: 1920,
      bitrateKbps: 8000,
      description: '9:16 — TikTok, Reels, Shorts',
    ),
    ExportPreset(
      name: 'Social Square',
      width: 1080,
      height: 1080,
      bitrateKbps: 6000,
      description: '1:1 — Instagram posts',
    ),
  ];
}
