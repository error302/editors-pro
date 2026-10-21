/// Unit tests for cloud sync conflict resolution logic.
///
/// These tests verify the conflict resolution strategies and the
/// CloudSyncState/CloudProjectEntry models used in the Flutter layer.
library;

import 'package:editors_pro/features/cloud/providers/cloud_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ─── CloudSyncState ──────────────────────────────────────────────

  group('CloudSyncState', () {
    test('default state is unauthenticated', () {
      const state = CloudSyncState();
      expect(state.isAuthenticated, false);
      expect(state.accountName, isNull);
      expect(state.providerName, 'None');
      expect(state.isSyncing, false);
      expect(state.pendingConflicts, 0);
      expect(state.lastError, isNull);
      expect(state.cloudProjects, isEmpty);
    });

    test('copyWith preserves unchanged fields', () {
      const state = CloudSyncState(
        isAuthenticated: true,
        accountName: 'user@example.com',
        providerName: 'Google Drive',
      );

      final copied = state.copyWith(isSyncing: true);
      expect(copied.isAuthenticated, true);
      expect(copied.accountName, 'user@example.com');
      expect(copied.providerName, 'Google Drive');
      expect(copied.isSyncing, true);
    });

    test('copyWith clearError removes error', () {
      const state = CloudSyncState(lastError: 'Some error');

      final copied = state.copyWith(clearError: true);
      expect(copied.lastError, isNull);
    });

    test('copyWith without clearError preserves error', () {
      const state = CloudSyncState(lastError: 'Some error');

      final copied = state.copyWith(isSyncing: true);
      expect(copied.lastError, 'Some error');
    });
  });

  // ─── CloudProjectEntry ──────────────────────────────────────────

  group('CloudProjectEntry', () {
    test('formattedSize formats bytes correctly', () {
      const entry = CloudProjectEntry(
        projectId: 'p1',
        name: 'Test',
        modifiedAt: 0,
        sizeBytes: 500,
        cloudFileId: 'f1',
        providerName: 'Google Drive',
      );
      expect(entry.formattedSize, '500 B');
    });

    test('formattedSize formats kilobytes correctly', () {
      const entry = CloudProjectEntry(
        projectId: 'p1',
        name: 'Test',
        modifiedAt: 0,
        sizeBytes: 1536,
        cloudFileId: 'f1',
        providerName: 'Google Drive',
      );
      expect(entry.formattedSize, '1.5 KB');
    });

    test('formattedSize formats megabytes correctly', () {
      const entry = CloudProjectEntry(
        projectId: 'p1',
        name: 'Test',
        modifiedAt: 0,
        sizeBytes: 1048576,
        cloudFileId: 'f1',
        providerName: 'Google Drive',
      );
      expect(entry.formattedSize, '1.0 MB');
    });

    test('formattedDate formats date correctly', () {
      // 2024-01-15 10:30 UTC
      const entry = CloudProjectEntry(
        projectId: 'p1',
        name: 'Test',
        modifiedAt: 1705312200000,
        sizeBytes: 0,
        cloudFileId: 'f1',
        providerName: 'Google Drive',
      );
      // Just verify it's a non-empty string with expected format
      expect(entry.formattedDate, isNotEmpty);
      expect(entry.formattedDate, contains('-'));
    });
  });

  // ─── SyncConflictInfo ───────────────────────────────────────────

  group('SyncConflictInfo', () {
    test('creates with all fields', () {
      const conflict = SyncConflictInfo(
        projectId: 'p1',
        projectName: 'My Project',
        localModifiedAt: 1000,
        cloudModifiedAt: 2000,
        localChecksum: 'abc',
        cloudChecksum: 'def',
        suggestedStrategy: 'KeepCloud',
      );

      expect(conflict.projectId, 'p1');
      expect(conflict.projectName, 'My Project');
      expect(conflict.localModifiedAt, 1000);
      expect(conflict.cloudModifiedAt, 2000);
      expect(conflict.localChecksum, 'abc');
      expect(conflict.cloudChecksum, 'def');
      expect(conflict.suggestedStrategy, 'KeepCloud');
    });
  });

  // ─── CloudSyncNotifier ──────────────────────────────────────────

  group('CloudSyncNotifier', () {
    test('initial state is unauthenticated', () {
      final notifier = CloudSyncNotifier();
      expect(notifier.state.isAuthenticated, false);
      expect(notifier.state.providerName, 'None');
    });

    test('setProvider updates provider name and clears auth', () {
      final notifier = CloudSyncNotifier();

      // First set authenticated state
      notifier.state = const CloudSyncState(
        isAuthenticated: true,
        accountName: 'user@example.com',
        providerName: 'Google Drive',
      );

      // Change provider
      notifier.setProvider('Dropbox');
      expect(notifier.state.providerName, 'Dropbox');
      expect(notifier.state.isAuthenticated, false);
      expect(notifier.state.accountName, isNull);
    });

    test('signOut resets to default state', () async {
      final notifier = CloudSyncNotifier();

      notifier.state = const CloudSyncState(
        isAuthenticated: true,
        accountName: 'user@example.com',
        providerName: 'Google Drive',
        pendingConflicts: 2,
      );

      await notifier.signOut();
      expect(notifier.state.isAuthenticated, false);
      expect(notifier.state.accountName, isNull);
      expect(notifier.state.providerName, 'None');
      expect(notifier.state.pendingConflicts, 0);
    });

    test('clearError removes error', () {
      final notifier = CloudSyncNotifier();
      notifier.state = const CloudSyncState(lastError: 'Something went wrong');

      notifier.clearError();
      expect(notifier.state.lastError, isNull);
    });
  });
}
