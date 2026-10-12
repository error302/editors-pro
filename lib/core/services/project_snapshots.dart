import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Phase E.15: project version history / snapshots.
///
/// Maintains a rolling set of timestamped snapshots for each project so
/// users can roll back to a previous state after a destructive edit.
/// Snapshots are stored as `.epp` files in a per-project `snapshots/`
/// directory inside the app's documents directory.
///
/// ## Storage layout
///
/// ```
/// <docs>/editors_pro/snapshots/
///   ├── <project-id>/
///   │   ├── 2026-06-17T09-30-00.epp
///   │   ├── 2026-06-17T09-45-00.epp
///   │   └── 2026-06-17T10-00-00.epp   ← most recent
/// ```
///
/// ## Retention
///
/// Each project keeps at most [maxSnapshotsPerProject] snapshots
/// (default 20). When the limit is exceeded, the oldest snapshots are
/// deleted. This bounds disk usage to roughly
/// `maxSnapshotsPerProject * avgProjectSize` per project.
///
/// ## Usage
///
/// ```dart
/// final snapshots = await ProjectSnapshots.listForProject(projectId);
/// await ProjectSnapshots.create(projectId, currentEppBytes);
/// await ProjectSnapshots.restore(projectId, snapshotId);
/// ```
class ProjectSnapshots {
  ProjectSnapshots._();

  /// Maximum number of snapshots to keep per project. Older snapshots
  /// are deleted when this limit is exceeded.
  static const int maxSnapshotsPerProject = 20;

