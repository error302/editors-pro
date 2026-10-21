import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/engine_service.dart';

/// Provider that asynchronously initializes and returns the
/// [EditorsProEngineApi] singleton.
///
/// The first subscriber triggers engine initialization. Subsequent
/// subscribers receive the same API instance.
final engineApiProvider = FutureProvider<EditorsProEngineApi>((ref) async {
  final service = EngineService.instance;
  final success = await service.initialize();
  if (!success) {
    throw Exception('Failed to initialize the Rust engine');
  }
  return service.api;
});

/// Provider that reads the current [ProjectInfo] from the engine.
///
/// Returns `null` when no project is open or when the engine has not
/// been initialized yet.
final projectInfoProvider = FutureProvider<ProjectInfo?>((ref) async {
  final api = await ref.watch(engineApiProvider.future);
  return api.getProjectInfo();
});

/// Provider that reads the timeline duration (in ms) from the engine.
///
/// Returns `0` when no project is open.
final timelineDurationProvider = FutureProvider<int>((ref) async {
  final api = await ref.watch(engineApiProvider.future);
  final duration = await api.getTimelineDuration();
  return duration.toInt();
});

/// A notifier that allows callers to manually invalidate the
/// project-info and duration caches after mutating the engine state
/// (e.g. after adding a clip or splitting).
class EngineStateRefresher extends StateNotifier<void> {
  EngineStateRefresher(this._ref) : super(null);

  final Ref _ref;

  /// Invalidate cached project info and timeline duration so that
  /// downstream widgets re-read from the engine.
  void refresh() {
    _ref.invalidate(projectInfoProvider);
    _ref.invalidate(timelineDurationProvider);
  }
}

/// Provider for the engine state refresher.
final engineStateRefresherProvider =
    StateNotifierProvider<EngineStateRefresher, void>((ref) {
  return EngineStateRefresher(ref);
});
