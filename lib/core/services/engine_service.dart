import 'dart:async';
import 'dart:developer' as developer;

import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:editors_pro/src/rust/frb_generated.dart';

// Re-export ProxyInfo so consumers don't need to import the bridge
typedef EngineProxyInfo = ProxyInfo;

/// Singleton service that manages the Rust engine lifecycle.
///
/// Lazily initializes [RustLib] and creates an [EditorsProEngineApi]
/// instance the first time it is accessed. All subsequent calls reuse
/// the same API instance.
///
/// Usage:
/// ```dart
/// final service = EngineService.instance;
/// await service.initialize();
/// final api = service.api;
/// ```
class EngineService {
  EngineService._();

  static final EngineService instance = EngineService._();

  EditorsProEngineApi? _api;
  bool _initialized = false;
  bool _initializing = false;
  Completer<void>? _initCompleter;

  /// Whether the engine has been successfully initialized.
  bool get isInitialized => _initialized;

  /// The bridge API instance.
  ///
  /// Throws [StateError] if the engine has not been initialized yet.
  EditorsProEngineApi get api {
    if (_api == null) {
      throw StateError(
        'EngineService not initialized. Call initialize() first.',
      );
    }
    return _api!;
  }

  /// Initialize the Rust engine.
  ///
  /// This must be called once before any engine operations. It is safe
  /// to call multiple times — subsequent calls will await the same
  /// initialization or return immediately if already done.
  ///
  /// Returns `true` if initialization succeeded, `false` otherwise.
  Future<bool> initialize() async {
    if (_initialized) return true;

    // If initialization is already in progress, wait for it.
    if (_initializing && _initCompleter != null) {
      await _initCompleter!.future;
      return _initialized;
    }

    _initializing = true;
    _initCompleter = Completer<void>();

    try {
      developer.log('Initializing RustLib…', name: 'EngineService');

      // Initialize the flutter_rust_bridge runtime.
      await RustLib.init();

      developer.log(
        'RustLib initialized, creating engine API…',
        name: 'EngineService',
      );

      // Get the API wrapper from the RustLib instance (which was
      // initialized above).  The noOp fallback is used when the
      // native library is not available.
      final engineApi = RustLib.instance.api;

      // If the engine is in noOp mode, skip native initialization.
      if (engineApi.isEngineAvailable) {
        await engineApi.initialize();
      } else {
        developer.log(
          'Engine is in noOp mode — skipping native initialization',
          name: 'EngineService',
        );
        // Don't mark as initialized since the engine isn't really available.
        _initializing = false;
        return false;
      }

      _api = engineApi;
      _initialized = true;

      developer.log(
        'Engine fully initialized',
        name: 'EngineService',
      );

      if (!(_initCompleter?.isCompleted ?? true)) {
        _initCompleter!.complete();
      }

      return true;
    } catch (e, st) {
      developer.log(
        'Engine initialization failed: $e',
        name: 'EngineService',
        error: e,
        stackTrace: st,
      );

      if (!(_initCompleter?.isCompleted ?? true)) {
        _initCompleter!.completeError(e, st);
      }

      _initializing = false;
      return false;
    }
  }

  /// Dispose of the engine and release resources.
  ///
  /// After calling this, the engine must be re-initialized before use.
  void dispose() {
    _api = null;
    _initialized = false;
    _initializing = false;
    _initCompleter = null;
  }

  // ─── GPU Acceleration (Phase 8) ──────────────────────────────────────

  /// Check if GPU rendering is available.
  ///
  /// Returns `true` when a compatible GPU adapter was found during
  /// engine initialization.
  Future<bool> isGpuAvailable() async {
    if (!_initialized) return false;
    try {
      return await _api!.isGpuAvailable();
    } catch (e) {
      developer.log('isGpuAvailable failed: $e', name: 'EngineService');
      return false;
    }
  }

  /// Get GPU adapter information.
  ///
  /// Returns a [GpuInfo] object describing the available GPU adapter,
  /// including its name, backend type, VRAM, and supported effects.
  Future<GpuInfo?> getGpuInfo() async {
    if (!_initialized) return null;
    try {
      return await _api!.getGpuInfo();
    } catch (e) {
      developer.log('getGpuInfo failed: $e', name: 'EngineService');
      return null;
    }
  }

  /// Export the project using a hardware encoder when available.
  ///
  /// When a hardware encoder is available (NVENC, VideoToolbox, etc.),
  /// this method uses it for significantly faster encoding. Falls back
  /// to the software encoder if the hardware encoder fails.
  Future<BridgeExportResult?> exportVideoHardware(
    String outputPath,
    BridgeExportSettings settings,
  ) async {
    if (!_initialized) return null;
    try {
      return await _api!.exportVideoHardware(
        outputPath: outputPath,
        settings: settings,
      );
    } catch (e) {
      developer.log('exportVideoHardware failed: $e', name: 'EngineService');
      return null;
    }
  }

