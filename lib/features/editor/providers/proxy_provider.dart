/// Proxy workflow state management for EDITORS-PRO.
///
/// Manages proxy generation settings, active proxy tracking, and
/// provides a Riverpod StateNotifier that wraps the engine bridge API.
library;

import 'dart:developer' as developer;

import 'package:editors_pro/src/rust/api/bridge_api.dart' show ProxyInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/engine_service.dart';

// ─── Data Classes ──────────────────────────────────────────────────

/// Immutable snapshot of the proxy workflow state.
class ProxyState {
  const ProxyState({
    this.quality = '480p',
    this.autoProxyEnabled = true,
    this.activeProxyCount = 0,
    this.cacheSizeBytes = 0,
    this.proxyInfo = const {},
    this.generatingAssetId,
    this.isGenerating = false,
    this.errorMessage,
  });

  /// Current proxy quality setting: "Off", "360p", "480p", "720p"
  final String quality;

  /// Whether auto-proxy generation is enabled on import
  final bool autoProxyEnabled;

  /// Number of assets that currently have proxy files
  final int activeProxyCount;

  /// Total size of the proxy cache in bytes
  final int cacheSizeBytes;

  /// Per-asset proxy info keyed by asset ID
  final Map<String, ProxyInfoData> proxyInfo;

  /// The asset ID currently being proxied (null when idle)
  final String? generatingAssetId;

  /// Whether a proxy generation operation is in progress
  final bool isGenerating;

  /// Last error message, if any
  final String? errorMessage;

