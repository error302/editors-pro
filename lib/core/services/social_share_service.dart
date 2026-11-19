import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

/// App handoffs only. These values never authorize or perform a social post.
enum SocialShareTarget {
  youtube('YouTube'),
  tiktok('TikTok'),
  instagram('Instagram'),
  facebook('Facebook'),
  x('X'),
  more('More share options');

  const SocialShareTarget(this.label);

  final String label;
}

/// None of these results is proof of uploading or publication.
enum SocialShareOutcome { handoffStarted, dismissed, unknown }

typedef GenericVideoShare = Future<ShareResult> Function(
  List<XFile> files,
  String caption,
  Rect? origin,
);

class SocialShareService {
  SocialShareService({bool? isAndroid, GenericVideoShare? genericShare})
      : _isAndroid = isAndroid ?? Platform.isAndroid,
        _genericShare = genericShare ?? _shareGeneric;

  static const _channel = MethodChannel('com.editorspro/social_share');
  final bool _isAndroid;
  final GenericVideoShare _genericShare;

  Future<Set<SocialShareTarget>> availableTargets() async {
    if (!_isAndroid) return {SocialShareTarget.more};
    final available =
        await _channel.invokeListMethod<String>('getAvailableTargets');
    if (available == null) {
      throw StateError('The sharing service did not report app availability.');
    }
    return {
      for (final target in SocialShareTarget.values)
        if (available.contains(target.name)) target,
      SocialShareTarget.more,
    };
  }

  /// Caller supplies a completed export, never an output still being encoded.
  /// Android revalidates the source while staging its private cache copy.
  Future<SocialShareOutcome> share({
    required String filePath,
    required SocialShareTarget target,
    String caption = '',
    Rect? sharePositionOrigin,
  }) async {
    final file = File(filePath);
    final stat = await file.stat();
    if (filePath.isEmpty || stat.type != FileSystemEntityType.file) {
      throw StateError('The exported video is unavailable. Export it again.');
    }
    if (stat.size <= 0) {
      throw StateError('The exported video is empty. Export it again.');
    }
    const videoTypes = {
      '.mp4': 'video/mp4',
      '.m4v': 'video/x-m4v',
      '.mov': 'video/quicktime',
      '.webm': 'video/webm',
      '.avi': 'video/x-msvideo',
      '.mkv': 'video/x-matroska',
    };
    final mimeType = videoTypes[p.extension(filePath).toLowerCase()];
    if (mimeType == null) {
      throw ArgumentError(
        'This export is not a supported video file. Export MP4 to share.',
      );
    }
    if (_isAndroid) {
      final acknowledgement =
          await _channel.invokeMethod<String>('shareVideo', {
        'filePath': filePath,
        'target': target.name,
        'caption': caption,
      });
      if (acknowledgement != 'handoff_started') {
        throw StateError(
          'The sharing service did not confirm opening another app.',
        );
      }
      return SocialShareOutcome.handoffStarted;
    }
    if (target != SocialShareTarget.more) {
      throw UnsupportedError(
        'App shortcuts require Android. Use More share options.',
      );
    }
    final result = await _genericShare(
      [XFile(filePath, mimeType: mimeType)],
      caption,
      sharePositionOrigin,
    );
    return switch (result.status) {
      ShareResultStatus.success => SocialShareOutcome.handoffStarted,
      ShareResultStatus.dismissed => SocialShareOutcome.dismissed,
      ShareResultStatus.unavailable => SocialShareOutcome.unknown,
    };
  }

  static Future<ShareResult> _shareGeneric(
    List<XFile> files,
    String caption,
    Rect? origin,
  ) =>
      Share.shareXFiles(
        files,
        text: caption.isEmpty ? null : caption,
        sharePositionOrigin: origin,
      );
}
