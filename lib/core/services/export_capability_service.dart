import 'dart:io';

import 'package:flutter/services.dart';

import '../../src/rust/api/bridge_api.dart';

/// Device-advertised support is a preflight, never a real-time encoding promise.
class ExportCapabilityService {
  static const _channel = MethodChannel('com.editorspro/export_capabilities');

  static Future<void> validate(BridgeExportSettings settings) async {
    if (!settings.fps.isFinite || settings.fps <= 0 || settings.fps > 240) {
      throw const FormatException(
          'Export frame rate must be between 1 and 240 fps.');
    }
    if (!Platform.isAndroid) return;
    final Map<String, dynamic>? response;
    try {
      response =
          await _channel.invokeMapMethod<String, dynamic>('inspectSettings', {
        'width': settings.width,
        'height': settings.height,
        'fps': settings.fps,
        'codec': settings.codec,
        'bitrateKbps': settings.bitrateKbps,
      });
    } on PlatformException catch (error) {
      throw StateError(
          'Could not verify this device encoder: ${error.message}');
    } on MissingPluginException {
      throw StateError(
          'Device encoder checking is unavailable. Restart the updated app.');
    }
    if (response?['supported'] != true) {
      throw StateError(response?['reason'] as String? ??
          'The device cannot confirm this export format. Choose a lower resolution or frame rate.');
    }
  }
}
