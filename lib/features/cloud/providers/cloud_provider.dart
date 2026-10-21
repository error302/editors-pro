/// Cloud sync state and Riverpod provider.
///
/// Manages the cloud sync lifecycle: authentication, project sync,
/// conflict resolution, and status tracking.
///
/// Phase E.20: Google Drive sync is now fully implemented via
/// [GoogleDriveSync]. When the provider is "Google Drive", the notifier
/// delegates to the real OAuth2 PKCE + Drive REST API implementation.
/// Other providers still use the placeholder.
library;

import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/cloud_config.dart';
import '../../../core/services/engine_service.dart';
import '../../../core/services/google_drive_sync.dart';

// ─── Cloud Sync State ─────────────────────────────────────────────

/// Immutable snapshot of the cloud sync state.
class CloudSyncState {
  const CloudSyncState({
    this.isAuthenticated = false,
    this.accountName,
    this.providerName = 'None',
    this.isSyncing = false,
    this.pendingConflicts = 0,
    this.lastError,
    this.cloudProjects = const [],
  });

  /// Whether the user is authenticated with a cloud provider.
  final bool isAuthenticated;

  /// The authenticated account name / email, if signed in.
  final String? accountName;

  /// The selected cloud provider's display name.
  final String providerName;

  /// Whether a sync operation is currently in progress.
  final bool isSyncing;

  /// Number of conflicts requiring resolution.
  final int pendingConflicts;

  /// Error message from the last failed operation, if any.
  final String? lastError;

  /// List of cloud project entries.
  final List<CloudProjectEntry> cloudProjects;

  CloudSyncState copyWith({
    bool? isAuthenticated,
    String? accountName,
    String? providerName,
    bool? isSyncing,
    int? pendingConflicts,
    String? lastError,
    bool clearError = false,
    bool clearAccount = false,
    List<CloudProjectEntry>? cloudProjects,
  }) {
    return CloudSyncState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      accountName: clearAccount ? null : (accountName ?? this.accountName),
      providerName: providerName ?? this.providerName,
      isSyncing: isSyncing ?? this.isSyncing,
      pendingConflicts: pendingConflicts ?? this.pendingConflicts,
      lastError: clearError ? null : (lastError ?? this.lastError),
      cloudProjects: cloudProjects ?? this.cloudProjects,
    );
  }
}

/// A single cloud project entry for display in the UI.
class CloudProjectEntry {
  const CloudProjectEntry({
    required this.projectId,
    required this.name,
    required this.modifiedAt,
    required this.sizeBytes,
    required this.cloudFileId,
    required this.providerName,
  });
  final String projectId;
  final String name;
  final int modifiedAt;
  final int sizeBytes;
  final String cloudFileId;
  final String providerName;

