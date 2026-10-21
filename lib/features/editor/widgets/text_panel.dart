import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/project_model.dart';
import '../../projects/providers/project_provider.dart';
import '../providers/editor_provider.dart';

/// Text panel — displays text presets, input, style controls, and animation
/// options for adding text overlays to the timeline.
class TextPanel extends ConsumerStatefulWidget {
  const TextPanel({super.key});

  @override
  ConsumerState<TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends ConsumerState<TextPanel> {
  final _textController = TextEditingController(text: 'Your Text');
  String _selectedFont = 'Inter';
  double _fontSize = 36.0;
  String _selectedColor = '#FFFFFF';
  bool _isBold = false;
  bool _isItalic = false;
  String _selectedAnimation = 'None';
  bool _enableStroke = false;
  double _strokeWidth = 2.0;
  String _strokeColor = '#000000';
  bool _enableShadow = false;
  double _shadowBlur = 4.0;
  String _shadowColor = '#000000';
  List<Map<String, String>> _availableFonts = [];

  static const List<Map<String, String>> _defaultFonts = [
    {'name': 'Inter', 'family': 'Inter', 'style': 'Regular'},
    {'name': 'Roboto', 'family': 'Roboto', 'style': 'Regular'},
    {'name': 'Open Sans', 'family': 'Open Sans', 'style': 'Regular'},
    {'name': 'Lato', 'family': 'Lato', 'style': 'Regular'},
    {'name': 'Montserrat', 'family': 'Montserrat', 'style': 'Regular'},
    {
      'name': 'Playfair Display',
      'family': 'Playfair Display',
      'style': 'Regular',
    },
    {'name': 'Oswald', 'family': 'Oswald', 'style': 'Regular'},
    {'name': 'Raleway', 'family': 'Raleway', 'style': 'Regular'},
  ];

  static const List<Map<String, dynamic>> _textPresets = [
    {
      'name': 'Title',
      'description': 'Large bold text',
      'icon': Icons.title,
      'fontSize': 72.0,
    },
    {
      'name': 'Subtitle',
      'description': 'Medium text',
      'icon': Icons.subtitles,
      'fontSize': 36.0,
    },
    {
      'name': 'Caption',
      'description': 'Small text with background',
      'icon': Icons.closed_caption,
      'fontSize': 24.0,
    },
    {
      'name': 'Lower Third',
      'description': 'Name/title bar',
      'icon': Icons.text_fields,
      'fontSize': 28.0,
    },
  ];

  static const List<String> _animations = [
    'None',
    'Fade In',
    'Fade Out',
    'Typewriter',
    'Slide In',
    'Pop In',
  ];

  static const List<Map<String, String>> _presetColors = [
    {'name': 'White', 'hex': '#FFFFFF'},
    {'name': 'Black', 'hex': '#000000'},
    {'name': 'Red', 'hex': '#FF0000'},
    {'name': 'Green', 'hex': '#00FF00'},
    {'name': 'Blue', 'hex': '#0000FF'},
    {'name': 'Yellow', 'hex': '#FFFF00'},
    {'name': 'Cyan', 'hex': '#00FFFF'},
    {'name': 'Magenta', 'hex': '#FF00FF'},
    {'name': 'Orange', 'hex': '#FF8800'},
    {'name': 'Purple', 'hex': '#8800FF'},
    {'name': 'Pink', 'hex': '#FF0088'},
    {'name': 'Lime', 'hex': '#88FF00'},
  ];

  @override
  void initState() {
    super.initState();
    _loadFonts();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadFonts() async {
    try {
      final fonts = await ref.read(editorProvider.notifier).getAvailableFonts();
      if (mounted && fonts.isNotEmpty) {
        setState(() {
          _availableFonts = fonts
              .map(
                (f) => {
                  'name': f.name,
                  'family': f.family,
                  'style': f.style,
                },
              )
              .toList();
          if (_availableFonts.isNotEmpty) {
            _selectedFont = _availableFonts.first['family']!;
          }
        });
      } else {
        setState(() {
          _availableFonts = _defaultFonts;
        });
      }
    } catch (_) {
      // Fallback to default fonts
      setState(() {
        _availableFonts = _defaultFonts;
      });
    }
  }

  void _applyPreset(Map<String, dynamic> preset) {
    setState(() {
      _textController.text = preset['name'] as String;
      _fontSize = preset['fontSize'] as double;
      _isBold = preset['name'] == 'Title';
    });
  }

  Future<void> _addTextToTimeline() async {
    final project = ref.read(currentProjectProvider);
    if (project == null) return;

    // Find the text track
    final textTrack =
        project.tracks.where((t) => t.trackType == TrackType.text).firstOrNull;

    if (textTrack == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No text track found')),
        );
      }
      return;
    }

    // Calculate the start position
    final lastClipEnd = textTrack.clips.isEmpty
        ? 0
        : textTrack.clips
            .map((c) => c.startMs + c.durationMs)
            .reduce((a, b) => a > b ? a : b);

    const defaultDurationMs = 5000;

    // Build font family string with style suffixes for bold/italic
    var fontFamily = _selectedFont;
    if (_isBold) fontFamily += '-Bold';
    if (_isItalic) fontFamily += '-Italic';

    // Log selected animation for future engine-side implementation
    debugPrint('[TextPanel] Animation selected: $_selectedAnimation');

    await ref.read(editorProvider.notifier).addTextClip(
          trackId: textTrack.id,
          text: _textController.text,
          fontFamily: fontFamily,
          fontSize: _fontSize,
          colorHex: _selectedColor,
          positionX: 0.5,
          positionY: 0.5,
          startMs: lastClipEnd,
          durationMs: defaultDurationMs,
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${_textController.text}" to ${textTrack.name}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Text Presets ──────────────────────────────────
          _buildSectionLabel('PRESETS'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _textPresets.map((preset) {
              return _TextPresetChip(
                name: preset['name'] as String,
                icon: preset['icon'] as IconData,
                onTap: () => _applyPreset(preset),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // ─── Text Input ────────────────────────────────────
          _buildSectionLabel('TEXT'),
          const SizedBox(height: 6),
          TextField(
            controller: _textController,
            maxLines: 3,
            minLines: 2,
            style: context.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Enter your text...',
              hintStyle: const TextStyle(color: AppTheme.textDisabled),
              filled: true,
              fillColor: AppTheme.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Font Picker ────────────────────────────────────
          _buildSectionLabel('FONT'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedFont,
                isExpanded: true,
                icon: const Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
                style: context.textTheme.bodyMedium,
                dropdownColor: AppTheme.surfaceVariant,
                items: _availableFonts.map((font) {
                  return DropdownMenuItem<String>(
                    value: font['family'],
                    child: Text(
                      font['name']!,
                      style: TextStyle(
                        fontFamily: font['family'],
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedFont = value);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Style Controls ────────────────────────────────
          _buildSectionLabel('STYLE'),
          const SizedBox(height: 6),

          // Font size slider
          Row(
            children: [
              const Icon(
                Icons.format_size,
                size: 16,
                color: AppTheme.textDisabled,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 8.0,
                  max: 120.0,
                  divisions: 56,
                  onChanged: (value) => setState(() => _fontSize = value),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  _fontSize.round().toString(),
                  style: context.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Bold / Italic toggles
          Row(
            children: [
              _StyleToggleButton(
                icon: Icons.format_bold,
                label: 'B',
                isActive: _isBold,
                onTap: () => setState(() => _isBold = !_isBold),
              ),
              const SizedBox(width: 6),
              _StyleToggleButton(
                icon: Icons.format_italic,
                label: 'I',
                isActive: _isItalic,
                onTap: () => setState(() => _isItalic = !_isItalic),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ─── Color Picker ──────────────────────────────────
          _buildSectionLabel('COLOR'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _presetColors.map((color) {
              final hex = color['hex']!;
              final isSelected = _selectedColor == hex;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = hex),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _parseHexColor(hex),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : const Color(0xFF2A2A3E),
                      width: isSelected ? 2.5 : 1,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.black54)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // ─── Animation Selector ─────────────────────────────
          _buildSectionLabel('ANIMATION'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedAnimation,
                isExpanded: true,
                icon: const Icon(
                  Icons.animation,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                style: context.textTheme.bodyMedium,
                dropdownColor: AppTheme.surfaceVariant,
                items: _animations.map((anim) {
                  return DropdownMenuItem<String>(
                    value: anim,
                    child: Text(
                      anim,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedAnimation = value);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ─── Stroke / Outline ───────────────────────────────
          _buildSectionLabel('STROKE / OUTLINE'),
          const SizedBox(height: 6),
          Row(
            children: [
              Switch(
                value: _enableStroke,
                onChanged: (v) => setState(() => _enableStroke = v),
                activeThumbColor: AppTheme.primary,
              ),
              const Text('Enable Stroke', style: TextStyle(fontSize: 13)),
            ],
          ),
          if (_enableStroke) ...[
            Row(
              children: [
                const Text(
                  'Width',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                Expanded(
                  child: Slider(
                    value: _strokeWidth,
                    min: 0.5,
                    max: 10.0,
                    divisions: 19,
                    activeColor: AppTheme.primary,
                    label: _strokeWidth.toStringAsFixed(1),
                    onChanged: (v) => setState(() => _strokeWidth = v),
                  ),
                ),
                Text(
                  _strokeWidth.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
            Row(
              children: [
                const Text(
                  'Color',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    // Toggle between common stroke colors
                    final strokeColors = [
                      '#000000',
                      '#FFFFFF',
                      '#FF0000',
                      '#333333',
                    ];
                    final idx = strokeColors.indexOf(_strokeColor);
                    setState(
                      () => _strokeColor =
                          strokeColors[(idx + 1) % strokeColors.length],
                    );
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _parseHexColor(_strokeColor),
                      borderRadius: BorderRadius.circular(4),
                      border:
                          Border.all(color: AppTheme.textSecondary, width: 1),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // ─── Shadow ──────────────────────────────────────────
          _buildSectionLabel('SHADOW'),
          const SizedBox(height: 6),
          Row(
            children: [
              Switch(
                value: _enableShadow,
                onChanged: (v) => setState(() => _enableShadow = v),
                activeThumbColor: AppTheme.primary,
              ),
              const Text('Enable Shadow', style: TextStyle(fontSize: 13)),
            ],
          ),
          if (_enableShadow) ...[
            Row(
              children: [
                const Text(
                  'Blur',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                Expanded(
                  child: Slider(
                    value: _shadowBlur,
                    min: 0.0,
                    max: 20.0,
                    divisions: 20,
                    activeColor: AppTheme.primary,
                    label: _shadowBlur.toStringAsFixed(0),
                    onChanged: (v) => setState(() => _shadowBlur = v),
                  ),
                ),
                Text(
                  _shadowBlur.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
            Row(
              children: [
                const Text(
                  'Color',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    final shadowColors = [
                      '#000000',
                      '#333333',
                      '#1a1a2e',
                      '#0f0f23',
                    ];
                    final idx = shadowColors.indexOf(_shadowColor);
                    setState(
                      () => _shadowColor =
                          shadowColors[(idx + 1) % shadowColors.length],
                    );
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _parseHexColor(_shadowColor),
                      borderRadius: BorderRadius.circular(4),
                      border:
                          Border.all(color: AppTheme.textSecondary, width: 1),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // ─── Add Text Button ────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _addTextToTimeline,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Text'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: context.textTheme.labelMedium?.copyWith(
        color: AppTheme.textDisabled,
        letterSpacing: 1,
      ),
    );
  }

  Color _parseHexColor(String hex) {
    final hexStr = hex.replaceFirst('#', '');
    return Color(int.parse('FF$hexStr', radix: 16));
  }
}

/// Chip-style button for text presets
class _TextPresetChip extends StatelessWidget {
  const _TextPresetChip({
    required this.name,
    required this.icon,
    required this.onTap,
  });
  final String name;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppTheme.textDisabled.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppTheme.textTrackColor),
            const SizedBox(width: 6),
            Text(
              name,
              style: context.textTheme.bodySmall?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Toggle button for bold/italic
class _StyleToggleButton extends StatelessWidget {
  const _StyleToggleButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 40,
        height: 36,
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.primary.withValues(alpha: 0.2)
              : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive
                ? AppTheme.primary
                : AppTheme.textDisabled.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: isActive ? FontWeight.w900 : FontWeight.w400,
              color: isActive ? AppTheme.primary : AppTheme.textSecondary,
              fontStyle: label == 'I' ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ),
    );
  }
}
