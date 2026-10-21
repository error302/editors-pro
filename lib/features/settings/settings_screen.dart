/// Settings screen for EDITORS-PRO.
///
/// Provides user-configurable preferences for the editor including
/// default project settings, storage management, performance tuning,
/// export defaults, and privacy options.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/cloud_config.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/services/database_provider.dart';
import '../../core/theme/app_theme.dart';
import '../cloud/providers/cloud_provider.dart';
import '../projects/providers/project_provider.dart';
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
  bool _isDeletingAllProjects = false;
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

    if (mounted) {
      setState(() {
        _autoSaveEnabled = autoSave != 'false';
        _autoSaveIntervalMinutes = int.tryParse(autoSaveInterval ?? '') ?? 2;
        _defaultResolution = defaultRes ?? '1080p';
        _defaultFps = double.tryParse(defaultFps ?? '') ?? 30.0;
      });
    }
  }

  Future<void> _setPreference(String key, String value) async {
    final db = ref.read(databaseProvider);
    await db.setPreference(key, value);
  }

  Future<void> _deleteAllProjects() async {
    if (_isDeletingAllProjects) return;
    setState(() => _isDeletingAllProjects = true);
    try {
      final count =
          await ref.read(projectProvider.notifier).deleteAllProjects();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count == 0
                  ? 'There are no projects to delete'
                  : '$count projects deleted; original media files were left untouched',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete all projects: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeletingAllProjects = false);
    }
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
          const _SectionHeader(title: 'Project Defaults'),
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
          const _SectionHeader(title: 'Appearance'),
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
          const _SectionHeader(title: 'Editor Behavior'),
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
          const _SectionHeader(title: 'Performance'),
          const _SettingsCard(
            children: [
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Performance controls unavailable'),
                subtitle:
                    Text('This engine build does not expose these controls.'),
                enabled: false,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ─── Proxy & Performance ───────────────────────────
          const _SectionHeader(title: 'Proxy & Performance'),
          const _SettingsCard(
            children: [
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Proxy tools unavailable'),
                subtitle:
                    Text('This engine build does not include proxy support.'),
                enabled: false,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ─── Export ────────────────────────────────────────
          const _SectionHeader(title: 'Export'),
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
          const _SectionHeader(title: 'Storage'),
          _SettingsCard(
            children: [
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Cache cleanup unavailable'),
                subtitle:
                    Text('This engine build does not expose cache cleanup.'),
                enabled: false,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.delete_sweep_outlined,
                  color: AppTheme.error,
                ),
                title: Text(
                  'Delete All Projects',
                  style: context.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  'Remove saved projects; keep original media files',
                  style: context.textTheme.bodySmall,
                ),
                trailing: _isDeletingAllProjects
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.chevron_right,
                        color: AppTheme.textDisabled,
                      ),
                onTap: _isDeletingAllProjects
                    ? null
                    : () => _showDeleteAllDialog(context),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Cloud Sync stays opt-in. Sign-in is unavailable until OAuth is
          // configured for this package and signing certificate.
          if (settings.experimentalCloudSync) ...[
            const _SectionHeader(title: 'Cloud Sync'),
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
                  Consumer(
                    builder: (context, ref, _) {
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
                    },
                  ),
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
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppTheme.textDisabled,
                  ),
                  onTap: () => context.push('/cloud'),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // ─── Privacy & Data ────────────────────────────────
          const _SectionHeader(title: 'Privacy & Data'),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.bug_report_outlined,
                  color: AppTheme.textSecondary,
                ),
                title: Text(
                  'Crash diagnostics',
                  style: context.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  'Kept in memory on this device. No external crash-reporting service is configured.',
                  style: context.textTheme.bodySmall,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.insights_outlined,
                  color: AppTheme.textSecondary,
                ),
                title: Text(
                  'Usage analytics',
                  style: context.textTheme.bodyMedium,
                ),
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
          const _SectionHeader(title: 'Experimental'),
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
          const _SectionHeader(title: 'About'),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.info_outline,
                  color: AppTheme.textSecondary,
                ),
                title: Text('Version', style: context.textTheme.bodyMedium),
                trailing: Text(
                  AppConstants.appVersion,
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
                leading: const Icon(
                  Icons.privacy_tip_outlined,
                  color: AppTheme.textSecondary,
                ),
                title:
                    Text('Privacy & Data', style: context.textTheme.bodyMedium),
                subtitle: Text(
                  'How this build handles your information',
                  style: context.textTheme.bodySmall,
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textDisabled,
                ),
                onTap: _showPrivacyAndData,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.description_outlined,
                  color: AppTheme.textSecondary,
                ),
                title: Text('Licenses', style: context.textTheme.bodyMedium),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textDisabled,
                ),
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
                leading: const Icon(
                  Icons.source_outlined,
                  color: AppTheme.textSecondary,
                ),
                title: Text(
                  'Open Source Notices',
                  style: context.textTheme.bodyMedium,
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textDisabled,
                ),
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
        content: const SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'On-device data',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6),
                Text(
                  'Project records, editing choices, and preferences are stored on this device. The app reads media from the locations you select; exports are saved to the destination you choose.',
                ),
                SizedBox(height: 16),
                Text(
                  'Diagnostics and analytics',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6),
                Text(
                  'This build keeps crash diagnostics in memory while the app is running. It does not send crash reports or usage analytics to EDITORS-PRO.',
                ),
                SizedBox(height: 16),
                Text(
                  'Google Drive',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6),
                Text(
                  'Cloud transfer is optional. If enabled and configured, signing in and syncing sends project data to Google Drive under your Google account. Signing out disconnects this app but does not remove copies already stored in Drive.',
                ),
                SizedBox(height: 16),
                Text(
                  'Store-release status',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6),
                Text(
                  'A public privacy-policy URL and support contact have not been configured for this build. This in-app notice does not replace the policy and disclosures required for store release.',
                ),
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

  void _showDeleteAllDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Projects?'),
        content: const Text(
          'This permanently deletes all saved project timelines and snapshots. '
          'Original media files will remain untouched. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: _isDeletingAllProjects
                ? null
                : () {
                    Navigator.pop(ctx);
                    unawaited(_deleteAllProjects());
                  },
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable Settings Widgets ────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

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
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(label, style: context.textTheme.bodyMedium),
      subtitle: subtitle != null
          ? Text(subtitle!, style: context.textTheme.bodySmall)
          : null,
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppTheme.primary,
    );
  }
}

/// Switch tile with an optional trailing badge (e.g. "GPU").
class _SettingsSwitchWithBadge extends StatelessWidget {
  const _SettingsSwitchWithBadge({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.badgeLabel,
    required this.showBadge,
    this.subtitle,
  });
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String badgeLabel;
  final bool showBadge;

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
                color: AppTheme.secondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AppTheme.secondary.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Text(
                badgeLabel,
                style: const TextStyle(
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
      activeThumbColor: AppTheme.primary,
    );
  }
}

class _SettingsDropdown extends StatelessWidget {
  const _SettingsDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

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
  const _SettingsSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final ValueChanged<double> onChanged;

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
