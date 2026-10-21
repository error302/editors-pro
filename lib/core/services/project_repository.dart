/// Repository that bridges the Drift database with the Rust engine.
///
/// This is the single source of truth for project persistence:
/// - Creating a project → insert into DB + create in engine
/// - Opening a project → read from DB + restore in engine
/// - Deleting a project → delete from DB + engine cleanup
///
/// The Drift database stores lightweight metadata (name, resolution, etc.)
/// while the Rust engine's .epp file stores the full timeline/clip state.
library;

import 'dart:developer' as developer;
import 'dart:io' show Directory, File;

import 'package:drift/drift.dart';
import 'package:editors_pro/src/rust/api/bridge_api.dart' as bridge
    show BridgeProjectSettings, MediaAssetInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/database_provider.dart';
import '../../core/services/engine_service.dart';
import '../../core/services/project_snapshots.dart';
import '../../data/database/app_database.dart';
import '../../data/models/project_model.dart';

class ProjectRepository {
  ProjectRepository(this._db, Ref _);
  final AppDatabase _db;

  final _uuid = const Uuid();

  // ─── Create ────────────────────────────────────────────────────

  /// Create a new project, persist it to the database, and initialize
  /// it in the Rust engine.
  ///
  /// Returns the fully-hydrated [ProjectModel] on success.
  Future<ProjectModel> createProject(
    String name, {
    int width = 1920,
    int height = 1080,
    double fps = 30.0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();

    // Persist to database
    await _db.upsertProject(
      ProjectEntriesCompanion(
        id: Value(id),
        name: Value(name),
        width: Value(width),
        height: Value(height),
        fps: Value(fps),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    // Initialize in the Rust engine
    if (EngineService.instance.isInitialized) {
      try {
        await EngineService.instance.api.createProject(
          name: name,
          settings: bridge.BridgeProjectSettings(
            width: width,
            height: height,
            fps: fps,
          ),
        );
      } catch (e) {
        developer.log(
          'Engine createProject failed: $e',
          name: 'ProjectRepository',
        );
      }
    }

    // Create default tracks in the model
    final videoTrackId = _uuid.v4();
    final audioTrackId = _uuid.v4();
    final textTrackId = _uuid.v4();

    return ProjectModel(
      id: id,
      name: name,
      createdAt: now,
      updatedAt: now,
      width: width,
      height: height,
      fps: fps,
      tracks: [
        TrackModel(
          id: videoTrackId,
          name: 'Video 1',
          trackType: TrackType.video,
          orderIndex: 0,
        ),
        TrackModel(
          id: audioTrackId,
          name: 'Audio 1',
          trackType: TrackType.audio,
          orderIndex: 1,
        ),
        TrackModel(
          id: textTrackId,
          name: 'Text',
          trackType: TrackType.text,
          orderIndex: 2,
        ),
      ],
    );
  }

  // ─── Read ──────────────────────────────────────────────────────

  /// Load all projects from the database, converting DB rows to
  /// lightweight [ProjectModel] instances (without clips/assets loaded).
  Future<List<ProjectModel>> getAllProjects() async {
    final rows = await _db.getAllProjects();
    return rows.map(_dbRowToModel).toList();
  }

  /// Load a single project by ID, including its media assets.
  Future<ProjectModel?> getProject(String id) async {
    final row = await _db.getProject(id);
    if (row == null) return null;

    final assets = await _db.getAssetsForProject(id);
    final model = _dbRowToModel(row);

    // Attach media assets
    return model.copyWith(
      mediaAssets: assets.map(_assetDbRowToModel).toList(),
    );
  }

  // ─── Update ────────────────────────────────────────────────────

  /// Update a project's metadata in the database.
  Future<void> updateProject(ProjectModel project) async {
    await _db.upsertProject(
      ProjectEntriesCompanion(
        id: Value(project.id),
        name: Value(project.name),
        width: Value(project.width),
        height: Value(project.height),
        fps: Value(project.fps),
        durationMs: Value(project.durationMs),
        createdAt: Value(project.createdAt),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        thumbnailPath: Value(project.thumbnailPath),
      ),
    );
  }

  /// Save a project's full state via the Rust engine (.epp format).
  Future<void> saveProjectToEngine(ProjectModel project) async {
    if (!EngineService.instance.isInitialized) {
      throw StateError('The editing engine is not ready.');
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final projectsDir = p.join(dir.path, AppConstants.projectsDir);
      await Directory(projectsDir).create(recursive: true);
      final eppPath = p.join(
        projectsDir,
        '${project.id}${AppConstants.projectFileExtension}',
      );

      await EngineService.instance.api.saveProject(filePath: eppPath);

      // Update the DB with the .epp file path
      await _db.upsertProject(
        ProjectEntriesCompanion(
          id: Value(project.id),
          eppFilePath: Value(eppPath),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
    } catch (e) {
      developer.log(
        'saveProjectToEngine failed: $e',
        name: 'ProjectRepository',
      );
      rethrow;
    }
  }

  /// Phase E.15: read the raw `.epp` bytes for a project from disk.
  ///
  /// Used by the snapshot system to copy the current project state into
  /// a versioned snapshot file. Returns `null` if the project has never
  /// been saved (no .epp file exists yet).
  Future<List<int>?> readProjectEppBytes(String projectId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final projectsDir = p.join(dir.path, AppConstants.projectsDir);
      final eppPath =
          p.join(projectsDir, '$projectId${AppConstants.projectFileExtension}');
      final file = File(eppPath);
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } catch (e) {
      developer.log(
        'readProjectEppBytes failed: $e',
        name: 'ProjectRepository',
      );
      return null;
    }
  }

  /// Load a project's full timeline state from the Rust engine (.epp).
  Future<void> loadProjectFromEngine(String eppFilePath) async {
    if (!EngineService.instance.isInitialized) return;
    try {
      await EngineService.instance.api.loadProject(filePath: eppFilePath);
    } catch (e) {
      developer.log(
        'loadProjectFromEngine failed: $e',
        name: 'ProjectRepository',
      );
    }
  }

  // ─── Media Assets ──────────────────────────────────────────────

  /// Persist a media asset record to the database.
  Future<void> addMediaAsset(String projectId, MediaAssetModel asset) async {
    await _db.upsertMediaAsset(
      MediaAssetEntriesCompanion(
        id: Value(asset.id),
        projectId: Value(projectId),
        filePath: Value(asset.filePath),
        fileName: Value(asset.fileName),
        mediaType: Value(asset.mediaType.name),
        durationMs: Value(asset.durationMs),
        width: Value(asset.width),
        height: Value(asset.height),
        fileSizeBytes: Value(asset.fileSizeBytes),
        codec: Value(asset.codec),
        bitrate: Value(asset.bitrate),
        thumbnailPath: Value(asset.thumbnailPath),
        importedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Register an app-owned media file in the native project using its stable
  /// database ID, so saved clips can resolve it after reopening.
  Future<void> restoreMediaAssetInEngine(MediaAssetModel asset) async {
    await EngineService.instance.api.restoreMediaAsset(
      asset: bridge.MediaAssetInfo(
        id: asset.id,
        filePath: asset.filePath,
        fileName: asset.fileName,
        mediaType: asset.mediaType.name,
        durationMs: asset.durationMs,
        width: asset.width,
        height: asset.height,
        fileSizeBytes: asset.fileSizeBytes,
        codec: asset.codec,
        bitrate: asset.bitrate,
      ),
    );
  }

  // ─── Delete ────────────────────────────────────────────────────

  /// Delete a project and all its associated data.
  Future<void> deleteProject(String projectId) async {
    final docs = await getApplicationDocumentsDirectory();
    final projectsDir =
        p.normalize(p.join(docs.path, AppConstants.projectsDir));
    final eppPath = p.normalize(
      p.join(projectsDir, '$projectId${AppConstants.projectFileExtension}'),
    );
    if (!p.isWithin(projectsDir, eppPath)) {
      throw ArgumentError.value(projectId, 'projectId', 'Invalid project ID');
    }

    final eppFile = File(eppPath);
    if (await eppFile.exists()) {
      await eppFile.delete();
    }
    await ProjectSnapshots.deleteAllForProject(projectId);

    await _db.transaction(() async {
      await _db.deleteAssetsForProject(projectId);
      await _db.deleteProject(projectId);
    });
  }

  // ─── Conversion helpers ────────────────────────────────────────

  ProjectModel _dbRowToModel(ProjectEntry row) {
    return ProjectModel(
      id: row.id,
      name: row.name,
      width: row.width,
      height: row.height,
      fps: row.fps,
      durationMs: row.durationMs,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      thumbnailPath: row.thumbnailPath,
      eppFilePath: row.eppFilePath,
    );
  }

  MediaAssetModel _assetDbRowToModel(MediaAssetEntry row) {
    return MediaAssetModel(
      id: row.id,
      filePath: row.filePath,
      fileName: row.fileName,
      mediaType: _mediaTypeFromString(row.mediaType),
      durationMs: row.durationMs,
      width: row.width,
      height: row.height,
      fileSizeBytes: row.fileSizeBytes,
      codec: row.codec,
      bitrate: row.bitrate,
      thumbnailPath: row.thumbnailPath,
    );
  }

  MediaType _mediaTypeFromString(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return MediaType.video;
      case 'audio':
        return MediaType.audio;
      case 'image':
        return MediaType.image;
      default:
        return MediaType.video;
    }
  }
}

/// Engine activation lives outside [ProjectRepository]'s interface so
/// editor test repositories do not need to depend on native project APIs.
extension ProjectRepositoryEngineActivation on ProjectRepository {
  /// Make a persisted project the engine's active project before editing.
  /// Projects that have not been saved yet start as an empty native project.
  Future<void> activateProjectInEngine(ProjectModel project) async {
    final service = EngineService.instance;
    if (!service.isInitialized) {
      throw StateError('The editing engine is not ready.');
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final projectsDirectory = p.normalize(
      p.join(documentsDirectory.path, AppConstants.projectsDir),
    );
    final defaultPath = p.join(
      projectsDirectory,
      '${project.id}${AppConstants.projectFileExtension}',
    );
    final eppPath = project.eppFilePath == null
        ? defaultPath
        : p.normalize(project.eppFilePath!);

    if (!p.isWithin(projectsDirectory, eppPath)) {
      throw StateError('The saved project file path is invalid.');
    }

    final eppFile = File(eppPath);
    if (await eppFile.exists()) {
      await service.api.loadProject(filePath: eppPath);
    } else {
      await Directory(projectsDirectory).create(recursive: true);
      await service.api.createProject(
        name: project.name,
        settings: bridge.BridgeProjectSettings(
          width: project.width,
          height: project.height,
          fps: project.fps,
        ),
      );
    }

    for (final asset in project.mediaAssets) {
      try {
        await restoreMediaAssetInEngine(asset);
      } catch (error, stackTrace) {
        developer.log(
          'Could not restore media asset ${asset.id}',
          name: 'ProjectRepository',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }
}

/// Provider for the [ProjectRepository].
final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ProjectRepository(db, ref);
});
