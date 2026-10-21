import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/project_model.dart';
import '../../projects/providers/project_provider.dart';
import '../providers/editor_provider.dart';

/// Effect catalog panel — displays available filters and presets
/// that can be applied to the selected clip.
class EffectCatalog extends ConsumerStatefulWidget {
  const EffectCatalog({super.key});

  @override
  ConsumerState<EffectCatalog> createState() => _EffectCatalogState();
}

class _EffectCatalogState extends ConsumerState<EffectCatalog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, String>> _filterCatalog = [];
  List<Map<String, String>> _presets = [];
  bool _isLoading = true;
  String _selectedFilterCategory = 'All';
  String _selectedPresetCategory = 'All';

  // ── Fallback data when the engine returns nothing ────────────────

  static const _fallbackFilters = [
    {'name': 'Brightness', 'icon_key': 'brightness', 'category': 'Basic'},
    {'name': 'Contrast', 'icon_key': 'contrast', 'category': 'Basic'},
    {'name': 'Saturation', 'icon_key': 'saturation', 'category': 'Basic'},
    {'name': 'Hue Shift', 'icon_key': 'hue', 'category': 'Color'},
    {'name': 'Temperature', 'icon_key': 'temperature', 'category': 'Color'},
    {'name': 'Blur', 'icon_key': 'blur', 'category': 'Stylize'},
    {'name': 'Sharpen', 'icon_key': 'sharpen', 'category': 'Stylize'},
    {'name': 'Vignette', 'icon_key': 'vignette', 'category': 'Stylize'},
    {'name': 'Grayscale', 'icon_key': 'grayscale', 'category': 'Stylize'},
    {'name': 'Sepia', 'icon_key': 'sepia', 'category': 'Stylize'},
    {'name': 'Invert', 'icon_key': 'invert', 'category': 'Stylize'},
    {'name': 'Chroma Key', 'icon_key': 'chroma_key', 'category': 'Keying'},
  ];

  static const _fallbackPresets = [
    {
      'id': 'cinematic',
      'name': 'Cinematic',
      'description': 'Warm tones with deep shadows',
      'category': 'Film',
    },
    {
      'id': 'vintage',
      'name': 'Vintage',
      'description': 'Faded warm tones with grain',
      'category': 'Film',
    },
    {
      'id': 'bw_classic',
      'name': 'B&W Classic',
      'description': 'Classic black and white',
      'category': 'Film',
    },
    {
      'id': 'cool_blue',
      'name': 'Cool Blue',
      'description': 'Cool blue color grade',
      'category': 'Color',
    },
    {
      'id': 'warm_golden',
      'name': 'Warm Golden',
      'description': 'Warm golden hour look',
      'category': 'Color',
    },
    {
      'id': 'high_contrast',
      'name': 'High Contrast',
      'description': 'Punchy high contrast',
      'category': 'Stylize',
    },
    {
      'id': 'fade',
      'name': 'Fade',
      'description': 'Lifted blacks, faded look',
      'category': 'Stylize',
    },
    {
      'id': 'teal_orange',
      'name': 'Teal & Orange',
      'description': 'Hollywood color grade',
      'category': 'Film',
    },
  ];

  // ── Categories derived from data ─────────────────────────────────

  List<String> get _filterCategories {
    final cats = _filterCatalog.map((f) => f['category']!).toSet().toList();
    cats.sort();
    return ['All', ...cats];
  }

  List<String> get _presetCategories {
    final cats = _presets.map((p) => p['category']!).toSet().toList();
    cats.sort();
    return ['All', ...cats];
  }

  List<Map<String, String>> get _filteredFilters {
    if (_selectedFilterCategory == 'All') return _filterCatalog;
    return _filterCatalog
        .where((f) => f['category'] == _selectedFilterCategory)
        .toList();
  }

  List<Map<String, String>> get _filteredPresets {
    if (_selectedPresetCategory == 'All') return _presets;
    return _presets
        .where((p) => p['category'] == _selectedPresetCategory)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadCatalog();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final notifier = ref.read(editorProvider.notifier);
    final rawFilters = await notifier.getFilterCatalog();
    final rawPresets = await notifier.getFilterPresets();
    if (mounted) {
      setState(() {
        _filterCatalog = rawFilters.isEmpty
            ? _fallbackFilters
            : _normalizeFilters(rawFilters);
        _presets = rawPresets.isEmpty
            ? _fallbackPresets
            : _normalizePresets(rawPresets);
        _isLoading = false;
      });
    }
  }

  /// Convert dynamic engine results into typed maps.
  List<Map<String, String>> _normalizeFilters(List<dynamic> raw) {
    return raw.map((f) {
      if (f is Map<String, dynamic>) {
        return {
          'name': (f['name'] as String?) ?? 'Unknown',
          'icon_key':
              (f['icon_key'] as String?) ?? (f['icon'] as String?) ?? 'filter',
          'category': (f['category'] as String?) ?? 'Basic',
        };
      }
      // If the engine returns objects with property access
      return {
        'name': _field(f, 'name') ?? 'Unknown',
        'icon_key': _field(f, 'icon_key') ?? _field(f, 'icon') ?? 'filter',
        'category': _field(f, 'category') ?? 'Basic',
      };
    }).toList();
  }

  List<Map<String, String>> _normalizePresets(List<dynamic> raw) {
    return raw.map((p) {
      if (p is Map<String, dynamic>) {
        return {
          'id': (p['id'] as String?) ?? '',
          'name': (p['name'] as String?) ?? 'Unknown',
          'description': (p['description'] as String?) ?? '',
          'category': (p['category'] as String?) ?? 'Film',
        };
      }
      return {
        'id': _field(p, 'id') ?? '',
        'name': _field(p, 'name') ?? 'Unknown',
        'description': _field(p, 'description') ?? '',
        'category': _field(p, 'category') ?? 'Film',
      };
    }).toList();
  }

  /// Try reading a field from a dynamic object via property access or map key.
  String? _field(dynamic obj, String key) {
    try {
      // Map-like
      if (obj is Map) return obj[key]?.toString();
    } catch (_) {}
    return null;
  }

  // ── Clip name lookup ─────────────────────────────────────────────

  String? _clipName() {
    final editorState = ref.read(editorProvider);
    final clipId = editorState.selectedClipId;
    if (clipId == null) return null;

    final project = ref.read(currentProjectProvider);
    if (project == null) return clipId;

    // Find the clip across all tracks
    ClipModel? clip;
    for (final track in project.tracks) {
      try {
        clip = track.clips.firstWhere((c) => c.id == clipId);
        break;
      } catch (_) {}
    }
    if (clip == null) return clipId;

    // Look up the asset for a human-readable name
    try {
      final asset =
          project.mediaAssets.firstWhere((a) => a.id == clip!.assetId);
      return asset.fileName;
    } catch (_) {
      return clipId;
    }
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final hasClip = editorState.selectedClipId != null;
    final clipName = _clipName();

    return Column(
      children: [
        // Selected clip indicator
        if (clipName != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.textDisabled.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.movie_filter_outlined,
                  size: 16,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Applying to: $clipName',
                    style: context.textTheme.labelMedium?.copyWith(
                      color: AppTheme.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        // Tab bar
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Filters'),
            Tab(text: 'Presets'),
          ],
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textDisabled,
          indicatorColor: AppTheme.primary,
          labelStyle: context.textTheme.labelMedium,
        ),

        // Category chips
        _buildCategoryChips(),

        // Tab content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFilterGrid(hasClip),
                    _buildPresetList(hasClip),
                  ],
                ),
        ),
      ],
    );
  }

  // ── Category chips ───────────────────────────────────────────────

  Widget _buildCategoryChips() {
    final isFilterTab = _tabController.index == 0;
    final categories = isFilterTab ? _filterCategories : _presetCategories;
    final selected =
        isFilterTab ? _selectedFilterCategory : _selectedPresetCategory;

    if (categories.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = cat == selected;
          return FilterChip(
            label: Text(cat),
            selected: isSelected,
            showCheckmark: false,
            labelStyle: context.textTheme.labelSmall?.copyWith(
              color: isSelected ? Colors.white : AppTheme.textPrimary,
            ),
            backgroundColor: AppTheme.surfaceVariant,
            selectedColor: AppTheme.primary,
            side: BorderSide(
              color: isSelected
                  ? AppTheme.primary
                  : AppTheme.textDisabled.withValues(alpha: 0.2),
            ),
            visualDensity: VisualDensity.compact,
            onSelected: (_) {
              setState(() {
                if (isFilterTab) {
                  _selectedFilterCategory = cat;
                } else {
                  _selectedPresetCategory = cat;
                }
              });
            },
          );
        },
      ),
    );
  }

  // ── Filter grid ──────────────────────────────────────────────────

  Widget _buildFilterGrid(bool hasClip) {
    final filters = _filteredFilters;
    if (filters.isEmpty) {
      return Center(
        child: Text('No filters available', style: context.textTheme.bodySmall),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.0,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: filters.length,
      itemBuilder: (context, index) {
        final filter = filters[index];
        final name = filter['name'] ?? 'Unknown';
        final icon = filter['icon_key'] ?? 'filter';

        return _FilterCard(
          name: name,
          icon: icon,
          enabled: hasClip,
          onTap: () => _addFilter(name),
        );
      },
    );
  }

  // ── Preset list ──────────────────────────────────────────────────

  Widget _buildPresetList(bool hasClip) {
    final presets = _filteredPresets;
    if (presets.isEmpty) {
      return Center(
        child: Text('No presets available', style: context.textTheme.bodySmall),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: presets.length,
      itemBuilder: (context, index) {
        final preset = presets[index];
        final id = preset['id'] ?? '';
        final name = preset['name'] ?? 'Unknown';
        final description = preset['description'] ?? '';
        final category = preset['category'] ?? '';

        return Card(
          color: AppTheme.surfaceVariant,
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: _PresetIcon(category: category),
            title: Text(name, style: context.textTheme.bodyMedium),
            subtitle: description.isNotEmpty
                ? Text(description, style: context.textTheme.bodySmall)
                : null,
            trailing: Icon(
              Icons.auto_fix_high,
              size: 18,
              color: hasClip ? AppTheme.primary : AppTheme.textDisabled,
            ),
            onTap: hasClip ? () => _applyPreset(id, name) : null,
          ),
        );
      },
    );
  }

  // ── Engine calls ─────────────────────────────────────────────────

  Future<void> _addFilter(String filterName) async {
    final notifier = ref.read(editorProvider.notifier);
    try {
      final effectId = await notifier.addEffect(filterName);
      if (!mounted) return;
      if (effectId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Applied $filterName'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to apply $filterName'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _applyPreset(String presetId, String presetName) async {
    final notifier = ref.read(editorProvider.notifier);
    try {
      await notifier.applyFilterPreset(presetId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Applied $presetName'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ── Filter card widget ──────────────────────────────────────────────

class _FilterCard extends StatelessWidget {
  const _FilterCard({
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
              color: enabled ? AppTheme.textPrimary : AppTheme.textDisabled,
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
      case 'brightness':
        return Icons.brightness_6;
      case 'contrast':
        return Icons.contrast;
      case 'saturation':
        return Icons.water_drop;
      case 'hue':
        return Icons.palette;
      case 'blur':
        return Icons.blur_on;
      case 'sharpen':
        return Icons.deblur;
      case 'grayscale':
        return Icons.gradient;
      case 'sepia':
        return Icons.filter_vintage;
      case 'invert':
        return Icons.invert_colors;
      case 'vignette':
        return Icons.vignette;
      case 'temperature':
        return Icons.thermostat;
      case 'chroma_key':
        return Icons.colorize;
      default:
        return Icons.auto_fix_high;
    }
  }
}

// ── Preset category icon ────────────────────────────────────────────

class _PresetIcon extends StatelessWidget {
  const _PresetIcon({required this.category});
  final String category;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
      child: Icon(
        _icon,
        size: 16,
        color: AppTheme.primary,
      ),
    );
  }

  IconData get _icon {
    switch (category) {
      case 'Film':
        return Icons.movie_outlined;
      case 'Color':
        return Icons.palette_outlined;
      case 'Stylize':
        return Icons.auto_awesome_outlined;
      default:
        return Icons.auto_fix_high;
    }
  }
}