  /// Toggle GPU acceleration on or off.
  ///
  /// When [enabled] is `false`, the engine will use CPU-only rendering
  /// even if a GPU is available. This is useful for debugging.
  Future<void> setGpuAcceleration(bool enabled) async {
    if (!_initialized) return;
    try {
      await _api!.setGpuAcceleration(enabled: enabled);
    } catch (e) {
      developer.log('setGpuAcceleration failed: $e', name: 'EngineService');
    }
  }

  // ─── Chroma Key (Phase 10.1) ────────────────────────────────────────

  // ─── Template Operations (Phase 10.3) ────────────────────────────────

  /// List all available built-in templates.
  ///
  /// Returns a list of [TemplateInfo] objects describing each template,
  /// including its category, duration, aspect ratio, and placeholder count.
  Future<List<TemplateInfo>> listTemplates() async {
    if (!_initialized) return [];
    try {
      return await _api!.getTemplates();
    } catch (e) {
      developer.log('listTemplates failed: $e', name: 'EngineService');
      return [];
    }
  }

  /// Get details for a specific template by its ID.
  ///
  /// Returns `null` if no template with the given ID exists or if
  /// the engine is not initialized.
  Future<TemplateInfo?> getTemplateDetails(String templateId) async {
    if (!_initialized) return null;
    try {
      return await _api!.getTemplateDetails(templateId: templateId);
    } catch (e) {
      developer.log('getTemplateDetails failed: $e', name: 'EngineService');
      return null;
    }
  }

  /// Create a new project from a template by filling placeholder slots.
  ///
  /// [templateId] identifies which built-in template to use.
  /// [assignments] is a map of slot ID → media file path.
  /// Slots without assignments are filled with placeholder (black) clips.
  ///
  /// Returns the [ProjectInfo] for the newly created project, or `null`
  /// if the operation failed.
  Future<ProjectInfo?> instantiateTemplate(
    String templateId,
    Map<String, String> assignments,
  ) async {
    if (!_initialized) return null;
    try {
      return await _api!.instantiateTemplate(
        templateId: templateId,
        assignments: assignments,
      );
    } catch (e) {
      developer.log('instantiateTemplate failed: $e', name: 'EngineService');
      return null;
    }
  }

  // ─── Chroma Key (Phase 10.1) ────────────────────────────────────────

  /// Add a chroma key effect to a clip with the specified parameters.
  ///
  /// Returns the [EffectInfo] for the newly added effect, or `null` if
  /// the operation failed.
  Future<EffectInfo?> addChromaKeyEffect(
    String clipId,
    double targetHue,
    double hueTolerance,
    double satTolerance,
    double softness,
    double spillSuppression,
  ) async {
    if (!_initialized) return null;
    try {
      return await _api!.addChromaKeyEffect(
        clipId: clipId,
        targetHue: targetHue,
        hueTolerance: hueTolerance,
        saturationTolerance: satTolerance,
        softness: softness,
        spillSuppression: spillSuppression,
      );
    } catch (e) {
      developer.log('addChromaKeyEffect failed: $e', name: 'EngineService');
      return null;
    }
  }

  /// Pick a color from the preview frame at the given coordinates.
  ///
  /// Decodes a frame at [timeMs] and samples the pixel at ([x], [y]),
  /// returning the RGB values as a list [r, g, b] in the range 0–255.
  /// This is used by the eyedropper tool in the chroma key UI to select
  /// the target color directly from the video frame.
  ///
  /// Returns `null` if the operation failed.
  Future<List<double>?> pickColorFromFrame(
    int timeMs,
    int x,
    int y,
  ) async {
    if (!_initialized) return null;
    try {
      return await _api!.pickColorFromFrame(
        timeMs: timeMs,
        x: x,
        y: y,
      );
    } catch (e) {
      developer.log('pickColorFromFrame failed: $e', name: 'EngineService');
      return null;
    }
  }

  // ─── Proxy Workflow (Phase 10.4) ──────────────────────────────────

  /// Set the proxy quality level.
  ///
  /// Valid values: "Off", "360p", "480p", "720p".
  Future<void> setProxyQuality(String quality) async {
    if (!_initialized) return;
    try {
      await _api!.setProxyQuality(quality: quality);
    } catch (e) {
      developer.log('setProxyQuality failed: $e', name: 'EngineService');
    }
  }

  /// Get the current proxy quality setting.
  ///
  /// Returns one of: "Off", "360p", "480p", "720p".
  Future<String> getProxyQuality() async {
    if (!_initialized) return '480p';
    try {
      return await _api!.getProxyQuality();
    } catch (e) {
      developer.log('getProxyQuality failed: $e', name: 'EngineService');
      return '480p';
    }
  }

  /// Generate a proxy for the given asset.
  ///
  /// Returns the path to the generated proxy file, or null on failure.
  Future<String?> generateProxy(String assetId, String sourcePath) async {
    if (!_initialized) return null;
    try {
      return await _api!.generateProxy(
        assetId: assetId,
        sourcePath: sourcePath,
      );
    } catch (e) {
      developer.log('generateProxy failed: $e', name: 'EngineService');
      return null;
    }
  }

