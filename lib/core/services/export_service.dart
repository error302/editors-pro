import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service that manages the Android foreground service for video export.
///
/// This service ensures that video encoding continues even when the
/// app is minimized, by using Android's foreground service API. It also
/// manages the notification that shows export progress.
///
/// Usage:
/// ```dart
/// final service = ExportForegroundService();
/// await service.start();
/// // ... during export:
/// service.updateProgress(50, 'Encoding');
/// // ... when complete:
/// await service.complete('/path/to/file.mp4', '42.3MB');
/// ```
class ExportForegroundService {
  ExportForegroundService._();
  static final ExportForegroundService instance = ExportForegroundService._();

  static const _channel = MethodChannel('com.editorspro/editors_pro/export');

  @visibleForTesting
  bool? androidPlatformOverride;

  bool get _isAndroid => androidPlatformOverride ?? Platform.isAndroid;

  bool _isRunning = false;

  /// Whether the foreground service is currently running.
  bool get isRunning => _isRunning;

  /// Start the export foreground service.
  ///
  /// This creates a persistent notification and elevates the service
  /// priority so that Android doesn't kill the encoding process when
  /// the app is minimized.
  Future<void> start() async {
    if (_isRunning) return;
    if (!_isAndroid) return;

    try {
      await _channel.invokeMethod('startExport');
      _isRunning = true;
    } on PlatformException catch (e) {
      // On Android 12+, foreground service restrictions may prevent
      // starting from background. This is a best-effort operation.
      // The export will still work without the foreground service;
      // it just may be killed if the app is minimized for too long.
      print('ExportForegroundService.start failed: ${e.message}');
    }
  }

  /// Update the progress notification.
  ///
  /// [progress] should be 0-100.
  /// [stage] should be a human-readable string like "Encoding" or "Finalizing".
  Future<void> updateProgress(int progress, String stage) async {
    if (!_isRunning || !_isAndroid) return;

    try {
      await _channel.invokeMethod('updateProgress', {
        'progress': progress.clamp(0, 100),
        'stage': stage,
      });
    } on PlatformException catch (e) {
      print('ExportForegroundService.updateProgress failed: ${e.message}');
    }
  }

  /// Signal that the export is complete.
  ///
  /// This stops the foreground service and shows a completion notification.
  Future<void> complete(String filePath, String fileSize) async {
    if (!_isRunning || !_isAndroid) return;

    try {
      await _channel.invokeMethod('complete', {
        'filePath': filePath,
        'fileSize': fileSize,
      });
    } on PlatformException catch (e) {
      print('ExportForegroundService.complete failed: ${e.message}');
    }
    _isRunning = false;
  }

  /// Cancel the export and stop the foreground service.
  Future<void> cancel() async {
    if (!_isRunning || !_isAndroid) return;

    try {
      await _channel.invokeMethod('cancel');
    } on PlatformException catch (e) {
      print('ExportForegroundService.cancel failed: ${e.message}');
    }
    _isRunning = false;
  }
}
