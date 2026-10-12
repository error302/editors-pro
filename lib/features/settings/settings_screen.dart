/// Settings screen for EDITORS-PRO.
///
/// Provides user-configurable preferences for the editor including
/// default project settings, storage management, performance tuning,
/// export defaults, and privacy options.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/cloud_config.dart';
import '../../core/services/database_provider.dart';
import '../../core/services/engine_service.dart';
import '../cloud/providers/cloud_provider.dart';
import '../editor/providers/proxy_provider.dart';
import 'providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _autoSaveEnabled = true;
  int _autoSaveIntervalMinutes = 2;
  String _defaultResolution = '1080p';
  double _defaultFps = 30.0;
  bool _proxyEnabled = false;
  String _proxyQuality = '480p';
  bool _hardwareDecoding = true;
  int _cacheSizeMb = 500;
  bool _isClearingProxyCache = false;
  String? _proxyCacheSizeDisplay;
  String _cloudProvider = 'None';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final db = ref.read(databaseProvider);
    final autoSave = await db.getPreference('auto_save_enabled');
    final autoSaveInterval = await db.getPreference('auto_save_interval');
    final defaultRes = await db.getPreference('default_resolution');
    final defaultFps = await db.getPreference('default_fps');
    final proxyEnabled = await db.getPreference('proxy_enabled');
    final proxyQuality = await db.getPreference('proxy_quality');
    final hwDecode = await db.getPreference('hardware_decoding');
    final cacheSize = await db.getPreference('cache_size_mb');

    // Also try to get proxy quality from the engine bridge
    String effectiveProxyQuality = proxyQuality ?? '480p';
    try {
      final engine = EngineService.instance;
      if (engine.isInitialized) {
        final engineQuality = await engine.api.getProxyQuality();
        if (engineQuality.isNotEmpty) {
          effectiveProxyQuality = engineQuality;
        }
      }
    } catch (_) {
      // Engine not available, use local preference
    }

    if (mounted) {
      setState(() {
        _autoSaveEnabled = autoSave != 'false';
        _autoSaveIntervalMinutes = int.tryParse(autoSaveInterval ?? '') ?? 2;
        _defaultResolution = defaultRes ?? '1080p';
        _defaultFps = double.tryParse(defaultFps ?? '') ?? 30.0;
        _proxyEnabled = proxyEnabled == 'true';
        _proxyQuality = effectiveProxyQuality;
        _hardwareDecoding = hwDecode != 'false';
        _cacheSizeMb = int.tryParse(cacheSize ?? '') ?? 500;
      });
      _loadProxyCacheSize();
    }
  }

  Future<void> _setPreference(String key, String value) async {
    final db = ref.read(databaseProvider);
    await db.setPreference(key, value);
  }

  Future<void> _setProxyQuality(String quality) async {
    setState(() => _proxyQuality = quality);
    await _setPreference('proxy_quality', quality);
    final notifier = ref.read(settingsProvider.notifier);
    notifier.setProxyQuality(quality);

    // Update engine proxy quality via bridge API
    try {
      final engine = EngineService.instance;
      if (engine.isInitialized) {
        await engine.api.setProxyQuality(quality: quality);
      }
    } catch (e) {
      debugPrint('Failed to set proxy quality on engine: $e');
    }
  }

  Future<void> _loadProxyCacheSize() async {
    try {
      final engine = EngineService.instance;
      if (engine.isInitialized) {
        final size = await engine.api.getProxyCacheSize();
        if (mounted && size > 0) {
          setState(() {
            _proxyCacheSizeDisplay = _formatBytes(size);
          });
        }
      }
    } catch (_) {
      // Engine not available
    }
  }

  Future<void> _clearProxyCache() async {
    setState(() => _isClearingProxyCache = true);
    try {
      final engine = EngineService.instance;
      if (engine.isInitialized) {
        final bytesFreed = await engine.api.clearProxyCache();
        if (mounted) {
          setState(() {
            _proxyCacheSizeDisplay = null;
            _isClearingProxyCache = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                bytesFreed > 0
                    ? 'Proxy cache cleared (${_formatBytes(bytesFreed)} freed)'
                    : 'Proxy cache is already empty',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearingProxyCache = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear proxy cache: $e')),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Project Defaults ──────────────────────────────
          _SectionHeader(title: 'Project Defaults'),
          _SettingsCard(
            children: [
              _SettingsDropdown(
                label: 'Default Resolution',
                value: _defaultResolution,
                options: const ['720p', '1080p', '4K'],
                onChanged: (v) {
                  setState(() => _defaultResolution = v);
                  _setPreference('default_resolution', v);
                },
              ),
              const Divider(height: 1),
              _SettingsDropdown(
                label: 'Default Frame Rate',
                value: _defaultFps == 24.0
                    ? '24 fps'
                    : _defaultFps == 25.0
                        ? '25 fps'
                        : _defaultFps == 30.0
                            ? '30 fps'
                            : _defaultFps == 60.0
                                ? '60 fps'
                                : '30 fps',
                options: const ['24 fps', '25 fps', '30 fps', '60 fps'],
                onChanged: (v) {
                  final fps = double.parse(v.replaceAll(' fps', ''));
                  setState(() => _defaultFps = fps);
                  _setPreference('default_fps', fps.toString());
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ─── Appearance (Phase E.5/E.6) ─────────────────────
          _SectionHeader(title: 'Appearance'),
          _SettingsCard(
            children: [
              _SettingsDropdown(
                label: 'Theme',
                value: settings.themeMode == 'light'
                    ? 'Light'
                    : settings.themeMode == 'dark'
                        ? 'Dark'
                        : 'Follow system',
                options: const ['Follow system', 'Light', 'Dark'],
                onChanged: (v) {
                  final mode = switch (v) {
                    'Light' => 'light',
                    'Dark' => 'dark',
                    _ => 'system',
                  };
                  settingsNotifier.setThemeMode(mode);
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ─── Editor Behavior ───────────────────────────────
          _SectionHeader(title: 'Editor Behavior'),
          _SettingsCard(
            children: [
              _SettingsSwitch(
                label: 'Auto-Save',
                subtitle:
                    'Automatically save project every $_autoSaveIntervalMinutes min',
                value: _autoSaveEnabled,
                onChanged: (v) {
                  setState(() => _autoSaveEnabled = v);
                  _setPreference('auto_save_enabled', v.toString());
                },
              ),
              if (_autoSaveEnabled) ...[
                const Divider(height: 1),
                _SettingsSlider(
                  label: 'Auto-Save Interval',
                  value: _autoSaveIntervalMinutes.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  unit: 'min',
                  onChanged: (v) {
                    setState(() => _autoSaveIntervalMinutes = v.round());
                    _setPreference('auto_save_interval', v.round().toString());
                  },
                ),
              ],
            ],
          ),

          const SizedBox(height: 24),

          // ─── Performance ───────────────────────────────────
          _SectionHeader(title: 'Performance'),
          _SettingsCard(
            children: [
              _SettingsSwitch(
                label: 'Hardware-Accelerated Decoding',
                subtitle: 'Use MediaCodec for faster video decode',
                value: _hardwareDecoding,
                onChanged: (v) {
                  setState(() => _hardwareDecoding = v);
                  _setPreference('hardware_decoding', v.toString());
                  settingsNotifier.setHardwareDecoding(v);
                },
              ),
              const Divider(height: 1),
              _SettingsSwitch(
                label: 'GPU Acceleration',
                subtitle: 'Use GPU for rendering when available',
                value: settings.gpuAccelerationEnabled,
                onChanged: (v) => settingsNotifier.setGpuAcceleration(v),
              ),
              const Divider(height: 1),
              _SettingsSlider(
                label: 'Preview Cache Size',
                value: _cacheSizeMb.toDouble(),
                min: 100,
                max: 2000,
                divisions: 19,
                unit: 'MB',
                onChanged: (v) {
                  setState(() => _cacheSizeMb = v.round());
                  _setPreference('cache_size_mb', v.round().toString());
                  settingsNotifier.setCacheSizeMb(v.round());
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ─── Proxy & Performance ───────────────────────────
          _SectionHeader(title: 'Proxy & Performance'),
          Consumer(builder: (context, ref, _) {
            final proxyState = ref.watch(proxyProvider);
            final proxyNotifier = ref.read(proxyProvider.notifier);
            return _SettingsCard(
              children: [
                _SettingsDropdown(
                  label: 'Proxy Quality',
                  value: proxyState.quality,
                  options: const ['Off', '360p', '480p', '720p'],
                  onChanged: (v) {
                    proxyNotifier.setQuality(v);
                    _setProxyQuality(v);
                  },
                ),
                const Divider(height: 1),
                _SettingsSwitch(
                  label: 'Auto-Generate Proxies',
                  subtitle:
                      'Automatically create proxies when importing high-res media',
                  value: proxyState.autoProxyEnabled,
                  onChanged: (v) => proxyNotifier.setAutoProxy(v),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.video_settings_outlined,
                      color: AppTheme.primary),
                  title:
                      Text('Proxy Cache', style: context.textTheme.bodyMedium),
                  subtitle: Text(
                    proxyState.cacheSizeBytes > 0
                        ? '${_formatBytes(proxyState.cacheSizeBytes)} · ${proxyState.activeProxyCount} active prox${proxyState.activeProxyCount == 1 ? 'y' : 'ies'}'
                        : '${proxyState.activeProxyCount} active prox${proxyState.activeProxyCount == 1 ? 'y' : 'ies'}',
                    style: context.textTheme.bodySmall,
                  ),
                  trailing: _isClearingProxyCache
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: proxyState.cacheSizeBytes > 0
                              ? () => _showClearProxyCacheDialog(context)
                              : null,
                          child: const Text('Clear'),
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Proxies are lower-resolution copies used for smooth editing. '
                    'The original full-resolution media is always used for export.',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textDisabled,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            );
          }),

          const SizedBox(height: 24),

          // ─── Export ────────────────────────────────────────
          _SectionHeader(title: 'Export'),
          _SettingsCard(
            children: [
              _SettingsDropdown(
                label: 'Default Export Codec',
                value: settings.defaultCodec,
                options: const ['H.264', 'H.265'],
                onChanged: (v) => settingsNotifier.setCodec(v),
              ),
              const Divider(height: 1),
              _SettingsSwitchWithBadge(
                label: 'Hardware Encoding',
                subtitle:
                    'Use hardware encoder (NVENC / VideoToolbox) for faster exports',
                value: settings.hardwareEncodingEnabled,
                badgeLabel: 'GPU',
                showBadge: settings.hardwareEncodingEnabled,
                onChanged: (v) => settingsNotifier.setHardwareEncoding(v),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ─── Storage ───────────────────────────────────────
          _SectionHeader(title: 'Storage'),
          _SettingsCard(
            children: [
              ListTile(
                leading:
                    const Icon(Icons.folder_outlined, color: AppTheme.primary),
                title: Text('Clear Preview Cache',
                    style: context.textTheme.bodyMedium),
                subtitle: Text('Free up disk space used by cached frames',
                    style: context.textTheme.bodySmall),
                trailing:
                    Icon(Icons.chevron_right, color: AppTheme.textDisabled),
                onTap: () => _showClearCacheDialog(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.video_settings_outlined,
                    color: AppTheme.primary),
                title: Text('Clear Proxy Cache',
                    style: context.textTheme.bodyMedium),
                subtitle: Text(
                  _proxyCacheSizeDisplay != null
                      ? 'Current size: $_proxyCacheSizeDisplay'
                      : 'Free up disk space used by proxy videos',
                  style: context.textTheme.bodySmall,
                ),
                trailing: _isClearingProxyCache
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.chevron_right, color: AppTheme.textDisabled),
                onTap: _isClearingProxyCache
                    ? null
                    : () => _showClearProxyCacheDialog(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined,
                    color: AppTheme.error),
                title: Text('Delete All Projects',
                    style: context.textTheme.bodyMedium),
                subtitle: Text('Permanently remove all projects and assets',
                    style: context.textTheme.bodySmall),
                trailing:
                    Icon(Icons.chevron_right, color: AppTheme.textDisabled),
                onTap: () => _showDeleteAllDialog(context),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Cloud Sync stays opt-in. Sign-in is unavailable until OAuth is
          // configured for this package and signing certificate.
          if (settings.experimentalCloudSync) ...[
            _SectionHeader(title: 'Cloud Sync'),
            _SettingsCard(
              children: [
                _SettingsDropdown(
                  label: 'Cloud Provider',
                  value: _cloudProvider,
                  options: const ['None', 'Google Drive'],
                  onChanged: (v) {
                    setState(() => _cloudProvider = v);
                    _setPreference('cloud_provider', v);
                    ref.read(cloudSyncProvider.notifier).setProvider(
                          v == 'None' ? 'None' : v,
                        );
                  },
                ),
                if (_cloudProvider != 'None') ...[
                  const Divider(height: 1),
                  Consumer(builder: (context, ref, _) {
                    final syncState = ref.watch(cloudSyncProvider);
                    return ListTile(
                      leading: Icon(
                        syncState.isAuthenticated
                            ? Icons.cloud_done
                            : Icons.cloud_outlined,
                        color: syncState.isAuthenticated
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                      ),
                      title: Text(
                        syncState.isAuthenticated ? 'Signed In' : 'Sign In',
                        style: context.textTheme.bodyMedium,
                      ),
                      subtitle: syncState.isAuthenticated &&
                              syncState.accountName != null
                          ? Text(
                              syncState.accountName!,
                              style: context.textTheme.bodySmall,
                            )
                          : null,
                      trailing: syncState.isAuthenticated
                          ? TextButton(
                              onPressed: () => ref
                                  .read(cloudSyncProvider.notifier)
                                  .signOut(),
                              child: const Text('Sign Out'),
                            )
                          : ElevatedButton(
                              onPressed: () => context.push('/cloud'),
                              child: const Text('Sign In'),
                            ),
                    );
                  }),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.cloud_sync_outlined,
                    color: AppTheme.primary,
                  ),
                  title: Text(
                    'Manage Cloud Sync',
                    style: context.textTheme.bodyMedium,
                  ),
                  subtitle: Text(
                    'View synced projects and resolve conflicts',
                    style: context.textTheme.bodySmall,
                  ),
                  trailing:
                      Icon(Icons.chevron_right, color: AppTheme.textDisabled),
                  onTap: () => context.push('/cloud'),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // ─── Privacy & Data ────────────────────────────────
          _SectionHeader(title: 'Privacy & Data'),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.bug_report_outlined,
                    color: AppTheme.textSecondary),
                title: Text('Crash diagnostics',
                    style: context.textTheme.bodyMedium),
                subtitle: Text(
                  'Kept in memory on this device. No external crash-reporting service is configured.',
                  style: context.textTheme.bodySmall,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.insights_outlined,
                    color: AppTheme.textSecondary),
                title: Text('Usage analytics',
                    style: context.textTheme.bodyMedium),
                subtitle: Text(
                  'This build does not collect or send usage analytics.',
                  style: context.textTheme.bodySmall,
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // ─── Experimental (Phase B.7) ──────────────────────
          // Features whose UI ships but whose Rust-side implementation
          // is a placeholder. Defaults to OFF so regular users never
          // see broken behavior. See AUDIT_REPORT.md §1.4-1.5.
          _SectionHeader(title: 'Experimental'),
          _SettingsCard(
            children: [
              _SettingsSwitch(
                label: 'Auto Captions',
                subtitle:
                    'Enable transcription UI (currently simulated; real Whisper coming in Phase D)',
                value: settings.experimentalAutoCaptions,
                onChanged: (v) =>
                    settingsNotifier.setExperimentalAutoCaptions(v),
              ),
              const Divider(height: 1),
              _SettingsSwitch(
                label: 'Cloud Sync',
                subtitle: CloudConfig.isGoogleDriveConfigured
                    ? 'Show the optional Google Drive sync screen'
                    : 'Google Drive sync is unavailable until OAuth is configured',
                value: settings.experimentalCloudSync,
                onChanged: (v) => settingsNotifier.setExperimentalCloudSync(v),
              ),
              const Divider(height: 1),
              _SettingsSwitch(
                label: 'AI Background Removal',
                subtitle:
                    'Enable U²-Net effect (not yet wired; ONNX Runtime coming in Phase D)',
                value: settings.experimentalAiBackgroundRemoval,
                onChanged: (v) =>
                    settingsNotifier.setExperimentalAiBackgroundRemoval(v),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // ─── About ─────────────────────────────────────────
          _SectionHeader(title: 'About'),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline,
                    color: AppTheme.textSecondary),
                title: Text('Version', style: context.textTheme.bodyMedium),
                trailing: Text(
                  '${AppConstants.appVersion}',
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: AppTheme.textSecondary),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.code, color: AppTheme.textSecondary),
                title:
                    Text('Architecture', style: context.textTheme.bodyMedium),
                trailing: Text(
                  'Flutter + Rust',
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: AppTheme.textSecondary),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined,
                    color: AppTheme.textSecondary),
                title:
                    Text('Privacy & Data', style: context.textTheme.bodyMedium),
                subtitle: Text('How this build handles your information',
                    style: context.textTheme.bodySmall),
                trailing:
                    Icon(Icons.chevron_right, color: AppTheme.textDisabled),
                onTap: _showPrivacyAndData,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.description_outlined,
                    color: AppTheme.textSecondary),
                title: Text('Licenses', style: context.textTheme.bodyMedium),
                trailing:
                    Icon(Icons.chevron_right, color: AppTheme.textDisabled),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: AppConstants.appName,
                    applicationVersion: AppConstants.appVersion,
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.source_outlined,
                    color: AppTheme.textSecondary),
                title: Text('Open Source Notices',
                    style: context.textTheme.bodyMedium),
                trailing:
                    Icon(Icons.chevron_right, color: AppTheme.textDisabled),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: AppConstants.appName,
                    applicationVersion: AppConstants.appVersion,
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  void _showPrivacyAndData() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Privacy & Data'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('On-device data',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 6),
                Text(
                    'Project records, editing choices, and preferences are stored on this device. The app reads media from the locations you select; exports are saved to the destination you choose.'),
                SizedBox(height: 16),
                Text('Diagnostics and analytics',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 6),
                Text(
                    'This build keeps crash diagnostics in memory while the app is running. It does not send crash reports or usage analytics to EDITORS-PRO.'),
                SizedBox(height: 16),
                Text('Google Drive',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 6),
                Text(
                    'Cloud transfer is optional. If enabled and configured, signing in and syncing sends project data to Google Drive under your Google account. Signing out disconnects this app but does not remove copies already stored in Drive.'),
                SizedBox(height: 16),
                Text('Store-release status',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 6),
                Text(
                    'A public privacy-policy URL and support contact have not been configured for this build. This in-app notice does not replace the policy and disclosures required for store release.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Preview Cache?'),
        content: const Text(
          'This will delete all cached preview frames and thumbnails. '
          'Your projects will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAllDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Projects?'),
        content: const Text(
          'This will permanently delete ALL projects and their associated media. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All projects deleted')),
              );
            },
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }

  void _showClearProxyCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Proxy Cache?'),
        content: const Text(
          'This will delete all proxy video files from the cache. '
          'Proxies will be regenerated automatically when needed. '
          'Your original media files will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearProxyCache();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable Settings Widgets ────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: context.textTheme.labelMedium?.copyWith(
          color: AppTheme.primaryLight,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitch({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(label, style: context.textTheme.bodyMedium),
      subtitle: subtitle != null
          ? Text(subtitle!, style: context.textTheme.bodySmall)
          : null,
      value: value,
      onChanged: onChanged,
      activeColor: AppTheme.primary,
    );
  }
}

/// Switch tile with an optional trailing badge (e.g. "GPU").
class _SettingsSwitchWithBadge extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String badgeLabel;
  final bool showBadge;

  const _SettingsSwitchWithBadge({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.badgeLabel,
    required this.showBadge,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Row(
        children: [
          Text(label, style: context.textTheme.bodyMedium),
          if (showBadge) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.secondary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AppTheme.secondary.withOpacity(0.4),
                  width: 1,
                ),
              ),
              child: Text(
                badgeLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.secondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: subtitle != null
          ? Text(subtitle!, style: context.textTheme.bodySmall)
          : null,
      value: value,
      onChanged: onChanged,
      activeColor: AppTheme.primary,
    );
  }
}

class _SettingsDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _SettingsDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label, style: context.textTheme.bodyMedium),
      trailing: DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _SettingsSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final ValueChanged<double> onChanged;

  const _SettingsSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: context.textTheme.bodyMedium),
              Text(
                '${value.round()} $unit',
                style: context.textTheme.bodySmall?.copyWith(
                  color: AppTheme.primaryLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppTheme.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
