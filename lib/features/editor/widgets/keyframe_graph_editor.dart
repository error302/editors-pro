import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/editor_provider.dart';

/// Keyframe data for display
class KeyframePoint {
  const KeyframePoint({
    required this.id,
    required this.timeMs,
    required this.value,
    required this.easingName,
  });
  final String id;
  final int timeMs;
  final double value;
  final String easingName;

  KeyframePoint copyWith({
    String? id,
    int? timeMs,
    double? value,
    String? easingName,
  }) {
    return KeyframePoint(
      id: id ?? this.id,
      timeMs: timeMs ?? this.timeMs,
      value: value ?? this.value,
      easingName: easingName ?? this.easingName,
    );
  }
}

/// Keyframe graph editor widget
class KeyframeGraphEditor extends ConsumerStatefulWidget {
  const KeyframeGraphEditor({
    required this.clipId,
    required this.clipDurationMs,
    super.key,
  });
  final String clipId;
  final int clipDurationMs;

  @override
  ConsumerState<KeyframeGraphEditor> createState() =>
      _KeyframeGraphEditorState();
}

class _KeyframeGraphEditorState extends ConsumerState<KeyframeGraphEditor> {
  String _selectedProperty = 'position_x';
  final Map<String, List<KeyframePoint>> _keyframeData = {};
  String? _draggingKeyframeId;
  int? _playheadMs;
  String? _selectedKeyframeId;

  static const Map<String, _PropertyConfig> _propertyConfigs = {
    'position_x': _PropertyConfig(
      label: 'Position X',
      min: -500,
      max: 500,
      color: Colors.blue,
    ),
    'position_y': _PropertyConfig(
      label: 'Position Y',
      min: -500,
      max: 500,
      color: Colors.green,
    ),
    'scale': _PropertyConfig(
      label: 'Scale',
      min: 0.0,
      max: 5.0,
      color: Colors.orange,
    ),
    'rotation': _PropertyConfig(
      label: 'Rotation',
      min: -360,
      max: 360,
      color: Colors.purple,
    ),
    'opacity': _PropertyConfig(
      label: 'Opacity',
      min: 0.0,
      max: 1.0,
      color: Colors.red,
    ),
  };

  static const List<String> _easingTypes = [
    'linear',
    'ease_in',
    'ease_out',
    'ease_in_out',
  ];

