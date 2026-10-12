import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/project_model.dart';
import '../../../core/services/engine_service.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../projects/providers/project_provider.dart';
import '../services/av_sync_coordinator.dart';
import 'engine_bridge_provider.dart';

// Re-export the bridge-generated DTOs so the rest of the app can
// reference them without knowing the bridge internals.
import 'package:editors_pro/src/rust/api/bridge_api.dart'
    show
        BridgeExportSettings,
        BridgeExportResult,
        BridgeProjectSettings,
        BridgeSpeedCurve,
        BridgeSpeedSegment,
        ClipInfo,
        EffectInfo,
        FontInfo,
        GpuInfo,
        MediaAssetInfo,
        ProjectInfo,
        TranscriptionSegmentInfo;

/// Editor state
class EditorState {
  final bool isPlaying;
  final int currentTimeMs;
  final int durationMs;
  final double zoomLevel;
  final bool isImporting;
  final bool isExporting;
  final double exportProgress;
  final String? selectedClipId;
  final String? selectedTrackId;
  final LeftPanelTab leftPanelTab;
  final bool showInspector;
  final double playbackSpeed;
  final String? lastError;
  /// Whether audio playback is active (synchronized with video)
  final bool isAudioPlaying;
  /// Master volume level for audio playback (0.0 to 1.0)
  final double masterVolume;
  /// Whether the editor is currently fetching frames in the playback loop
  final bool isDecodingFrame;
  /// Whether GPU rendering is available on this device
  final bool gpuAvailable;
  /// Detailed GPU adapter information (null when GPU is unavailable)
  final GpuInfo? gpuInfo;
  /// Whether a hardware encoder is available for accelerated export
  final bool hardwareEncoderAvailable;
  /// Whether GPU acceleration is currently enabled by the user
  final bool gpuAccelerationEnabled;
  /// Phase F.2: whether the safe-zones overlay is visible on the preview.
  final bool showSafeZones;
  /// Phase F.2: which safe-zone config to show (broadcast / social / composition).
  final SafeZoneMode safeZoneMode;
  /// Phase F.2: whether the audio meter bridge is visible at the bottom.
  final bool showAudioMeterBridge;

  const EditorState({
    this.isPlaying = false,
    this.currentTimeMs = 0,
    this.durationMs = 0,
    this.zoomLevel = 1.0,
    this.isImporting = false,
    this.isExporting = false,
    this.exportProgress = 0,
    this.selectedClipId,
    this.selectedTrackId,
    this.leftPanelTab = LeftPanelTab.media,
    this.showInspector = false,
    this.playbackSpeed = 1.0,
    this.lastError,
    this.isAudioPlaying = false,
    this.masterVolume = 1.0,
    this.isDecodingFrame = false,
    this.gpuAvailable = false,
    this.gpuInfo,
    this.hardwareEncoderAvailable = false,
    this.gpuAccelerationEnabled = true,
    this.showSafeZones = false,
    this.safeZoneMode = SafeZoneMode.broadcast,
    this.showAudioMeterBridge = false,
  });

  EditorState copyWith({
    bool? isPlaying,
    int? currentTimeMs,
    int? durationMs,
    double? zoomLevel,
    bool? isImporting,
    bool? isExporting,
    double? exportProgress,
    String? selectedClipId,
    String? selectedTrackId,
    LeftPanelTab? leftPanelTab,
    bool? showInspector,
    double? playbackSpeed,
    String? lastError,
    bool clearError = false,
    bool? isAudioPlaying,
    double? masterVolume,
    bool? isDecodingFrame,
    bool? gpuAvailable,
    GpuInfo? gpuInfo,
    bool clearGpuInfo = false,
    bool? hardwareEncoderAvailable,
    bool? gpuAccelerationEnabled,
    bool? showSafeZones,
    SafeZoneMode? safeZoneMode,
    bool? showAudioMeterBridge,
  }) {
    return EditorState(
      isPlaying: isPlaying ?? this.isPlaying,
      currentTimeMs: currentTimeMs ?? this.currentTimeMs,
      durationMs: durationMs ?? this.durationMs,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      isImporting: isImporting ?? this.isImporting,
      isExporting: isExporting ?? this.isExporting,
      exportProgress: exportProgress ?? this.exportProgress,
      selectedClipId: selectedClipId,
      selectedTrackId: selectedTrackId,
      leftPanelTab: leftPanelTab ?? this.leftPanelTab,
      showInspector: showInspector ?? this.showInspector,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      lastError: clearError ? null : (lastError ?? this.lastError),
      isAudioPlaying: isAudioPlaying ?? this.isAudioPlaying,
      masterVolume: masterVolume ?? this.masterVolume,
      isDecodingFrame: isDecodingFrame ?? this.isDecodingFrame,
      gpuAvailable: gpuAvailable ?? this.gpuAvailable,
      gpuInfo: clearGpuInfo ? null : (gpuInfo ?? this.gpuInfo),
      hardwareEncoderAvailable: hardwareEncoderAvailable ?? this.hardwareEncoderAvailable,
      gpuAccelerationEnabled: gpuAccelerationEnabled ?? this.gpuAccelerationEnabled,
      showSafeZones: showSafeZones ?? this.showSafeZones,
      safeZoneMode: safeZoneMode ?? this.safeZoneMode,
      showAudioMeterBridge: showAudioMeterBridge ?? this.showAudioMeterBridge,
    );
  }
}

