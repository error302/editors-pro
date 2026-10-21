import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/onboarding_provider.dart';

/// Premium three-page onboarding flow.
///
/// Pages:
///   1. Welcome  — branded hero with gradient wordmark
///   2. Edit Like a Pro — timeline / effects / transitions
///   3. Export & Share — 4K export / social share
///
/// Uses a [PageView] with custom pill indicator, gradient CTA, and a
/// Skip button that completes onboarding immediately.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  static const _pageCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _pageCount) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _completeOnboarding() async {
    await ref.read(onboardingProvider.notifier).completeOnboarding();
    if (mounted) {
      context.go('/');
    }
  }

  void _onActionPressed() {
    if (_currentPage < _pageCount - 1) {
      _goToPage(_currentPage + 1);
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ─── Skip button (top-right) ──────────────────────────
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              // ─── PageView ─────────────────────────────────────────
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (index) =>
                      setState(() => _currentPage = index),
                  itemCount: _pageCount,
                  itemBuilder: (context, index) {
                    switch (index) {
                      case 0:
                        return const _WelcomePage();
                      case 1:
                        return const _EditLikeAProPage();
                      case 2:
                        return const _ExportSharePage();
                      default:
                        return const SizedBox.shrink();
                    }
                  },
                ),
              ),

              // ─── Page indicator ───────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: _PageIndicator(
                  pageCount: _pageCount,
                  currentPage: _currentPage,
                  onDotTapped: _goToPage,
                ),
              ),

              // ─── Bottom CTA ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: _GradientCtaButton(
                  label: _currentPage < _pageCount - 1 ? 'Next' : 'Get Started',
                  onPressed: _onActionPressed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Page 1: Welcome ──────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
              boxShadow: AppTheme.primaryGlow(opacity: 0.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
              child: Image.asset(
                'assets/icons/logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 40),

          // "Welcome to"
          const Text(
            'Welcome to',
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),

          // Gradient wordmark
          ShaderMask(
            shaderCallback: (bounds) =>
                AppTheme.primaryGradient.createShader(bounds),
            child: const Text(
              'EDITORS-PRO',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Subtitle
          const Text(
            'Professional mobile video editing\npowered by native performance',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1);
  }
}

// ─── Page 2: Edit Like a Pro ──────────────────────────────────────

class _EditLikeAProPage extends StatelessWidget {
  const _EditLikeAProPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Hero illustration
          SvgPicture.asset(
            AppIcons.onboardingEdit,
            width: 160,
            height: 160,
          ),
          const SizedBox(height: 40),

          // Heading
          const Text(
            'Edit Like a Pro',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Subtitle
          const Text(
            'Multi-track timeline, professional effects,\nand smooth transitions',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 32),

          // Feature pills
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _FeaturePill(label: 'Multi-Track'),
              _FeaturePill(label: 'Effects'),
              _FeaturePill(label: 'Transitions'),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1);
  }
}

// ─── Page 3: Export & Share ───────────────────────────────────────

class _ExportSharePage extends StatelessWidget {
  const _ExportSharePage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Hero illustration
          SvgPicture.asset(
            AppIcons.onboardingExport,
            width: 160,
            height: 160,
          ),
          const SizedBox(height: 40),

          // Heading
          const Text(
            'Export & Share',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Subtitle
          const Text(
            'Export in up to 4K quality and share\ndirectly to social media',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 32),

          // Feature pills
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _FeaturePill(label: '4K Export'),
              _FeaturePill(label: 'Share'),
              _FeaturePill(label: 'Multiple Formats'),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1);
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────

/// Feature pill — surfaceVariant background, primary border, primaryLight label.
class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        border: Border.all(color: AppTheme.primary, width: 1.2),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryLight,
        ),
      ),
    );
  }
}

/// Pill-style page indicator. Active dot uses the brand gradient and
/// stretches to 24px; inactive dots are 8px square pills.
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.pageCount,
    required this.currentPage,
    required this.onDotTapped,
  });
  final int pageCount;
  final int currentPage;
  final ValueChanged<int> onDotTapped;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pageCount, (index) {
        final isActive = index == currentPage;
        return GestureDetector(
          onTap: () => onDotTapped(index),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              gradient: isActive ? AppTheme.primaryGradient : null,
              color: isActive ? null : AppTheme.textDisabled,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
          ),
        );
      }),
    );
  }
}

/// Full-width gradient CTA with primary glow.
class _GradientCtaButton extends StatelessWidget {
  const _GradientCtaButton({
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          boxShadow: AppTheme.primaryGlow(opacity: 0.4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
