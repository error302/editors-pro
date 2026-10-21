import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/profiling_service.dart';

/// A developer overlay that displays real-time performance metrics
/// on top of the editor UI.
///
/// Shows FPS, frame timing, memory usage, cache hit rate, GPU status,
/// and buffer pool statistics. Can be toggled on/off with a long-press
/// on the preview viewport.
///
/// ## Layout
///
/// ```
/// ┌────────────────────────────┐
/// │ FPS: 24.0/24.0  │ DROP: 0% │
/// │ Frame: 41ms (p95: 45ms)    │
/// │ Decode: 8ms  Render: 30ms  │
/// │ Cache: 87.3% │ Buffers: 6  │
/// │ Memory: 245MB │ Pressure: OK│
/// │ GPU: Vulkan (Adreno 740)   │
/// │ Budget: ON TRACK           │
/// └────────────────────────────┘
/// ```
class PerformanceOverlayWidget extends StatefulWidget {
  const PerformanceOverlayWidget({super.key});

  @override
  State<PerformanceOverlayWidget> createState() =>
      _PerformanceOverlayWidgetState();
}

class _PerformanceOverlayWidgetState extends State<PerformanceOverlayWidget> {
  final _monitor = PerformanceMonitor.instance;
  StreamSubscription<PerformanceSnapshot>? _subscription;
  PerformanceSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _subscription = _monitor.onUpdate.listen((snapshot) {
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot ?? _monitor.takeSnapshot();
    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _statusColor(snapshot).withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFpsRow(snapshot),
              const SizedBox(height: 2),
              _buildFrameTimingRow(snapshot),
              const SizedBox(height: 2),
              _buildDecodeRenderRow(snapshot),
              const SizedBox(height: 2),
              _buildCacheRow(snapshot),
              const SizedBox(height: 2),
              _buildMemoryRow(snapshot),
              const SizedBox(height: 2),
              _buildGpuRow(snapshot),
              const SizedBox(height: 2),
              _buildBudgetRow(snapshot),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFpsRow(PerformanceSnapshot s) {
    final fpsColor = _fpsColor(s);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'FPS: ${s.averageFps.toStringAsFixed(1)}/${s.targetFps.toStringAsFixed(0)}',
          style: _metricStyle(color: fpsColor),
        ),
        const SizedBox(width: 12),
        Text(
          'DROP: ${(s.dropRate * 100).toStringAsFixed(1)}%',
          style: _metricStyle(
            color: s.dropRate < 0.05 ? Colors.green : Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildFrameTimingRow(PerformanceSnapshot s) {
    return Text(
      'Frame: ${s.averageFrameDuration.inMilliseconds}ms '
      '(p95: ${s.p95FrameDuration.inMilliseconds}ms)',
      style: _metricStyle(),
    );
  }

  Widget _buildDecodeRenderRow(PerformanceSnapshot s) {
    return Text(
      'Decode: ${s.averageDecodeDuration.inMilliseconds}ms  '
      'Render: ${s.averageRenderDuration.inMilliseconds}ms',
      style: _metricStyle(),
    );
  }

  Widget _buildCacheRow(PerformanceSnapshot s) {
    final cacheColor = s.cacheHitRate > 0.8
        ? Colors.green
        : s.cacheHitRate > 0.5
            ? Colors.orange
            : Colors.red;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Cache: ${(s.cacheHitRate * 100).toStringAsFixed(1)}%',
          style: _metricStyle(color: cacheColor),
        ),
        const SizedBox(width: 12),
        Text(
          'BufPool: ${(s.bufferPoolHitRate * 100).toStringAsFixed(0)}% (${s.pooledBufferCount})',
          style: _metricStyle(),
        ),
      ],
    );
  }

  Widget _buildMemoryRow(PerformanceSnapshot s) {
    final memColor = s.memoryPressureLevel == 'normal'
        ? Colors.green
        : s.memoryPressureLevel == 'warning'
            ? Colors.orange
            : Colors.red;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Mem: ${s.memoryRssMb.toStringAsFixed(0)}MB',
          style: _metricStyle(color: memColor),
        ),
        const SizedBox(width: 12),
        Text(
          'Pressure: ${s.memoryPressureLevel.toUpperCase()}',
          style: _metricStyle(color: memColor),
        ),
      ],
    );
  }

  Widget _buildGpuRow(PerformanceSnapshot s) {
    if (!s.gpuAvailable) {
      return Text(
        'GPU: CPU-only',
        style: _metricStyle(color: Colors.orange),
      );
    }
    return Text(
      'GPU: ${s.gpuBackendName} (${s.gpuAdapterName})',
      style: _metricStyle(color: Colors.green, fontSize: 10),
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildBudgetRow(PerformanceSnapshot s) {
    final color = s.isOnBudget ? Colors.green : Colors.red;
    final text = s.isOnBudget ? 'BUDGET: ON TRACK' : 'BUDGET: OVER';
    return Text(
      text,
      style: _metricStyle(color: color, bold: true),
    );
  }

  TextStyle _metricStyle({
    Color? color,
    double fontSize = 11,
    bool bold = false,
  }) {
    return TextStyle(
      color: color ?? Colors.white70,
      fontSize: fontSize,
      fontFamily: 'monospace',
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
  }

  Color _fpsColor(PerformanceSnapshot s) {
    if (s.averageFps >= s.targetFps * 0.95) return Colors.green;
    if (s.averageFps >= s.targetFps * 0.75) return Colors.orange;
    return Colors.red;
  }

  Color _statusColor(PerformanceSnapshot s) {
    if (s.isOnBudget && s.memoryPressureLevel == 'normal') {
      return Colors.green;
    }
    if (s.memoryPressureLevel == 'critical' || s.dropRate > 0.2) {
      return Colors.red;
    }
    return Colors.orange;
  }
}

/// A toggle button for the performance overlay
class PerformanceOverlayToggle extends StatefulWidget {
  const PerformanceOverlayToggle({required this.child, super.key});
  final Widget child;

  @override
  State<PerformanceOverlayToggle> createState() =>
      _PerformanceOverlayToggleState();
}

class _PerformanceOverlayToggleState extends State<PerformanceOverlayToggle> {
  bool _showOverlay = false;

  void _toggle() {
    setState(() {
      _showOverlay = !_showOverlay;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onLongPress: _toggle,
          child: widget.child,
        ),
        if (_showOverlay) const PerformanceOverlayWidget(),
      ],
    );
  }
}
