import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/proxy_provider.dart';

/// A small badge that shows when a proxy is being used for preview.
///
/// Displays:
/// - "PROXY" in amber/yellow when viewing a proxy instead of the original
/// - "4K→720p" style text indicating original → proxy resolution
/// - An animated pulse when proxy generation is in progress
class ProxyStatusBadge extends ConsumerWidget {
  const ProxyStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyState = ref.watch(proxyProvider);

    // If proxy quality is off, don't show the badge
    if (proxyState.quality == 'Off') return const SizedBox.shrink();

    // If generating, show animated badge
    if (proxyState.isGenerating && proxyState.generatingAssetId != null) {
      return _ProxyGeneratingBadge(quality: proxyState.quality);
    }

    // If there are active proxies, show proxy indicator
    if (proxyState.activeProxyCount > 0) {
      return _buildBadge(
        label: 'PROXY',
        sublabel: proxyState.quality,
        color: AppTheme.warning,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildBadge({
    required String label,
    required String sublabel,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            sublabel,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated badge shown while proxy is being generated.
class _ProxyGeneratingBadge extends StatefulWidget {
  const _ProxyGeneratingBadge({required this.quality});
  final String quality;

  @override
  State<_ProxyGeneratingBadge> createState() => _ProxyGeneratingBadgeState();
}

class _ProxyGeneratingBadgeState extends State<_ProxyGeneratingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const color = AppTheme.warning;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = 0.4 + (_controller.value * 0.6);
        return Opacity(
          opacity: opacity,
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'PROXY',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              widget.quality,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget that resolves the proxy resolution label for the currently
/// selected clip, displaying e.g. "4K→720p" on the viewport.
class ProxyResolutionBadge extends ConsumerWidget {
  const ProxyResolutionBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyState = ref.watch(proxyProvider);

    if (proxyState.quality == 'Off') return const SizedBox.shrink();

    // Find a proxy info entry to display the resolution mapping
    final activeInfo = proxyState.proxyInfo.values.firstWhere(
      (info) => info.hasProxy,
      orElse: () => const ProxyInfoData(
        assetId: '',
        originalPath: '',
        quality: '',
        originalWidth: 0,
        originalHeight: 0,
      ),
    );

    if (activeInfo.assetId.isEmpty) return const SizedBox.shrink();

    final origLabel = ProxyInfoData.resolutionLabel(
      activeInfo.originalWidth,
      activeInfo.originalHeight,
    );
    final proxyLabel =
        activeInfo.proxyWidth != null && activeInfo.proxyHeight != null
            ? ProxyInfoData.resolutionLabel(
                activeInfo.proxyWidth!,
                activeInfo.proxyHeight!,
              )
            : proxyState.quality;

    const color = AppTheme.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Text(
        '$origLabel→$proxyLabel',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
