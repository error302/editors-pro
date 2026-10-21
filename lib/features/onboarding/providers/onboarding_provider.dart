import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for SharedPreferences instance.
///
/// Must be overridden in the top-level ProviderScope with an
/// asynchronously-initialised instance of SharedPreferences.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

/// Provider for whether onboarding has been completed.
///
/// Defaults to `false` and is updated by [OnboardingNotifier].
final onboardingCompletedProvider = StateProvider<bool>((ref) => false);

/// Notifier that reads and persists the onboarding-completed flag
/// to SharedPreferences.
class OnboardingNotifier extends StateNotifier<bool> {
  OnboardingNotifier(this._prefs) : super(_prefs.getBool(_key) ?? false);
  final SharedPreferences _prefs;
  static const _key = 'onboarding_completed';

  /// Mark onboarding as completed and persist the flag.
  Future<void> completeOnboarding() async {
    await _prefs.setBool(_key, true);
    state = true;
  }

  /// Whether the user has already finished onboarding.
  bool get isCompleted => state;
}

/// Provider that exposes [OnboardingNotifier].
final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return OnboardingNotifier(prefs);
});