  ProxyState copyWith({
    String? quality,
    bool? autoProxyEnabled,
    int? activeProxyCount,
    int? cacheSizeBytes,
    Map<String, ProxyInfoData>? proxyInfo,
    String? generatingAssetId,
    bool clearGeneratingAssetId = false,
    bool? isGenerating,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProxyState(
      quality: quality ?? this.quality,
      autoProxyEnabled: autoProxyEnabled ?? this.autoProxyEnabled,
      activeProxyCount: activeProxyCount ?? this.activeProxyCount,
      cacheSizeBytes: cacheSizeBytes ?? this.cacheSizeBytes,
      proxyInfo: proxyInfo ?? this.proxyInfo,
      generatingAssetId: clearGeneratingAssetId
          ? null
          : (generatingAssetId ?? this.generatingAssetId),
      isGenerating: isGenerating ?? this.isGenerating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Proxy information for a single asset.
class ProxyInfoData {
  const ProxyInfoData({
    required this.assetId,
    required this.originalPath,
    required this.quality,
    required this.originalWidth,
    required this.originalHeight,
    this.proxyPath,
    this.proxyWidth,
    this.proxyHeight,
    this.fileSizeBytes,
  });

  /// Create from a bridge [ProxyInfo] DTO.
  factory ProxyInfoData.fromBridge(ProxyInfo info) {
    return ProxyInfoData(
      assetId: info.assetId,
      originalPath: info.originalPath,
      proxyPath: info.proxyPath,
      quality: info.quality,
      originalWidth: info.originalWidth,
      originalHeight: info.originalHeight,
      proxyWidth: info.proxyWidth,
      proxyHeight: info.proxyHeight,
      fileSizeBytes: info.fileSizeBytes,
    );
  }
  final String assetId;
  final String originalPath;
  final String? proxyPath;
  final String quality;
  final int originalWidth;
  final int originalHeight;
  final int? proxyWidth;
  final int? proxyHeight;
  final int? fileSizeBytes;

  /// Whether this asset has a generated proxy file
  bool get hasProxy => proxyPath != null;

  /// Human-readable file size (e.g. "4.8 MB")
  String get formattedSize {
    final bytes = fileSizeBytes ?? 0;
    if (bytes <= 0) return '—';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  /// Resolution label like "4K→720p"
  String get resolutionDisplayLabel {
    final origLabel = resolutionLabel(originalWidth, originalHeight);
    if (proxyWidth != null && proxyHeight != null) {
      return '$origLabel→${resolutionLabel(proxyWidth!, proxyHeight!)}';
    }
    return origLabel;
  }

  /// Convert width/height to a human-readable resolution name.
  static String resolutionLabel(int w, int h) {
    if (w >= 3840 || h >= 2160) return '4K';
    if (w >= 2560 || h >= 1440) return '1440p';
    if (w >= 1920 || h >= 1080) return '1080p';
    if (w >= 1280 || h >= 720) return '720p';
    if (w >= 854 || h >= 480) return '480p';
    if (w >= 640 || h >= 360) return '360p';
    return '${w}x$h';
  }
}

// ─── Notifier ──────────────────────────────────────────────────────

/// Riverpod StateNotifier that manages proxy workflow state.
///
/// All methods call the engine bridge API and update the state
/// accordingly.  Errors are caught and stored in [ProxyState.errorMessage].
class ProxyNotifier extends StateNotifier<ProxyState> {
  ProxyNotifier() : super(const ProxyState());

  /// Load current settings from the engine.
  Future<void> loadSettings() async {
    try {
      final engine = EngineService.instance;
      if (!engine.isInitialized) return;

      final quality = await engine.getProxyQuality();
      final autoProxy = await engine.isAutoProxyEnabled();
      final count = await engine.getProxyCount();
      final cacheSize = await engine.getProxyCacheSize();

      if (!mounted) return;
      state = state.copyWith(
        quality: quality,
        autoProxyEnabled: autoProxy,
        activeProxyCount: count,
        cacheSizeBytes: cacheSize,
      );
    } catch (e) {
      developer.log(
        'loadSettings failed: $e',
        name: 'ProxyNotifier',
      );
    }
  }

  /// Set the proxy quality level.
  ///
  /// Valid values: "Off", "360p", "480p", "720p"
  Future<void> setQuality(String quality) async {
    try {
      final engine = EngineService.instance;
      if (!engine.isInitialized) return;

      await engine.setProxyQuality(quality);
      if (!mounted) return;
      state = state.copyWith(quality: quality);
    } catch (e) {
      developer.log(
        'setQuality failed: $e',
        name: 'ProxyNotifier',
      );
      if (!mounted) return;
      state = state.copyWith(errorMessage: 'Failed to set quality: $e');
    }
  }

  /// Enable or disable automatic proxy generation on import.
  Future<void> setAutoProxy(bool enabled) async {
    try {
      final engine = EngineService.instance;
      if (!engine.isInitialized) return;

      await engine.setAutoProxy(enabled);
      if (!mounted) return;
      state = state.copyWith(autoProxyEnabled: enabled);
    } catch (e) {
      developer.log(
        'setAutoProxy failed: $e',
        name: 'ProxyNotifier',
      );
      if (!mounted) return;
      state = state.copyWith(errorMessage: 'Failed to toggle auto-proxy: $e');
    }
  }

  /// Generate a proxy for the given asset.
  Future<void> generateProxy(String assetId, String sourcePath) async {
    if (state.isGenerating) return; // prevent concurrent generation

    try {
      if (!mounted) return;
      state = state.copyWith(
        generatingAssetId: assetId,
        isGenerating: true,
        clearError: true,
      );

      final engine = EngineService.instance;
      if (!engine.isInitialized) return;

      final proxyPath = await engine.generateProxy(assetId, sourcePath);

      if (!mounted) return;

      // Fetch updated proxy info for this asset
      final info = await engine.getProxyInfo(assetId);
      final newProxyInfo = Map<String, ProxyInfoData>.from(state.proxyInfo);
      if (info != null) {
        newProxyInfo[assetId] = ProxyInfoData.fromBridge(info);
      } else if (proxyPath != null) {
        // Fallback: create minimal info
        newProxyInfo[assetId] = ProxyInfoData(
          assetId: assetId,
          originalPath: sourcePath,
          proxyPath: proxyPath,
          quality: state.quality,
          originalWidth: 0,
          originalHeight: 0,
        );
      }

      state = state.copyWith(
        proxyInfo: newProxyInfo,
        generatingAssetId: assetId,
        clearGeneratingAssetId: true,
        isGenerating: false,
        activeProxyCount: state.activeProxyCount + 1,
      );
    } catch (e) {
      developer.log(
        'generateProxy failed: $e',
        name: 'ProxyNotifier',
      );
      if (!mounted) return;
      state = state.copyWith(
        isGenerating: false,
        clearGeneratingAssetId: true,
        errorMessage: 'Failed to generate proxy: $e',
      );
    }
  }

  /// Regenerate the proxy for an asset (e.g., after quality change).
  Future<void> regenerateProxy(String assetId) async {
    if (state.isGenerating) return;

    try {
      if (!mounted) return;
      state = state.copyWith(
        generatingAssetId: assetId,
        isGenerating: true,
        clearError: true,
      );

      final engine = EngineService.instance;
      if (!engine.isInitialized) return;

      await engine.regenerateProxy(assetId);

      // Refresh proxy info for this asset
      final info = await engine.getProxyInfo(assetId);
      final newProxyInfo = Map<String, ProxyInfoData>.from(state.proxyInfo);
      if (info != null) {
        newProxyInfo[assetId] = ProxyInfoData.fromBridge(info);
      }

      if (!mounted) return;
      state = state.copyWith(
        proxyInfo: newProxyInfo,
        generatingAssetId: assetId,
        clearGeneratingAssetId: true,
        isGenerating: false,
      );
    } catch (e) {
      developer.log(
        'regenerateProxy failed: $e',
        name: 'ProxyNotifier',
      );
      if (!mounted) return;
      state = state.copyWith(
        isGenerating: false,
        clearGeneratingAssetId: true,
        errorMessage: 'Failed to regenerate proxy: $e',
      );
    }
  }

  /// Clear all proxy files from the cache.
  Future<void> clearProxyCache() async {
    try {
      final engine = EngineService.instance;
      if (!engine.isInitialized) return;

      await engine.clearProxyCache();

      if (!mounted) return;
      state = state.copyWith(
        activeProxyCount: 0,
        cacheSizeBytes: 0,
        proxyInfo: {},
      );
    } catch (e) {
      developer.log(
        'clearProxyCache failed: $e',
        name: 'ProxyNotifier',
      );
      if (!mounted) return;
      state = state.copyWith(errorMessage: 'Failed to clear cache: $e');
    }
  }

  /// Refresh proxy count and cache size from the engine.
  Future<void> refreshProxyInfo() async {
    try {
      final engine = EngineService.instance;
      if (!engine.isInitialized) return;

      final count = await engine.getProxyCount();
      final cacheSize = await engine.getProxyCacheSize();

      if (!mounted) return;
      state = state.copyWith(
        activeProxyCount: count,
        cacheSizeBytes: cacheSize,
      );
    } catch (e) {
      developer.log(
        'refreshProxyInfo failed: $e',
        name: 'ProxyNotifier',
      );
    }
  }
}

// ─── Provider ──────────────────────────────────────────────────────

/// Provider that exposes [ProxyNotifier] and the current [ProxyState].
final proxyProvider = StateNotifierProvider<ProxyNotifier, ProxyState>(
  (ref) => ProxyNotifier(),
);
