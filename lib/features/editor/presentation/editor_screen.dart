import 'dart:async';
import 'dart:convert' show base64Decode, base64Encode;
import 'dart:developer' as developer;
import 'dart:typed_data' show ByteData, Endian, Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/services/engine_service.dart';
// Phase F.3 + F.4 + F.5: top-level FFI wrappers
import 'package:editors_pro/src/rust/api/bridge_api.dart'
    show
        computeScopes,
        applyEqToSamples,
        markersAdd,
        markersGet,
        markersRemove,
        analyzeLoudness,
        setTrackPan,
        getTrackPan,
        setTrackSolo,
        getTrackSolo,
        setTrackEqSettings,
        getTrackEqSettings,
        setAudioSamples,
        getCurrentLoudness,
        setActiveLut,
        clearActiveLut;
import '../../../data/models/project_model.dart';
import '../../projects/providers/project_provider.dart';
import '../providers/editor_provider.dart';
import '../providers/engine_bridge_provider.dart';
import '../services/media_library_service.dart';
import '../widgets/preview_viewport.dart';
import '../widgets/timeline_panel.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/inspector_panel.dart';
import '../widgets/effect_catalog.dart';
import '../widgets/transition_picker.dart';
import '../widgets/text_panel.dart';
import '../widgets/speed_curve_editor.dart';
// Phase F.2: pro videographer widgets
import '../widgets/audio_mixer_panel.dart';
import '../widgets/color_scopes_panel.dart';
import '../widgets/markers_panel.dart';
import '../widgets/lut_browser.dart';
import '../widgets/eq_panel.dart';
import '../widgets/audio_loudness_meter.dart';
import '../widgets/safe_zones_overlay.dart';
import '../widgets/keyframe_graph_editor.dart';
import '../widgets/gpu_status_badge.dart';
import '../widgets/proxy_status_badge.dart';
import '../widgets/audio_mixer_panel.dart';
import '../widgets/video_scopes.dart';
import '../widgets/markers_panel.dart';
import '../widgets/lut_browser.dart';
import '../widgets/audio_eq_panel.dart';

/// Main editor screen - the core editing experience
class EditorScreen extends ConsumerStatefulWidget {
  final String projectId;

  const EditorScreen({super.key, required this.projectId});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final MediaLibraryService _mediaLibrary = MediaLibraryService();
  bool _showingMobileMediaLibrary = false;

  /// Phase F.2: in-memory timeline markers. In a full integration these
  /// would be persisted via the engine's `effects/markers.rs` module.
  /// For now, scoped to the screen lifetime.
  List<Marker> _markers = const [];

  /// Phase F.5: the currently-loaded LUT (parsed JSON from lutLoadCubeContent).
  /// When non-null, the LUT is applied in the engine's get_frame via setActiveLut.
  Map<String, dynamic>? _loadedLutJson;

  /// Phase F.5: LUT application intensity (0.0 = no LUT, 1.0 = full LUT).
  double _lutIntensity = 1.0;

  /// Phase F.3: current EQ settings JSON (stored when the user changes the
  /// EQ panel; applied to audio samples on playback).
  Map<String, dynamic>? _eqSettings;

  /// Phase F.6: cached Future for mixer tracks. Avoids re-fetching on every
  /// widget rebuild. Set to null to invalidate (e.g., when tracks change).
  Future<List<MixerTrack>>? _mixerTracksFuture;

  /// Phase F.6: cached Future for markers. Invalidated on add/delete.
  Future<List<Marker>>? _markersFuture;

  @override
  void initState() {
    super.initState();
    // Initialize the editor state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(editorProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final project = ref.watch(currentProjectProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 600;
    // Phase E.19: tablet/large-screen breakpoint. On tablets (>=1200px)
    // the left panel is wider (320px vs 240px) and the inspector takes
    // more space, giving professional editors room to work.
    final isTablet = screenWidth >= 1200;

    return Scaffold(
      body: Column(
        children: [
          // Top toolbar
          const EditorToolbar(),

          // Main content area
          Expanded(
            child: Row(
              children: [
                // Left: Media library / Tools (hidden on narrow screens)
                if (!isNarrowScreen)
                  _buildLeftPanel(context, editorState, isTablet: isTablet),

                // Center: Preview viewport
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      const PreviewViewport(),
                      // Phase F.2: Safe Zones overlay (broadcast / social / composition).
                      // Toggleable from the toolbar; only renders when showSafeZones is true.
                      if (editorState.showSafeZones &&
                          editorState.safeZoneMode != SafeZoneMode.off)
                        Positioned.fill(
                          child: SafeZonesOverlay(
                            config:
                                _safeZoneConfigFor(editorState.safeZoneMode),
                            previewAspectRatio: 16 / 9,
                          ),
                        ),
                      // GPU status badge — top-right of viewport
                      Positioned(
                        top: 8,
                        right: 8,
                        child: const GpuStatusBadge(),
                      ),
                      // Proxy status badge — next to GPU badge
                      Positioned(
                        top: 8,
                        right: 58,
                        child: const ProxyStatusBadge(),
                      ),
                      // Phase F.2: Safe zones indicator badge (left of proxy badge)
                      if (editorState.showSafeZones)
                        Positioned(
                          top: 8,
                          right: 108,
                          child: _SafeZoneBadge(mode: editorState.safeZoneMode),
                        ),
                      // Phase F.2: Safe zones toggle — bottom-left of viewport
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: FloatingActionButton.small(
                          heroTag: 'safezones_fab',
                          tooltip:
                              'Safe zones: ${editorState.safeZoneMode.name}',
                          backgroundColor: editorState.showSafeZones
                              ? AppTheme.primary
                              : AppTheme.surface,
                          foregroundColor: editorState.showSafeZones
                              ? Colors.white
                              : AppTheme.textSecondary,
                          onPressed: () => ref
                              .read(editorProvider.notifier)
                              .cycleSafeZoneMode(),
                          child: const Icon(Icons.crop_free, size: 18),
                        ),
                      ),
                      // Phase F.2: Audio Meter Bridge toggle — bottom-right of viewport
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: FloatingActionButton.small(
                          heroTag: 'audiometer_fab',
                          tooltip: 'Audio meter bridge',
                          backgroundColor: editorState.showAudioMeterBridge
                              ? AppTheme.primary
                              : AppTheme.surface,
                          foregroundColor: editorState.showAudioMeterBridge
                              ? Colors.white
                              : AppTheme.textSecondary,
                          onPressed: () => ref
                              .read(editorProvider.notifier)
                              .toggleAudioMeterBridge(),
                          child: const Icon(Icons.graphic_eq, size: 18),
                        ),
                      ),
                      // Phase E.9: on narrow screens, show a floating action
                      // button that opens the InspectorPanel as a draggable
                      // bottom sheet. Without this, phone users have no way
                      // to edit clip properties.
                      if (isNarrowScreen)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: FloatingActionButton.small(
                            heroTag: 'inspector_fab',
                            tooltip: 'Inspector',
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            onPressed: () => _showInspectorBottomSheet(context),
                            child: const Icon(Icons.tune),
                          ),
                        ),
                      // Phase E.10: importing overlay — shown whenever
                      // editorState.isImporting is true. Previously the flag
                      // was set but no UI surfaced it, leaving the user
                      // wondering if the app was frozen.
                      if (editorState.isImporting)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.5),
                            child: Center(
                              child: Card(
                                color: AppTheme.surface,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.all(AppTheme.spacing24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(
                                        color: AppTheme.primary,
                                      ),
                                      const SizedBox(
                                          height: AppTheme.spacing16),
                                      Text(
                                        'Importing media…',
                                        style: TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Right: Inspector / Properties (hidden on narrow screens)
                if (!isNarrowScreen)
                  Expanded(
                    // Phase E.19: give the inspector more room on tablets
                    // (flex 2) so color grading wheels and effect chains
                    // aren't cramped. On phones it's flex 1.
                    flex: isTablet ? 2 : 1,
                    child: const InspectorPanel(),
                  ),
              ],
            ),
          ),

          // Phase F.2: Audio Meter Bridge — thin horizontal strip showing
          // integrated LUFS + true-peak, between the timeline and the bottom
          // of the screen. Toggleable via the audio-meter FAB on the viewport.
          if (editorState.showAudioMeterBridge)
            _buildAudioMeterBridge(context, editorState),

          if (isNarrowScreen) _buildMobileImportBar(),

          // Bottom: Timeline
          const TimelinePanel(),
        ],
      ),
    );
  }

