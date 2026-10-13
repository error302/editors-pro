// Phase 1: Using plain Dart classes instead of freezed-generated code.
// When the build pipeline is set up, we'll switch to freezed with:
//   import 'package:freezed_annotation/freezed_annotation.dart';
//   part 'project_model.freezed.dart';
//   part 'project_model.g.dart';
import 'package:flutter/foundation.dart';

/// Project data model matching the Rust engine's Project struct
class ProjectModel {
  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;
  final int width;
  final int height;
  final double fps;
  final int durationMs;
  final List<TrackModel> tracks;
  final List<MediaAssetModel> mediaAssets;
  final String? thumbnailPath;
  final String? eppFilePath;

  const ProjectModel({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.width,
    required this.height,
    required this.fps,
    this.durationMs = 0,
    this.tracks = const [],
    this.mediaAssets = const [],
    this.thumbnailPath,
    this.eppFilePath,
  });

  ProjectModel copyWith({
    String? id,
    String? name,
    int? createdAt,
    int? updatedAt,
    int? width,
    int? height,
    double? fps,
    int? durationMs,
    List<TrackModel>? tracks,
    List<MediaAssetModel>? mediaAssets,
    String? thumbnailPath,
    String? eppFilePath,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      durationMs: durationMs ?? this.durationMs,
      tracks: tracks ?? this.tracks,
      mediaAssets: mediaAssets ?? this.mediaAssets,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      eppFilePath: eppFilePath ?? this.eppFilePath,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          width == other.width &&
          height == other.height &&
          fps == other.fps &&
          durationMs == other.durationMs &&
          listEquals(tracks, other.tracks) &&
          listEquals(mediaAssets, other.mediaAssets) &&
          thumbnailPath == other.thumbnailPath &&
          eppFilePath == other.eppFilePath;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        createdAt,
        updatedAt,
        width,
        height,
        fps,
        durationMs,
        Object.hashAll(tracks),
        Object.hashAll(mediaAssets),
        thumbnailPath,
        eppFilePath,
      );
}

/// Track data model
class TrackModel {
  final String id;
  final String name;
  final TrackType trackType;
  final List<ClipModel> clips;
  final bool locked;
  final bool visible;
  final double volume;
  final int orderIndex;

  const TrackModel({
    required this.id,
    required this.name,
    required this.trackType,
    this.clips = const [],
    this.locked = false,
    this.visible = true,
    this.volume = 1.0,
    this.orderIndex = 0,
  });

  TrackModel copyWith({
    String? id,
    String? name,
    TrackType? trackType,
    List<ClipModel>? clips,
    bool? locked,
    bool? visible,
    double? volume,
    int? orderIndex,
  }) {
    return TrackModel(
      id: id ?? this.id,
      name: name ?? this.name,
      trackType: trackType ?? this.trackType,
      clips: clips ?? this.clips,
      locked: locked ?? this.locked,
      visible: visible ?? this.visible,
      volume: volume ?? this.volume,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }
}

/// Track type enum
enum TrackType {
  video,
  audio,
  text,
  effect,
}

/// Clip data model
class ClipModel {
  final String id;
  final String assetId;
  final int startMs;
  final int durationMs;
  final int trimStartMs;
  final int trimEndMs;
  final double speed;
  final double opacity;
  final List<EffectModel> effects;
  final TransitionModel? transitionIn;
  final TransitionModel? transitionOut;

  /// Phase E.14: whether this clip is locked (cannot be moved, trimmed,
  /// split, or deleted). A small lock icon appears on locked clips in
  /// the timeline. Useful for protecting key clips (e.g., the opening
  /// title or the closing logo) from accidental edits.
  final bool locked;

  const ClipModel({
    required this.id,
    required this.assetId,
    required this.startMs,
    required this.durationMs,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.speed = 1.0,
    this.opacity = 1.0,
    this.effects = const [],
    this.transitionIn,
    this.transitionOut,
    this.locked = false,
  });

  ClipModel copyWith({
    String? id,
    String? assetId,
    int? startMs,
    int? durationMs,
    int? trimStartMs,
    int? trimEndMs,
    double? speed,
    double? opacity,
    List<EffectModel>? effects,
    TransitionModel? transitionIn,
    TransitionModel? transitionOut,
    bool? locked,
  }) {
    return ClipModel(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      startMs: startMs ?? this.startMs,
      durationMs: durationMs ?? this.durationMs,
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: trimEndMs ?? this.trimEndMs,
      speed: speed ?? this.speed,
      opacity: opacity ?? this.opacity,
      effects: effects ?? this.effects,
      transitionIn: transitionIn ?? this.transitionIn,
      transitionOut: transitionOut ?? this.transitionOut,
      locked: locked ?? this.locked,
    );
  }
}

/// Effect model for clip effects
class EffectModel {
  final String id;
  final String name;
  final String effectType;
  final bool enabled;
  final int order;
  final List<EffectParameterModel> parameters;

  const EffectModel({
    required this.id,
    required this.name,
    required this.effectType,
    this.enabled = true,
    this.order = 0,
    this.parameters = const [],
  });
}

/// Effect parameter model
class EffectParameterModel {
  final String name;
  final String displayName;
  final double value;
  final double minValue;
  final double maxValue;
  final double defaultValue;
  final double step;

  const EffectParameterModel({
    required this.name,
    required this.displayName,
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.defaultValue,
    required this.step,
  });
}

/// Transition model for clip transitions
class TransitionModel {
  final String id;
  final String transitionType;
  final int durationMs;
  final String fromClipId;
  final String toClipId;

  const TransitionModel({
    required this.id,
    required this.transitionType,
    required this.durationMs,
    required this.fromClipId,
    required this.toClipId,
  });
}

/// Media asset data model
class MediaAssetModel {
  final String id;
  final String filePath;
  final String fileName;
  final MediaType mediaType;
  final int? durationMs;
  final int? width;
  final int? height;
  final int fileSizeBytes;
  final String? codec;
  final int? bitrate;
  final String? thumbnailPath;

  const MediaAssetModel({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.mediaType,
    this.durationMs,
    this.width,
    this.height,
    this.fileSizeBytes = 0,
    this.codec,
    this.bitrate,
    this.thumbnailPath,
  });
}

/// Media type enum
enum MediaType {
  video,
  audio,
  image,
}
