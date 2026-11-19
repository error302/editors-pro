import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/project_model.dart';
import '../../src/rust/api/bridge_api.dart' as bridge;
import '../constants/app_constants.dart';
import 'engine_service.dart';

/// The cache describes the saved edited timeline, never an imported source clip.
class ProjectPreview {
  const ProjectPreview({
    required this.key,
    required this.durationMs,
    required this.previewDurationMs,
    this.coverPath,
    this.videoPath,
  });
  final String key;
  final String? coverPath;
  final String? videoPath;
  final int durationMs;
  final int previewDurationMs;
  bool get isEmpty => durationMs == 0;
}

abstract class ProjectPreviewBackend {
  Future<Map<String, dynamic>> inspect(String path);
  Future<Map<String, dynamic>> start(String path, String cover, String? video);
  Future<Map<String, dynamic>> status(String jobId);
  Future<void> release(String jobId);
}

class _NativePreviewBackend implements ProjectPreviewBackend {
  @override
  Future<Map<String, dynamic>> inspect(String path) =>
      bridge.inspectSavedProject(projectPath: path);
  @override
  Future<Map<String, dynamic>> start(
    String path,
    String cover,
    String? video,
  ) =>
      bridge.startProjectPreview(
        projectPath: path,
        coverPath: cover,
        videoPath: video,
      );
  @override
  Future<Map<String, dynamic>> status(String jobId) =>
      bridge.projectPreviewStatus(jobId: jobId);
  @override
  Future<void> release(String jobId) =>
      bridge.releaseProjectPreview(jobId: jobId);
}

class ProjectPreviewService {
  ProjectPreviewService({
    ProjectPreviewBackend? backend,
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? cacheDirectory,
    this.pollInterval = const Duration(milliseconds: 180),
  })  : _backend = backend ?? _NativePreviewBackend(),
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory;

  // Regenerate covers/previews produced before frame-accurate seeking.
  static const rendererVersion = 'saved-timeline-v4-accurate-seek-480p-12fps-10sec';
  final ProjectPreviewBackend _backend;
  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory> Function() _cacheDirectory;
  final Duration pollInterval;
  final Map<String, Future<ProjectPreview>> _pending = {};
  final Map<String, Future<void>> _inputWrites = {};
  final Map<String, int> _epochs = {};
  Future<void> _renderQueue = Future<void>.value();

  Future<Directory> _projectCache(String id) async {
    final cache = await _cacheDirectory();
    return Directory(
      p.join(
        cache.path,
        'project_previews',
        sha256.convert(utf8.encode(id)).toString().substring(0, 24),
      ),
    );
  }

