import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase F.2: Audio Mixer panel.
///
/// Per-track mixer with volume fader, pan, mute, solo, and a master
/// fader. Calls `setTrackVolume` and `toggleTrackVisibility` (mute)
/// on the engine.
///
/// The amateur move is to mix by eye on phone speakers. The pro move
/// is to mix at conversation volume on reference monitors or headphones,
/// verify with the loudness meter, and never ship without checking the
/// master fader has headroom. See persona/skills/loudness-target/SKILL.md.
class AudioMixerPanel extends StatefulWidget {
  final List<MixerTrack> tracks;
  final MixerMaster master;
  final void Function(String trackId, double volume) onVolumeChanged;
  final void Function(String trackId, double pan) onPanChanged;
  final void Function(String trackId, bool muted) onMuteToggled;
  final void Function(String trackId, bool solo) onSoloToggled;
  final void Function(double masterVolume) onMasterVolumeChanged;
  final VoidCallback? onOpenLoudnessMeter;

  const AudioMixerPanel({
    super.key,
    required this.tracks,
    required this.master,
    required this.onVolumeChanged,
    required this.onPanChanged,
    required this.onMuteToggled,
    required this.onSoloToggled,
    required this.onMasterVolumeChanged,
    this.onOpenLoudnessMeter,
  });

  @override
  State<AudioMixerPanel> createState() => _AudioMixerPanelState();
}

class _AudioMixerPanelState extends State<AudioMixerPanel> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Audio Mixer',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (widget.onOpenLoudnessMeter != null)
              IconButton(
                icon: const Icon(Icons.analytics_outlined, size: 18),
                tooltip: 'Open Loudness Meter',
                onPressed: widget.onOpenLoudnessMeter,
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing4),
        Text(
          'Mix at conversation volume. Never ship without checking '
          'the loudness meter and master headroom.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Track channels (horizontal scroll)
        Expanded(
          child: widget.tracks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.equalizer,
                          size: 48, color: AppTheme.textSecondary),
                      const SizedBox(height: AppTheme.spacing8),
                      Text('No audio tracks yet.',
                          style: TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.tracks.length + 1, // +1 for master
                  itemBuilder: (context, i) {
                    if (i < widget.tracks.length) {
                      return _MixerChannel(
                        track: widget.tracks[i],
                        onVolumeChanged: (v) =>
                            widget.onVolumeChanged(widget.tracks[i].id, v),
                        onPanChanged: (v) =>
                            widget.onPanChanged(widget.tracks[i].id, v),
                        onMuteToggled: (b) =>
                            widget.onMuteToggled(widget.tracks[i].id, b),
                        onSoloToggled: (b) =>
                            widget.onSoloToggled(widget.tracks[i].id, b),
                      );
                    }
                    return _MasterChannel(
                      master: widget.master,
                      onVolumeChanged: widget.onMasterVolumeChanged,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MixerChannel extends StatelessWidget {
  final MixerTrack track;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onPanChanged;
  final ValueChanged<bool> onMuteToggled;
  final ValueChanged<bool> onSoloToggled;

  const _MixerChannel({
    required this.track,
    required this.onVolumeChanged,
    required this.onPanChanged,
    required this.onMuteToggled,
    required this.onSoloToggled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      margin: const EdgeInsets.only(right: AppTheme.spacing8),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          // Track name
          Text(
            track.name,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppTheme.spacing4),
          // Mute / Solo row
          Row(
            children: [
              Expanded(
                child: _MiniButton(
                  label: 'M',
                  active: track.muted,
                  activeColor: Colors.red,
                  onPressed: () => onMuteToggled(!track.muted),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _MiniButton(
                  label: 'S',
                  active: track.solo,
                  activeColor: Colors.yellow.shade700,
                  onPressed: () => onSoloToggled(!track.solo),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing8),
          // Pan knob
          Text('PAN', style: TextStyle(fontSize: 9, color: AppTheme.textSecondary)),
          RotatedBox(
            quarterTurns: 1,
            child: Slider(
              value: track.pan,
              min: -1,
              max: 1,
              divisions: 20,
              onChanged: onPanChanged,
            ),
          ),
          Text(
            track.pan == 0
                ? 'C'
                : track.pan < 0
                    ? 'L${(track.pan.abs() * 100).round()}'
                    : 'R${(track.pan * 100).round()}',
            style: const TextStyle(fontSize: 9),
          ),
          const SizedBox(height: AppTheme.spacing4),
          // Volume fader
          Expanded(
            child: RotatedBox(
              quarterTurns: 1,
              child: Slider(
                value: track.volume,
                min: 0,
                max: 1,
                divisions: 100,
                onChanged: onVolumeChanged,
              ),
            ),
          ),
          // dB readout
          Text(
            _volumeToDb(track.volume),
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  String _volumeToDb(double v) {
    if (v <= 0.001) return '−∞';
    final db = 20 * math.log(v) / math.ln10;
    return '${db.toStringAsFixed(1)} dB';
  }
}

class _MasterChannel extends StatelessWidget {
  final MixerMaster master;
  final ValueChanged<double> onVolumeChanged;

  const _MasterChannel({
    required this.master,
    required this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      margin: const EdgeInsets.only(right: AppTheme.spacing8),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primary.withOpacity(0.5), width: 2),
      ),
      child: Column(
        children: [
          const Text(
            'MASTER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: AppTheme.spacing8),
          Expanded(
            child: RotatedBox(
              quarterTurns: 1,
              child: Slider(
                value: master.volume,
                min: 0,
                max: 1,
                divisions: 100,
                onChanged: onVolumeChanged,
              ),
            ),
          ),
          Text(
            _volumeToDb(master.volume),
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  String _volumeToDb(double v) {
    if (v <= 0.001) return '−∞';
    final db = 20 * math.log(v) / math.ln10;
    return '${db.toStringAsFixed(1)} dB';
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onPressed;

  const _MiniButton({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Material(
        color: active ? activeColor : AppTheme.surface,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: active ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MixerTrack {
  final String id;
  final String name;
  final double volume;
  final double pan; // -1 (L) to +1 (R)
  final bool muted;
  final bool solo;

  MixerTrack({
    required this.id,
    required this.name,
    this.volume = 1.0,
    this.pan = 0.0,
    this.muted = false,
    this.solo = false,
  });
}

class MixerMaster {
  final double volume;

  const MixerMaster({this.volume = 1.0});
}