  Widget _buildMobileImportBar() {
    final mediaCount = ref.watch(mediaAssetsProvider).length;

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: () => _importMedia(),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                label: const Text('Add media'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _mobileImportAction(
            icon: Icons.audio_file_outlined,
            tooltip: 'Add audio',
            onPressed: _importAudio,
          ),
          const SizedBox(width: 8),
          _mobileImportAction(
            icon: Icons.video_library_outlined,
            tooltip: 'Media bin ($mediaCount)',
            onPressed: _showMobileMediaLibrary,
          ),
        ],
      ),
    );
  }

  Future<void> _showMobileMediaLibrary() async {
    if (_showingMobileMediaLibrary) return;
    _showingMobileMediaLibrary = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppTheme.surface,
        builder: (sheetContext) => FractionallySizedBox(
          heightFactor: 0.78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final count = ref.watch(mediaAssetsProvider).length;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Media bin',
                                  style: context.textTheme.titleMedium),
                              const SizedBox(height: 2),
                              Text(
                                '$count item${count == 1 ? '' : 's'}',
                                style: context.textTheme.labelSmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close media bin',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _buildMediaLibrary(sheetContext)),
            ],
          ),
        ),
      );
    } finally {
      _showingMobileMediaLibrary = false;
    }
  }

  Widget _mobileImportAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          foregroundColor: AppTheme.textPrimary,
          backgroundColor: AppTheme.surfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
        ),
      ),
    );
  }

  /// Phase F.2: Audio Meter Bridge — a compact horizontal loudness display
  /// that sits between the main content area and the timeline. Shows
  /// integrated LUFS, short-term LUFS, true-peak, and the active target.
  ///
  /// Phase F.3: uses a _LiveLoudnessBuilder that polls the engine's
  /// `analyzeLoudness` FFI every 1 second. The poll interval is intentionally
  /// slow because loudness is an integrated measurement — 1-second updates
  /// are sufficient for the bridge display.
  Widget _buildAudioMeterBridge(BuildContext context, EditorState state) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.border.withOpacity(0.5)),
          bottom: BorderSide(color: AppTheme.border.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          // Label
          Text(
            'LOUDNESS',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: AppTheme.spacing12),
          // Compact loudness display — single line, live-polled
          Expanded(
            child: _LiveLoudnessBuilder(
              target: LoudnessTarget.ebuR128,
              builder: (context, reading) => _CompactLoudnessBar(
                reading: reading,
                target: LoudnessTarget.ebuR128,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacing8),
          // Open full meter button
          IconButton(
            icon: const Icon(Icons.open_in_full, size: 16),
            tooltip: 'Open full loudness meter',
            onPressed: () => _showLoudnessMeterDialog(context),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  /// Phase F.2: map a SafeZoneMode to a SafeZoneConfig for the overlay widget.
  SafeZoneConfig _safeZoneConfigFor(SafeZoneMode mode) {
    switch (mode) {
      case SafeZoneMode.broadcast:
        return SafeZoneConfig.broadcast;
      case SafeZoneMode.social:
        return SafeZoneConfig.social;
      case SafeZoneMode.composition:
        return SafeZoneConfig.composition;
      case SafeZoneMode.off:
        return SafeZoneConfig.none;
    }
  }

  /// Phase E.9: show the InspectorPanel as a draggable bottom sheet
  /// on narrow screens (phones). This is the same widget used in the
  /// right-hand panel on tablets — no duplicate UI to maintain.
  void _showInspectorBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXLarge),
        ),
      ),
      builder: (sheetContext) {
        // Wrap in a DraggableScrollableSheet so the user can drag
        // the sheet up to full height and back down to dismiss.
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textDisabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing16,
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Inspector',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Inspector content (scrollable)
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(AppTheme.spacing16),
                    child: const InspectorPanel(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLeftPanel(BuildContext context, EditorState state,
      {bool isTablet = false}) {
    return Container(
      // Phase E.19: tablets get a wider left panel (320 vs 240) so
      // media thumbnails and effect names don't truncate.
      width: isTablet ? 320 : 240,
      color: AppTheme.surface,
      child: Column(
        children: [
          // Panel tabs — Phase F.2: horizontal scroll to fit 11 pro tabs.
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2A2A3E))),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _TabButton(
                    label: 'Media',
                    icon: Icons.video_library,
                    selected: state.leftPanelTab == LeftPanelTab.media,
                    onTap: () => ref
                        .read(editorProvider.notifier)
                        .setLeftPanelTab(LeftPanelTab.media),
                  ),
                  _TabButton(
                    label: 'Audio',
                    icon: Icons.audiotrack,
                    selected: state.leftPanelTab == LeftPanelTab.audio,
                    onTap: () => ref
                        .read(editorProvider.notifier)
                        .setLeftPanelTab(LeftPanelTab.audio),
                  ),
                  _TabButton(
                    label: 'Effects',
                    icon: Icons.auto_fix_high,
                    selected: state.leftPanelTab == LeftPanelTab.effects,
                    onTap: () => ref
                        .read(editorProvider.notifier)
                        .setLeftPanelTab(LeftPanelTab.effects),
                  ),
                  _TabButton(
                    label: 'Text',
                    icon: Icons.text_fields,
                    selected: state.leftPanelTab == LeftPanelTab.text,
                    onTap: () => ref
                        .read(editorProvider.notifier)
                        .setLeftPanelTab(LeftPanelTab.text),
                  ),
                  _TabButton(
                    label: 'Speed',
                    icon: Icons.speed,
                    selected: state.leftPanelTab == LeftPanelTab.speed,
                    onTap: () => ref
                        .read(editorProvider.notifier)
                        .setLeftPanelTab(LeftPanelTab.speed),
                  ),
                  _TabButton(
                    label: 'Keys',
                    icon: Icons.timeline,
                    selected: state.leftPanelTab == LeftPanelTab.keyframes,
                    onTap: () => ref
                        .read(editorProvider.notifier)
                        .setLeftPanelTab(LeftPanelTab.keyframes),
                  ),
                  _TabButton(
                    label: 'Mixer',
                    icon: Icons.graphic_eq,
                    selected: state.leftPanelTab == LeftPanelTab.mixer,
                    onTap: () => ref
                        .read(editorProvider.notifier)
                        .setLeftPanelTab(LeftPanelTab.mixer),
                  ),
                  _TabButton(
                    label: 'Scopes',
                    icon: Icons.analytics_outlined,
                    selected: state.leftPanelTab == LeftPanelTab.scopes,
                    onTap: () => ref
                        .read(editorProvider.notifier)
                        .setLeftPanelTab(LeftPanelTab.scopes),
                  ),
                  _TabButton(
                    label: 'Markers',
                    icon: Icons.bookmark_border,
                    selected: state.leftPanelTab == LeftPanelTab.markers,
                    onTap: () => ref
                        .read(editorProvider.notifier)
                        .setLeftPanelTab(LeftPanelTab.markers),
                  ),
                  _TabButton(
                    label: 'LUTs',
                    icon: Icons.palette_outlined,
                    selected: state.leftPanelTab == LeftPanelTab.luts,
                    onTap: () => ref
                        .read(editorProvider.notifier)
                        .setLeftPanelTab(LeftPanelTab.luts),
                  ),
                  _TabButton(
                    label: 'EQ',
                    icon: Icons.equalizer,
                    selected: state.leftPanelTab == LeftPanelTab.eq,
                    onTap: () => ref
                        .read(editorProvider.notifier)
                        .setLeftPanelTab(LeftPanelTab.eq),
                  ),
                ],
              ),
            ),
          ),

          // Panel content
          Expanded(
            child: _buildLeftPanelContent(context, state),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanelContent(BuildContext context, EditorState state) {
    switch (state.leftPanelTab) {
      case LeftPanelTab.media:
        return _buildMediaLibrary(context);
      case LeftPanelTab.audio:
        return _buildAudioPanel(context);
      case LeftPanelTab.effects:
        return _buildEffectsPanel(context);
      case LeftPanelTab.text:
        return _buildTextPanel(context);
      case LeftPanelTab.speed:
        return _buildSpeedPanel(context, state);
      case LeftPanelTab.keyframes:
        return _buildKeyframesPanel(context, state);
      case LeftPanelTab.mixer:
        return _buildMixerPanel(context, state);
      case LeftPanelTab.scopes:
        return _buildScopesPanel(context, state);
      case LeftPanelTab.markers:
        return _buildMarkersPanel(context, state);
      case LeftPanelTab.luts:
        return _buildLutPanel(context, state);
      case LeftPanelTab.eq:
        return _buildEqPanel(context, state);
    }
  }

  // ─── Phase F.2: Pro videographer panel builders ──────────────────────

  /// Per-track audio mixer with volume, pan, mute, solo, master fader.
  ///
  /// Phase F.3: pulls the real audio track list from the engine via
  /// `getTimelineState()`. The Future is cached in _mixerTracksFuture to
  /// avoid re-fetching on every widget rebuild. Call _invalidateMixerCache()
  /// when tracks are added/removed to force a refresh.
  Widget _buildMixerPanel(BuildContext context, EditorState state) {
    _mixerTracksFuture ??= _loadMixerTracks();
    return FutureBuilder<List<MixerTrack>>(
      future: _mixerTracksFuture,
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? const <MixerTrack>[];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          developer.log('Mixer track load failed: ${snapshot.error}',
              name: 'MixerPanel');
        }
        return AudioMixerPanel(
          tracks: tracks,
          master: MixerMaster(volume: state.masterVolume),
          onVolumeChanged: (trackId, volume) {
            if (!EngineService.instance.isInitialized) return;
            unawaited(
              EngineService.instance.api
                  .setTrackVolume(
                trackId: trackId,
                volume: volume,
              )
                  .catchError((e) {
                developer.log('setTrackVolume failed: $e', name: 'MixerPanel');
              }),
            );
          },
          onPanChanged: (trackId, pan) {
            if (!EngineService.instance.isInitialized) return;
            unawaited(
              setTrackPan(trackId: trackId, pan: pan).catchError((e) {
                developer.log('setTrackPan failed: $e', name: 'MixerPanel');
              }),
            );
          },
          onMuteToggled: (trackId, muted) {
            if (!EngineService.instance.isInitialized) return;
            unawaited(
              EngineService.instance.api
                  .toggleTrackVisibility(
                trackId: trackId,
              )
                  .catchError((e) {
                developer.log('toggleTrackVisibility failed: $e',
                    name: 'MixerPanel');
              }),
            );
          },
          onSoloToggled: (trackId, solo) {
            if (!EngineService.instance.isInitialized) return;
            unawaited(
              setTrackSolo(trackId: trackId, solo: solo).catchError((e) {
                developer.log('setTrackSolo failed: $e', name: 'MixerPanel');
              }),
            );
          },
          onMasterVolumeChanged: (volume) {
            ref.read(editorProvider.notifier).setMasterVolume(volume);
          },
          onOpenLoudnessMeter: () => _showLoudnessMeterDialog(context),
        );
      },
    );
  }

  /// Phase F.3 + F.4: fetch the timeline state from the engine and convert
  /// the audio tracks into MixerTrack objects. Also fetches per-track pan
  /// and solo via the new setTrackPan/setTrackSolo FFIs.
  Future<List<MixerTrack>> _loadMixerTracks() async {
    if (!EngineService.instance.isInitialized) return const [];
    try {
      final timeline = await EngineService.instance.api.getTimelineState();
      if (timeline == null) return const [];
      final audioTracks =
          timeline.tracks.where((t) => t.trackType == 'audio').toList();
      // Fetch pan + solo for each track in parallel.
      final futures = audioTracks.map((t) async {
        double pan = 0.0;
        bool solo = false;
        try {
          pan = await getTrackPan(trackId: t.id);
          solo = await getTrackSolo(trackId: t.id);
        } catch (e) {
          // Fall back to defaults if the FFI call fails.
          developer.log('getTrackPan/Solo failed for ${t.id}: $e',
              name: 'MixerPanel');
        }
        return MixerTrack(
          id: t.id,
          name: t.name,
          volume: t.volume,
          pan: pan,
          muted: !t.visible,
          solo: solo,
        );
      });
      return await Future.wait(futures);
    } catch (e) {
      developer.log('_loadMixerTracks failed: $e', name: 'MixerPanel');
      return const [];
    }
  }

  /// Color scopes — waveform, vectorscope, RGB parade, histogram.
  ///
  /// Phase F.3: fetches the current frame from the engine via `getFrame()`,
  /// base64-encodes it, and calls `computeScopes()` to get the four scope
  /// data structures. The result is parsed into the `ScopesData` DTO the
  /// widget expects.
  Widget _buildScopesPanel(BuildContext context, EditorState state) {
    return ColorScopesPanel(
      scopes: null, // computed on-demand via onRequestRefresh
      onRequestRefresh: () => _refreshScopes(context, state),
    );
  }

  /// Phase F.3: fetch the current frame and compute scopes.
  ///
  /// The engine's `get_frame` method returns raw RGBA8 bytes; we base64-
  /// encode them and pass to `computeScopes`. The result is parsed into
  /// the `ScopesData` DTO and shown via a stateful overlay.
  ///
  /// video: scopes are recomputed on each refresh tap, not real-time —
  /// upgrade to per-frame scope update via StreamSink when codegen runs.
  Future<void> _refreshScopes(BuildContext context, EditorState state) async {
    if (!EngineService.instance.isInitialized) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Engine not initialized — open a project first.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    try {
      // Fetch the current frame as RGBA8 bytes
      final frameBytes = await EngineService.instance.api.getFrame(
        timeMs: BigInt.from(state.currentTimeMs),
      );
      if (frameBytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No frame available at the current playhead.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      // Phase F.5: pass PNG bytes directly. compute_scopes decodes PNG
      // internally when width/height are 0 (the default).
      final frameB64 = base64Encode(frameBytes);
      final result = await computeScopes(
        frameBase64: frameB64,
      );

      // Parse into the ScopesData DTO
      final scopes = _parseScopesResult(result);
      if (!mounted) return;

      // Show the scopes in a dialog (the panel widget itself is stateless
      // and doesn't hold the scopes; in a future iteration, hoist scopes
      // into EditorState for live preview).
      _showScopesDialog(context, scopes);
    } catch (e) {
      developer.log('_refreshScopes failed: $e', name: 'ScopesPanel');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scopes refresh failed: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Phase F.3: parse the JSON result from computeScopes into the ScopesData DTO.
  ScopesData _parseScopesResult(Map<String, dynamic> json) {
    final wf = json['waveform'] as Map<String, dynamic>;
    final vs = json['vectorscope'] as Map<String, dynamic>;
    final rp = json['rgb_parade'] as Map<String, dynamic>;
    final hg = json['histogram'] as Map<String, dynamic>;

    final wfWidth = (wf['width'] as num).toInt();
    final wfColumns = (wf['columns'] as List)
        .map((col) => (col as List).map((v) => (v as num).toInt()).toList())
        .toList();

    final vsSize = (vs['size'] as num).toInt();
    final vsGrid = (vs['grid'] as List).map((v) => (v as num).toInt()).toList();

    final rpWidth = (rp['width'] as num).toInt();
    List<List<int>> parseParadeChannel(dynamic channel) {
      return (channel as List)
          .map((col) => (col as List).map((v) => (v as num).toInt()).toList())
          .toList();
    }

    final histBins =
        (hg['bins'] as List).map((v) => (v as num).toInt()).toList();

    return ScopesData(
      waveform: WaveformData(width: wfWidth, columns: wfColumns),
      vectorscope: VectorscopeData(size: vsSize, grid: vsGrid),
      rgbParade: RgbParadeData(
        width: rpWidth,
        red: parseParadeChannel(rp['red']),
        green: parseParadeChannel(rp['green']),
        blue: parseParadeChannel(rp['blue']),
      ),
      histogram: HistogramData(bins: histBins),
    );
  }

  /// Phase F.3: show the computed scopes in a dialog. The dialog renders
  /// the ColorScopesPanel in a larger size for detailed inspection.
  void _showScopesDialog(BuildContext context, ScopesData scopes) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 600,
          height: 500,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacing16),
            child: ColorScopesPanel(
              scopes: scopes,
              onRequestRefresh: () =>
                  _refreshScopes(context, ref.read(editorProvider)),
            ),
          ),
        ),
      ),
    );
  }

  /// Timeline markers — chapter, note, sync, QC, edit, audio, VFX.
  ///
  /// Phase F.3: persists via the engine's `markers_add` / `markers_remove`
  /// FFI arms. The Future is cached in _markersFuture to avoid re-fetching
  /// on every rebuild. Invalidated when markers are added/removed.
  Widget _buildMarkersPanel(BuildContext context, EditorState state) {
    _markersFuture ??= _loadMarkers();
    return FutureBuilder<List<Marker>>(
      future: _markersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final markers = snapshot.data ?? const <Marker>[];
        return MarkersPanel(
          markers: markers,
          onAddMarker: (type, color, note) async {
            await _addMarker(state.currentTimeMs, type, color, note);
          },
          onDeleteMarker: (markerId) async {
            await _deleteMarker(markerId);
          },
          onJumpToMarker: (markerId) {
            final marker = markers.firstWhere((m) => m.id == markerId);
            _seekToMs(marker.timeMs);
          },
        );
      },
    );
  }

  /// Phase F.3: load all markers from the engine and convert to the
  /// Flutter `Marker` DTO. Marker colors and types come back as strings
  /// from the engine (snake_case); we map them back to the enum values.
  Future<List<Marker>> _loadMarkers() async {
    if (!EngineService.instance.isInitialized) return const [];
    try {
      final result = await markersGet();
      return result.map(_engineMarkerToFlutter).toList();
    } catch (e) {
      developer.log('_loadMarkers failed: $e', name: 'MarkersPanel');
      return const [];
    }
  }

  /// Phase F.3: add a marker via the engine FFI and refresh the local list.
  Future<void> _addMarker(
    int timeMs,
    MarkerType type,
    MarkerColor color,
    String note,
  ) async {
    if (!EngineService.instance.isInitialized) return;
    try {
      await markersAdd(
        name: note.isEmpty ? type.label : note,
        positionMs: timeMs.toDouble(),
        color: _markerColorToString(color),
        markerType: _markerTypeToString(type),
        comment: note,
      );
      // Invalidate cache + rebuild so the FutureBuilder re-fetches.
      _markersFuture = null;
      setState(() {});
    } catch (e) {
      developer.log('_addMarker failed: $e', name: 'MarkersPanel');
    }
  }

  /// Phase F.3: remove a marker via the engine FFI and refresh the local list.
  Future<void> _deleteMarker(String markerId) async {
    if (!EngineService.instance.isInitialized) return;
    try {
      await markersRemove(id: markerId);
      _markersFuture = null;
      setState(() {});
    } catch (e) {
      developer.log('_deleteMarker failed: $e', name: 'MarkersPanel');
    }
  }

  /// Convert engine marker JSON → Flutter Marker DTO.
  Marker _engineMarkerToFlutter(Map<String, dynamic> json) {
    return Marker(
      id: json['id'] as String,
      timeMs: (json['position_ms'] as num).toInt(),
      type: _stringToMarkerType(json['marker_type'] as String? ?? 'standard'),
      color: _stringToMarkerColor(json['color'] as String? ?? 'blue'),
      note: json['comment'] as String? ?? json['name'] as String? ?? '',
    );
  }

  String _markerColorToString(MarkerColor c) {
    switch (c) {
      case MarkerColor.red:
        return 'red';
      case MarkerColor.orange:
        return 'orange';
      case MarkerColor.yellow:
        return 'yellow';
      case MarkerColor.green:
        return 'green';
      case MarkerColor.blue:
        return 'blue';
      case MarkerColor.purple:
        return 'purple';
      case MarkerColor.pink:
        return 'pink';
      case MarkerColor.white:
        return 'gray'; // engine has no 'white'
    }
  }

  MarkerColor _stringToMarkerColor(String s) {
    switch (s.toLowerCase()) {
      case 'red':
        return MarkerColor.red;
      case 'orange':
        return MarkerColor.orange;
      case 'yellow':
        return MarkerColor.yellow;
      case 'green':
        return MarkerColor.green;
      case 'blue':
        return MarkerColor.blue;
      case 'purple':
        return MarkerColor.purple;
      case 'pink':
        return MarkerColor.pink;
      case 'gray':
      case 'grey':
      default:
        return MarkerColor.white; // map engine gray → Flutter white
    }
  }

  String _markerTypeToString(MarkerType t) {
    switch (t) {
      case MarkerType.chapter:
        return 'chapter';
      case MarkerType.note:
        return 'comment';
      case MarkerType.sync:
        return 'standard';
      case MarkerType.qc:
        return 'error';
      case MarkerType.edit:
        return 'standard';
      case MarkerType.audio:
        return 'standard';
      case MarkerType.vfx:
        return 'custom';
    }
  }

  MarkerType _stringToMarkerType(String s) {
    switch (s.toLowerCase()) {
      case 'chapter':
        return MarkerType.chapter;
      case 'comment':
        return MarkerType.note;
      case 'todo':
        return MarkerType.qc;
      case 'error':
        return MarkerType.qc;
      case 'musicbeat':
      case 'music_beat':
      case 'beat':
        return MarkerType.audio;
      case 'custom':
        return MarkerType.vfx;
      case 'standard':
      default:
        return MarkerType.note;
    }
  }

  /// LUT browser — import .cube, apply with intensity slider.
  ///
  /// Phase F.3: when a LUT is loaded, store its JSON in the editor state
  /// Phase F.5: LUT browser — applies LUT via setActiveLut FFI.
  /// The engine applies the LUT in get_frame itself, so every preview
  /// frame is LUT-processed. This retires the 'LUT applied lazily' debt.
  Widget _buildLutPanel(BuildContext context, EditorState state) {
    return LutBrowser(
      onLutSelected: (lutJson) {
        _loadedLutJson = lutJson;
        _applyActiveLut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('LUT applied to preview. Adjust intensity live.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      onIntensityChanged: (intensity) {
        _lutIntensity = intensity;
        _applyActiveLut();
      },
    );
  }

  /// Phase F.5: apply (or clear) the active LUT via the engine FFI.
  Future<void> _applyActiveLut() async {
    if (!EngineService.instance.isInitialized) return;
    try {
      if (_loadedLutJson == null || _lutIntensity <= 0.001) {
        await clearActiveLut();
      } else {
        await setActiveLut(
          lutJson: _loadedLutJson!,
          intensity: _lutIntensity,
        );
      }
    } catch (e) {
      developer.log('_applyActiveLut failed: $e', name: 'LutPanel');
    }
  }

  /// 8-band parametric EQ — high-pass, 8 bands, low-pass.
  ///
  /// Phase F.3: applies the EQ chain via `applyEqToSamples` FFI when the
  /// user changes any band. The EQ is applied to the currently-selected
  /// audio clip's samples (or the master mix if no clip is selected).
  Widget _buildEqPanel(BuildContext context, EditorState state) {
    return EqPanel(
      onChanged: (settings) {
        _applyEqSettings(settings, state);
      },
    );
  }

  /// Phase F.5: Convert EqSettings (Flutter DTO) to JSON for FFI calls.
  /// Single source of truth — used by both _applyEqSettings and _applyEqToSelectedClip.
  static Map<String, dynamic> _eqSettingsToJson(EqSettings settings) {
    return {
      'enabled': settings.enabled,
      'high_pass_hz': settings.highPassHz,
      'low_pass_hz': settings.lowPassHz,
      'bands': settings.bands
          .map((b) => {
                'frequency': b.frequency,
                'gain_db': b.gain,
                'q': b.q,
                'enabled': b.enabled,
              })
          .toList(),
    };
  }

  /// Phase F.3 + F.4: apply EQ settings to the current audio clip's samples.
  ///
  /// Persists the EQ settings per-track via `setTrackEqSettings` (so the
  /// mixer can apply them during playback). When a clip is selected, also
  /// fetches the audio samples, applies the EQ chain immediately via
  /// `applyEqToSamples`, and writes the result back to the engine's audio
  /// cache via `setAudioSamples` — so the user hears the change instantly
  /// on the next preview scrub.
  ///
  /// video: EQ applied per-clip on demand, upgrade to real-time streaming
  /// EQ when the audio pipeline supports per-track effect chains natively
  /// (the per-track settings are already stored; the mixer just needs to
  /// call apply_eq_chain when rendering each track).
  Future<void> _applyEqSettings(EqSettings settings, EditorState state) async {
    if (!EngineService.instance.isInitialized) return;

    try {
      final settingsJson = _eqSettingsToJson(settings);

      // Phase F.4: persist the EQ settings per-track so the mixer can
      // apply them during playback. Use the selected track (or fall back
      // to the first audio track if no clip is selected).
      final trackId = state.selectedTrackId ?? 'default_audio_track';
      await setTrackEqSettings(trackId: trackId, settings: settingsJson);
      developer.log(
        'EQ settings persisted for track $trackId: '
        '${settings.bands.where((b) => b.enabled).length} bands active',
        name: 'EqPanel',
      );

      // Store for later application
      _eqSettings = settingsJson;

      // Phase F.4: if a clip is selected, also apply immediately to the
      // audio cache so the user hears the change on the next scrub.
      // This requires the selected clip's asset_id, which we don't have
      // directly — we'd need to look it up from the timeline state.
      // video: immediate apply requires asset_id lookup from clip_id;
      // add a get_clip_asset_id FFI or extend TrackInfo/ClipInfo to expose it.
      if (state.selectedClipId != null) {
        // Try to fetch the clip's audio samples and apply EQ immediately.
        // This is best-effort — if it fails, the per-track settings will
        // still be applied on the next playback.
        try {
          await _applyEqToSelectedClip(settings, state);
        } catch (e) {
          developer.log(
              'Immediate EQ apply failed (per-track settings still persisted): $e',
              name: 'EqPanel');
        }
      }
    } catch (e) {
      developer.log('_applyEqSettings failed: $e', name: 'EqPanel');
    }
  }

  /// Phase F.4: best-effort immediate EQ application to the selected clip.
  ///
  /// Fetches the timeline state, finds the selected clip, fetches its
  /// Phase F.5: immediate EQ application to the selected clip's audio.
  /// Uses TrackInfo.clips (now parsed) to find the asset_id, fetches
  /// samples, applies EQ, writes back via setAudioSamples.
  Future<void> _applyEqToSelectedClip(
      EqSettings settings, EditorState state) async {
    final timeline = await EngineService.instance.api.getTimelineState();
    if (timeline == null || state.selectedClipId == null) return;

    // Phase F.5: find the selected clip via TrackInfo.clips
    String? assetId;
    int? clipStartMs;
    int? clipDurationMs;
    for (final track in timeline.tracks) {
      for (final clip in track.clips) {
        if (clip.id == state.selectedClipId) {
          assetId = clip.assetId;
          clipStartMs = clip.startMs;
          clipDurationMs = clip.durationMs;
          break;
        }
      }
      if (assetId != null) break;
    }
    if (assetId == null || clipStartMs == null || clipDurationMs == null)
      return;

    try {
      final samples = await EngineService.instance.api.getAudioSamples(
        assetId: assetId,
        startMs: BigInt.from(clipStartMs),
        durationMs: BigInt.from(clipDurationMs),
      );
      if (samples.isEmpty) return;

      final sampleBytes = Uint8List(samples.length * 4);
      for (int i = 0; i < samples.length; i++) {
        final byteData = ByteData.view(sampleBytes.buffer, i * 4, 4);
        byteData.setFloat32(0, samples[i], Endian.little);
      }
      final samplesB64 = base64Encode(sampleBytes);
      final settingsJson = _eqSettingsToJson(settings);

      final resultB64 = await applyEqToSamples(
        settings: settingsJson,
        samplesBase64: samplesB64,
        sampleRate: 44100,
      );

      await setAudioSamples(
        assetId: assetId,
        samplesBase64: resultB64,
        sampleRate: 44100,
        channels: 2,
      );

      developer.log('EQ immediate-apply succeeded for asset $assetId',
          name: 'EqPanel');
    } catch (e) {
      developer.log('_applyEqToSelectedClip failed: $e', name: 'EqPanel');
      rethrow;
    }
  }

  /// Phase F.2: show the loudness meter in a floating dialog (called from
  /// the mixer panel's loudness-meter button).
  ///
  /// Phase F.3: the dialog is a _LoudnessMeterDialog stateful widget that
  /// polls the engine's `analyzeLoudness` FFI every 500ms with the current
  /// audio samples. Replaces the hardcoded placeholder values.
  void _showLoudnessMeterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _LoudnessMeterDialog(),
    );
  }

  /// Seek the playhead to a specific time in milliseconds.
  /// Used by the markers panel to jump to a marker.
  void _seekToMs(int timeMs) {
    ref.read(editorProvider.notifier).seekTo(timeMs);
  }

  Widget _buildMediaLibrary(BuildContext context) {
    final assets = ref.watch(mediaAssetsProvider);

    if (assets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline,
                  size: 48, color: AppTheme.textDisabled),
              const SizedBox(height: 16),
              Text(
                'Import Media',
                style: context.textTheme.titleSmall
                    ?.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap + to add videos, audio, or images',
                style: context.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _importMedia(),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Choose from Gallery'),
              ),
              TextButton.icon(
                onPressed: () => _browseMediaFiles(),
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Browse files'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: assets.length + 1, // +1 for import actions
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _importMedia(),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Choose from Gallery'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: () => _browseMediaFiles(),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Browse files'),
                  ),
                ),
              ],
            ),
          );
        }

        final asset = assets[index - 1];
        return _MediaAssetItem(
          asset: asset,
          onAddToTimeline: () => _addAssetToTimeline(asset),
        );
      },
    );
  }

  Widget _buildAudioPanel(BuildContext context) {
    final assets = ref.watch(mediaAssetsProvider);
    final audioAssets =
        assets.where((a) => a.mediaType == MediaType.audio).toList();

    return Column(
      children: [
        // Import audio button
        Padding(
          padding: const EdgeInsets.all(8),
          child: OutlinedButton.icon(
            onPressed: () => _importAudio(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Import Audio'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(36)),
          ),
        ),

        // Audio assets list
        if (audioAssets.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_note,
                        size: 48, color: AppTheme.textDisabled),
                    const SizedBox(height: 16),
                    Text(
                      'No Audio Files',
                      style: context.textTheme.titleSmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Import MP3, WAV, AAC, FLAC,\nor OGG audio files',
                      style: context.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: audioAssets.length,
              itemBuilder: (context, index) {
                final asset = audioAssets[index];
                return Card(
                  child: ListTile(
                    dense: true,
                    leading: Container(
                      width: 48,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.audioTrackColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.audiotrack,
                        color: AppTheme.audioTrackColor,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      asset.fileName,
                      style: context.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: asset.durationMs != null
                        ? Text(
                            Duration(milliseconds: asset.durationMs!).formatted,
                            style: context.textTheme.labelSmall,
                          )
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      onPressed: () => _addAssetToTimeline(asset),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildEffectsPanel(BuildContext context) {
    return const EffectCatalog();
  }

  Widget _buildTextPanel(BuildContext context) {
    return const TextPanel();
  }

  Widget _buildSpeedPanel(BuildContext context, EditorState state) {
    // Find the selected clip to get clipId and duration
    final project = ref.read(currentProjectProvider);
    String? clipId;
    int clipDurationMs = 5000; // default

    if (state.selectedClipId != null && project != null) {
      for (final track in project.tracks) {
        for (final clip in track.clips) {
          if (clip.id == state.selectedClipId) {
            clipId = clip.id;
            clipDurationMs = clip.durationMs;
            break;
          }
        }
        if (clipId != null) break;
      }
    }

    if (clipId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.speed, size: 48, color: AppTheme.textDisabled),
              const SizedBox(height: 16),
              Text(
                'Select a Clip',
                style: context.textTheme.titleSmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a clip on the timeline\nto edit its speed curve',
                style: context.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: SpeedCurveEditor(
        clipId: clipId,
        clipDurationMs: clipDurationMs,
      ),
    );
  }

  Widget _buildKeyframesPanel(BuildContext context, EditorState state) {
    // Find the selected clip to get clipId and duration
    final project = ref.read(currentProjectProvider);
    String? clipId;
    int clipDurationMs = 5000; // default

    if (state.selectedClipId != null && project != null) {
      for (final track in project.tracks) {
        for (final clip in track.clips) {
          if (clip.id == state.selectedClipId) {
            clipId = clip.id;
            clipDurationMs = clip.durationMs;
            break;
          }
        }
        if (clipId != null) break;
      }
    }

    if (clipId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timeline,
                  size: 48, color: AppTheme.textDisabled),
              const SizedBox(height: 16),
              Text(
                'Select a Clip',
                style: context.textTheme.titleSmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a clip on the timeline\nto edit its keyframes',
                style: context.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return KeyframeGraphEditor(
      clipId: clipId,
      clipDurationMs: clipDurationMs,
    );
  }

  // ─── "Add to Timeline" Implementation ───────────────────────────

  /// Add a media asset to the appropriate track on the timeline.
  ///
  /// Finds the first track matching the asset's type, calculates the
  /// start position (append after the last clip), and calls the Rust
  /// engine to create the clip via the Command pattern.
  Future<bool> _addAssetToTimeline(
    MediaAssetModel asset, {
    bool showFeedback = true,
  }) async {
    final project = ref.read(currentProjectProvider);
    if (project == null) return false;

    // Determine which track type this asset goes on
    final TrackType targetTrackType;
    switch (asset.mediaType) {
      case MediaType.video:
      case MediaType.image:
        targetTrackType = TrackType.video;
        break;
      case MediaType.audio:
        targetTrackType = TrackType.audio;
        break;
    }

    // Find the first track of the matching type
    final targetTrack =
        project.tracks.where((t) => t.trackType == targetTrackType).firstOrNull;

    if (targetTrack == null) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No ${targetTrackType.name} track found')),
        );
      }
      return false;
    }

    // Calculate the start position: append after the last clip on the track
    final lastClipEnd = targetTrack.clips.isEmpty
        ? 0
        : targetTrack.clips
            .map((c) => c.startMs + c.durationMs)
            .reduce((a, b) => a > b ? a : b);

    final clipDurationMs = asset.mediaType == MediaType.image
        ? ((asset.durationMs ?? 0) > 0 ? asset.durationMs! : 5000)
        : asset.durationMs;
    if (clipDurationMs == null || clipDurationMs <= 0) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not read the duration for ${asset.fileName}.'),
          ),
        );
      }
      return false;
    }

    // Call into the Rust engine to add the clip
    final clipInfo = await ref.read(editorProvider.notifier).addClipToTrack(
          trackId: targetTrack.id,
          assetId: asset.id,
          startMs: lastClipEnd,
          durationMs: clipDurationMs,
        );

    if (clipInfo != null) {
      // Update the Flutter model to reflect the new clip
      final clip = ClipModel(
        id: clipInfo.id,
        assetId: asset.id,
        startMs: lastClipEnd,
        durationMs: clipDurationMs,
      );
      ref.read(projectProvider.notifier).addClipToTrack(targetTrack.id, clip);

      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${asset.fileName} to ${targetTrack.name}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
      return true;
    } else {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add clip')),
        );
      }
      return false;
    }
  }

  /// Add a text overlay to the text track.
  Future<void> _addTextToTimeline(String text, double fontSize) async {
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

    // Create a placeholder text clip (5 seconds default duration)
    const defaultDurationMs = 5000;
    final clipId = const Uuid().v4();
    final clip = ClipModel(
      id: clipId,
      assetId: 'text_$clipId',
      startMs: lastClipEnd,
      durationMs: defaultDurationMs,
    );

    // Update the Flutter model immediately for responsiveness
    ref.read(projectProvider.notifier).addClipToTrack(textTrack.id, clip);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "$text" to ${textTrack.name}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// Open Android's gallery-style picker for photos and videos.
  Future<void> _importMedia() async {
    await _runMediaImport(() async {
      final files = await ImagePicker().pickMultipleMedia(limit: 20);
      return files
          .map((file) => _PickedMedia(path: file.path, name: file.name))
          .toList();
    });
  }

  Future<void> _importAudio() async {
    await _runMediaImport(() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      return result?.files
              .map((file) => _PickedMedia(path: file.path, name: file.name))
              .toList() ??
          const [];
    });
  }

  Future<void> _browseMediaFiles() async {
    await _runMediaImport(() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp4',
          'avi',
          'mov',
          'mkv',
          'webm',
          'flv',
          'wmv',
          '3gp',
          'mp3',
          'wav',
          'aac',
          'flac',
          'ogg',
          'm4a',
          'wma',
          'jpg',
          'jpeg',
          'png',
          'gif',
          'bmp',
          'webp',
        ],
        allowMultiple: true,
      );
      return result?.files
              .map((file) => _PickedMedia(path: file.path, name: file.name))
              .toList() ??
          const [];
    });
  }

  Future<void> _runMediaImport(
    Future<List<_PickedMedia>> Function() pickFiles,
  ) async {
    final editorNotifier = ref.read(editorProvider.notifier);
    editorNotifier.setImporting(true);
    try {
      final pickedFiles = await pickFiles();
      if (pickedFiles.isEmpty) return;

      if (!EngineService.instance.isInitialized &&
          !await EngineService.instance.initialize()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The gallery opened, but the editing engine could not start. Restart the app and try again.',
              ),
            ),
          );
        }
        return;
      }

      var importedCount = 0;
      var timelineAddedCount = 0;
      final failedFiles = <String>[];
      final timelineFailures = <String>[];
      for (final pickedFile in pickedFiles) {
        try {
          final sourcePath = pickedFile.path;
          if (sourcePath == null || sourcePath.isEmpty) {
            throw StateError('The selected file could not be opened.');
          }

          final copy = await _mediaLibrary.copyIntoLibrary(
            sourcePath: sourcePath,
            fileName: pickedFile.name,
          );

          final assetInfo = await editorNotifier.importMedia(copy.path);
          if (assetInfo == null) {
            await copy.delete();
            throw StateError('The editing engine could not read this format.');
          }

          await ref.read(projectProvider.notifier).importMedia(
                assetInfo.filePath,
                pickedFile.name,
                _mediaTypeFromString(assetInfo.mediaType),
                assetId: assetInfo.id,
                durationMs: assetInfo.durationMs?.toInt(),
                width: assetInfo.width?.toInt(),
                height: assetInfo.height?.toInt(),
                fileSizeBytes: assetInfo.fileSizeBytes.toInt(),
                codec: assetInfo.codec,
                bitrate: assetInfo.bitrate?.toInt(),
              );
          importedCount++;

          final importedAsset = ref
              .read(currentProjectProvider)
              ?.mediaAssets
              .where((asset) => asset.id == assetInfo.id)
              .firstOrNull;
          if (importedAsset == null) {
            timelineFailures.add(pickedFile.name);
            continue;
          }

          if (await _addAssetToTimeline(importedAsset, showFeedback: false)) {
            timelineAddedCount++;
          } else {
            timelineFailures.add(pickedFile.name);
          }
        } catch (error, stackTrace) {
          failedFiles.add(pickedFile.name);
          developer.log(
            'Media import failed for ${pickedFile.name}',
            name: 'EditorScreen',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      if (!mounted) return;
      final projectSaved = importedCount == 0 ||
          await ref.read(projectProvider.notifier).saveCurrentProject();
      final messages = <String>[];
      if (timelineAddedCount > 0) {
        messages.add(
          'Added $timelineAddedCount item${timelineAddedCount == 1 ? '' : 's'} to the timeline.',
        );
      }
      if (failedFiles.isNotEmpty) {
        messages.add('Could not import: ${failedFiles.take(2).join(', ')}.');
      }
      if (timelineFailures.isNotEmpty) {
        messages.add(
          'Imported, but could not add to the timeline: ${timelineFailures.take(2).join(', ')}.',
        );
      }
      if (messages.isEmpty) {
        messages.add('No items were imported.');
      }
      if (!projectSaved) {
        messages.add('Project save failed; save again before closing.');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messages.join(' '))),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Could not open media picker',
        name: 'EditorScreen',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the media picker: $error')),
        );
      }
    } finally {
      if (mounted) {
        editorNotifier.setImporting(false);
      }
    }
  }

  /// Map the string media type returned by the Rust engine to the
  /// Dart [MediaType] enum.
  MediaType _mediaTypeFromString(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return MediaType.video;
      case 'audio':
        return MediaType.audio;
      case 'image':
        return MediaType.image;
      default:
        return MediaType.video;
    }
  }
}