/// Phase F.2: which set of safe-zone overlays to show.
/// Drives the SafeZoneConfig passed to SafeZonesOverlay.
enum SafeZoneMode {
  /// Title-safe (90%) + action-safe (80%) + center crosshair.
  broadcast,
  /// Title-safe (80% for captions) + center crosshair.
  social,
  /// Rule-of-thirds + center crosshair.
  composition,
  /// No overlays.
  off,
}

/// Phase F.2: extended with pro videographer tabs.
enum LeftPanelTab {
  media,
  effects,
  text,
  audio,
  speed,
  keyframes,
  mixer,
  scopes,
  markers,
  luts,
  eq,
}

/// Editor state notifier — mediates between the UI and the Rust engine.
///
/// Phase 4 improvements:
/// - Real-time preview playback with continuous frame decode loop
/// - Clip drag-and-move via engine bridge
/// - Project save/load integration
class EditorNotifier extends StateNotifier<EditorState> {
  Timer? _playbackTimer;
  DateTime? _lastFrameTime;
  final Ref _ref;

  EditorNotifier(this._ref) : super(const EditorState());

  @override
  void dispose() {
    _playbackTimer?.cancel();
    // Stop AV sync coordinator
    try {
      _ref.read(avSyncCoordinatorProvider).release();
    } catch (_) {
      // Provider may not be mounted — safe to ignore.
    }
    super.dispose();
  }

  /// Whether the engine is available for use.
  bool get _engineReady => EngineService.instance.isInitialized;

  /// Initialize the editor state from the engine.
  Future<void> initialize() async {
    if (!_engineReady) return;
    await _syncDurationFromEngine();
    state = const EditorState();
    // Check GPU availability on init
    await checkGpuAvailability();
  }

  // ─── Playback ────────────────────────────────────────────────────

  /// Play/pause toggle — uses AV sync coordinator for synchronized
  /// audio-video playback when audio is available.
  void togglePlayback() {
    if (state.isPlaying) {
      _stopPlayback();
    } else {
      state = state.copyWith(isPlaying: true, isAudioPlaying: true);
      _startPlayback();
    }
  }

  /// Stop playback and cancel timer + audio sync
  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _lastFrameTime = null;

    // Stop AV sync coordinator
    _ref.read(avSyncCoordinatorProvider).stop();