  /// Get the proxy path for an asset, if one exists.
  Future<String?> getProxyPath(String assetId) async {
    if (!_initialized) return null;
    try {
      return await _api!.getProxyPath(assetId: assetId);
    } catch (e) {
      developer.log('getProxyPath failed: $e', name: 'EngineService');
      return null;
    }
  }

  /// Clear all proxy files from the cache directory.
  ///
  /// Returns the total bytes freed, or 0 on failure.
  Future<int> clearProxyCache() async {
    if (!_initialized) return 0;
    try {
      final freed = await _api!.clearProxyCache();
      return freed;
    } catch (e) {
      developer.log('clearProxyCache failed: $e', name: 'EngineService');
      return 0;
    }
  }

  /// Get the total size of all proxy files in the cache, in bytes.
  Future<int> getProxyCacheSize() async {
    if (!_initialized) return 0;
    try {
      final size = await _api!.getProxyCacheSize();
      return size;
    } catch (e) {
      developer.log('getProxyCacheSize failed: $e', name: 'EngineService');
      return 0;
    }
  }

  /// Get the number of active proxies.
  Future<int> getProxyCount() async {
    if (!_initialized) return 0;
    try {
      return await _api!.getProxyCount();
    } catch (e) {
      developer.log('getProxyCount failed: $e', name: 'EngineService');
      return 0;
    }
  }

  /// Enable or disable automatic proxy generation on import.
  Future<void> setAutoProxy(bool enabled) async {
    if (!_initialized) return;
    try {
      await _api!.setAutoProxy(enabled: enabled);
    } catch (e) {
      developer.log('setAutoProxy failed: $e', name: 'EngineService');
    }
  }

  /// Check whether automatic proxy generation is enabled.
  Future<bool> isAutoProxyEnabled() async {
    if (!_initialized) return true;
    try {
      return await _api!.isAutoProxyEnabled();
    } catch (e) {
      developer.log('isAutoProxyEnabled failed: $e', name: 'EngineService');
      return true;
    }
  }

  /// Regenerate the proxy for an asset.
  ///
  /// Returns the path to the newly generated proxy file, or null on failure.
  Future<String?> regenerateProxy(String assetId) async {
    if (!_initialized) return null;
    try {
      return await _api!.regenerateProxy(assetId: assetId);
    } catch (e) {
      developer.log('regenerateProxy failed: $e', name: 'EngineService');
      return null;
    }
  }

  /// Check whether a video at the given resolution would trigger
  /// proxy generation.
  Future<bool> shouldGenerateProxy(int width, int height) async {
    if (!_initialized) return false;
    try {
      return await _api!.shouldGenerateProxy(width: width, height: height);
    } catch (e) {
      developer.log('shouldGenerateProxy failed: $e', name: 'EngineService');
      return false;
    }
  }

  /// Get detailed proxy metadata for an asset.
  ///
  /// Returns a [ProxyInfo] object, or null if no proxy exists.
  Future<ProxyInfo?> getProxyInfo(String assetId) async {
    if (!_initialized) return null;
    try {
      return await _api!.getProxyInfo(assetId: assetId);
    } catch (e) {
      developer.log('getProxyInfo failed: $e', name: 'EngineService');
      return null;
    }
  }

  // ─── Transcription (Phase 10.2) ──────────────────────────────────

  /// Transcribe audio from a media asset.
  ///
  /// Uses the built-in transcription engine to convert speech in the
  /// audio to timestamped text segments. [language] should be a language
  /// code (e.g., "en", "es") or "auto" for auto-detection.
  ///
  /// Returns a list of [TranscriptionSegmentInfo] DTOs, or an empty
  /// list if the engine is not initialized or the operation fails.
  Future<List<TranscriptionSegmentInfo>> transcribeAudio(
    String assetId,
    String language,
  ) async {
    if (!_initialized) return [];
    try {
      return await _api!.transcribeAudio(
        assetId: assetId,
        language: language,
      );
    } catch (e) {
      developer.log('transcribeAudio failed: $e', name: 'EngineService');
      return [];
    }
  }

  /// Create text clips on a text track from a transcription result.
  ///
  /// Transcribes the audio from the given asset and creates text clips
  /// on the specified track, one for each transcription segment.
  /// Returns the IDs of the newly created text clips, or an empty list
  /// on failure.
  Future<List<String>> addSubtitlesFromTranscription(
    String assetId,
    String trackId,
  ) async {
    if (!_initialized) return [];
    try {
      return await _api!.addSubtitlesFromTranscription(
        assetId: assetId,
        trackId: trackId,
      );
    } catch (e) {
      developer.log(
        'addSubtitlesFromTranscription failed: $e',
        name: 'EngineService',
      );
      return [];
    }
  }
}
