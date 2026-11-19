import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/frame_rates.dart';
import '../../../core/services/database_provider.dart';
import '../../onboarding/providers/onboarding_provider.dart';

// ─── Settings State ───────────────────────────────────────────────

/// Immutable snapshot of all user-configurable settings.
class AppSettings {
  const AppSettings({
    this.defaultResolution = '1080p',
    this.defaultFps = 30,
    this.defaultCodec = 'H.264',
    this.autoSaveIntervalMinutes = 2,
    this.autoSaveEnabled = true,
    this.gpuAccelerationEnabled = true,
    this.hardwareEncodingEnabled = true,
    this.crashReportingEnabled = true,
    this.analyticsEnabled = false,
    this.proxyQuality = '480p',
    this.cacheSizeMb = 500,
    this.hardwareDecoding = true,
    this.experimentalAutoCaptions = false,
    this.experimentalCloudSync = false,
    this.experimentalAiBackgroundRemoval = false,
    this.themeMode = 'system',
    this.isLoaded = false,
    this.lastError,
  });
  final String defaultResolution; // '720p', '1080p', '4K'
  final double defaultFps;
  final bool isLoaded;
  final String? lastError;
  final String defaultCodec; // 'H.264', 'H.265'
  final int autoSaveIntervalMinutes; // 1-10
  final bool autoSaveEnabled;
  final bool gpuAccelerationEnabled;
  final bool hardwareEncodingEnabled;
  final bool crashReportingEnabled;
  final bool analyticsEnabled;
  final String proxyQuality; // 'off', '360p', '480p', '720p'
  final int cacheSizeMb;
  final bool hardwareDecoding;

  // ─── Experimental feature flags (Phase B.7) ───────────────────────────
  //
  // Retain older flags for compatibility. Unsupported features are explained
  // in Settings without offering controls that imply working functionality.

  /// Enable the "Auto Captions" UI button.
  //
  // The Rust `audio/transcription.rs` is a simulation that generates
  // placeholder segments. Real Whisper integration is Phase D work
  // (`whisper-rs` crate). Until then, this flag is `false` by default
  // so users aren't shown a button that does nothing useful.
  final bool experimentalAutoCaptions;

  /// Enable the optional Cloud Sync screen. Google Drive additionally requires
  /// this build's OAuth configuration and an authenticated account.
  final bool experimentalCloudSync;

  /// Enable the AI Background Removal effect.
  //
  // Phase D will port U²-Net to ONNX Runtime. Until then, this flag
  // is `false` by default.
  final bool experimentalAiBackgroundRemoval;

  /// Phase E.5/E.6: theme mode preference.
  ///
  /// - `'system'` (default): follow the platform's brightness setting.
  /// - `'light'`: force light theme.
  /// - `'dark'`: force dark theme.
  final String themeMode;

