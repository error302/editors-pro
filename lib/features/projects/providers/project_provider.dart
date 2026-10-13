import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/engine_service.dart';
import '../../../core/services/project_repository.dart';
import '../../../core/services/project_snapshots.dart';
import '../../../data/models/project_model.dart';

/// Current project state
class ProjectState {
  final ProjectModel? currentProject;
  final List<ProjectModel> recentProjects;
  final bool isLoading;
  final String? error;

  const ProjectState({
    this.currentProject,
    this.recentProjects = const [],
    this.isLoading = false,
    this.error,
  });

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
  final Ref _ref;
  ProjectNotifier(this._ref) : super(const ProjectState());

  ProjectRepository get _repo => _ref.read(projectRepositoryProvider);

  /// Load all projects from the database on app startup.
  Future<void> loadProjects() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final projects = await _repo.getAllProjects();
      state = state.copyWith(
        recentProjects: projects,
        isLoading: false,
      );
    } catch (e) {
      developer.log('loadProjects failed: $e', name: 'ProjectNotifier');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Create a new project — persists to database and initializes in the
  /// Rust engine.
  Future<ProjectModel?> createProject(String name,
      {int width = 1920, int height = 1080, double fps = 30.0}) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final project = await _repo.createProject(name,
          width: width, height: height, fps: fps);

      state = state.copyWith(
        currentProject: project,
        recentProjects: [project, ...state.recentProjects],
        isLoading: false,
      );
      await syncFromEngine();
      return project;
    } catch (e) {
      developer.log('createProject failed: $e', name: 'ProjectNotifier');
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  /// Open an existing project — loads from DB and restores in engine.
  Future<bool> openProject(ProjectModel project) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
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
    state = state.copyWith(currentProject: null);
  }

  /// Delete a project — removes from DB and engine.
  Future<void> deleteProject(String projectId) async {
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
  Future<int> deleteAllProjects() async {
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

  /// Phase F.2: Duplicate a project — creates a new project with the same
  /// name + " (copy)" suffix, same dimensions/fps, and copies the media
  /// asset references (file paths point to the same source files; no
  /// media duplication on disk). The new project opens empty (no timeline
  /// clips copied) — the user can then re-link or copy clip ranges as needed.
  ///
  /// This is the workflow pattern: duplicate to fork a delivery variant
  /// (e.g., "Reel v3 (copy)" → edit down for a 9:16 social cut) without
  /// losing the original.
  Future<String> duplicateProject(String projectId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final original = await _repo.getProject(projectId);
      if (original == null) {
        throw Exception('Project not found: $projectId');
      }
      final newName = '${original.name} (copy)';
      final duplicate = await _repo.createProject(
        newName,
        width: original.width,
        height: original.height,
        fps: original.fps,
      );
      // Copy media asset references (files stay where they are on disk)
      for (final asset in original.mediaAssets) {
        await _repo.addMediaAsset(duplicate.id, asset);
      }
      final updatedRecent = [duplicate, ...state.recentProjects];
      state = state.copyWith(
        recentProjects: updatedRecent,
        isLoading: false,
      );
      return duplicate.id;
    } catch (e) {
      developer.log('duplicateProject failed: $e', name: 'ProjectNotifier');
      state = state.copyWith(isLoading: false, error: 'Duplicate failed: $e');
      rethrow;
    }
  }

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
  Future<bool> saveCurrentProject() async {
    final project = state.currentProject;
    if (project == null) return false;
    try {
      await _repo.updateProject(project);
      await _repo.saveProjectToEngine(project);
      return true;
    } catch (e) {
      developer.log('saveCurrentProject failed: $e', name: 'ProjectNotifier');
      return false;
    }
  }

  /// Save a project and return its `.epp` timeline-backup path for sharing.
  Future<String?> prepareProjectExport(ProjectModel project) async {
    final currentProject = state.currentProject;
    try {
      if (currentProject?.id == project.id) {
        if (!await saveCurrentProject()) return null;
      } else {
        if (currentProject != null && !await saveCurrentProject()) return null;

        final exportProject = await _repo.getProject(project.id) ?? project;
        try {
          await _repo.activateProjectInEngine(exportProject);
          await _repo.saveProjectToEngine(exportProject);
        } finally {
          if (currentProject != null) {
            await _repo.activateProjectInEngine(currentProject);
          }
        }
      }

      final savedProject = await _repo.getProject(project.id);
      return savedProject?.eppFilePath;
    } catch (error, stackTrace) {
      developer.log(
        'prepareProjectExport failed',
        name: 'ProjectNotifier',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Phase E.15: create a version-history snapshot of the current project.
  ///
  /// Reads the current `.epp` file from the engine and stores a copy
  /// in the per-project snapshots directory. The user can later restore
  /// to this snapshot via the snapshot browser UI.
  ///
  /// Returns the snapshot ID, or `null` on failure.
  Future<String?> createSnapshot() async {
    if (state.currentProject == null) return null;
    try {
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

  /// Phase E.15: list all snapshots for the current project.
  Future<List<ProjectSnapshot>> listSnapshots() async {
    if (state.currentProject == null) return [];
    return ProjectSnapshots.listForProject(state.currentProject!.id);
  }

  /// Sync the project model with the latest engine state (after
  /// engine mutations like addClip, split, etc.).
  Future<void> syncFromEngine() async {
    if (!EngineService.instance.isInitialized || state.currentProject == null)
      return;
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
                effects: existing?.effects ?? const [],
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