  @override
  void initState() {
    super.initState();
    // Initialize with empty keyframe lists for each property
    for (final prop in _propertyConfigs.keys) {
      _keyframeData[prop] = [];
    }
    // Listen to current time for playhead
    _playheadMs = ref.read(editorProvider).currentTimeMs;
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    _playheadMs = editorState.currentTimeMs;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(bottom: BorderSide(color: Color(0xFF2A2A3E))),
            ),
            child: Row(
              children: [
                const Icon(Icons.timeline, color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Keyframe Editor',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),

                // Property selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedProperty,
                      isDense: true,
                      dropdownColor: AppTheme.surfaceVariant,
                      style: TextStyle(
                        color: _propertyConfigs[_selectedProperty]?.color ??
                            AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      items: _propertyConfigs.entries.map((entry) {
                        return DropdownMenuItem(
                          value: entry.key,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: entry.value.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(entry.value.label),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedProperty = value);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Add keyframe button
                IconButton(
                  onPressed: _addKeyframeAtPlayhead,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  color: AppTheme.primary,
                  tooltip: 'Add keyframe at playhead',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),

                // Delete keyframe button
                IconButton(
                  onPressed: _deleteSelectedKeyframe,
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  color: Colors.redAccent,
                  tooltip: 'Delete selected keyframe',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),

                // Open in graph editor (full screen) button
                IconButton(
                  onPressed: () {
                    // Could expand to fullscreen; for now just shows snackbar
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Graph editor expanded mode coming soon'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_full, size: 18),
                  color: AppTheme.textSecondary,
                  tooltip: 'Expand graph editor',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),

          // Graph canvas
          Expanded(
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              onTapUp: _onTapUp,
              child: CustomPaint(
                painter: _KeyframeGraphPainter(
                  keyframes: _keyframeData[_selectedProperty] ?? [],
                  config: _propertyConfigs[_selectedProperty]!,
                  durationMs: widget.clipDurationMs,
                  playheadMs: _playheadMs,
                  allProperties: _keyframeData,
                  propertyConfigs: _propertyConfigs,
                  selectedKeyframeId: _selectedKeyframeId,
                ),
                size: Size.infinite,
              ),
            ),
          ),

          // Keyframe list & easing editor for selected keyframe
          if (_selectedKeyframeId != null) _buildSelectedKeyframeEditor(),

          // Value display footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(top: BorderSide(color: Color(0xFF2A2A3E))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Keyframes: ${_keyframeData[_selectedProperty]?.length ?? 0}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
                if (_playheadMs != null)
                  Text(
                    'Playhead: ${(_playheadMs! / 1000.0).toStringAsFixed(2)}s',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedKeyframeEditor() {
    final keyframes = _keyframeData[_selectedProperty] ?? [];
    final selectedKf =
        keyframes.where((kf) => kf.id == _selectedKeyframeId).firstOrNull;
    if (selectedKf == null) {
      _selectedKeyframeId = null;
      return const SizedBox.shrink();
    }

    final config = _propertyConfigs[_selectedProperty]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceVariant,
        border: Border(top: BorderSide(color: Color(0xFF2A2A3E))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.diamond, size: 14, color: AppTheme.primary),
              const SizedBox(width: 6),
              Text(
                'Keyframe at ${(selectedKf.timeMs / 1000.0).toStringAsFixed(2)}s',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Easing selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedKf.easingName,
                    isDense: true,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 11,
                    ),
                    dropdownColor: AppTheme.surfaceVariant,
                    items: _easingTypes.map((easing) {
                      return DropdownMenuItem(
                        value: easing,
                        child: Text(easing.replaceAll('_', ' ').toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _updateKeyframe(selectedKf.id, easingName: value);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${config.label}: ',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              Expanded(
                child: Slider(
                  value: selectedKf.value.clamp(config.min, config.max),
                  min: config.min,
                  max: config.max,
                  activeColor: config.color,
                  onChanged: (v) => _updateKeyframe(selectedKf.id, value: v),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  selectedKf.value.toStringAsFixed(
                    config.max - config.min > 10 ? 0 : 2,
                  ),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addKeyframeAtPlayhead() {
    final timeMs = _playheadMs ?? 0;
    final config = _propertyConfigs[_selectedProperty]!;
    final defaultValue = (config.min + config.max) / 2;

    // Check if a keyframe already exists at this time
    final existing = _keyframeData[_selectedProperty]!
        .where((kf) => (kf.timeMs - timeMs).abs() < 50)
        .firstOrNull;
    if (existing != null) {
      // Select the existing keyframe instead
      setState(() => _selectedKeyframeId = existing.id);
      return;
    }

    final newId = 'kf_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _keyframeData[_selectedProperty]!.add(
        KeyframePoint(
          id: newId,
          timeMs: timeMs,
          value: defaultValue,
          easingName: 'linear',
        ),
      );
      _keyframeData[_selectedProperty]!
          .sort((a, b) => a.timeMs.compareTo(b.timeMs));
      _selectedKeyframeId = newId;
    });

    // Wire to engine bridge API
    ref.read(editorProvider.notifier).addKeyframe(
          widget.clipId,
          _selectedProperty,
          timeMs,
          defaultValue,
          'linear',
        );
  }

  void _deleteSelectedKeyframe() {
    if (_selectedKeyframeId == null) return;
    final keyframes = _keyframeData[_selectedProperty];
    if (keyframes == null || keyframes.isEmpty) return;

    final toRemove =
        keyframes.where((kf) => kf.id == _selectedKeyframeId).firstOrNull;
    if (toRemove != null) {
      setState(() {
        keyframes.remove(toRemove);
        _selectedKeyframeId = null;
      });
      ref.read(editorProvider.notifier).removeKeyframe(
            widget.clipId,
            _selectedProperty,
            toRemove.id,
          );
    }
  }

  void _updateKeyframe(String keyframeId, {double? value, String? easingName}) {
    final keyframes = _keyframeData[_selectedProperty];
    if (keyframes == null) return;

    final idx = keyframes.indexWhere((kf) => kf.id == keyframeId);
    if (idx < 0) return;

    setState(() {
      keyframes[idx] = keyframes[idx].copyWith(
        value: value,
        easingName: easingName,
      );
    });

    ref.read(editorProvider.notifier).updateKeyframe(
          widget.clipId,
          _selectedProperty,
          keyframeId,
          value: value ?? keyframes[idx].value,
          easing: easingName ?? keyframes[idx].easingName,
        );
  }

  void _onTapUp(TapUpDetails details) {
    // Find keyframe near tap point
    final keyframes = _keyframeData[_selectedProperty] ?? [];
    if (keyframes.isEmpty) return;

    final box = context.findRenderObject() as RenderBox;
    final localPos = details.localPosition;
    const padding = 40.0;
    final graphWidth = box.size.width - padding * 2;
    final graphHeight = box.size.height - padding * 2;
    final config = _propertyConfigs[_selectedProperty]!;

    var closestDist = 20.0;
    String? closestId;

    for (final kf in keyframes) {
      final x = padding +
          (kf.timeMs /
                  (widget.clipDurationMs > 0 ? widget.clipDurationMs : 1)) *
              graphWidth;
      final y =
          padding + graphHeight - _valueToY(kf.value, config) * graphHeight;
      final dist = math
          .sqrt(math.pow(localPos.dx - x, 2) + math.pow(localPos.dy - y, 2));
      if (dist < closestDist) {
        closestDist = dist;
        closestId = kf.id;
      }
    }

    setState(() {
      _selectedKeyframeId = closestId;
    });
  }

  void _onPanStart(DragStartDetails details) {
    // Find keyframe near touch point
    final keyframes = _keyframeData[_selectedProperty] ?? [];
    if (keyframes.isEmpty) return;

    final box = context.findRenderObject() as RenderBox;
    final localPos = details.localPosition;
    const padding = 40.0;
    final graphWidth = box.size.width - padding * 2;
    final graphHeight = box.size.height - padding * 2;
    final config = _propertyConfigs[_selectedProperty]!;

    var closestDist = 20.0;

    for (final kf in keyframes) {
      final x = padding +
          (kf.timeMs /
                  (widget.clipDurationMs > 0 ? widget.clipDurationMs : 1)) *
              graphWidth;
      final y =
          padding + graphHeight - _valueToY(kf.value, config) * graphHeight;
      final dist = math
          .sqrt(math.pow(localPos.dx - x, 2) + math.pow(localPos.dy - y, 2));
      if (dist < closestDist) {
        closestDist = dist;
        _draggingKeyframeId = kf.id;
        _selectedKeyframeId = kf.id;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_draggingKeyframeId == null) return;

    final keyframes = _keyframeData[_selectedProperty];
    if (keyframes == null) return;

    final idx = keyframes.indexWhere((kf) => kf.id == _draggingKeyframeId);
    if (idx < 0) return;

    final box = context.findRenderObject() as RenderBox;
    const padding = 40.0;
    final graphWidth = box.size.width - padding * 2;
    final graphHeight = box.size.height - padding * 2;
    final config = _propertyConfigs[_selectedProperty]!;

    // Convert delta to time and value changes
    final timeDelta =
        (details.delta.dx / graphWidth * widget.clipDurationMs).round();
    final valueDelta =
        -details.delta.dy / graphHeight * (config.max - config.min);

    final kf = keyframes[idx];
    final newTime = (kf.timeMs + timeDelta).clamp(0, widget.clipDurationMs);
    final newValue = (kf.value + valueDelta).clamp(config.min, config.max);

    setState(() {
      keyframes[idx] = kf.copyWith(timeMs: newTime, value: newValue);
      // Re-sort by time
      keyframes.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    });

    ref.read(editorProvider.notifier).updateKeyframe(
          widget.clipId,
          _selectedProperty,
          kf.id,
          value: newValue,
          easing: kf.easingName,
        );
  }

  void _onPanEnd(DragEndDetails details) {
    _draggingKeyframeId = null;
  }

  double _valueToY(double value, _PropertyConfig cfg) {
    if (cfg.max == cfg.min) return 0.5;
    return ((value - cfg.min) / (cfg.max - cfg.min)).clamp(0.0, 1.0);
  }
}

class _PropertyConfig {
  const _PropertyConfig({
    required this.label,
    required this.min,
    required this.max,
    required this.color,
  });
  final String label;
  final double min;
  final double max;
  final Color color;
}

/// Custom painter for keyframe graph
class _KeyframeGraphPainter extends CustomPainter {
  _KeyframeGraphPainter({
    required this.keyframes,
    required this.config,
    required this.durationMs,
    required this.allProperties,
    required this.propertyConfigs,
    this.playheadMs,
    this.selectedKeyframeId,
  });
  final List<KeyframePoint> keyframes;
  final _PropertyConfig config;
  final int durationMs;
  final int? playheadMs;
  final Map<String, List<KeyframePoint>> allProperties;
  final Map<String, _PropertyConfig> propertyConfigs;
  final String? selectedKeyframeId;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 40.0;
    final graphWidth = size.width - padding * 2;
    final graphHeight = size.height - padding * 2;

    // Draw background grid
    _drawGrid(canvas, size, padding, graphWidth, graphHeight);

    // Draw property curves for other properties (dimmed)
    for (final entry in allProperties.entries) {
      if (entry.key == _getCurrentPropertyKey()) continue;
      final propConfig = propertyConfigs[entry.key];
      if (propConfig == null || entry.value.isEmpty) continue;

      _drawCurve(
        canvas,
        padding,
        graphWidth,
        graphHeight,
        entry.value,
        propConfig,
        true,
      );
    }

    // Draw current property curve (bright)
    _drawCurve(
      canvas,
      padding,
      graphWidth,
      graphHeight,
      keyframes,
      config,
      false,
    );

    // Draw keyframe diamonds
    _drawKeyframeDiamonds(canvas, padding, graphWidth, graphHeight);

    // Draw playhead
    if (playheadMs != null && durationMs > 0) {
      final x = padding + (playheadMs! / durationMs) * graphWidth;
      final playheadPaint = Paint()
        ..color = AppTheme.playheadColor.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(x, padding),
        Offset(x, size.height - padding),
        playheadPaint,
      );

      // Playhead triangle at top
      final triPath = Path();
      triPath.moveTo(x - 5, padding - 2);
      triPath.lineTo(x + 5, padding - 2);
      triPath.lineTo(x, padding + 6);
      triPath.close();
      canvas.drawPath(triPath, Paint()..color = AppTheme.playheadColor);
    }

    // Draw axis labels
    _drawAxisLabels(canvas, size, padding, graphWidth, graphHeight);
  }

  String _getCurrentPropertyKey() {
    for (final entry in propertyConfigs.entries) {
      if (entry.value.label == config.label) return entry.key;
    }
    return '';
  }

  void _drawGrid(
    Canvas canvas,
    Size size,
    double padding,
    double gw,
    double gh,
  ) {
    final gridPaint = Paint()
      ..color = const Color(0xFF2A2A3E).withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Horizontal lines (value axis)
    for (var i = 0; i <= 8; i++) {
      final y = padding + gh * i / 8;
      canvas.drawLine(Offset(padding, y), Offset(padding + gw, y), gridPaint);
    }

    // Vertical lines (time axis)
    for (var i = 0; i <= 10; i++) {
      final x = padding + gw * i / 10;
      canvas.drawLine(Offset(x, padding), Offset(x, padding + gh), gridPaint);
    }
  }

  void _drawCurve(
    Canvas canvas,
    double pad,
    double gw,
    double gh,
    List<KeyframePoint> kfs,
    _PropertyConfig cfg,
    bool dimmed,
  ) {
    if (kfs.isEmpty) return;

    final paint = Paint()
      ..color = dimmed ? cfg.color.withValues(alpha: 0.3) : cfg.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = dimmed ? 1 : 2.5
      ..strokeCap = StrokeCap.round;

    if (kfs.length == 1) {
      // Single keyframe - draw horizontal line
      final y = pad + gh - _valueToY(kfs.first.value, cfg) * gh;
      canvas.drawLine(Offset(pad, y), Offset(pad + gw, y), paint);
      return;
    }

    // Draw interpolated curve between keyframes with easing
    final path = Path();
    const stepsPerSegment = 40;

    for (var i = 0; i < kfs.length; i++) {
      final x = pad + (kfs[i].timeMs / (durationMs > 0 ? durationMs : 1)) * gw;
      final y = pad + gh - _valueToY(kfs[i].value, cfg) * gh;

      if (i == 0) {
        path.moveTo(x, y);
        // Extend line to left edge if first keyframe is not at start
        if (kfs[i].timeMs > 0) {
          path.moveTo(pad, y);
          path.lineTo(x, y);
        }
      }

      if (i < kfs.length - 1) {
        // Draw interpolated segment with easing
        final nextX =
            pad + (kfs[i + 1].timeMs / (durationMs > 0 ? durationMs : 1)) * gw;
        final nextY = pad + gh - _valueToY(kfs[i + 1].value, cfg) * gh;

        for (var s = 1; s <= stepsPerSegment; s++) {
          final t = s / stepsPerSegment;
          final easedT = _applyEasing(t, kfs[i].easingName);
          final interpX = x + (nextX - x) * t;
          final interpY = y + (nextY - y) * easedT;
          path.lineTo(interpX, interpY);
        }
      } else {
        // Extend line to right edge if last keyframe is not at end
        final lastX = pad + gw;
        if (kfs[i].timeMs < durationMs) {
          path.lineTo(lastX, y);
        }
      }
    }

    canvas.drawPath(path, paint);
  }

  double _applyEasing(double t, String easingName) {
    switch (easingName) {
      case 'ease_in':
        return t * t;
      case 'ease_out':
        return 1 - (1 - t) * (1 - t);
      case 'ease_in_out':
        return t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;
      case 'linear':
      default:
        return t;
    }
  }

  double _valueToY(double value, _PropertyConfig cfg) {
    if (cfg.max == cfg.min) return 0.5;
    return ((value - cfg.min) / (cfg.max - cfg.min)).clamp(0.0, 1.0);
  }

  void _drawKeyframeDiamonds(Canvas canvas, double pad, double gw, double gh) {
    for (final kf in keyframes) {
      final x = pad + (kf.timeMs / (durationMs > 0 ? durationMs : 1)) * gw;
      final y = pad + gh - _valueToY(kf.value, config) * gh;

      final isSelected = kf.id == selectedKeyframeId;
      final diamondSize = isSelected ? 7.0 : 5.0;

      final path = Path();
      path.moveTo(x, y - diamondSize);
      path.lineTo(x + diamondSize, y);
      path.lineTo(x, y + diamondSize);
      path.lineTo(x - diamondSize, y);
      path.close();

      // Selection glow
      if (isSelected) {
        canvas.drawPath(
          path,
          Paint()..color = config.color.withValues(alpha: 0.4),
        );
      }

      canvas.drawPath(
        path,
        Paint()..color = config.color,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = AppTheme.background
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.0 : 1.5,
      );
    }
  }

  void _drawAxisLabels(
    Canvas canvas,
    Size size,
    double pad,
    double gw,
    double gh,
  ) {
    // Time labels (bottom)
    for (var i = 0; i <= 5; i++) {
      final t = i / 5;
      final timeSec = (t * durationMs / 1000).toStringAsFixed(1);
      final x = pad + gw * t;

      final tp = TextPainter(
        text: TextSpan(
          text: '${timeSec}s',
          style: const TextStyle(color: AppTheme.textDisabled, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - pad + 4));
    }

    // Value labels (left)
    for (var i = 0; i <= 4; i++) {
      final t = i / 4;
      final value = config.min + (config.max - config.min) * t;
      final y = pad + gh - t * gh;

      final tp = TextPainter(
        text: TextSpan(
          text: value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
          style: const TextStyle(color: AppTheme.textDisabled, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pad - tp.width - 4, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _KeyframeGraphPainter oldDelegate) =>
      keyframes != oldDelegate.keyframes ||
      playheadMs != oldDelegate.playheadMs ||
      selectedKeyframeId != oldDelegate.selectedKeyframeId;
}
