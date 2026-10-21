import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Storage integration service for Android SAF and MediaStore.
///
/// Provides methods for:
/// - Copying SAF content:// URIs to temp files the Rust engine can access
/// - Saving exported videos to the Android MediaStore (visible in gallery)
/// - Managing temporary files
/// - Checking available storage
///
/// Uses the platform channel `com.editorspro/storage`.
class StorageService {
  StorageService._();

  static const _channel = MethodChannel('com.editorspro/storage');

  /// Returns the Android video MIME type supported by the Gallery save path.
  static String? videoMimeTypeForPath(String filePath) {
    switch (p.extension(filePath).toLowerCase()) {
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.webm':
        return 'video/webm';
      case '.avi':
        return 'video/x-msvideo';
      default:
        return null;
    }
  }

  /// Copy a content:// URI to a temporary file.
  ///
  /// The Rust engine can only read file:// paths, so content from
  /// SAF file pickers must be copied first.
  ///
  /// Returns the absolute path of the temp file, or null on error.
  static Future<String?> copyContentUriToTempFile(String uri) async {
    try {
      final path = await _channel.invokeMethod<String>(
        'copyContentUriToTempFile',
        {'uri': uri},
      );
      return path;
    } on PlatformException {
      return null;
    }
  }

  /// Get the display name from a content:// URI.
  static Future<String?> getFileName(String uri) async {
    try {
      final name = await _channel.invokeMethod<String>(
        'getFileName',
        {'uri': uri},
      );
      return name;
    } on PlatformException {
      return null;
    }
  }

  /// Get the file size from a content:// URI.
  static Future<int> getFileSize(String uri) async {
    try {
      final size = await _channel.invokeMethod<int>(
        'getFileSize',
        {'uri': uri},
      );
      return size ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  /// Save an exported video to the Android MediaStore.
  ///
  /// The video will appear in the Movies/EDITORS-PRO/ directory
  /// and be visible in the gallery and file manager.
  ///
  /// Returns the content:// URI of the saved video, or null on error.
  static Future<String?> saveToMediaStore({
    required String filePath,
    required String displayName,
    String mimeType = 'video/mp4',
  }) async {
    try {
      final uri = await _channel.invokeMethod<String>(
        'saveToMediaStore',
        {
          'filePath': filePath,
          'displayName': displayName,
          'mimeType': mimeType,
        },
      );
      return uri;
    } on PlatformException {
      return null;
    }
  }

  /// Clean up temporary files in the engine_media cache.
  static Future<void> cleanupTempFiles() async {
    try {
      await _channel.invokeMethod<void>('cleanupTempFiles');
    } on PlatformException {
      // Ignore
    }
  }

  /// Get the total size of temporary files in bytes.
  static Future<int> getTempFilesSize() async {
    try {
      final size = await _channel.invokeMethod<int>('getTempFilesSize');
      return size ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  /// Get available storage space in bytes.
  static Future<int> getAvailableStorageBytes() async {
    try {
      final bytes =
          await _channel.invokeMethod<int>('getAvailableStorageBytes');
      return bytes ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  /// Delete a file from the MediaStore by its content URI.
  ///
  /// Only works for files that the app created.
  static Future<bool> deleteFromMediaStore(String uri) async {
    try {
      final deleted = await _channel.invokeMethod<bool>(
        'deleteFromMediaStore',
        {'uri': uri},
      );
      return deleted ?? false;
    } on PlatformException {
      return false;
    }
  }
}