class _PickedMedia {
  const _PickedMedia({required this.path, required this.name});

  final String? path;
  final String name;
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Phase F.2: fixed width (70px) instead of Expanded so the tab row
    // can scroll horizontally when there are more than ~6 tabs.
    return SizedBox(
      width: 70,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? AppTheme.primary : AppTheme.textDisabled,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? AppTheme.primary : AppTheme.textDisabled,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaAssetItem extends StatelessWidget {
  final MediaAssetModel asset;
  final VoidCallback onAddToTimeline;

  const _MediaAssetItem({
    required this.asset,
    required this.onAddToTimeline,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = asset.mediaType == MediaType.video;
    final isAudio = asset.mediaType == MediaType.audio;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onAddToTimeline,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 64,
                height: 48,
                decoration: BoxDecoration(
                  color: isVideo
                      ? AppTheme.videoTrackColor.withOpacity(0.15)
                      : isAudio
                          ? AppTheme.audioTrackColor.withOpacity(0.15)
                          : AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      isVideo
                          ? Icons.videocam
                          : isAudio
                              ? Icons.audiotrack
                              : Icons.image,
                      color: isVideo
                          ? AppTheme.videoTrackColor
                          : isAudio
                              ? AppTheme.audioTrackColor
                              : AppTheme.primary,
                      size: 24,
                    ),
                    if (asset.durationMs != null)
                      Positioned(
                        bottom: 2,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            Duration(milliseconds: asset.durationMs!).formatted,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.fileName,
                      style: context.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (asset.width != null && asset.height != null)
                          '${asset.width}×${asset.height}',
                        if (asset.durationMs != null)
                          Duration(milliseconds: asset.durationMs!).formatted,
                        if (asset.fileSizeBytes > 0)
                          _formatBytes(asset.fileSizeBytes),
                      ].join(' · '),
                      style: context.textTheme.labelSmall
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              // Add button
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.add, size: 18, color: AppTheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1073741824)
      return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

// Note: _EffectCard replaced by EffectCatalog widget in effect_catalog.dart

// ─── Phase F.2: Helper widgets for the editor screen ───────────────────

/// Compact horizontal loudness bar — used in the Audio Meter Bridge.
/// Renders integrated LUFS, true-peak, target, and a compliance indicator
/// in a single line.
class _CompactLoudnessBar extends StatelessWidget {
  final LoudnessReading reading;
  final LoudnessTarget target;

  const _CompactLoudnessBar({required this.reading, required this.target});

  @override
  Widget build(BuildContext context) {
    final loudnessOk =
        (reading.integratedLufs - target.integratedTarget).abs() <=
            target.integratedTolerance + 0.5;
    final truePeakOk = reading.truePeakDbtp <= target.truePeakCeiling;
    final allOk = loudnessOk && truePeakOk;

    return Row(
      children: [
        _Metric(
          label: 'I',
          value: '${reading.integratedLufs.toStringAsFixed(1)}',
          unit: 'LUFS',
          target: '${target.integratedTarget.toStringAsFixed(0)}',
          ok: loudnessOk,
        ),
        const SizedBox(width: AppTheme.spacing12),
        _Metric(
          label: 'S',
          value: '${reading.shortTermLufs.toStringAsFixed(1)}',
          unit: 'LUFS',
          target: '',
          ok: true,
        ),
        const SizedBox(width: AppTheme.spacing12),
        _Metric(
          label: 'M',
          value: '${reading.momentaryLufs.toStringAsFixed(1)}',
          unit: 'LUFS',
          target: '',
          ok: true,
        ),
        const SizedBox(width: AppTheme.spacing12),
        _Metric(
          label: 'TP',
          value: '${reading.truePeakDbtp.toStringAsFixed(1)}',
          unit: 'dBTP',
          target: '≤ ${target.truePeakCeiling.toStringAsFixed(0)}',
          ok: truePeakOk,
        ),
        const SizedBox(width: AppTheme.spacing12),
        // Compliance pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (allOk ? Colors.green : Colors.red).withOpacity(0.15),
            border: Border.all(
                color: (allOk ? Colors.green : Colors.red).withOpacity(0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                allOk ? Icons.check_circle : Icons.warning,
                size: 12,
                color: allOk ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 4),
              Text(
                allOk ? 'COMPLIANT' : 'NON-COMPLIANT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: allOk ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                target.label,
                style: TextStyle(
                  fontSize: 9,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String target;
  final bool ok;

  const _Metric({
    required this.label,
    required this.value,
    required this.unit,
    required this.target,
    required this.ok,
  });

  @override
  Widget build(BuildContext context) {
    final color = ok ? Colors.green : Colors.red;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 2),
        Text(
          unit,
          style: TextStyle(
            fontSize: 9,
            color: color,
          ),
        ),
        if (target.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            '($target)',
            style: TextStyle(
              fontSize: 9,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Phase F.2: small badge showing the current safe-zone mode, displayed
/// at the top-right of the preview viewport.
class _SafeZoneBadge extends StatelessWidget {
  final SafeZoneMode mode;

  const _SafeZoneBadge({required this.mode});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (mode) {
      SafeZoneMode.broadcast => ('SAFE:BC', Colors.blue),
      SafeZoneMode.social => ('SAFE:SO', Colors.purple),
      SafeZoneMode.composition => ('SAFE:3RDS', Colors.orange),
      SafeZoneMode.off => ('', Colors.grey),
    };
    if (mode == SafeZoneMode.off) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ─── Phase F.3: Live loudness polling widgets ──────────────────────────

/// Polls the engine's `analyzeLoudness` FFI on a timer and rebuilds its
/// child with the latest reading.
///
/// Used by the Audio Meter Bridge (compact) and the _LoudnessMeterDialog
/// (full). The poll interval is 1 second — loudness is an integrated
/// measurement, faster polling just wastes CPU.
///
/// video: 1-second poll interval, upgrade to real-time streaming loudness
/// when the audio pipeline supports per-frame LUFS output.
class _LiveLoudnessBuilder extends StatefulWidget {
  final LoudnessTarget target;
  final Widget Function(BuildContext context, LoudnessReading reading) builder;

  const _LiveLoudnessBuilder({
    required this.target,
    required this.builder,
  });

  @override
  State<_LiveLoudnessBuilder> createState() => _LiveLoudnessBuilderState();
}

class _LiveLoudnessBuilderState extends State<_LiveLoudnessBuilder> {
  Timer? _timer;
  LoudnessReading _reading = LoudnessReading.silent;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!EngineService.instance.isInitialized) return;
    try {
      // Phase F.4: poll the engine's last computed loudness reading.
      // The engine updates this whenever audio is mixed (preview playback
      // or export). If no audio has been analyzed yet, this returns null
      // and we display silence.
      final result = await getCurrentLoudness();
      if (result == null) {
        if (mounted) {
          setState(() => _reading = LoudnessReading.silent);
        }
        return;
      }
      final reading = LoudnessReading(
        integratedLufs:
            (result['integrated_lufs'] as num?)?.toDouble() ?? -70.0,
        shortTermLufs: (result['short_term_lufs'] as num?)?.toDouble() ?? -70.0,
        momentaryLufs: (result['momentary_lufs'] as num?)?.toDouble() ?? -70.0,
        truePeakDbtp: (result['true_peak_dbtp'] as num?)?.toDouble() ?? -70.0,
      );
      if (mounted) {
        setState(() => _reading = reading);
      }
    } catch (e) {
      developer.log('_LiveLoudnessBuilder refresh failed: $e',
          name: 'LoudnessMeter');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _reading);
  }
}

/// Phase F.3: Full loudness meter dialog — stateful, polls every 500ms,
/// lets the user switch the target (EBU R128 / ATSC A/85 / YouTube / TikTok / Podcast).
class _LoudnessMeterDialog extends StatefulWidget {
  const _LoudnessMeterDialog();

  @override
  State<_LoudnessMeterDialog> createState() => _LoudnessMeterDialogState();
}

class _LoudnessMeterDialogState extends State<_LoudnessMeterDialog> {
  LoudnessTarget _target = LoudnessTarget.ebuR128;
  Timer? _timer;
  LoudnessReading _reading = LoudnessReading.silent;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer =
        Timer.periodic(const Duration(milliseconds: 500), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!EngineService.instance.isInitialized) return;
    try {
      // Phase F.4: poll the engine's last computed loudness reading.
      // Same pattern as _LiveLoudnessBuilder but at 2x the rate (500ms).
      final result = await getCurrentLoudness();
      if (result == null) {
        if (mounted) {
          setState(() => _reading = LoudnessReading.silent);
        }
        return;
      }
      final reading = LoudnessReading(
        integratedLufs:
            (result['integrated_lufs'] as num?)?.toDouble() ?? -70.0,
        shortTermLufs: (result['short_term_lufs'] as num?)?.toDouble() ?? -70.0,
        momentaryLufs: (result['momentary_lufs'] as num?)?.toDouble() ?? -70.0,
        truePeakDbtp: (result['true_peak_dbtp'] as num?)?.toDouble() ?? -70.0,
      );
      if (mounted) {
        setState(() => _reading = reading);
      }
    } catch (e) {
      developer.log('_LoudnessMeterDialog refresh failed: $e',
          name: 'LoudnessMeter');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing16),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Loudness Meter',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacing8),
              // Target picker
              DropdownButton<LoudnessTarget>(
                value: _target,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: LoudnessTarget.ebuR128,
                    child: Text('EBU R128 (−23 LUFS) — EU broadcast'),
                  ),
                  DropdownMenuItem(
                    value: LoudnessTarget.atscA85,
                    child: Text('ATSC A/85 (−24 LKFS) — US broadcast'),
                  ),
                  DropdownMenuItem(
                    value: LoudnessTarget.youtube,
                    child: Text('YouTube (−14 LUFS)'),
                  ),
                  DropdownMenuItem(
                    value: LoudnessTarget.tiktok,
                    child: Text('TikTok (−18 LUFS)'),
                  ),
                  DropdownMenuItem(
                    value: LoudnessTarget.podcast,
                    child: Text('Apple Podcasts (−16 LUFS)'),
                  ),
                ],
                onChanged: (t) {
                  if (t != null) setState(() => _target = t);
                },
              ),
              const SizedBox(height: AppTheme.spacing16),
              AudioLoudnessMeter(
                reading: _reading,
                target: _target,
              ),
              const SizedBox(height: AppTheme.spacing8),
              // Refresh button (manual refresh — useful when the engine
              // doesn't have continuous audio playback running)
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Reads from the engine audio cache. Play the timeline '
                      'to populate; loudness updates every 500ms.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
