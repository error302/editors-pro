import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/cloud/presentation/cloud_screen.dart';
import 'features/editor/presentation/editor_screen.dart';
import 'features/editor/providers/editor_provider.dart';
import 'features/export/presentation/export_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/projects/presentation/project_home_screen.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/templates/presentation/template_browser.dart';
import 'l10n/app_localizations.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Phase B.7: gate the /cloud route behind the experimental feature
  // flag so users don't see a non-functional cloud screen. The flag
  // can be toggled in Settings > Experimental.
  final showCloud = ref.watch(
    settingsProvider.select((s) => s.experimentalCloudSync),
  );

  return GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const ProjectHomeScreen(),
      ),
      GoRoute(
        path: '/editor/:projectId',
        name: 'editor',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          return EditorScreen(projectId: projectId);
        },
      ),
      GoRoute(
        path: '/export/:projectId',
        name: 'export',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          return ExportScreen(projectId: projectId);
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // Phase B.7: only register the /cloud route if the experimental
      // flag is enabled. This also removes it from the navigation drawer
      // for users who haven't opted in.
      if (showCloud)
        GoRoute(
          path: '/cloud',
          name: 'cloud',
          builder: (context, state) => const CloudScreen(),
        ),
      GoRoute(
        path: '/templates',
        name: 'templates',
        builder: (context, state) => const TemplateBrowserScreen(),
      ),
    ],
  );
});

class EditorsProApp extends ConsumerStatefulWidget {
  const EditorsProApp({super.key});

  @override
  ConsumerState<EditorsProApp> createState() => _EditorsProAppState();
}

class _EditorsProAppState extends ConsumerState<EditorsProApp> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  String? _lastShownError;

  @override
  void initState() {
    super.initState();
    // Phase E.2: surface `EditorState.lastError` as a global SnackBar.
    // The previous code set `lastError` on every error but never showed
    // it to the user. This listener watches the editor state and shows
    // a SnackBar whenever a new error appears.
    // The actual subscription happens in build() via ref.listen.
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // Phase E.6: react to the user's theme mode preference.
    final themeMode = ref.watch(
      settingsProvider.select((s) => s.themeModeEnum),
    );

    // Phase E.2: listen for editor errors and show a SnackBar.
    // Using ref.listen so we only react to changes, not on every build.
    ref.listen<EditorState>(editorProvider, (previous, next) {
      if (next.lastError != null && next.lastError != _lastShownError) {
        _lastShownError = next.lastError;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final messenger = _scaffoldMessengerKey.currentState;
          if (messenger == null) return;
          messenger.showSnackBar(
            SnackBar(
              content: Text(next.lastError!),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Dismiss',
                textColor: Colors.white,
                onPressed: messenger.hideCurrentSnackBar,
              ),
            ),
          );
        });
      } else if (next.lastError == null) {
        // Error was cleared — reset our dedup token.
        _lastShownError = null;
      }
    });

    return MaterialApp.router(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'EDITORS-PRO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      // Phase E.7: localization delegates + supported locales.
      // The AppLocalizations class is generated from lib/l10n/*.arb
      // by `flutter gen-l10n` (configured in l10n.yaml).
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('es'),
        Locale('fr'),
        Locale('pt'),
        Locale('hi'),
        Locale('zh'),
      ],
      routerConfig: router,
    );
  }
}