  /// One render runs at a time, independently of the editing engine's queue.
  Future<ProjectPreview> ensure(
    ProjectModel project, {
    bool playable = false,
    void Function(ProjectPreview)? onCover,
  }) async {
    if (_backend is _NativePreviewBackend &&
        !EngineService.instance.isInitialized) {
      throw StateError(
        'The editing engine is not available to prepare project previews.',
      );
    }
    final epoch = _epochs[project.id] ?? 0;
    final docs = await _documentsDirectory();
    final projects = p.normalize(p.join(docs.path, AppConstants.projectsDir));
    final savedPath = p.normalize(
      project.eppFilePath ?? p.join(projects, '${project.id}.epp'),
    );
    if (!p.isWithin(projects, savedPath)) {
      throw StateError('The saved project path is invalid.');
    }
    final saved = File(savedPath);
    if (!await saved.exists()) {
      throw StateError(
        project.eppFilePath == null
            ? 'Save the project to create a preview.'
            : 'The saved project file is missing.',
      );
    }
    final bytes = await saved.readAsBytes();
    final eppHash = sha256.convert(bytes).toString();
    final root = await _projectCache(project.id);
    await root.create(recursive: true);
    // A unique immutable input prevents a simultaneous save changing the render.
    final input = File(p.join(root.path, 'i-${eppHash.substring(0, 32)}.epp'));
    final inputWrite = _inputWrites.putIfAbsent(input.path, () async {
      // Validate and repair inside the shared write operation so concurrent
      // requests cannot remove a snapshot another request just repaired.
      if (await input.exists()) {
        if (sha256.convert(await input.readAsBytes()).toString() == eppHash)
          return;
        await input.delete();
      }
      final temporary = File('${input.path}.${const Uuid().v4()}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      if (await input.exists()) {
        await temporary.delete();
      } else {
        await temporary.rename(input.path);
      }
    });
    try {
      await inputWrite;
    } finally {
      if (identical(_inputWrites[input.path], inputWrite)) {
        final _ = _inputWrites.remove(input.path);
      }
    }
    final info = await _backend.inspect(input.path);
    final paths = (info['source_paths'] as List).cast<String>()..sort();
    final fingerprints = <Object>[];
    for (final path in paths) {
      fingerprints.add(await _sourceFingerprint(path));
    }
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              rendererVersion,
              eppHash,
              fingerprints,
            ]),
          ),
        )
        .toString();
    final duration = (info['duration_ms'] as num).toInt();
    if ((_epochs[project.id] ?? 0) != epoch ||
        !await saved.exists() ||
        sha256.convert(await saved.readAsBytes()).toString() != eppHash) {
      throw StateError(
        'The project changed while preparing its preview. Try again.',
      );
    }
    final folder = Directory(p.join(root.path, key.substring(0, 32)));
    final cached = await _readCache(folder, key, duration, playable);
    if (cached != null) return cached;
    final pendingKey = '${project.id}:$key:$playable';
    final existing = _pending[pendingKey];
    if (existing != null) return existing;
    final completer = Completer<ProjectPreview>();
    _pending[pendingKey] = completer.future;
    final previous = _renderQueue;
    _renderQueue = completer.future.then<void>((_) {}, onError: (Object _) {});
    unawaited(() async {
      try {
        await previous;
        if ((_epochs[project.id] ?? 0) != epoch) {
          throw StateError('Project changed. Try the preview again.');
        }
        final again = await _readCache(folder, key, duration, playable);
        final result = again ??
            await _render(
              project,
              epoch,
              input,
              saved,
              eppHash,
              fingerprints,
              paths,
              folder,
              key,
              duration,
              playable,
              onCover,
            );
        completer.complete(result);
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        final _ = _pending.remove(pendingKey);
      }
    }());
    return completer.future;
  }

  Future<ProjectPreview> _render(
    ProjectModel project,
    int epoch,
    File input,
    File saved,
    String eppHash,
    List<Object> fingerprints,
    List<String> paths,
    Directory folder,
    String key,
    int duration,
    bool playable,
    void Function(ProjectPreview)? onCover,
  ) async {
    if (duration == 0) {
      return ProjectPreview(key: key, durationMs: 0, previewDurationMs: 0);
    }
    await folder.create(recursive: true);
    final work = await folder.createTemp('work-');
    final cover = File(p.join(work.path, 'cover.png'));
    final video = File(p.join(work.path, 'preview.mp4'));
    String? jobId;
    var finished = false;
    try {
      var status = await _backend.start(
        input.path,
        cover.path,
        playable ? video.path : null,
      );
      jobId = status['job_id'] as String;
      var notified = false;
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (true) {
        if (status['cover_ready'] == true &&
            !notified &&
            await cover.exists()) {
          notified = true;
          onCover?.call(
            ProjectPreview(
              key: key,
              coverPath: cover.path,
              durationMs: duration,
              previewDurationMs: duration.clamp(0, 10000),
            ),
          );
        }
        if (status['finished'] == true) {
          finished = true;
          if (status['error'] != null) {
            throw StateError(status['error'] as String);
          }
          break;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException(
            'Preview is taking too long. Try again shortly.',
          );
        }
        await Future<void>.delayed(pollInterval);
        status = await _backend.status(jobId);
      }
      if (status['cover_ready'] != true ||
          (playable && status['video_ready'] != true)) {
        throw StateError('The project preview did not finish.');
      }
      if ((_epochs[project.id] ?? 0) != epoch ||
          !await saved.exists() ||
          sha256.convert(await saved.readAsBytes()).toString() != eppHash) {
        throw StateError(
          'The project changed while preparing its preview. Try again.',
        );
      }
      final currentSources = <Object>[];
      for (final path in paths) {
        currentSources.add(await _sourceFingerprint(path));
      }
      if (jsonEncode(currentSources) != jsonEncode(fingerprints)) {
        throw StateError(
          'Source media changed while preparing the preview. Try again.',
        );
      }
      final finalCover = File(p.join(folder.path, 'cover.png'));
      final finalVideo = File(p.join(folder.path, 'preview.mp4'));
      await _publish(cover, finalCover);
      if (playable) await _publish(video, finalVideo);
      final manifest = <String, dynamic>{
        'key': key,
        'cover_sha256': await _digest(finalCover),
        if (playable) 'video_sha256': await _digest(finalVideo),
      };
      final temporary = File(p.join(work.path, 'manifest.json'));
      await temporary.writeAsString(jsonEncode(manifest), flush: true);
      await _publish(temporary, File(p.join(folder.path, 'manifest.json')));
      return ProjectPreview(
        key: key,
        coverPath: finalCover.path,
        videoPath: playable ? finalVideo.path : null,
        durationMs: duration,
        previewDurationMs: duration.clamp(0, 10000),
      );
    } finally {
      if (jobId != null && finished) {
        try {
          await _backend.release(jobId);
        } catch (_) {/* bounded native retention */}
      }
      // Do not delete files an unfinished worker may still be writing.
      if (finished || jobId == null) {
        if (await work.exists()) await work.delete(recursive: true);
      }
    }
  }

  Future<ProjectPreview?> _readCache(
    Directory folder,
    String key,
    int duration,
    bool playable,
  ) async {
    try {
      final manifest = jsonDecode(
        await File(p.join(folder.path, 'manifest.json')).readAsString(),
      ) as Map;
      final cover = File(p.join(folder.path, 'cover.png'));
      final video = File(p.join(folder.path, 'preview.mp4'));
      if (manifest['key'] != key ||
          manifest['cover_sha256'] != await _digest(cover)) {
        return null;
      }
      if (playable &&
          (manifest['video_sha256'] == null ||
              manifest['video_sha256'] != await _digest(video))) {
        return null;
      }
      return ProjectPreview(
        key: key,
        coverPath: cover.path,
        videoPath: playable ? video.path : null,
        durationMs: duration,
        previewDurationMs: duration.clamp(0, 10000),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String> _digest(File file) async {
    if (await file.length() == 0) throw StateError('Preview file is empty.');
    return (await sha256.bind(file.openRead()).first).toString();
  }

  static Future<Object> _sourceFingerprint(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Source media is missing: ${p.basename(path)}');
    }
    final stat = await file.stat();
    // Include sampled content as well as size/timestamps to detect replacement.
    final handle = await file.open();
    try {
      final first = await handle.read(65536);
      await handle.setPosition((stat.size - 65536).clamp(0, stat.size));
      final last = await handle.read(65536);
      return [
        path,
        stat.size,
        stat.modified.microsecondsSinceEpoch,
        stat.changed.microsecondsSinceEpoch,
        sha256.convert([...first, ...last]).toString(),
      ];
    } finally {
      await handle.close();
    }
  }

  static Future<void> _publish(File source, File destination) async {
    if (await source.length() == 0) {
      throw StateError('Preview output is empty.');
    }
    // rename replaces atomically on supported mobile filesystems.
    await source.rename(destination.path);
  }

  /// Invalidates work in flight after a save; old keys cannot become current.
  void invalidate(String projectId) {
    _epochs[projectId] = (_epochs[projectId] ?? 0) + 1;
  }

  Future<void> removeProject(String projectId) async {
    invalidate(projectId);
    // Native workers own their scratch directories. Defer deletion until queued work settles.
    await _renderQueue;
    final directory = await _projectCache(projectId);
    if (await directory.exists()) await directory.delete(recursive: true);
    _inputWrites.removeWhere((path, _) => p.isWithin(directory.path, path));
  }
}

final projectPreviewServiceProvider =
    Provider<ProjectPreviewService>((ref) => ProjectPreviewService());