    state = state.copyWith(isPlaying: false, isAudioPlaying: false);
  }

  /// Start real-time playback from current position.
  ///
  /// This uses a high-frequency Timer that advances the playhead based
  /// on real elapsed time. When the engine is available, the AV sync
  /// coordinator handles synchronized audio feeding alongside the
  /// video playback loop.
  void _startPlayback() {
    _playbackTimer?.cancel();
    _lastFrameTime = DateTime.now();

    // Start AV sync for synchronized audio-video playback.
    // The sync coordinator drives its own timer for audio feeding,
    // while this timer drives the video playhead advancement.
    if (_engineReady) {
      _ref.read(avSyncCoordinatorProvider).start();
    }

    // Use ~60Hz tick for smooth video playhead advancement
    const tickMs = 16;
    _playbackTimer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      if (!state.isPlaying) {
        timer.cancel();
        _playbackTimer = null;
        return;
      }

      final now = DateTime.now();
      final elapsed = _lastFrameTime != null
          ? now.difference(_lastFrameTime!).inMilliseconds
          : tickMs;
      _lastFrameTime = now;

      // Apply playback speed multiplier
      final adjustedElapsed = (elapsed * state.playbackSpeed).round();

      final newTime = state.currentTimeMs + adjustedElapsed;
      if (newTime >= state.durationMs) {
        // Loop back to start when reaching the end
        seekTo(0);
      } else {
        seekTo(newTime);
      }
    });
  }

  /// Seek to a specific time position
  void seekTo(int timeMs) {
    state = state.copyWith(
      currentTimeMs: timeMs.clamp(0, state.durationMs > 0 ? state.durationMs : 300000),
    );
  }

  /// Set the timeline duration
  void setDuration(int durationMs) {
    state = state.copyWith(durationMs: durationMs);
  }

  /// Set playback speed (0.25x to 4.0x)
  void setPlaybackSpeed(double speed) {
    state = state.copyWith(playbackSpeed: speed.clamp(0.25, 4.0));
  }

  // ─── Zoom ────────────────────────────────────────────────────────

  /// Set zoom level
  void setZoom(double zoom) {
    state = state.copyWith(zoomLevel: zoom.clamp(0.1, 10.0));
  }

  /// Zoom in
  void zoomIn() {
    setZoom(state.zoomLevel * 1.2);
  }

  /// Zoom out
  void zoomOut() {
    setZoom(state.zoomLevel / 1.2);
  }

  // ─── Selection ───────────────────────────────────────────────────

  /// Select a clip
  void selectClip(String? clipId) {
    state = state.copyWith(
      selectedClipId: clipId,
      showInspector: clipId != null,
    );
  }

  /// Select a track
  void selectTrack(String? trackId) {
    state = state.copyWith(
      selectedTrackId: trackId,
      showInspector: trackId != null,
    );
  }

  // ─── State flags ─────────────────────────────────────────────────

  /// Set importing state
  void setImporting(bool importing) {
    state = state.copyWith(isImporting: importing);
  }

  /// Set exporting state
  void setExporting(bool exporting, {double progress = 0}) {
    state = state.copyWith(isExporting: exporting, exportProgress: progress);
  }

  /// Set the left panel tab
  void setLeftPanelTab(LeftPanelTab tab) {
    state = state.copyWith(leftPanelTab: tab);
  }

  /// Toggle inspector visibility
  void toggleInspector() {
    state = state.copyWith(showInspector: !state.showInspector);
  }

  /// Phase F.2: toggle the safe-zones overlay on/off.
  void toggleSafeZones() {
    if (state.safeZoneMode == SafeZoneMode.off) {
      state = state.copyWith(
        showSafeZones: true,
        safeZoneMode: SafeZoneMode.broadcast,
      );
    } else {
      state = state.copyWith(
        showSafeZones: false,
        safeZoneMode: SafeZoneMode.off,
      );
    }
  }

  /// Phase F.2: cycle through safe-zone modes (broadcast → social → composition → off).
  void cycleSafeZoneMode() {
    final next = switch (state.safeZoneMode) {
      SafeZoneMode.broadcast => SafeZoneMode.social,
      SafeZoneMode.social => SafeZoneMode.composition,
      SafeZoneMode.composition => SafeZoneMode.off,
      SafeZoneMode.off => SafeZoneMode.broadcast,
    };
    state = state.copyWith(
      showSafeZones: next != SafeZoneMode.off,
      safeZoneMode: next,
    );
  }

  /// Phase F.2: toggle the audio meter bridge at the bottom of the editor.
  void toggleAudioMeterBridge() {
    state = state.copyWith(showAudioMeterBridge: !state.showAudioMeterBridge);
  }

  /// Set master volume for audio playback
  void setMasterVolume(double volume) {
    state = state.copyWith(masterVolume: volume.clamp(0.0, 1.0));
    // Update AV sync volume if engine is available
    if (_engineReady) {
      _ref.read(avSyncCoordinatorProvider).setVolume(volume.clamp(0.0, 1.0));
    }
  }

  // ─── Bridge-wired operations ─────────────────────────────────────

  /// Undo last action via the Rust engine.
  Future<void> undo() async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.undo();
      await _syncDurationFromEngine();
      await _ref.read(projectProvider.notifier).syncFromEngine();
    } catch (e) {
      developer.log('undo failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Undo failed: $e');
    }
  }

  /// Redo last undone action via the Rust engine.
  Future<void> redo() async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.redo();
      await _syncDurationFromEngine();
      await _ref.read(projectProvider.notifier).syncFromEngine();
    } catch (e) {
      developer.log('redo failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Redo failed: $e');
    }
  }

  /// Split the currently selected clip at the playhead via the Rust engine.
  Future<void> splitAtPlayhead() async {
    if (!_engineReady) return;
    final clipId = state.selectedClipId;
    if (clipId == null) return;
    try {
      final api = EngineService.instance.api;
      await api.splitClip(clipId: clipId, timeMs: BigInt.from(state.currentTimeMs));
      await _syncDurationFromEngine();
      _refreshEngineState();
      await _ref.read(projectProvider.notifier).syncFromEngine();
    } catch (e) {
      developer.log('splitAtPlayhead failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Split failed: $e');
    }
  }

  /// Delete the currently selected clip via the Rust engine.
  Future<void> deleteSelected() async {
    if (!_engineReady) return;
    final clipId = state.selectedClipId;
    if (clipId == null) return;

    // Phase E.14: refuse to delete a locked clip. The user must unlock
    // it first via the inspector. This protects pinned clips (titles,
    // logos, etc.) from accidental deletion.
    final project = _ref.read(currentProjectProvider);
    if (project != null) {
      final clip = project.tracks
          .expand((t) => t.clips)
          .cast<ClipModel?>()
          .firstWhere((c) => c?.id == clipId, orElse: () => null);
      if (clip != null && clip.locked) {
        state = state.copyWith(
          lastError: 'Clip is locked — unlock it first to delete.',
        );
        return;
      }
    }

    try {
      final api = EngineService.instance.api;
      await api.removeClip(clipId: clipId);
      state = state.copyWith(selectedClipId: null, showInspector: false);
      await _syncDurationFromEngine();
      _refreshEngineState();
      await _ref.read(projectProvider.notifier).syncFromEngine();
    } catch (e) {
      developer.log('deleteSelected failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Delete failed: $e');
    }
  }

  /// Import a media file via the Rust engine.
  Future<MediaAssetInfo?> importMedia(String filePath) async {
    if (!_engineReady) return null;
    try {
      final api = EngineService.instance.api;
      final assetInfo = await api.importMedia(filePath: filePath);
      await _syncDurationFromEngine();
      _refreshEngineState();
      return assetInfo;
    } catch (e) {
      developer.log('importMedia failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Import failed: $e');
      return null;
    }
  }

  /// Add a clip to a track via the Rust engine.
  Future<ClipInfo?> addClipToTrack({
    required String trackId,
    required String assetId,
    required int startMs,
    int durationMs = 0,
  }) async {
    if (!_engineReady) return null;
    try {
      final api = EngineService.instance.api;
      final clipInfo = await api.addClip(
        trackId: trackId,
        assetId: assetId,
        startMs: BigInt.from(startMs),
        durationMs: BigInt.from(durationMs),
      );
      await _syncDurationFromEngine();
      _refreshEngineState();
      return clipInfo;
    } catch (e) {
      developer.log('addClipToTrack failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Add clip failed: $e');
      return null;
    }
  }

  /// Move a clip to a new position on the timeline.
  ///
  /// This is the engine-backed implementation for clip drag-and-drop.
  Future<void> moveClip({
    required String clipId,
    required int newStartMs,
    String? newTrackId,
  }) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.moveClip(
        clipId: clipId,
        newStartMs: BigInt.from(newStartMs),
        newTrackId: newTrackId,
      );
      await _syncDurationFromEngine();
      _refreshEngineState();
      await _ref.read(projectProvider.notifier).syncFromEngine();
    } catch (e) {
      developer.log('moveClip failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Move clip failed: $e');
    }
  }

  /// Trim a clip by adjusting its start/end trim points.
  Future<void> trimClip({
    required String clipId,
    required int trimStartMs,
    required int trimEndMs,
  }) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.trimClip(
        clipId: clipId,
        trimStartMs: BigInt.from(trimStartMs),
        trimEndMs: BigInt.from(trimEndMs),
      );
      await _syncDurationFromEngine();
      _refreshEngineState();
    } catch (e) {
      developer.log('trimClip failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Trim clip failed: $e');
    }
  }

  /// Create a new project via the Rust engine.
  Future<ProjectInfo?> createProject(String name, {int? width, int? height, double? fps}) async {
    if (!_engineReady) return null;
    try {
      final api = EngineService.instance.api;

      BridgeProjectSettings? settings;
      if (width != null || height != null || fps != null) {
        settings = BridgeProjectSettings(
          width: width ?? 1920,
          height: height ?? 1080,
          fps: fps ?? 30.0,
        );
      }

      final projectInfo = await api.createProject(name: name, settings: settings);
      await _syncDurationFromEngine();
      _refreshEngineState();
      return projectInfo;
    } catch (e) {
      developer.log('createProject failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Create project failed: $e');
      return null;
    }
  }

  /// Save the current project via the Rust engine.
  Future<void> saveProject({required String filePath}) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.saveProject(filePath: filePath);
    } catch (e) {
      developer.log('saveProject failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Save failed: $e');
    }
  }

  /// Load a project from a .epp file via the Rust engine.
  Future<void> loadProject({required String filePath}) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.loadProject(filePath: filePath);
      await _syncDurationFromEngine();
      _refreshEngineState();
    } catch (e) {
      developer.log('loadProject failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Load failed: $e');
    }
  }

  // ─── Audio Bridge Operations ──────────────────────────────────────

  /// Set the volume level for a track via the Rust engine.
  Future<void> setTrackVolume(String trackId, double volume) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.setTrackVolume(trackId: trackId, volume: volume);
      _refreshEngineState();
    } catch (e) {
      developer.log('setTrackVolume failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Set volume failed: $e');
    }
  }

  /// Toggle track visibility (mute/unmute) via the Rust engine.
  Future<void> toggleTrackVisibility(String trackId) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.toggleTrackVisibility(trackId: trackId);
      _refreshEngineState();
    } catch (e) {
      developer.log('toggleTrackVisibility failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Toggle mute failed: $e');
    }
  }

  /// Get waveform peak data for an audio asset.
  Future<List<double>> getWaveform(String assetId, {int numBins = 200}) async {
    if (!_engineReady) return [];
    try {
      final api = EngineService.instance.api;
      final peaks = await api.getWaveform(assetId: assetId, numBins: numBins);
      return peaks.map((e) => e.toDouble()).toList();
    } catch (e) {
      developer.log('getWaveform failed: $e', name: 'EditorNotifier');
      return [];
    }
  }

  /// Configure audio ducking for a track.
  Future<void> setDucking(String trackId, {required bool enabled, double duckLevel = 0.3}) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.setDucking(trackId: trackId, enabled: enabled, duckLevel: duckLevel);
    } catch (e) {
      developer.log('setDucking failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Set ducking failed: $e');
    }
  }

  /// Get the full timeline state from the engine.
  Future<dynamic> getTimelineState() async {
    if (!_engineReady) return null;
    try {
      final api = EngineService.instance.api;
      return await api.getTimelineState();
    } catch (e) {
      developer.log('getTimelineState failed: $e', name: 'EditorNotifier');
      return null;
    }
  }

  // ─── Effect Bridge Operations ──────────────────────────────────────

  /// Add a filter effect to the selected clip.
  Future<String?> addEffect(String filterTypeName) async {
    if (!_engineReady) return null;
    final clipId = state.selectedClipId;
    if (clipId == null) return null;
    try {
      final api = EngineService.instance.api;
      final effectInfo = await api.addEffect(
        clipId: clipId,
        filterTypeName: filterTypeName,
      );
      _refreshEngineState();
      return effectInfo.id;
    } catch (e) {
      developer.log('addEffect failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Add effect failed: $e');
      return null;
    }
  }

  /// Remove an effect from the selected clip.
  Future<void> removeEffect(String effectId) async {
    if (!_engineReady) return;
    final clipId = state.selectedClipId;
    if (clipId == null) return;
    try {
      final api = EngineService.instance.api;
      await api.removeEffect(clipId: clipId, effectId: effectId);
      _refreshEngineState();
    } catch (e) {
      developer.log('removeEffect failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Remove effect failed: $e');
    }
  }

  /// Set a parameter value for an effect on the selected clip.
  Future<void> setEffectParameter(
    String effectId,
    String paramName,
    double value,
  ) async {
    if (!_engineReady) return;
    final clipId = state.selectedClipId;
    if (clipId == null) return;
    try {
      final api = EngineService.instance.api;
      await api.setEffectParameter(
        clipId: clipId,
        effectId: effectId,
        paramName: paramName,
        value: value,
      );
      _refreshEngineState();
    } catch (e) {
      developer.log('setEffectParameter failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Set parameter failed: $e');
    }
  }

  /// Toggle the enabled/disabled state of an effect.
  Future<void> toggleEffect(String effectId) async {
    if (!_engineReady) return;
    final clipId = state.selectedClipId;
    if (clipId == null) return;
    try {
      final api = EngineService.instance.api;
      await api.toggleEffect(clipId: clipId, effectId: effectId);
      _refreshEngineState();
    } catch (e) {
      developer.log('toggleEffect failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Toggle effect failed: $e');
    }
  }

  /// Get the filter catalog from the engine.
  Future<List<dynamic>> getFilterCatalog() async {
    if (!_engineReady) return [];
    try {
      final api = EngineService.instance.api;
      return await api.getFilterCatalog();
    } catch (e) {
      developer.log('getFilterCatalog failed: $e', name: 'EditorNotifier');
      return [];
    }
  }

  /// Get the filter presets from the engine.
  Future<List<dynamic>> getFilterPresets() async {
    if (!_engineReady) return [];
    try {
      final api = EngineService.instance.api;
      return await api.getFilterPresets();
    } catch (e) {
      developer.log('getFilterPresets failed: $e', name: 'EditorNotifier');
      return [];
    }
  }

  /// Apply a filter preset to the selected clip.
  Future<void> applyFilterPreset(String presetId) async {
    if (!_engineReady) return;
    final clipId = state.selectedClipId;
    if (clipId == null) return;
    try {
      final api = EngineService.instance.api;
      await api.applyFilterPreset(clipId: clipId, presetId: presetId);
      _refreshEngineState();
    } catch (e) {
      developer.log('applyFilterPreset failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Apply preset failed: $e');
    }
  }

  // ─── Transition Bridge Operations ──────────────────────────────────

  /// Add a transition to the selected clip.
  Future<String?> addTransition(
    String transitionType,
    int durationMs,
    String direction,
  ) async {
    if (!_engineReady) return null;
    final clipId = state.selectedClipId;
    if (clipId == null) return null;
    try {
      final api = EngineService.instance.api;
      final info = await api.addTransition(
        clipId: clipId,
        transitionType: transitionType,
        durationMs: BigInt.from(durationMs),
        direction: direction,
      );
      _refreshEngineState();
      return info.id;
    } catch (e) {
      developer.log('addTransition failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Add transition failed: $e');
      return null;
    }
  }

  /// Remove a transition from the selected clip.
  Future<void> removeTransition(String direction) async {
    if (!_engineReady) return;
    final clipId = state.selectedClipId;
    if (clipId == null) return;
    try {
      final api = EngineService.instance.api;
      await api.removeTransition(clipId: clipId, direction: direction);
      _refreshEngineState();
    } catch (e) {
      developer.log('removeTransition failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Remove transition failed: $e');
    }
  }

  /// Get the transition catalog from the engine.
  Future<List<dynamic>> getTransitionCatalog() async {
    if (!_engineReady) return [];
    try {
      final api = EngineService.instance.api;
      return await api.getTransitionCatalog();
    } catch (e) {
      developer.log('getTransitionCatalog failed: $e', name: 'EditorNotifier');
      return [];
    }
  }

  // ─── Text Overlay Bridge Operations ────────────────────────────────

  /// Add a text clip to a track via the Rust engine.
  Future<ClipInfo?> addTextClip({
    required String trackId,
    required String text,
    required String fontFamily,
    required double fontSize,
    required String colorHex,
    required double positionX,
    required double positionY,
    required int startMs,
    required int durationMs,
  }) async {
    if (!_engineReady) return null;
    try {
      final api = EngineService.instance.api;
      final clipInfo = await api.addTextClip(
        trackId: trackId,
        text: text,
        fontFamily: fontFamily,
        fontSize: fontSize,
        colorHex: colorHex,
        positionX: positionX,
        positionY: positionY,
        startMs: startMs,
        durationMs: durationMs,
      );
      await _syncDurationFromEngine();
      _refreshEngineState();
      await _ref.read(projectProvider.notifier).syncFromEngine();
      return clipInfo;
    } catch (e) {
      developer.log('addTextClip failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Add text clip failed: $e');
      return null;
    }
  }

  /// Update the position of a text overlay clip.
  Future<void> updateTextPosition({
    required String clipId,
    required double positionX,
    required double positionY,
  }) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.setTextPosition(
        clipId: clipId,
        positionX: positionX,
        positionY: positionY,
      );
      _refreshEngineState();
    } catch (e) {
      developer.log('updateTextPosition failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Update text position failed: $e');
    }
  }

  /// Update the style of a text overlay clip.
  Future<void> updateTextStyle({
    required String clipId,
    required String fontFamily,
    required double fontSize,
    required String colorHex,
  }) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.setTextStyle(
        clipId: clipId,
        fontFamily: fontFamily,
        fontSize: fontSize,
        colorHex: colorHex,
      );
      _refreshEngineState();
    } catch (e) {
      developer.log('updateTextStyle failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Update text style failed: $e');
    }
  }

  /// Get the list of available fonts from the engine.
  Future<List<FontInfo>> getAvailableFonts() async {
    if (!_engineReady) return [];
    try {
      final api = EngineService.instance.api;
      return await api.getAvailableFonts();
    } catch (e) {
      developer.log('getAvailableFonts failed: $e', name: 'EditorNotifier');
      return [];
    }
  }

  /// Check whether undo is available.
  Future<bool> canUndo() async {
    if (!_engineReady) return false;
    try {
      final api = EngineService.instance.api;
      return await api.canUndo();
    } catch (e) {
      return false;
    }
  }

  /// Check whether redo is available.
  Future<bool> canRedo() async {
    if (!_engineReady) return false;
    try {
      final api = EngineService.instance.api;
      return await api.canRedo();
    } catch (e) {
      return false;
    }
  }

  // ─── Speed & Keyframe Bridge Operations ───────────────────────────

  /// Set the playback speed for a clip via the engine.
  Future<void> setClipSpeed(String clipId, double speed) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      developer.log(
        'setClipSpeed: clipId=$clipId, speed=$speed',
        name: 'EditorNotifier',
      );
      final curve = BridgeSpeedCurve.constant(speed);
      await api.setClipSpeedCurve(clipId: clipId, curve: curve);
      _refreshEngineState();
    } catch (e) {
      developer.log('setClipSpeed failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Set clip speed failed: $e');
    }
  }

  /// Set a multi-segment speed curve for a clip.
  Future<void> setClipSpeedCurve(String clipId, List<dynamic> segments) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      developer.log(
        'setClipSpeedCurve: clipId=$clipId, segments=${segments.length}',
        name: 'EditorNotifier',
      );
      final bridgeSegments = segments.map((s) {
        return BridgeSpeedSegment(
          startMs: s['start_ms'] as int? ?? 0,
          endMs: s['end_ms'] as int? ?? 0,
          startSpeed: (s['start_speed'] as num?)?.toDouble() ?? 1.0,
          endSpeed: (s['end_speed'] as num?)?.toDouble() ?? 1.0,
          easingName: s['easing_name'] as String? ?? 'linear',
        );
      }).toList();
      final curve = BridgeSpeedCurve(segments: bridgeSegments);
      await api.setClipSpeedCurve(clipId: clipId, curve: curve);
      _refreshEngineState();
    } catch (e) {
      developer.log('setClipSpeedCurve failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Set speed curve failed: $e');
    }
  }

  /// Add a keyframe to a clip property via the engine.
  Future<void> addKeyframe(
    String clipId,
    String property,
    int timeMs,
    double value,
    String easingName,
  ) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.addKeyframe(
        clipId: clipId,
        property: property,
        timeMs: timeMs,
        value: value,
        easingName: easingName,
      );
      _refreshEngineState();
    } catch (e) {
      developer.log('addKeyframe failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Add keyframe failed: $e');
    }
  }

  /// Remove a keyframe from a clip property via the engine.
  Future<void> removeKeyframe(
    String clipId,
    String property,
    String keyframeId,
  ) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.removeKeyframe(
        clipId: clipId,
        property: property,
        keyframeId: keyframeId,
      );
      _refreshEngineState();
    } catch (e) {
      developer.log('removeKeyframe failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Remove keyframe failed: $e');
    }
  }

  /// Update a keyframe on a clip property via the engine.
  Future<void> updateKeyframe(
    String clipId,
    String property,
    String keyframeId, {
    double? value,
    String? easing,
  }) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.updateKeyframe(
        clipId: clipId,
        property: property,
        keyframeId: keyframeId,
        value: value,
        easingName: easing,
      );
      _refreshEngineState();
    } catch (e) {
      developer.log('updateKeyframe failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Update keyframe failed: $e');
    }
  }

  /// Get keyframes for a clip property.
  Future<List<dynamic>> getKeyframes(String clipId, String property) async {
    if (!_engineReady) return [];
    try {
      final api = EngineService.instance.api;
      return await api.getKeyframes(clipId: clipId, property: property);
    } catch (e) {
      developer.log('getKeyframes failed: $e', name: 'EditorNotifier');
      return [];
    }
  }

  /// Update a clip transform property (position, scale, rotation) via keyframes.
  ///
  /// This is called by the transform handles in the preview viewport when
  /// the user drags to move, scale, or rotate a clip. It adds or updates
  /// a keyframe at the current playhead time.
  Future<void> updateClipTransform({
    required String clipId,
    required String property,
    required double delta,
  }) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      final timeMs = state.currentTimeMs;
      // Get existing keyframes at this time, or add a new one
      await api.addKeyframe(
        clipId: clipId,
        property: property,
        timeMs: timeMs,
        value: delta,
        easingName: 'Linear',
      );
      _refreshEngineState();
    } catch (e) {
      developer.log('updateClipTransform failed: $e', name: 'EditorNotifier');
    }
  }

  // ─── Internal helpers ────────────────────────────────────────────

  /// Read the timeline duration from the engine and update state.
  Future<void> _syncDurationFromEngine() async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      final duration = await api.getTimelineDuration();
      state = state.copyWith(durationMs: duration.toInt());
    } catch (e) {
      developer.log('syncDuration failed: $e', name: 'EditorNotifier');
    }
  }

  /// Invalidate the engine-state caches so that downstream providers
  /// (project info, timeline duration) re-read fresh data.
  void _refreshEngineState() {
    try {
      _ref.read(engineStateRefresherProvider.notifier).refresh();
    } catch (_) {
      // Provider may not be mounted yet — safe to ignore.
    }
  }

  // ─── GPU Acceleration (Phase 8) ──────────────────────────────────

  /// Check GPU availability and update state.
  ///
  /// Queries the engine for GPU info and updates the editor state
  /// with the results. Called during initialization and can be called
  /// again to re-check after a GPU toggle.
  Future<void> checkGpuAvailability() async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      final available = await api.isGpuAvailable();
      final gpuInfo = await api.getGpuInfo();
      state = state.copyWith(
        gpuAvailable: available,
        gpuInfo: gpuInfo,
        hardwareEncoderAvailable: gpuInfo?.isHardwareEncoderAvailable ?? false,
      );
      developer.log(
        'GPU availability: $available, HW encoder: ${gpuInfo?.isHardwareEncoderAvailable ?? false}',
        name: 'EditorNotifier',
      );
    } catch (e) {
      developer.log('checkGpuAvailability failed: $e', name: 'EditorNotifier');
      state = state.copyWith(gpuAvailable: false, clearGpuInfo: true);
    }
  }

  /// Toggle GPU acceleration on or off.
  ///
  /// When [enabled] is `false`, the engine will use CPU-only rendering
  /// even if a GPU is available. This is useful for debugging or when
  /// GPU rendering produces incorrect results on a particular device.
  Future<void> toggleGpuAcceleration(bool enabled) async {
    if (!_engineReady) return;
    try {
      final api = EngineService.instance.api;
      await api.setGpuAcceleration(enabled: enabled);
      state = state.copyWith(gpuAccelerationEnabled: enabled);
      developer.log(
        'GPU acceleration ${enabled ? "enabled" : "disabled"} by user',
        name: 'EditorNotifier',
      );
    } catch (e) {
      developer.log('toggleGpuAcceleration failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Toggle GPU acceleration failed: $e');
    }
  }

  // ─── Chroma Key Operations (Phase 10.1) ────────────────────────────

  /// Add a chroma key effect to a clip with the specified parameters.
  ///
  /// Returns the [EffectInfo] for the newly created effect, or `null`
  /// on failure. After adding the effect, the engine state is refreshed
  /// so the UI reflects the new effect in the inspector panel.
  Future<EffectInfo?> addChromaKeyEffect(
    String clipId, {
    double targetHue = 120.0,
    double hueTolerance = 30.0,
    double saturationTolerance = 0.4,
    double softness = 0.15,
    double spillSuppression = 0.5,
  }) async {
    if (!_engineReady) return null;
    try {
      final service = EngineService.instance;
      final result = await service.addChromaKeyEffect(
        clipId,
        targetHue,
        hueTolerance,
        saturationTolerance,
        softness,
        spillSuppression,
      );
      _refreshEngineState();
      developer.log(
        'addChromaKeyEffect: clipId=$clipId, targetHue=$targetHue',
        name: 'EditorNotifier',
      );
      return result;
    } catch (e) {
      developer.log('addChromaKeyEffect failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Add chroma key effect failed: $e');
      return null;
    }
  }

  /// Pick a color from the preview frame at the given coordinates.
  ///
  /// Returns the RGB values as a list [r, g, b] in the range 0–255,
  /// or `null` on failure. This is used by the eyedropper tool in the
  /// chroma key UI to select the target color directly from the video.
  Future<List<double>?> pickColorFromFrame(int timeMs, int x, int y) async {
    if (!_engineReady) return null;
    try {
      final service = EngineService.instance;
      final result = await service.pickColorFromFrame(timeMs, x, y);
      developer.log(
        'pickColorFromFrame: timeMs=$timeMs, x=$x, y=$y → $result',
        name: 'EditorNotifier',
      );
      return result;
    } catch (e) {
      developer.log('pickColorFromFrame failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Pick color from frame failed: $e');
      return null;
    }
  }

  // ─── Transcription Operations (Phase 10.2) ────────────────────────

  /// Transcribe audio from a media asset.
  ///
  /// Returns a list of [TranscriptionSegmentInfo] DTOs with timestamped
  /// text segments, or an empty list on failure.
  Future<List<TranscriptionSegmentInfo>> transcribeAudio(
    String assetId,
    String language,
  ) async {
    if (!_engineReady) return [];
    try {
      final service = EngineService.instance;
      final segments = await service.transcribeAudio(assetId, language);
      developer.log(
        'transcribeAudio: assetId=$assetId, language=$language → ${segments.length} segments',
        name: 'EditorNotifier',
      );
      return segments;
    } catch (e) {
      developer.log('transcribeAudio failed: $e', name: 'EditorNotifier');
      state = state.copyWith(lastError: 'Transcription failed: $e');
      return [];
    }
  }

  /// Create text clips on a text track from a transcription result.
  ///
  /// Transcribes the audio from the given asset and creates text clips
  /// on the specified track, one for each transcription segment.
  /// Returns the IDs of the newly created text clips.
  Future<List<String>> addSubtitlesFromTranscription(
    String assetId,
    String trackId,
  ) async {
    if (!_engineReady) return [];
    try {
      final service = EngineService.instance;
      final clipIds = await service.addSubtitlesFromTranscription(
        assetId,
        trackId,
      );
      _refreshEngineState();
      developer.log(
        'addSubtitlesFromTranscription: assetId=$assetId, trackId=$trackId → ${clipIds.length} clips',
        name: 'EditorNotifier',
      );
      return clipIds;
    } catch (e) {
      developer.log(
        'addSubtitlesFromTranscription failed: $e',
        name: 'EditorNotifier',
      );
      state = state.copyWith(
        lastError: 'Add subtitles from transcription failed: $e',
      );
      return [];
    }
  }
}

/// Provider for editor state
final editorProvider = StateNotifierProvider<EditorNotifier, EditorState>((ref) {
  return EditorNotifier(ref);
});

/// Provider for current playback time formatted
final playbackTimeProvider = Provider<String>((ref) {
  final timeMs = ref.watch(editorProvider.select((s) => s.currentTimeMs));
  return Duration(milliseconds: timeMs).formatted;
});

/// Provider for duration formatted
final durationTimeProvider = Provider<String>((ref) {
  final durationMs = ref.watch(editorProvider.select((s) => s.durationMs));
  return Duration(milliseconds: durationMs).formatted;
});

/// Provider for waveform data, keyed by asset ID
final waveformProvider = FutureProvider.family<List<double>, String>((ref, assetId) async {
  final notifier = ref.read(editorProvider.notifier);
  return notifier.getWaveform(assetId);
});
