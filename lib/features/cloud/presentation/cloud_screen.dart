/// Cloud sync screen for EDITORS-PRO.
///
/// Provides a UI for managing cloud sync operations:
/// - View cloud provider status and authenticate
/// - Browse cloud-synced projects
/// - Trigger sync operations
/// - Resolve conflicts
///
/// Google Drive is the only implemented provider. OAuth remains unavailable
/// until the package ID and signing certificate are registered.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/constants/cloud_config.dart';
import '../providers/cloud_provider.dart';

class CloudScreen extends ConsumerStatefulWidget {
  const CloudScreen({super.key});

  @override
  ConsumerState<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends ConsumerState<CloudScreen> {
  @override
  void initState() {
    super.initState();
    // Load cloud projects on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cloudSyncProvider.notifier).fetchCloudProjects();
    });
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(cloudSyncProvider);
    final syncNotifier = ref.read(cloudSyncProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Sync'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (syncState.isAuthenticated)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: () => _showSignOutDialog(context, syncNotifier),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Provider Status Card ──────────────────────────────
          _ProviderStatusCard(
            isAuthenticated: syncState.isAuthenticated,
            accountName: syncState.accountName,
            providerName: syncState.providerName,
            isProviderConfigured: CloudConfig.isGoogleDriveConfigured,
            onSignIn: () => _handleSignIn(syncNotifier),
          ),

          const SizedBox(height: 24),

          // ─── Sync Actions ─────────────────────────────────────
          if (syncState.isAuthenticated) ...[
            _SyncActionsCard(
              isSyncing: syncState.isSyncing,
              pendingConflicts: syncState.pendingConflicts,
              onSyncAll: () => _handleSyncAll(syncNotifier),
            ),
            const SizedBox(height: 24),
          ],

          // ─── Error Banner ─────────────────────────────────────
          if (syncState.lastError != null) ...[
            _ErrorBanner(
              message: syncState.lastError!,
              onDismiss: () => syncNotifier.clearError(),
            ),
            const SizedBox(height: 16),
          ],

          // ─── Cloud Projects ───────────────────────────────────
          _SectionHeader(title: 'Cloud Projects'),
          const SizedBox(height: 8),
          _CloudProjectsList(
            projects: syncState.cloudProjects,
            isSyncing: syncState.isSyncing,
            onSyncProject: (projectId) =>
                _handleSyncProject(syncNotifier, projectId),
            onResolveConflict: (projectId) =>
                _showConflictDialog(context, syncNotifier, projectId),
          ),

          const SizedBox(height: 24),

          // ─── Info Card ────────────────────────────────────────
          _InfoCard(),
        ],
      ),
    );
  }

  Future<void> _handleSignIn(CloudSyncNotifier notifier) async {
    notifier.setProvider('Google Drive');
    await notifier.authenticate();
  }

  Future<void> _handleSyncAll(CloudSyncNotifier notifier) async {
    // Phase E.20: sync all tracked projects.
    final projects = notifier.state.cloudProjects;
    if (projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No cloud projects to sync')),
      );
      return;
    }
    int successCount = 0;
    for (final project in projects) {
      final ok = await notifier.syncProject(project.projectId);
      if (ok) successCount++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Synced $successCount/${projects.length} projects',
          ),
        ),
      );
    }
  }

  Future<void> _handleSyncProject(
    CloudSyncNotifier notifier,
    String projectId,
  ) async {
    final success = await notifier.syncProject(projectId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Project synced to ${notifier.state.providerName}'
                : (notifier.state.lastError ?? 'Sync failed'),
          ),
        ),
      );
    }
  }

  void _showSignOutDialog(
    BuildContext context,
    CloudSyncNotifier notifier,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out?'),
        content: Text(
          'This will disconnect your ${notifier.state.providerName} account. '
          'Your local projects will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.signOut();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _showConflictDialog(
    BuildContext context,
    CloudSyncNotifier notifier,
    String projectId,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve Conflict'),
        content: const Text(
          'This project has been modified both locally and in the cloud. '
          'Choose how to resolve the conflict:',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.resolveConflict(projectId, 'KeepLocal');
            },
            child: const Text('Keep Local'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.resolveConflict(projectId, 'KeepCloud');
            },
            child: const Text('Keep Cloud'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.resolveConflict(projectId, 'KeepBoth');
            },
            child: const Text('Keep Both'),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable Widgets ──────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 4),
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

class _ProviderStatusCard extends StatelessWidget {
  final bool isAuthenticated;
  final String? accountName;
  final String providerName;
  final bool isProviderConfigured;
  final VoidCallback onSignIn;

  const _ProviderStatusCard({
    required this.isAuthenticated,
    this.accountName,
    required this.providerName,
    required this.isProviderConfigured,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isAuthenticated ? Icons.cloud_done : Icons.cloud_off,
                  color: isAuthenticated
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAuthenticated ? 'Connected' : 'Not Connected',
                        style: context.textTheme.titleMedium?.copyWith(
                          color: isAuthenticated
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                        ),
                      ),
                      if (isAuthenticated && accountName != null)
                        Text(
                          accountName!,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isAuthenticated)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppTheme.success.withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      providerName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.success,
                      ),
                    ),
                  ),
              ],
            ),
            if (!isAuthenticated) ...[
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('Google Drive'),
                subtitle: Text(
                  isProviderConfigured
                      ? 'Selected provider'
                      : 'Unavailable until Google OAuth is configured for this app',
                ),
                trailing:
                    const Icon(Icons.check_circle, color: AppTheme.primary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isProviderConfigured ? onSignIn : null,
                  icon: const Icon(Icons.login, size: 18),
                  label: Text(
                    isProviderConfigured
                        ? 'Sign in with Google Drive'
                        : 'Google Drive not configured',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncActionsCard extends StatelessWidget {
  final bool isSyncing;
  final int pendingConflicts;
  final VoidCallback onSyncAll;

  const _SyncActionsCard({
    required this.isSyncing,
    required this.pendingConflicts,
    required this.onSyncAll,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                if (isSyncing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                else
                  const Icon(Icons.sync, color: AppTheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isSyncing ? 'Syncing…' : 'All projects synced',
                    style: context.textTheme.bodyMedium,
                  ),
                ),
                if (pendingConflicts > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppTheme.warning.withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '$pendingConflicts conflict${pendingConflicts > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.warning,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isSyncing ? null : onSyncAll,
                icon: const Icon(Icons.cloud_sync, size: 18),
                label: const Text('Sync All'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: AppTheme.error.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: context.textTheme.bodySmall?.copyWith(
                color: AppTheme.error,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: AppTheme.error),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _CloudProjectsList extends StatelessWidget {
  final List<CloudProjectEntry> projects;
  final bool isSyncing;
  final ValueChanged<String> onSyncProject;
  final ValueChanged<String> onResolveConflict;

  const _CloudProjectsList({
    required this.projects,
    required this.isSyncing,
    required this.onSyncProject,
    required this.onResolveConflict,
  });

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: AppTheme.textDisabled,
              ),
              const SizedBox(height: 12),
              Text(
                'No cloud projects yet',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Sign in to view your synced projects',
                style: context.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textDisabled,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: projects.map((project) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(
              Icons.description_outlined,
              color: AppTheme.primary,
            ),
            title: Text(project.name, style: context.textTheme.bodyMedium),
            subtitle: Text(
              '${project.formattedSize} · ${project.formattedDate}',
              style: context.textTheme.bodySmall,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.info.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    project.providerName,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.info,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.sync, size: 18),
                  onPressed:
                      isSyncing ? null : () => onSyncProject(project.projectId),
                  tooltip: 'Sync',
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppTheme.secondary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'How Cloud Sync Works',
                  style: context.textTheme.titleSmall?.copyWith(
                    color: AppTheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.description_outlined,
              text: 'Only .epp project files are synced (typically < 1MB)',
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.videocam_off_outlined,
              text: 'Source media (video files) stays local — not uploaded',
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.merge_outlined,
              text: 'Conflicts are detected and resolved per project',
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.offline_bolt_outlined,
              text: 'Works offline — syncs when connectivity is restored',
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: context.textTheme.bodySmall?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
