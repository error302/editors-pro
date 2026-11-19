import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/social_share_service.dart';

/// Sharing is an explicit handoff; final publishing happens in the chosen app.
class SocialSharePanel extends StatefulWidget {
  const SocialSharePanel({required this.filePath, super.key, this.service});

  final String filePath;
  final SocialShareService? service;

  @override
  State<SocialSharePanel> createState() => _SocialSharePanelState();
}

class _SocialSharePanelState extends State<SocialSharePanel> {
  final _caption = TextEditingController();
  late final SocialShareService _service;
  Set<SocialShareTarget> _available = {SocialShareTarget.more};
  bool _checking = true;
  bool _sharing = false;
  String? _availabilityMessage;
  String? _feedback;
  bool _feedbackIsError = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SocialShareService();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    try {
      final available = await _service.availableTargets();
      if (!mounted) return;
      setState(() => _available = available);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _availabilityMessage =
            'App shortcuts could not be checked. Try More share options.';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void didUpdateWidget(covariant SocialSharePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _feedback = null;
      _feedbackIsError = false;
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _copyCaption() async {
    try {
      await Clipboard.setData(ClipboardData(text: _caption.text));
      if (!mounted) return;
      setState(() {
        _feedback = 'Caption copied';
        _feedbackIsError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _feedback =
            'Could not copy the caption. Select and copy the text manually.';
        _feedbackIsError = true;
      });
    }
  }

  Future<void> _share(SocialShareTarget target) async {
    if (_sharing) return;
    final sharedPath = widget.filePath;
    FocusScope.of(context).unfocus();
    final renderObject = context.findRenderObject();
    final origin = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;
    setState(() {
      _sharing = true;
      _feedback = null;
      _feedbackIsError = false;
    });
    try {
      final outcome = await _service.share(
        filePath: sharedPath,
        target: target,
        caption: _caption.text,
        sharePositionOrigin: origin,
      );
      if (!mounted || widget.filePath != sharedPath) return;
      setState(() {
        _feedback = switch (outcome) {
          SocialShareOutcome.handoffStarted => target == SocialShareTarget.more
              ? 'Sharing options opened. Finish sharing in the app you choose.'
              : 'Finish sharing in ${target.label}. Review the account and audience there.',
          SocialShareOutcome.dismissed => 'Sharing was closed.',
          SocialShareOutcome.unknown =>
            'Sharing was requested. Check the receiving app to finish.',
        };
      });
    } catch (error) {
      if (!mounted || widget.filePath != sharedPath) return;
      setState(() {
        _feedback = _shareError(error, target);
        _feedbackIsError = true;
        if (error is PlatformException && error.code == 'APP_UNAVAILABLE') {
          _available = {..._available}..remove(target);
          _available.add(SocialShareTarget.more);
        }
      });
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _shareError(Object error, SocialShareTarget target) {
    if (error is PlatformException) {
      if (error.code == 'APP_UNAVAILABLE') {
        return '${target == SocialShareTarget.more ? 'The chosen app' : target.label} '
            'is unavailable for this video. Use More share options.';
      }
      return error.message ?? 'Could not open video sharing. Please try again.';
    }
    if (error is StateError) return error.message.toString();
    if (error is ArgumentError) return error.message.toString();
    if (error is MissingPluginException) {
      return 'Sharing is unavailable in this build. The exported video is still saved.';
    }
    return 'Could not open video sharing. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Share your video', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Choose an app, review your account and audience, then finish sharing there.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _caption,
            enabled: !_sharing,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Caption (optional)',
              hintText: 'Add a caption or hashtags',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Copy caption',
                onPressed: _sharing ? null : _copyCaption,
                icon: const Icon(Icons.copy_outlined),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Some apps ignore captions. Copy yours and paste it in the receiving app.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final target in SocialShareTarget.values)
                if (target != SocialShareTarget.more)
                  Tooltip(
                    message: _available.contains(target)
                        ? 'Share video to ${target.label}'
                        : '${target.label} unavailable. Use More share options.',
                    child: OutlinedButton(
                      onPressed:
                          !_sharing && !_checking && _available.contains(target)
                              ? () => _share(target)
                              : null,
                      child: Text(target.label),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _checking
                ? 'Checking available apps…'
                : _availabilityMessage ??
                    'Unavailable apps are dimmed. Use More share options for other apps.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sharing ? null : () => _share(SocialShareTarget.more),
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              label: const Text('More share options'),
            ),
          ),
          if (_feedback != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _feedback!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _feedbackIsError ? theme.colorScheme.error : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
