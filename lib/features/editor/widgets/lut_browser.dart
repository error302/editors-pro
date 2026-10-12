import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../src/rust/api/bridge_api.dart';

/// Phase F: LUT Browser panel.
///
/// Lets the user browse, import, and apply .cube LUTs to the current clip.
/// Calls `lut_load_cube_content` to parse a .cube file (returned as a
/// serializable struct) and `apply_lut_to_frame` (a future method) to
/// preview the LUT on the current frame.
///
/// The amateur move is to stack 3 creative LUTs hoping one looks right.
/// The pro move is: technical LUT first (Log→Rec.709), then grade, then
/// creative LUT last. See persona/skills/lut-management/SKILL.md.
class LutBrowser extends StatefulWidget {
  /// Called with the parsed LUT data when the user picks one.
  final void Function(Map<String, dynamic> lutData) onLutSelected;

  /// Called when the user adjusts the LUT intensity (0.0–1.0).
  final void Function(double intensity) onIntensityChanged;

  /// Initial intensity. Defaults to 1.0 (full LUT).
  final double initialIntensity;

  const LutBrowser({
    super.key,
    required this.onLutSelected,
    required this.onIntensityChanged,
    this.initialIntensity = 1.0,
  });

  @override
  State<LutBrowser> createState() => _LutBrowserState();
}

class _LutBrowserState extends State<LutBrowser> {
  late double _intensity;
  String? _loadedLutName;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _intensity = widget.initialIntensity;
  }

  Future<void> _importLut() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['cube', '3dl'],
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final content = await File(filePath).readAsString();
      final lutData = await lutLoadCubeContent(content: content);

      widget.onLutSelected(lutData);
      setState(() => _loadedLutName = result.files.single.name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('LUT import failed: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LUT Browser', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppTheme.spacing4),
        Text(
          'Technical LUT first (Log→Rec.709), then grade, then creative LUT last.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _importLut,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_upload_outlined),
              label: const Text('Import .cube file'),
            ),
            const SizedBox(width: AppTheme.spacing8),
            if (_loadedLutName != null)
              Expanded(
                child: Text(
                  'Loaded: $_loadedLutName',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing16),
        Text(
          'Intensity',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Slider(
          value: _intensity,
          min: 0.0,
          max: 1.0,
          divisions: 100,
          label: '${(_intensity * 100).round()}%',
          onChanged: (v) {
            setState(() => _intensity = v);
            widget.onIntensityChanged(v);
          },
        ),
        const SizedBox(height: AppTheme.spacing8),
        Text(
          'Lower intensity = blend with original. 100% = full LUT.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Safety reminder — the persona pins "legal range" verification after LUT
        Container(
          padding: const EdgeInsets.all(AppTheme.spacing8),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.amber, size: 20),
              const SizedBox(width: AppTheme.spacing8),
              Expanded(
                child: Text(
                  'Verify legal range after LUT in full/ultra mode. '
                  'Open color scopes to check.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