  /// Format the file size for display (e.g., "1.2 MB").
  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Format the modification date for display.
  String get formattedDate {
    final dt = DateTime.fromMillisecondsSinceEpoch(modifiedAt);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ─── Conflict Info ────────────────────────────────────────────────

/// Describes a sync conflict that the user needs to resolve.
class SyncConflictInfo {
  const SyncConflictInfo({
    required this.projectId,
    required this.projectName,
    required this.localModifiedAt,
    required this.cloudModifiedAt,
    required this.localChecksum,
    required this.cloudChecksum,
    required this.suggestedStrategy,
  });
  final String projectId;
  final String projectName;
  final int localModifiedAt;
  final int cloudModifiedAt;
  final String localChecksum;
  final String cloudChecksum;
  final String suggestedStrategy;
}

// ─── Cloud Sync Notifier ──────────────────────────────────────────

/// Riverpod notifier that manages the cloud sync lifecycle.
///
/// All cloud I/O is currently placeholder — the actual OAuth2 flows
/// and API calls will be implemented in a future phase.
class CloudSyncNotifier extends StateNotifier<CloudSyncState> {
  CloudSyncNotifier() : super(const CloudSyncState());
  CloudSyncState get currentState => state;

  /// Authenticate with the selected cloud provider.
  ///
  /// Phase E.20: when the provider is "Google Drive", this delegates
  /// to [GoogleDriveSync.authenticate] which performs the real OAuth2
  /// PKCE flow via `flutter_appauth`. Other providers still use the
  /// placeholder.
  Future<void> authenticate() async {
    state = state.copyWith(isSyncing: true, clearError: true);

    try {
      if (state.providerName == 'Google Drive') {
        if (!CloudConfig.isGoogleDriveConfigured) {
          state = state.copyWith(
            isSyncing: false,
            lastError:
                'Google Drive client ID not configured. See docs/GOOGLE_DRIVE_SETUP.md.',
          );
          return;
        }

        final email = await GoogleDriveSync.instance.authenticate();
        state = state.copyWith(
          isAuthenticated: true,
          accountName: email,
          isSyncing: false,
        );
        developer.log(
          'Google Drive authentication successful: $email',
          name: 'CloudSyncNotifier',
        );
      } else {
        // Other providers — placeholder
        developer.log(
          'Cloud authentication for ${state.providerName} not yet implemented',
          name: 'CloudSyncNotifier',
        );
        state = state.copyWith(
          isSyncing: false,
          lastError: '${state.providerName} sync not yet implemented',
        );
      }
    } catch (e) {
      developer.log(
        'Cloud authentication failed: $e',
        name: 'CloudSyncNotifier',
        error: e,
      );
      state = state.copyWith(
        isSyncing: false,
        lastError: 'Authentication failed: $e',
      );
    }
  }

  /// Sign out from the cloud provider.
  Future<void> signOut() async {
    if (state.providerName == 'Google Drive' && state.isAuthenticated) {
      try {
        await GoogleDriveSync.instance.signOut();
      } catch (e) {
        developer.log(
          'Google Drive sign-out failed (non-fatal): $e',
          name: 'CloudSyncNotifier',
        );
      }
    }
    state = const CloudSyncState();
    developer.log(
      'Signed out from cloud provider',
      name: 'CloudSyncNotifier',
    );
  }

  /// Set the cloud provider.
  void setProvider(String providerName) {
    state = state.copyWith(
      providerName: providerName,
      isAuthenticated: false,
      clearAccount: true,
    );
  }

  /// Sync a single project.
  ///
  /// Phase E.20: when the provider is "Google Drive" and authenticated,
  /// this uploads the project's `.epp` file to Drive via
  /// [GoogleDriveSync.uploadProject]. Other providers fall back to the
  /// engine's placeholder sync.
  ///
  /// Returns `true` if the sync succeeded, `false` otherwise.
  Future<bool> syncProject(String projectId) async {
    if (state.isSyncing) return false;

    state = state.copyWith(isSyncing: true, clearError: true);

    try {
      if (state.providerName == 'Google Drive' && state.isAuthenticated) {
        // Get the local .epp file path from the engine.
        final api = EngineService.instance.api;
        final projectInfo = await api.getProjectInfo();
        if (projectInfo == null) {
          state = state.copyWith(
            isSyncing: false,
            lastError: 'No project open',
          );
          return false;
        }

        // Save the project to a temp file, then upload it.
        // The saveProject call writes the .epp file to the engine's
        // projects directory.
        // We need the path — get it from the project repository.
        // For now, use the engine's save_project + read pattern.
        final eppPath = await _getProjectEppPath(projectId);
        if (eppPath == null) {
          state = state.copyWith(
            isSyncing: false,
            lastError: 'Could not find project file to sync',
          );
          return false;
        }

        // Ensure the project is saved before uploading.
        await api.saveProject(filePath: eppPath);

        final fileId = await GoogleDriveSync.instance.uploadProject(
          projectId,
          eppPath,
        );

        state = state.copyWith(
          isSyncing: false,
          lastError: null,
        );

        developer.log(
          'Synced project $projectId to Google Drive (fileId=$fileId)',
          name: 'CloudSyncNotifier',
        );
        return true;
      } else {
        // Other providers — use the engine's sync (placeholder).
        final api = EngineService.instance.api;
        final result = await api.syncProject(projectId: projectId);

        state = state.copyWith(
          isSyncing: false,
          lastError: result.success ? null : result.message,
        );

        return result.success;
      }
    } catch (e) {
      developer.log(
        'Sync project failed: $e',
        name: 'CloudSyncNotifier',
        error: e,
      );
      state = state.copyWith(
        isSyncing: false,
        lastError: 'Sync failed: $e',
      );
      return false;
    }
  }

  /// Get the local `.epp` file path for a project.
  ///
  /// Constructs the same path that `ProjectRepository.saveProjectToEngine`
  /// uses: `<docs>/editors_pro/projects/<projectId>.epp`.
  Future<String?> _getProjectEppPath(String projectId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      // Use the same path pattern as ProjectRepository + AppConstants.
      return '${dir.path}/editors_pro/projects/$projectId.epp';
    } catch (e) {
      developer.log(
        'Failed to get project EPP path: $e',
        name: 'CloudSyncNotifier',
      );
      return null;
    }
  }

  /// Get the sync status for a project.
  Future<Map<String, dynamic>?> getSyncStatus(String projectId) async {
    try {
      final api = EngineService.instance.api;
      final status = await api.getSyncStatus(projectId: projectId);
      return {
        'projectId': status.projectId,
        'status': status.status,
        'statusDisplayName': status.statusDisplayName,
        'isActionable': status.isActionable,
        'lastSyncedAt': status.lastSyncedAt,
        'errorMessage': status.errorMessage,
      };
    } catch (e) {
      developer.log(
        'Get sync status failed: $e',
        name: 'CloudSyncNotifier',
        error: e,
      );
      return null;
    }
  }

  /// Fetch the list of cloud projects.
  ///
  /// Phase E.20: when the provider is "Google Drive" and authenticated,
  /// this lists projects from Drive via [GoogleDriveSync.listProjects].
  Future<void> fetchCloudProjects() async {
    try {
      if (state.providerName == 'Google Drive' && state.isAuthenticated) {
        final driveProjects = await GoogleDriveSync.instance.listProjects();
        state = state.copyWith(
          cloudProjects: driveProjects
              .map(
                (p) => CloudProjectEntry(
                  projectId: p.projectId,
                  name: p.name,
                  modifiedAt: p.modifiedAt,
                  sizeBytes: p.sizeBytes,
                  cloudFileId: p.cloudFileId,
                  providerName: 'Google Drive',
                ),
              )
              .toList(),
        );
      } else {
        // Other providers — use the engine's placeholder.
        final api = EngineService.instance.api;
        final projects = await api.getCloudProjects();

        state = state.copyWith(
          cloudProjects: projects
              .map(
                (p) => CloudProjectEntry(
                  projectId: p.projectId,
                  name: p.name,
                  modifiedAt: p.modifiedAt,
                  sizeBytes: p.sizeBytes,
                  cloudFileId: p.cloudFileId,
                  providerName: p.providerName,
                ),
              )
              .toList(),
        );
      }
    } catch (e) {
      developer.log(
        'Fetch cloud projects failed: $e',
        name: 'CloudSyncNotifier',
        error: e,
      );
      // Keep the existing project list on error
    }
  }

  /// Resolve a sync conflict for a project.
  ///
  /// `strategy` must be one of: "KeepLocal", "KeepCloud", "KeepBoth",
  /// or "AutoMerge".
  Future<bool> resolveConflict(String projectId, String strategy) async {
    try {
      final api = EngineService.instance.api;
      await api.resolveSyncConflict(projectId: projectId, strategy: strategy);

      // Update conflict count
      final newCount =
          state.pendingConflicts > 0 ? state.pendingConflicts - 1 : 0;
      state = state.copyWith(pendingConflicts: newCount);
      return true;
    } catch (e) {
      developer.log(
        'Resolve conflict failed: $e',
        name: 'CloudSyncNotifier',
        error: e,
      );
      state = state.copyWith(lastError: 'Conflict resolution failed: $e');
      return false;
    }
  }

  /// Clear the last error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ─── Provider ─────────────────────────────────────────────────────

/// Provider that exposes [CloudSyncNotifier] and the current [CloudSyncState].
final cloudSyncProvider =
    StateNotifierProvider<CloudSyncNotifier, CloudSyncState>((ref) {
  return CloudSyncNotifier();
});