  /// Phase E.6: resolve the string preference to a Flutter [ThemeMode].
  ThemeMode get themeModeEnum {
    switch (themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  AppSettings copyWith({
    String? defaultResolution,
    double? defaultFps,
    String? defaultCodec,
    int? autoSaveIntervalMinutes,
    bool? autoSaveEnabled,
    bool? gpuAccelerationEnabled,
    bool? hardwareEncodingEnabled,
    bool? crashReportingEnabled,
    bool? analyticsEnabled,
    String? proxyQuality,
    int? cacheSizeMb,
    bool? hardwareDecoding,
    bool? experimentalAutoCaptions,
    bool? experimentalCloudSync,
    bool? experimentalAiBackgroundRemoval,
    String? themeMode,
    bool? isLoaded,
    String? lastError,
    bool clearError = false,
  }) {
    return AppSettings(
      defaultResolution: defaultResolution ?? this.defaultResolution,
      defaultFps: defaultFps ?? this.defaultFps,
      isLoaded: isLoaded ?? this.isLoaded,
      lastError: clearError ? null : lastError ?? this.lastError,
      defaultCodec: defaultCodec ?? this.defaultCodec,
      autoSaveIntervalMinutes:
          autoSaveIntervalMinutes ?? this.autoSaveIntervalMinutes,
      autoSaveEnabled: autoSaveEnabled ?? this.autoSaveEnabled,
      gpuAccelerationEnabled:
          gpuAccelerationEnabled ?? this.gpuAccelerationEnabled,
      hardwareEncodingEnabled:
          hardwareEncodingEnabled ?? this.hardwareEncodingEnabled,
      crashReportingEnabled:
          crashReportingEnabled ?? this.crashReportingEnabled,
      analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
      proxyQuality: proxyQuality ?? this.proxyQuality,
      cacheSizeMb: cacheSizeMb ?? this.cacheSizeMb,
      hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
      experimentalAutoCaptions:
          experimentalAutoCaptions ?? this.experimentalAutoCaptions,
      experimentalCloudSync:
          experimentalCloudSync ?? this.experimentalCloudSync,
      experimentalAiBackgroundRemoval: experimentalAiBackgroundRemoval ??
          this.experimentalAiBackgroundRemoval,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

// ─── Settings Notifier ────────────────────────────────────────────

/// App preferences are independent of a saved project's canvas and timeline.
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(
    this._prefs, {
    Future<String?> Function(String key)? readLegacyPreference,
  })  : _readLegacyPreference = readLegacyPreference,
        super(const AppSettings()) {
    _loadFromPrefs();
  }

  final SharedPreferences _prefs;
  final Future<String?> Function(String key)? _readLegacyPreference;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();

  static const _keyResolution = 'settings_default_resolution';
  static const _keyFps = 'settings_default_fps';
  static const _keyCodec = 'settings_default_codec';
  static const _keyAutoSaveInterval = 'settings_auto_save_interval';
  static const _keyAutoSaveEnabled = 'settings_auto_save_enabled';
  static const _keyGpuAcceleration = 'settings_gpu_acceleration';
  static const _keyHardwareEncoding = 'settings_hardware_encoding';
  static const _keyCrashReporting = 'settings_crash_reporting';
  static const _keyAnalytics = 'settings_analytics';
  static const _keyProxyQuality = 'settings_proxy_quality';
  static const _keyCacheSizeMb = 'settings_cache_size_mb';
  static const _keyHardwareDecoding = 'settings_hardware_decoding';
  static const _keyExperimentalAutoCaptions =
      'settings_experimental_auto_captions';
  static const _keyExperimentalCloudSync = 'settings_experimental_cloud_sync';
  static const _keyExperimentalAiBackgroundRemoval =
      'settings_experimental_ai_bg_removal';
  static const _keyThemeMode = 'settings_theme_mode';
  static const _migrationKey = 'settings_legacy_migration_version';
  static const _resolutions = ['720p', '1080p', '4K'];
  static const _codecs = ['H.264', 'H.265'];
  static const _proxyQualities = ['off', '360p', '480p', '720p'];
  static const _themes = ['system', 'light', 'dark'];

  T _saved<T>(String key, T fallback) {
    final value = _prefs.get(key);
    return value is T ? value : fallback;
  }

  static String _choice(Object? value, List<String> options, String fallback) =>
      options.contains(value) ? value! as String : fallback;

  void _loadFromPrefs() {
    final fps = _prefs.get(_keyFps);
    final cacheSize = _saved(_keyCacheSizeMb, 500);
    state = AppSettings(
      defaultResolution:
          _choice(_prefs.get(_keyResolution), _resolutions, '1080p'),
      defaultFps:
          fps is num && supportedProjectFrameRates.contains(fps.toDouble())
              ? fps.toDouble()
              : 30,
      defaultCodec: _choice(_prefs.get(_keyCodec), _codecs, 'H.264'),
      autoSaveIntervalMinutes: _saved(_keyAutoSaveInterval, 2).clamp(1, 10),
      autoSaveEnabled: _saved(_keyAutoSaveEnabled, true),
      gpuAccelerationEnabled: _saved(_keyGpuAcceleration, true),
      hardwareEncodingEnabled: _saved(_keyHardwareEncoding, true),
      crashReportingEnabled: _saved(_keyCrashReporting, true),
      analyticsEnabled: _saved(_keyAnalytics, false),
      proxyQuality:
          _choice(_prefs.get(_keyProxyQuality), _proxyQualities, '480p'),
      cacheSizeMb: cacheSize > 0 && cacheSize <= 10000 ? cacheSize : 500,
      hardwareDecoding: _saved(_keyHardwareDecoding, true),
      experimentalAutoCaptions: _saved(_keyExperimentalAutoCaptions, false),
      experimentalCloudSync: _saved(_keyExperimentalCloudSync, false),
      experimentalAiBackgroundRemoval:
          _saved(_keyExperimentalAiBackgroundRemoval, false),
      themeMode: _choice(_prefs.get(_keyThemeMode), _themes, 'system'),
    );
  }

  /// Consumers await this before using defaults that may live in the old DB.
  /// Failures remain visible and a later call retries initialization.
  Future<void> ensureLoaded() {
    if (state.isLoaded) return Future<void>.value();
    return _loading ??= _initialize().whenComplete(() => _loading = null);
  }

  Future<void> _initialize() async {
    try {
      final readLegacy = _readLegacyPreference;
      if (readLegacy != null && _saved(_migrationKey, 0) < 1) {
        final legacy = await Future.wait([
          readLegacy('default_resolution'),
          readLegacy('default_fps'),
          readLegacy('auto_save_enabled'),
          readLegacy('auto_save_interval'),
        ]);
        final parsedFps = double.tryParse(legacy[1] ?? '');
        final resolution = legacy[0] == null
            ? state.defaultResolution
            : _choice(legacy[0], _resolutions, '1080p');
        final fps = legacy[1] == null
            ? state.defaultFps
            : supportedProjectFrameRates.contains(parsedFps)
                ? parsedFps!
                : 30.0;
        final enabled = switch (legacy[2]) {
          'true' => true,
          'false' => false,
          _ => state.autoSaveEnabled,
        };
        final interval = legacy[3] == null
            ? state.autoSaveIntervalMinutes
            : (int.tryParse(legacy[3]!) ?? 2).clamp(1, 10);
        await _persist(_keyResolution, resolution);
        await _persist(_keyFps, fps);
        await _persist(_keyAutoSaveEnabled, enabled);
        await _persist(_keyAutoSaveInterval, interval);
        // Keep old DB rows for recovery. Mark complete only after every
        // canonical value has been accepted by the persistence layer.
        await _persist(_migrationKey, 1);
        if (!mounted) return;
        state = state.copyWith(
          defaultResolution: resolution,
          defaultFps: fps,
          autoSaveEnabled: enabled,
          autoSaveIntervalMinutes: interval,
        );
      }
      if (mounted) state = state.copyWith(isLoaded: true, clearError: true);
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          lastError: 'Could not load your settings. Please retry.',
        );
      }
      rethrow;
    }
  }

  static void _require(bool valid, String name, Object value) {
    if (!valid) throw ArgumentError.value(value, name, 'Unsupported setting');
  }

  Future<bool> _writeValue(String key, Object value) => switch (value) {
        String() => _prefs.setString(key, value),
        bool() => _prefs.setBool(key, value),
        int() => _prefs.setInt(key, value),
        double() => _prefs.setDouble(key, value),
        _ => throw ArgumentError.value(value, key),
      };

  Future<void> _persist(String key, Object value) async {
    try {
      if (!await _writeValue(key, value) || _prefs.get(key) != value) {
        throw StateError('Could not save setting $key');
      }
    } catch (_) {
      // SharedPreferences updates its cache before the platform write completes.
      // Reload prevents a rejected write appearing saved on the next screen.
      await _prefs.reload();
      rethrow;
    }
  }

  Future<void> _set(String key, Object value, AppSettings Function() updated) {
    final operation = _writes.then((_) async {
      await ensureLoaded();
      try {
        await _persist(key, value);
        if (mounted) state = updated().copyWith(clearError: true);
      } catch (_) {
        if (mounted) {
          state = state.copyWith(
            lastError: 'Could not save this setting. Please try again.',
          );
        }
        rethrow;
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> setResolution(String value) async {
    _require(_resolutions.contains(value), 'resolution', value);
    await _set(
      _keyResolution,
      value,
      () => state.copyWith(defaultResolution: value),
    );
  }

  Future<void> setDefaultFps(double value) async {
    _require(supportedProjectFrameRates.contains(value), 'fps', value);
    await _set(_keyFps, value, () => state.copyWith(defaultFps: value));
  }

  Future<void> setCodec(String value) async {
    _require(_codecs.contains(value), 'codec', value);
    await _set(_keyCodec, value, () => state.copyWith(defaultCodec: value));
  }

  Future<void> setAutoSaveInterval(int minutes) async {
    _require(minutes >= 1 && minutes <= 10, 'minutes', minutes);
    await _set(
      _keyAutoSaveInterval,
      minutes,
      () => state.copyWith(autoSaveIntervalMinutes: minutes),
    );
  }

  Future<void> setAutoSaveEnabled(bool enabled) => _set(
        _keyAutoSaveEnabled,
        enabled,
        () => state.copyWith(autoSaveEnabled: enabled),
      );
  Future<void> setGpuAcceleration(bool enabled) => _set(
        _keyGpuAcceleration,
        enabled,
        () => state.copyWith(gpuAccelerationEnabled: enabled),
      );
  Future<void> setHardwareEncoding(bool enabled) => _set(
        _keyHardwareEncoding,
        enabled,
        () => state.copyWith(hardwareEncodingEnabled: enabled),
      );
  Future<void> setCrashReporting(bool enabled) => _set(
        _keyCrashReporting,
        enabled,
        () => state.copyWith(crashReportingEnabled: enabled),
      );
  Future<void> setAnalytics(bool enabled) => _set(
        _keyAnalytics,
        enabled,
        () => state.copyWith(analyticsEnabled: enabled),
      );
  Future<void> setProxyQuality(String quality) async {
    _require(_proxyQualities.contains(quality), 'proxyQuality', quality);
    await _set(
      _keyProxyQuality,
      quality,
      () => state.copyWith(proxyQuality: quality),
    );
  }

  Future<void> setCacheSizeMb(int mb) async {
    _require(mb > 0 && mb <= 10000, 'cacheSizeMb', mb);
    await _set(_keyCacheSizeMb, mb, () => state.copyWith(cacheSizeMb: mb));
  }

  Future<void> setHardwareDecoding(bool enabled) => _set(
        _keyHardwareDecoding,
        enabled,
        () => state.copyWith(hardwareDecoding: enabled),
      );
  Future<void> setExperimentalAutoCaptions(bool enabled) => _set(
        _keyExperimentalAutoCaptions,
        enabled,
        () => state.copyWith(experimentalAutoCaptions: enabled),
      );
  Future<void> setExperimentalCloudSync(bool enabled) => _set(
        _keyExperimentalCloudSync,
        enabled,
        () => state.copyWith(experimentalCloudSync: enabled),
      );
  Future<void> setExperimentalAiBackgroundRemoval(bool enabled) => _set(
        _keyExperimentalAiBackgroundRemoval,
        enabled,
        () => state.copyWith(experimentalAiBackgroundRemoval: enabled),
      );
  Future<void> setThemeMode(String mode) async {
    _require(_themes.contains(mode), 'themeMode', mode);
    await _set(_keyThemeMode, mode, () => state.copyWith(themeMode: mode));
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsNotifier(
    prefs,
    readLegacyPreference: (key) =>
        ref.read(databaseProvider).getPreference(key),
  );
});
