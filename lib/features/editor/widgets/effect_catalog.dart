import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/user_look_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/project_model.dart';
import '../../../src/rust/api/bridge_api.dart';
import '../../projects/providers/project_provider.dart';
import '../providers/editor_provider.dart';

/// Native looks, adjustment controls and reusable recipes share the preview dock.
class EffectCatalog extends ConsumerStatefulWidget {
  const EffectCatalog({super.key});
  @override
  ConsumerState<EffectCatalog> createState() => _EffectCatalogState();
}

class _EffectCatalogState extends ConsumerState<EffectCatalog> {
  final _adjustmentsScroll = ScrollController();
  final _draftValues = <String, double>{};
  List<FilterTypeInfo> _filters = [];
  List<FilterPresetInfo> _looks = [];
  List<EffectInfo> _effects = [];
  List<UserLook> _myLooks = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _libraryError;
  String? _lookId;
  String? _focusedEffectId;
  double _intensity = 1;
  bool _lookEnabled = true;
  int _effectRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _loadMyLooks();
  }

  @override
  void dispose() {
    _adjustmentsScroll.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() { _loading = true; _error = null; });
    try {
      final editor = ref.read(editorProvider.notifier);
      final filters = await editor.getFilterCatalog();
      final looks = await editor.getFilterPresets();
      if (filters.isEmpty || looks.isEmpty) throw StateError('The engine returned an empty catalog');
      if (!mounted) return;
      setState(() { _filters = filters; _looks = looks; _loading = false; });
      await _loadEffects();
    } catch (error) {
      if (mounted) setState(() { _error = 'Effects unavailable: $error'; _loading = false; });
    }
  }

  Future<void> _loadMyLooks() async {
    try {
      final looks = await ref.read(userLookServiceProvider).load();
      if (mounted) setState(() { _myLooks = looks; _libraryError = null; });
    } catch (error) {
      if (mounted) setState(() => _libraryError = 'Could not load saved looks: $error');
    }
  }

  Future<void> _loadEffects() async {
    final request = ++_effectRequest;
    final clipId = ref.read(editorProvider).selectedClipId;
    try {
      final effects = await ref.read(editorProvider.notifier).getSelectedClipEffects();
      if (!mounted || request != _effectRequest || !_sameClip(clipId)) return;
      EffectInfo? look;
      for (final effect in effects) {
        if (effect.id.startsWith('look:')) { look = effect; break; }
      }
      var intensity = 1.0;
      for (final parameter in look?.parameters ?? <EffectParameterInfo>[]) {
        if (parameter.name == '__look_intensity') intensity = parameter.value;
      }
      setState(() {
        _effects = effects;
        _draftValues.clear();
        _lookId = look?.id.split(':').elementAtOrNull(1);
        _intensity = intensity.clamp(0.0, 1.0);
        _lookEnabled = look?.enabled ?? true;
      });
    } catch (_) {
      if (!mounted || request != _effectRequest || !_sameClip(clipId)) return;
      setState(() { _effects = []; _lookId = null; _draftValues.clear(); });
    }
  }

  bool _sameClip(String? clipId) => clipId == ref.read(editorProvider).selectedClipId;

  bool _isVisualClip(String? clipId, ProjectModel? project) {
    if (clipId == null || project == null) return false;
    return project.tracks.any((track) => track.trackType == TrackType.video &&
      !track.locked && track.clips.any((clip) => clip.id == clipId && !clip.locked));
  }

  bool get _canEdit {
    final state = ref.read(editorProvider);
    return !_busy && !state.isImporting && !state.isExporting &&
      _isVisualClip(state.selectedClipId, ref.read(currentProjectProvider));
  }

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _applyLook(String id, {double? intensity, bool? enabled}) async {
    if (!_canEdit) return;
    final clipId = ref.read(editorProvider).selectedClipId;
    setState(() => _busy = true);
    try {
      final success = await ref.read(editorProvider.notifier).setFilterLook(id,
        intensity: intensity ?? _intensity, enabled: enabled ?? true);
      if (!mounted) return;
      if (!success && _sameClip(clipId)) _message(ref.read(editorProvider).lastError ?? 'Could not apply look');
      await _loadEffects();
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _addFilter(FilterTypeInfo filter) async {
    if (!_canEdit) return;
    final clipId = ref.read(editorProvider).selectedClipId;
    setState(() => _busy = true);
    try {
      final id = await ref.read(editorProvider.notifier).addEffect(filter.name);
      if (!mounted || !_sameClip(clipId)) return;
      if (id == null) {
        _message(ref.read(editorProvider).lastError ?? 'Could not add adjustment');
      } else {
        setState(() => _focusedEffectId = id);
        await _loadEffects();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _adjustmentsScroll.hasClients) _adjustmentsScroll.jumpTo(0);
        });
      }
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _mutateEffect(String? clipId, Future<bool> Function(EditorNotifier) mutate) async {
    if (!_canEdit || !_sameClip(clipId)) return;
    setState(() => _busy = true);
    try {
      final success = await mutate(ref.read(editorProvider.notifier));
      if (!mounted || !_sameClip(clipId)) return;
      if (!success) _message(ref.read(editorProvider).lastError ?? 'Could not update adjustment');
      await _loadEffects();
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _saveCurrentLook() async {
    if (!_canEdit) return;
    final clipId = ref.read(editorProvider).selectedClipId;
    var draft = '';
    final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Save look'),
      content: SingleChildScrollView(child: TextField(key: const ValueKey('look-name'),
        autofocus: true, maxLength: 80, onChanged: (value) => draft = value,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (value) { if (value.trim().isNotEmpty) Navigator.pop(context, value.trim()); })),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () { if (draft.trim().isNotEmpty) Navigator.pop(context, draft.trim()); }, child: const Text('Save')),
      ],
    ));
    if (!mounted || name == null) return;
    if (!_sameClip(clipId) || !_canEdit) { _message('Select the original clip to save its look'); return; }
    setState(() => _busy = true);
    try {
      final effects = await ref.read(editorProvider.notifier).getSelectedClipEffects();
      if (!mounted || !_sameClip(clipId)) return;
      await ref.read(userLookServiceProvider).save(name: name, effects: effects);
      await _loadMyLooks();
      _message('Look saved on this device');
    } catch (error) { _message('Could not save look: $error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _applySavedLook(UserLook look) async {
    if (!_canEdit) return;
    final clipId = ref.read(editorProvider).selectedClipId;
    setState(() => _busy = true);
    try {
      final success = await ref.read(editorProvider.notifier).applyUserLook(look.recipeJson);
      if (!mounted || !_sameClip(clipId)) return;
      if (!success) _message(ref.read(editorProvider).lastError ?? 'Could not apply saved look');
      await _loadEffects();
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _deleteSavedLook(UserLook look) async {
    try {
      await ref.read(userLookServiceProvider).delete(look.id);
      await _loadMyLooks();
    } catch (error) { _message('Could not delete look: $error'); }
  }

  Future<void> _importLook() async {
    var draft = '';
    final recipe = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Import look'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: TextField(
        key: const ValueKey('import-look-json'), onChanged: (value) => draft = value, minLines: 3, maxLines: 8,
        decoration: const InputDecoration(labelText: 'Paste a look recipe (JSON)')))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, draft), child: const Text('Import'))],
    ));
    if (!mounted || recipe == null) return;
    try {
      await ref.read(userLookServiceProvider).importLook(recipe);
      await _loadMyLooks();
      _message('Look imported on this device');
    } catch (error) { _message('Could not import look: $error'); }
  }

  Future<void> _exportLook(UserLook look) async {
    final recipe = ref.read(userLookServiceProvider).exportLook(look);
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text('Export ${look.name}'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: SelectableText(recipe))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        TextButton(onPressed: () async {
          await Clipboard.setData(ClipboardData(text: recipe));
          if (context.mounted) Navigator.pop(context);
          _message('Look recipe copied. Share it with another editor to import.');
        }, child: const Text('Copy recipe'))],
    ));
  }

  Widget _selectionNotice(bool supports) => supports ? const SizedBox.shrink() : const Padding(
    padding: EdgeInsets.all(12), child: Text(
      'Select a photo or video clip on an unlocked video track to use looks and adjustments.'));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final supports = _isVisualClip(state.selectedClipId, ref.watch(currentProjectProvider));
    final enabled = supports && !_busy && !state.isImporting && !state.isExporting;
    ref.listen(editorProvider.select((state) => state.selectedClipId), (_, __) {
      _focusedEffectId = null;
      _draftValues.clear();
      _loadEffects();
    });
    ref.listen(editorProvider.select((state) => state.renderRevision), (_, __) => _loadEffects());
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return SingleChildScrollView(padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.warning_amber_outlined), const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _loadCatalog, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]));
    return DefaultTabController(length: 3, child: Column(children: [
      const TabBar(isScrollable: true, tabAlignment: TabAlignment.start,
        tabs: [Tab(text: 'Looks'), Tab(text: 'Adjustments'), Tab(text: 'My looks')]),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: TabBarView(children: [
        _buildLooks(enabled, supports, state.selectedClipId),
        _buildAdjustments(enabled, supports, state.selectedClipId),
        _buildMyLooks(enabled, supports),
      ])),
    ]));
  }

  Widget _buildLooks(bool enabled, bool supports, String? clipId) {
    final lookId = _lookId;
    return ListView(padding: const EdgeInsets.all(8), children: [
      _selectionNotice(supports),
      if (lookId != null) ...[
        Row(children: [const Expanded(child: Text('Intensity')), Text('${(_intensity * 100).round()}%')]),
        Slider(value: _intensity, min: 0, max: 1,
          onChanged: enabled ? (value) { if (_sameClip(clipId)) setState(() => _intensity = value); } : null,
          onChangeEnd: enabled ? (value) { if (_sameClip(clipId)) _applyLook(lookId, intensity: value, enabled: _lookEnabled); } : null),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Look enabled'), value: _lookEnabled,
          onChanged: enabled ? (value) { if (_sameClip(clipId)) _applyLook(lookId, enabled: value); } : null),
        Align(alignment: Alignment.centerLeft, child: TextButton(
          onPressed: enabled ? () => _applyLook('') : null, child: const Text('Reset look'))),
      ],
      ..._looks.map((look) => Card(
        color: look.id == lookId ? AppTheme.primary.withValues(alpha: 0.14) : AppTheme.surfaceVariant,
        child: ListTile(selected: look.id == lookId,
          leading: Icon(look.id == lookId ? Icons.check_circle : Icons.photo_filter_outlined),
          title: Text(look.name), subtitle: Text(look.description),
          onTap: enabled ? () => _applyLook(look.id, intensity: look.id == lookId ? _intensity : 1) : null))),
    ]);
  }

  Widget _buildAdjustments(bool enabled, bool supports, String? clipId) {
    final manual = _effects.where((effect) => !effect.id.startsWith('look:')).toList();
    manual.sort((a, b) => a.id == _focusedEffectId ? -1 : b.id == _focusedEffectId ? 1 : 0);
    return ListView(controller: _adjustmentsScroll, padding: const EdgeInsets.all(8), children: [
      _selectionNotice(supports),
      if (manual.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.all(8), child: Text('Current adjustments', style: TextStyle(fontWeight: FontWeight.w600))),
        ...manual.map((effect) => _adjustmentCard(effect, enabled, clipId)),
      ],
      const Padding(padding: EdgeInsets.all(8), child: Text('Add an adjustment, then move its sliders here to change the image.')),
      ..._filters.map((filter) => ListTile(key: ValueKey('add-adjustment-${filter.name}'),
        title: Text(filter.displayName), subtitle: Text(filter.category), trailing: const Icon(Icons.add_circle_outline),
        onTap: enabled ? () => _addFilter(filter) : null)),
    ]);
  }

  Widget _adjustmentCard(EffectInfo effect, bool enabled, String? clipId) => Card(child: Padding(
    padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(effect.name, style: const TextStyle(fontWeight: FontWeight.w600))),
        Switch(value: effect.enabled, onChanged: enabled ? (_) => _mutateEffect(clipId, (editor) => editor.toggleEffect(effect.id)) : null),
        IconButton(tooltip: 'Remove ${effect.name}', icon: const Icon(Icons.close, size: 20),
          onPressed: enabled ? () => _mutateEffect(clipId, (editor) => editor.removeEffect(effect.id)) : null),
      ]),
      if (effect.parameters.where((p) => !p.name.startsWith('__')).isEmpty)
        const Text('This adjustment has no numeric controls.'),
      ...effect.parameters.where((p) => !p.name.startsWith('__') && p.value.isFinite && p.minValue.isFinite && p.maxValue.isFinite && p.maxValue > p.minValue).map((p) {
        final key = '${effect.id}-${p.name}';
        final value = (_draftValues[key] ?? p.value).clamp(p.minValue, p.maxValue);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(p.displayName)), Text(value.toStringAsFixed(2), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))]),
          Slider(key: ValueKey('adjustment-$key'), value: value, min: p.minValue, max: p.maxValue,
            onChanged: enabled && effect.enabled ? (value) { if (_sameClip(clipId)) setState(() => _draftValues[key] = value); } : null,
            onChangeEnd: enabled && effect.enabled ? (value) => _mutateEffect(clipId, (editor) => editor.setEffectParameter(effect.id, p.name, value)) : null),
        ]);
      }),
    ])));

  Widget _buildMyLooks(bool enabled, bool supports) => ListView(padding: const EdgeInsets.all(12), children: [
    _selectionNotice(supports),
    const Text('Save an adjustment stack to reuse on another clip. Looks stay on this device; export a recipe to share it.'),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(onPressed: enabled && _effects.isNotEmpty ? _saveCurrentLook : null,
        icon: const Icon(Icons.bookmark_add_outlined, size: 18), label: const Text('Save current look')),
      OutlinedButton.icon(onPressed: _busy ? null : _importLook,
        icon: const Icon(Icons.input, size: 18), label: const Text('Import look')),
    ]),
    if (_libraryError != null) ...[
      Text(_libraryError!), TextButton(onPressed: _loadMyLooks, child: const Text('Retry saved looks')),
    ] else if (_myLooks.isEmpty)
      const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('No saved looks yet.')),
    ..._myLooks.map((look) => ListTile(contentPadding: EdgeInsets.zero,
      title: Text(look.name), subtitle: const Text('Tap to apply to the selected clip'),
      onTap: enabled ? () => _applySavedLook(look) : null,
      trailing: PopupMenuButton<String>(tooltip: 'Look options: ${look.name}',
        onSelected: (action) { if (action == 'delete') _deleteSavedLook(look); else _exportLook(look); },
        itemBuilder: (_) => [const PopupMenuItem(value: 'export', child: Text('Export recipe')),
          const PopupMenuItem(value: 'delete', child: Text('Delete look'))]))),
  ]);
}
