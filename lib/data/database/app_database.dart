import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Drift database for EDITORS-PRO persistent storage.
///
/// Stores project metadata, media assets, and user preferences.
/// Timeline/clip state is the Rust engine's responsibility — this DB
/// only caches what Flutter needs to display project lists and restore sessions.
@DriftDatabase(
  tables: [
    ProjectEntries,
    MediaAssetEntries,
    UserPreferences,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // Future migration logic goes here
        },
      );

  // ─── Project CRUD ──────────────────────────────────────────────

  /// Insert or update a project record.
  Future<void> upsertProject(ProjectEntriesCompanion entry) {
    return into(projectEntries).insertOnConflictUpdate(entry);
  }

  /// Get all projects, most recently updated first.
  Future<List<ProjectEntry>> getAllProjects() {
    return (select(projectEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  /// Get a single project by ID.
  Future<ProjectEntry?> getProject(String id) {
    return (select(projectEntries)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Delete a project by ID (cascades to media assets).
  Future<int> deleteProject(String id) {
    return (delete(projectEntries)..where((t) => t.id.equals(id))).go();
  }

  /// Update a project's last-modified timestamp.
  Future<void> touchProject(String id) {
    return (update(projectEntries)..where((t) => t.id.equals(id))).write(
      ProjectEntriesCompanion(
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  // ─── Media Asset CRUD ──────────────────────────────────────────

  /// Insert or update a media asset.
  Future<void> upsertMediaAsset(MediaAssetEntriesCompanion entry) {
    return into(mediaAssetEntries).insertOnConflictUpdate(entry);
  }

  /// Get all media assets for a project.
  Future<List<MediaAssetEntry>> getAssetsForProject(String projectId) {
    return (select(mediaAssetEntries)
          ..where((t) => t.projectId.equals(projectId)))
        .get();
  }

  /// Delete a media asset by ID.
  Future<int> deleteMediaAsset(String id) {
    return (delete(mediaAssetEntries)..where((t) => t.id.equals(id))).go();
  }

  /// Delete all media assets for a project.
  Future<int> deleteAssetsForProject(String projectId) {
    return (delete(mediaAssetEntries)
          ..where((t) => t.projectId.equals(projectId)))
        .go();
  }

  // ─── User Preferences ──────────────────────────────────────────

  /// Get a preference value by key. Returns null if not set.
  Future<String?> getPreference(String key) async {
    final row = await (select(userPreferences)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// Set a preference value (insert or update).
  Future<void> setPreference(String key, String value) {
    return into(userPreferences).insertOnConflictUpdate(
      UserPreferencesCompanion(
        key: Value(key),
        value: Value(value),
      ),
    );
  }

  /// Delete a preference by key.
  Future<int> deletePreference(String key) {
    return (delete(userPreferences)..where((t) => t.key.equals(key))).go();
  }
}

/// Projects table — stores metadata about each editing project.
class ProjectEntries extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant('Untitled'))();
  IntColumn get width => integer().withDefault(const Constant(1920))();
  IntColumn get height => integer().withDefault(const Constant(1080))();
  RealColumn get fps => real().withDefault(const Constant(30.0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get thumbnailPath => text().nullable()();
  TextColumn get eppFilePath => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Media assets table — stores imported media files per project.
class MediaAssetEntries extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(ProjectEntries, #id)();
  TextColumn get filePath => text()();
  TextColumn get fileName => text()();
  TextColumn get mediaType => text()(); // 'video', 'audio', 'image'
  IntColumn get durationMs => integer().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get fileSizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get codec => text().nullable()();
  IntColumn get bitrate => integer().nullable()();
  TextColumn get thumbnailPath => text().nullable()();
  IntColumn get importedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// User preferences table — key-value store for app settings.
class UserPreferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Open a database connection using the app's documents directory.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'editors_pro.db'));
    return NativeDatabase.createInBackground(file);
  });
}
