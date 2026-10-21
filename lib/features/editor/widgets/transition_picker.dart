import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/editor_provider.dart';

/// Transition picker — shows available transition types and lets the user
/// apply one to the selected clip's in-point or out-point.
class TransitionPicker extends ConsumerStatefulWidget {
  const TransitionPicker({super.key});

  @override
  ConsumerState<TransitionPicker> createState() => _TransitionPickerState();
}

class _TransitionPickerState extends ConsumerState<TransitionPicker> {
  List<dynamic> _transitions = [];
  bool _isLoading = true;
  String _direction = 'out'; // "in" or "out"
  int _durationMs = 500;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final notifier = ref.read(editorProvider.notifier);
    final catalog = await notifier.getTransitionCatalog();
    if (mounted) {
      setState(() {
        _transitions = catalog;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final hasClip = editorState.selectedClipId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Direction selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(
                'DIRECTION',
                style: context.textTheme.labelMedium?.copyWith(
                  color: AppTheme.textDisabled,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('In', style: TextStyle(fontSize: 11)),
                selected: _direction == 'in',
                onSelected: (_) => setState(() => _direction = 'in'),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Out', style: TextStyle(fontSize: 11)),
                selected: _direction == 'out',
                onSelected: (_) => setState(() => _direction = 'out'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),

        // Duration slider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text('Duration', style: context.textTheme.bodySmall),
              Expanded(
                child: Slider(
                  value: _durationMs.toDouble(),
                  min: 100,
                  max: 2000,
                  divisions: 19,
                  onChanged: (v) => setState(() => _durationMs = v.round()),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  '${(_durationMs / 1000).toStringAsFixed(1)}s',
                  style: context.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Transition grid
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: _transitions.length,
                  itemBuilder: (context, index) {
                    final transition = _transitions[index];
                    final name = (transition.name as String?) ??
                        (transition['name'] as String?) ??
                        'Unknown';
                    final icon = (transition.icon as String?) ??
                        (transition['icon'] as String?) ??
                        'transition';
                    final defaultDuration =
                        (transition.defaultDurationMs as int?) ??
                            (transition['default_duration_ms'] as int?) ??
                            500;

                    return _TransitionCard(
                      name: name,
                      icon: icon,
                      enabled: hasClip,
                      onTap: () => _addTransition(name, defaultDuration),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _addTransition(String typeName, int defaultDuration) async {
    final notifier = ref.read(editorProvider.notifier);
    final duration = typeName == 'Cut' ? 0 : _durationMs;
    await notifier.addTransition(typeName, duration, _direction);
    if (mounted) {
      Navigator.of(context).pop(); // Close the picker after applying
    }
  }
}

class _TransitionCard extends StatelessWidget {
  const _TransitionCard({
    required this.name,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final String name;
  final String icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled
                ? AppTheme.textDisabled.withValues(alpha: 0.2)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _iconData,
              size: 24,
              color: enabled ? AppTheme.secondary : AppTheme.textDisabled,
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: context.textTheme.labelSmall?.copyWith(
                color: enabled ? AppTheme.textPrimary : AppTheme.textDisabled,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  IconData get _iconData {
    switch (icon) {
      case 'cut':
        return Icons.content_cut;
      case 'fade':
        return Icons.gradient;
      case 'dissolve':
        return Icons.auto_fix_high;
      case 'wipe_left':
        return Icons.arrow_back;
      case 'wipe_right':
        return Icons.arrow_forward;
      case 'wipe_up':
        return Icons.arrow_upward;
      case 'wipe_down':
        return Icons.arrow_downward;
      case 'slide_left':
        return Icons.chevron_left;
      case 'slide_right':
        return Icons.chevron_right;
      case 'zoom_in':
        return Icons.zoom_in;
      case 'zoom_out':
        return Icons.zoom_out;
      case 'spin':
        return Icons.rotate_right;
      default:
        return Icons.swap_horiz;
    }
  }
}