  /// Get the base snapshots directory (creating it if needed).
  static Future<Directory> _snapshotsRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'editors_pro', 'snapshots'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Get the per-project snapshots directory (creating it if needed).
  static Future<Directory> _projectDir(String projectId) async {
    final root = await _snapshotsRoot();
    final dir = Directory(p.join(root.path, projectId));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Create a new snapshot for the given project.
  ///
  /// [eppBytes] is the raw `.epp` file content (the same bytes that
  /// would be written by `Project.saveAsEpp`). The snapshot is stored
  /// with a timestamped filename so the order is deterministic.
  ///
  /// Returns the snapshot ID (which is the filename without extension).
  static Future<String> create(String projectId, List<int> eppBytes) async {
    try {
      final dir = await _projectDir(projectId);
      final now = DateTime.now();
      // Use ISO 8601 with hyphens instead of colons (colons are
      // illegal in filenames on Windows).
      final stamp =
          now.toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final filename = '$stamp.epp';
      final file = File(p.join(dir.path, filename));
      await file.writeAsBytes(eppBytes);

      // Enforce retention: delete oldest snapshots if over the limit.
      await _enforceRetention(dir);

      developer.log(
        'Created snapshot $filename for project $projectId '
        '(${eppBytes.length} bytes)',
        name: 'ProjectSnapshots',
      );
      return stamp;
    } catch (e, st) {
      developer.log(
        'Failed to create snapshot: $e',
        name: 'ProjectSnapshots',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// List all snapshots for a project, oldest first.
  ///
  /// Returns a list of [ProjectSnapshot] records with the snapshot ID,
  /// timestamp, and file size. Returns an empty list if the project
  /// has no snapshots (or the directory doesn't exist).
  static Future<List<ProjectSnapshot>> listForProject(String projectId) async {
    try {
      final root = await _snapshotsRoot();
      final dir = Directory(p.join(root.path, projectId));
      if (!dir.existsSync()) return [];

      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.epp'))
          .toList();

      final snapshots = <ProjectSnapshot>[];
      for (final file in files) {
        final basename = p.basenameWithoutExtension(file.path);
        // Parse the ISO timestamp back from the filename.
        final timestamp = DateTime.tryParse(basename.replaceAll('-', ':')) ??
            file.statSync().modified;
        snapshots.add(ProjectSnapshot(
          id: basename,
          projectId: projectId,
          timestamp: timestamp,
          sizeBytes: file.statSync().size,
          filePath: file.path,
        ));
      }

      // Sort by timestamp ascending (oldest first).
      snapshots.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return snapshots;
    } catch (e, st) {
      developer.log(
        'Failed to list snapshots: $e',
        name: 'ProjectSnapshots',
        error: e,
        stackTrace: st,
      );
      return [];
    }
  }

  /// Read the raw `.epp` bytes for a specific snapshot.
  ///
  /// Returns `null` if the snapshot doesn't exist.
  static Future<List<int>?> read(String projectId, String snapshotId) async {
    try {
      final root = await _snapshotsRoot();
      final file = File(p.join(root.path, projectId, '$snapshotId.epp'));
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } catch (e, st) {
      developer.log(
        'Failed to read snapshot $snapshotId: $e',
        name: 'ProjectSnapshots',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Delete a specific snapshot.
  static Future<bool> delete(String projectId, String snapshotId) async {
    try {
      final root = await _snapshotsRoot();
      final file = File(p.join(root.path, projectId, '$snapshotId.epp'));
      if (!file.existsSync()) return false;
      await file.delete();
      developer.log(
        'Deleted snapshot $snapshotId for project $projectId',
        name: 'ProjectSnapshots',
      );
      return true;
    } catch (e) {
      developer.log(
        'Failed to delete snapshot $snapshotId: $e',
        name: 'ProjectSnapshots',
      );
      return false;
    }
  }

  /// Delete all snapshots for a project. Called when the project
  /// itself is deleted.
  static Future<void> deleteAllForProject(String projectId) async {
    try {
      final root = await _snapshotsRoot();
      final rootPath = p.normalize(root.path);
      final dirPath = p.normalize(p.join(rootPath, projectId));
      if (!p.isWithin(rootPath, dirPath)) {
        throw ArgumentError.value(projectId, 'projectId', 'Invalid project ID');
      }
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      developer.log(
        'Failed to delete all snapshots for project $projectId: $e',
        name: 'ProjectSnapshots',
      );
      rethrow;
    }
  }

  /// Delete the oldest snapshots until the count is at or below
  /// [maxSnapshotsPerProject].
  static Future<void> _enforceRetention(Directory projectDir) async {
    final files = projectDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.epp'))
        .toList()
      ..sort((a, b) => p
          .basenameWithoutExtension(a.path)
          .compareTo(p.basenameWithoutExtension(b.path)));

    if (files.length <= maxSnapshotsPerProject) return;

    final toDelete = files.length - maxSnapshotsPerProject;
    for (int i = 0; i < toDelete; i++) {
      try {
        await files[i].delete();
        developer.log(
          'Retention: deleted old snapshot ${p.basename(files[i].path)}',
          name: 'ProjectSnapshots',
        );
      } catch (e) {
        developer.log(
          'Retention: failed to delete ${files[i].path}: $e',
          name: 'ProjectSnapshots',
        );
      }
    }
  }
}

/// A single project snapshot.
class ProjectSnapshot {
  /// The snapshot ID (ISO 8601 timestamp string used as the filename).
  final String id;

  /// The project this snapshot belongs to.
  final String projectId;

  /// When the snapshot was created.
  final DateTime timestamp;

  /// Size of the `.epp` file in bytes.
  final int sizeBytes;

  /// Absolute path to the `.epp` file on disk.
  final String filePath;

  const ProjectSnapshot({
    required this.id,
    required this.projectId,
    required this.timestamp,
    required this.sizeBytes,
    required this.filePath,
  });

  /// Human-readable size (e.g., "12.3 KB", "1.2 MB").
  String get sizeHuman {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = sizeBytes.toDouble();
    var unitIdx = 0;
    while (size >= 1024 && unitIdx < units.length - 1) {
      size /= 1024;
      unitIdx++;
    }
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[unitIdx]}';
  }

  /// Short label for the snapshot (e.g., "Jun 17, 09:45").
  String label({DateTime? now}) {
    final reference = now ?? DateTime.now();
    final datePart = _monthAbbrev(timestamp.month);
    final dayPart = timestamp.day.toString();
    final timePart =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

    // If the snapshot is from a different year, include the year.
    if (timestamp.year != reference.year) {
      return '$datePart $dayPart, ${timestamp.year} $timePart';
    }
    return '$datePart $dayPart, $timePart';
  }

  static String _monthAbbrev(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }
}
