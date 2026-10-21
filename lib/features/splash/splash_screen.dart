import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';

/// Polished, animated splash screen.
///
/// Reads the `onboarding_completed` SharedPreferences flag and routes
/// the user to either `/onboarding` (first run) or `/` (returning user).
/// While that async check runs, we display a branded loading animation.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loaderController;
  late final Animation<double> _loaderTween;

  @override
  void initState() {
    super.initState();

    // Indeterminate pill animation — slides left-to-right and back.
    _loaderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    // Pill is 40px wide on a 120px track → travel range = 80px.
    _loaderTween = Tween<double>(begin: 0.0, end: 80.0).animate(
      CurvedAnimation(parent: _loaderController, curve: Curves.easeInOut),
    );

    _navigate();
  }

  @override
  void dispose() {
    _loaderController.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;

    if (!mounted) return;

    if (onboardingCompleted) {
      context.go('/');
    } else {
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─── Logo ──────────────────────────────────────────────
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  boxShadow: AppTheme.primaryGlow(opacity: 0.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  child: Image.asset(
                    'assets/icons/logo.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ─── Brand wordmark (gradient) ─────────────────────────
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppTheme.primaryGradient.createShader(bounds),
                child: const Text(
                  'EDITORS-PRO',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 4,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // ─── Tagline ───────────────────────────────────────────
              const Text(
                'Professional Video Editor',
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 1,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 40),

              // ─── Indeterminate loading pill ────────────────────────
              SizedBox(
                width: 120,
                height: 4,
                child: Stack(
                  children: [
                    // Track
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                      ),
                    ),
                    // Animated inner pill
                    AnimatedBuilder(
                      animation: _loaderTween,
                      builder: (context, _) {
                        return Positioned(
                          left: _loaderTween.value,
                          top: 0,
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusFull,
                              ),
                              boxShadow: AppTheme.primaryGlow(opacity: 0.6),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 600.ms)
              .scale(begin: const Offset(0.95, 0.95)),
        ),
      ),
    );
  }
}
