import 'package:editors_pro/features/export/presentation/export_screen.dart';
import 'package:editors_pro/features/export/providers/export_provider.dart';
import 'package:editors_pro/features/onboarding/providers/onboarding_provider.dart';
import 'package:editors_pro/features/settings/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Android Back from an idle export returns to its editor', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final router = GoRouter(initialLocation: '/export/qa', routes: [
      GoRoute(path: '/editor/:id', builder: (_, __) => const Scaffold(body: Text('Returned to QA editor'))),
      GoRoute(path: '/export/:id', builder: (_, __) => const ExportScreen(projectId: 'qa')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      settingsProvider.overrideWith((ref) => SettingsNotifier(preferences)),
      exportProvider.overrideWith((ref) => ExportNotifier()),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Export Video'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Returned to QA editor'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
