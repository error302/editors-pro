import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/services/engine_service.dart';
import '../../../core/services/project_repository.dart';
import '../../../core/services/project_snapshots.dart';
import '../../../data/models/project_model.dart';
import '../../editor/providers/editor_provider.dart';

/// Current project state
class ProjectState {
  const ProjectState({
    this.currentProject,
    this.recentProjects = const [],
    this.isLoading = false,
    this.error,
  });
  final ProjectModel? currentProject;
  final List<ProjectModel> recentProjects;
  final bool isLoading;
  final String? error;

  ProjectState copyWith({
    ProjectModel? currentProject,
    List<ProjectModel>? recentProjects,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearCurrentProject = false,
  }) {
    return ProjectState(
      currentProject:
          clearCurrentProject ? null : (currentProject ?? this.currentProject),
      recentProjects: recentProjects ?? this.recentProjects,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Project state notifier — now backed by the Drift database via
/// [ProjectRepository] for persistent storage.
class ProjectNotifier extends StateNotifier<ProjectState> {
  ProjectNotifier(this._ref) : super(const ProjectState());
  final Ref _ref;

  ProjectRepository get _repo => _ref.read(projectRepositoryProvider);

  Future<void> _operations = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Load all projects from the database on app startup.
  Future<void> loadProjects() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final projects = await _repo.getAllProjects();
      state = state.copyWith(
        recentProjects: projects,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      developer.log('loadProjects failed: $e', name: 'ProjectNotifier');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Create a new project — persists to database and initializes in the
  /// Rust engine.
  Future<ProjectModel?> createProject(
    String name, {
    int width = 1920,
    int height = 1080,
    double fps = 30.0,
  }) =>
      _serialize(
          () => _createProject(name, width: width, height: height, fps: fps));

  Future<ProjectModel?> _createProject(
    String name, {
    int width = 1920,
    int height = 1080,
    double fps = 30,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    var previous = state.currentProject;
    var engineChanged = false;
    try {
      if (previous != null && !await _saveCurrentProject()) {
        throw StateError('Save the current project before creating another.');
      }
      previous = state.currentProject;
      engineChanged = true;
      final project = await _repo.createProject(
        name,
        width: width,
        height: height,
        fps: fps,
      );

      state = state.copyWith(
        currentProject: project,
        recentProjects: [project, ...state.recentProjects],
        isLoading: false,
      );
      await syncFromEngine();
      return project;
    } catch (e) {
      if (engineChanged && previous != null) {
        try {
          await _repo.activateProjectInEngine(previous);
          state = state.copyWith(currentProject: previous);
          await syncFromEngine();
        } catch (_) {
          state = state.copyWith(clearCurrentProject: true);
        }
      }
      developer.log('createProject failed: $e', name: 'ProjectNotifier');
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  /// Open an existing project — loads from DB and restores in engine.
  Future<bool> openProject(ProjectModel project) =>
      _serialize(() => _openProject(project));

  Future<bool> _openProject(ProjectModel project) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      if (state.currentProject != null && !await _saveCurrentProject()) {
        throw StateError('Save the current project before opening another.');
      }
      // Load full project with assets from DB
      final fullProject = await _repo.getProject(project.id) ?? project;
      await _repo.activateProjectInEngine(fullProject);
      state = state.copyWith(
        currentProject: fullProject,
        isLoading: false,
        clearError: true,
      );
      await syncFromEngine();
      return true;
    } catch (e) {
      developer.log('openProject failed: $e', name: 'ProjectNotifier');
      state = state.copyWith(
        isLoading: false,
        error: 'Could not open project: $e',
      );
      return false;
    }
  }

  /// Close the current project
  void closeProject() {
    state = state.copyWith(clearCurrentProject: true);
  }

  /// Delete a project — removes from DB and engine.
  Future<void> deleteProject(String projectId) =>
      _serialize(() => _deleteProject(projectId));

  Future<void> _deleteProject(String projectId) async {
    try {
      await _repo.deleteProject(projectId);
      final updatedRecent =
          state.recentProjects.where((p) => p.id != projectId).toList();
      state = state.copyWith(
        recentProjects: updatedRecent,
        clearCurrentProject: state.currentProject?.id == projectId,
      );
    } catch (e) {
      developer.log('deleteProject failed: $e', name: 'ProjectNotifier');
      state = state.copyWith(error: 'Delete failed: $e');
    }
  }

  /// Delete every saved project while keeping source media files untouched.
  Future<int> deleteAllProjects() => _serialize(_deleteAllProjects);

  Future<int> _deleteAllProjects() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final projects = await _repo.getAllProjects();
      for (final project in projects) {
        await _repo.deleteProject(project.id);
      }

      state = state.copyWith(
        recentProjects: const [],
        clearCurrentProject: true,
        isLoading: false,
        clearError: true,
      );
      return projects.length;
    } catch (e) {
      List<ProjectModel>? remainingProjects;
      try {
        remainingProjects = await _repo.getAllProjects();
      } catch (_) {
        // Preserve the last known list if the database cannot be re-read.
      }
      final currentProjectRemains = remainingProjects?.any(
            (project) => project.id == state.currentProject?.id,
          ) ??
          true;
      state = state.copyWith(
        recentProjects: remainingProjects,
        clearCurrentProject: !currentProjectRemains,
        isLoading: false,
        error: 'Delete failed: $e',
      );
      rethrow;
    }
  }

  /// Clone the saved timeline and media references without activating the copy.
  Future<String> duplicateProject(String projectId) => _serialize(() async {
        state = state.copyWith(isLoading: true, clearError: true);
        try {
          if (state.currentProject?.id == projectId &&
              !await _saveCurrentProject()) {
            throw StateError(
                'Save the original project before duplicating it.');
          }
          final duplicate = await _repo.duplicateSavedProject(projectId);
          state = state.copyWith(
            recentProjects: [duplicate, ...state.recentProjects],
            isLoading: false,
          );
          return duplicate.id;
        } catch (error) {
          state = state.copyWith(
              isLoading: false, error: 'Duplicate failed: $error');
          rethrow;
        }
      });

  /// Import media into the current project — persists to DB + engine.
  Future<void> importMedia(
    String filePath,
    String fileName,
    MediaType mediaType, {
    required String assetId,
    int? durationMs,
    int? width,
    int? height,
    int fileSizeBytes = 0,
    String? codec,
    int? bitrate,
  }) async {
    if (state.currentProject == null) return;

    final asset = MediaAssetModel(
      id: assetId,
      filePath: filePath,
      fileName: fileName,
      mediaType: mediaType,
      durationMs: durationMs,
      width: width,
      height: height,
      fileSizeBytes: fileSizeBytes,
      codec: codec,
      bitrate: bitrate,
    );

    await _repo.restoreMediaAssetInEngine(asset);

    // Persist to database
    await _repo.addMediaAsset(state.currentProject!.id, asset);

    final updatedProject = state.currentProject!.copyWith(
      mediaAssets: [...state.currentProject!.mediaAssets, asset],
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    state = state.copyWith(currentProject: updatedProject);
  }

  /// Add a clip to a track — updates the Flutter model (engine handles
  /// the actual clip creation via EditorNotifier).
  void addClipToTrack(String trackId, ClipModel clip) {
    if (state.currentProject == null) return;

    final updatedTracks = state.currentProject!.tracks.map((track) {
      if (track.id == trackId) {
        return track.copyWith(clips: [...track.clips, clip]);
      }
      return track;
    }).toList();

    state = state.copyWith(
      currentProject: state.currentProject!.copyWith(
        tracks: updatedTracks,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Update a track's properties (e.g., locked, visible, volume).
  void updateTrack(String trackId, TrackModel updatedTrack) {
    if (state.currentProject == null) return;

    final updatedTracks = state.currentProject!.tracks.map((track) {
      return track.id == trackId ? updatedTrack : track;
    }).toList();

    state = state.copyWith(
      currentProject: state.currentProject!.copyWith(
        tracks: updatedTracks,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Update a clip
  void updateClip(String clipId, ClipModel updatedClip) {
    if (state.currentProject == null) return;

    final updatedTracks = state.currentProject!.tracks.map((track) {
      final updatedClips = track.clips.map((clip) {
        return clip.id == clipId ? updatedClip : clip;
      }).toList();
      return track.copyWith(clips: updatedClips);
    }).toList();

    state = state.copyWith(
      currentProject: state.currentProject!.copyWith(
        tracks: updatedTracks,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Phase E.14: toggle the `locked` flag on a clip. Locked clips
  /// cannot be moved, trimmed, split, or deleted — they're protected
  /// from accidental edits. The UI shows a small lock icon on locked
  /// clips in the timeline.
  void toggleClipLock(String clipId) {
    if (state.currentProject == null) return;

    final updatedTracks = state.currentProject!.tracks.map((track) {
      final updatedClips = track.clips.map((clip) {
        if (clip.id == clipId) {
          return clip.copyWith(locked: !clip.locked);
        }
        return clip;
      }).toList();
      return track.copyWith(clips: updatedClips);
    }).toList();

    state = state.copyWith(
      currentProject: state.currentProject!.copyWith(
        tracks: updatedTracks,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Remove a clip
  void removeClip(String clipId) {
    if (state.currentProject == null) return;

    final updatedTracks = state.currentProject!.tracks.map((track) {
      final updatedClips = track.clips.where((c) => c.id != clipId).toList();
      return track.copyWith(clips: updatedClips);
    }).toList();

    state = state.copyWith(
      currentProject: state.currentProject!.copyWith(
        tracks: updatedTracks,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Update the timeline duration
  void updateDuration(int durationMs) {
    if (state.currentProject == null) return;
    state = state.copyWith(
      currentProject: state.currentProject!.copyWith(durationMs: durationMs),
    );
  }

  /// Save the current project to the engine (.epp format).
  Future<bool> saveCurrentProject() => _serialize(_saveCurrentProject);

  Future<bool> _saveCurrentProject() async {
    try {
      await _ref.read(editorProvider.notifier).flushPendingTextEdits();
      final project = state.currentProject;
      if (project == null) return false;
      // The durable timeline must succeed before publishing metadata.
      await _repo.saveProjectToEngine(project);
      final saved = await _repo.getProject(project.id);
      final refreshed = saved == null
          ? project
          : project.copyWith(
              eppFilePath: saved.eppFilePath,
              updatedAt: saved.updatedAt,
            );
      final recent = [
        refreshed,
        ...state.recentProjects.where((item) => item.id != project.id)
      ];
      state = state.copyWith(
        currentProject: state.currentProject?.id == project.id
            ? refreshed
            : state.currentProject,
        recentProjects: recent,
        clearError: true,
      );
      return true;
    } catch (e) {
      developer.log('saveCurrentProject failed: $e', name: 'ProjectNotifier');
      state = state.copyWith(error: 'Could not save project: $e');
      return false;
    }
  }

  /// Share the saved timeline without changing which project the engine owns.
  Future<String?> prepareProjectExport(ProjectModel project) =>
      _serialize(() async {
        if (state.currentProject?.id == project.id &&
            !await _saveCurrentProject()) return null;
        final saved = await _repo.getProject(project.id);
        final path = saved?.eppFilePath;
        if (path == null || !await File(path).exists()) return null;
        return path;
      });

  /// Phase E.15: create a version-history snapshot of the current project.
  ///
  /// Reads the current `.epp` file from the engine and stores a copy
  /// in the per-project snapshots directory. The user can later restore
  /// to this snapshot via the snapshot browser UI.
  ///
  /// Returns the snapshot ID, or `null` on failure.
  Future<String?> createSnapshot() => _serialize(_createSnapshot);

  Future<String?> _createSnapshot() async {
    if (state.currentProject == null) return null;
    try {
      if (!await _saveCurrentProject()) return null;
      // Read the current .epp bytes from the engine's save location.
      final eppBytes =
          await _repo.readProjectEppBytes(state.currentProject!.id);
      if (eppBytes == null) {
        developer.log(
          'createSnapshot: no .epp file found for project ${state.currentProject!.id}',
          name: 'ProjectNotifier',
        );
        return null;
      }
      return await ProjectSnapshots.create(
        state.currentProject!.id,
        eppBytes,
      );
    } catch (e, st) {
      developer.log(
        'createSnapshot failed: $e',
        name: 'ProjectNotifier',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<bool> restoreSnapshot(String projectId, String snapshotId) =>
      _serialize(() async {
        final current = state.currentProject;
        if (current == null || current.id != projectId) return false;
        final bytes = await ProjectSnapshots.read(projectId, snapshotId);
        if (bytes == null || !await _saveCurrentProject()) return false;
        final backup = await _repo.readProjectEppBytes(projectId);
        if (backup == null) return false;
        await ProjectSnapshots.create(projectId, backup);
        final temp = await getTemporaryDirectory();
        final directory = await temp.createTemp('editors-restore-');
        try {
          final file = File(p.join(directory.path, 'snapshot.epp'));
          await file.writeAsBytes(bytes, flush: true);
          await _repo.loadProjectFromEngine(file.path);
          await syncFromEngine();
          if (!await _saveCurrentProject())
            throw StateError('Could not save the restored timeline.');
          return true;
        } catch (error) {
          try {
            await _repo.activateProjectInEngine(current);
            state = state.copyWith(currentProject: current);
            await syncFromEngine();
          } catch (_) {
            state = state.copyWith(clearCurrentProject: true);
          }
          state = state.copyWith(error: 'Could not restore snapshot: $error');
          return false;
        } finally {
          await directory.delete(recursive: true);
        }
      });

  /// Phase E.15: list all snapshots for the current project.
  Future<List<ProjectSnapshot>> listSnapshots() async {
    if (state.currentProject == null) return [];
    return ProjectSnapshots.listForProject(state.currentProject!.id);
  }

  /// Sync the project model with the latest engine state (after
  /// engine mutations like addClip, split, etc.).
  Future<void> syncFromEngine() async {
    if (!EngineService.instance.isInitialized || state.currentProject == null) {
      return;
    }
    try {
      final api = EngineService.instance.api;
      final timelineState = await api.getTimelineState();
      if (timelineState != null) {
        final existingClips = {
          for (final track in state.currentProject!.tracks)
            for (final clip in track.clips) clip.id: clip,
        };
        final tracks = timelineState.tracks.map((track) {
          final trackType = switch (track.trackType.toLowerCase()) {
            'video' => TrackType.video,
            'audio' => TrackType.audio,
            'text' => TrackType.text,
            'effect' => TrackType.effect,
            _ => TrackType.video,
          };
          return TrackModel(
            id: track.id,
            name: track.name,
            trackType: trackType,
            locked: track.locked,
            visible: track.visible,
            volume: track.volume,
            orderIndex: timelineState.tracks.indexOf(track),
            clips: track.clips.map((clipInfo) {
              final existing = existingClips[clipInfo.id];
              return ClipModel(
                id: clipInfo.id,
                assetId: clipInfo.assetId,
                startMs: clipInfo.startMs,
                durationMs: clipInfo.durationMs,
                trimStartMs: clipInfo.trimStartMs,
                trimEndMs: clipInfo.trimEndMs,
                speed: clipInfo.speed,
                opacity: clipInfo.opacity,
                properties: Map.unmodifiable(clipInfo.properties),
                effects: [
                  for (var i = 0; i < clipInfo.effects.length; i++)
                    EffectModel(
                      id: clipInfo.effects[i].id,
                      name: clipInfo.effects[i].name,
                      effectType: clipInfo.effects[i].effectType,
                      enabled: clipInfo.effects[i].enabled,
                      order: clipInfo.effects[i].order,
                      parameters: [
                        for (final parameter in clipInfo.effects[i].parameters)
                          EffectParameterModel(
                            name: parameter.name,
                            displayName: parameter.displayName,
                            value: parameter.value,
                            minValue: parameter.minValue,
                            maxValue: parameter.maxValue,
                            defaultValue: parameter.defaultValue,
                            step: parameter.step,
                          ),
                      ],
                    ),
                ],
                transitionIn: existing?.transitionIn,
                transitionOut: existing?.transitionOut,
                locked: existing?.locked ?? false,
              );
            }).toList(),
          );
        }).toList();
        state = state.copyWith(
          currentProject: state.currentProject!.copyWith(
            durationMs: timelineState.durationMs,
            tracks: tracks,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    } catch (e) {
      developer.log('syncFromEngine failed: $e', name: 'ProjectNotifier');
    }
  }
}

/// Provider for project state
final projectProvider =
    StateNotifierProvider<ProjectNotifier, ProjectState>((ref) {
  return ProjectNotifier(ref);
});

/// Provider for current project
final currentProjectProvider = Provider<ProjectModel?>((ref) {
  return ref.watch(projectProvider).currentProject;
});

/// Provider for tracks in the current project
final tracksProvider = Provider<List<TrackModel>>((ref) {
  final project = ref.watch(currentProjectProvider);
  return project?.tracks ?? [];
});

/// Provider for media assets in the current project
final mediaAssetsProvider = Provider<List<MediaAssetModel>>((ref) {
  final project = ref.watch(currentProjectProvider);
  return project?.mediaAssets ?? [];
});
