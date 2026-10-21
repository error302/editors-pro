import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase F: Markers panel.
///
/// Exposes the existing engine/src/effects/markers.rs module. Markers
/// are colored pins on the timeline — used for chapter points, notes,
/// sync references, andQC flags.
///
/// 8 colors, 7 types (Chapter, Note, Sync, QC, Edit, Audio, VFX).
/// Tap to add a marker at the playhead; long-press to edit or delete.
///
/// Markers are the workflow backbone — pros mark sync points, problem
/// spots, chapter boundaries, and notes as they cut. Amateurs skip
/// markers and lose track of everything.
class MarkersPanel extends StatefulWidget {
  const MarkersPanel({
    required this.markers,
    required this.onAddMarker,
    required this.onDeleteMarker,
    required this.onJumpToMarker,
    super.key,
  });
  final List<Marker> markers;
  final void Function(MarkerType type, MarkerColor color, String note)
      onAddMarker;
  final void Function(String markerId) onDeleteMarker;
  final void Function(String markerId) onJumpToMarker;

  @override
  State<MarkersPanel> createState() => _MarkersPanelState();
}

class _MarkersPanelState extends State<MarkersPanel> {
  MarkerType _selectedType = MarkerType.chapter;
  MarkerColor _selectedColor = MarkerColor.blue;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Markers', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text(
              '${widget.markers.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing8),
        // Type picker
        Text('Type', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppTheme.spacing4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: MarkerType.values.map((t) {
            return ChoiceChip(
              label: Text(t.label),
              selected: _selectedType == t,
              onSelected: (_) => setState(() => _selectedType = t),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
        const SizedBox(height: AppTheme.spacing8),
        // Color picker
        Text('Color', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppTheme.spacing4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: MarkerColor.values.map((c) {
            return GestureDetector(
              onTap: () => setState(() => _selectedColor = c),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: c.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        _selectedColor == c ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppTheme.spacing8),
        // Note input
        TextField(
          controller: _noteController,
          decoration: const InputDecoration(
            hintText: 'Marker note (optional)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: AppTheme.spacing8),
        ElevatedButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Add marker at playhead'),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Existing markers
        Expanded(
          child: widget.markers.isEmpty
              ? const Center(
                  child: Text(
                    'No markers yet. Add one at the playhead.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  itemCount: widget.markers.length,
                  itemBuilder: (context, i) {
                    final m = widget.markers[i];
                    return ListTile(
                      leading: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: m.color.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(m.note.isEmpty ? m.type.label : m.note),
                      subtitle: Text(
                        '${m.type.label} • ${_formatTime(m.timeMs)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.play_arrow, size: 18),
                            tooltip: 'Jump to marker',
                            onPressed: () => widget.onJumpToMarker(m.id),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            tooltip: 'Delete',
                            onPressed: () => widget.onDeleteMarker(m.id),
                          ),
                        ],
                      ),
                      onTap: () => widget.onJumpToMarker(m.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _add() {
    widget.onAddMarker(_selectedType, _selectedColor, _noteController.text);
    _noteController.clear();
  }

  String _formatTime(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}

class Marker {
  Marker({
    required this.id,
    required this.timeMs,
    required this.type,
    required this.color,
    this.note = '',
  });
  final String id;
  final int timeMs;
  final MarkerType type;
  final MarkerColor color;
  final String note;
}

enum MarkerType {
  chapter('Chapter'),
  note('Note'),
  sync('Sync'),
  qc('QC'),
  edit('Edit'),
  audio('Audio'),
  vfx('VFX');

  const MarkerType(this.label);
  final String label;
}

enum MarkerColor {
  red(Colors.red),
  orange(Colors.orange),
  yellow(Colors.yellow),
  green(Colors.green),
  blue(Colors.blue),
  purple(Colors.purple),
  pink(Colors.pink),
  white(Colors.white);

  const MarkerColor(this.color);
  final Color color;
}
