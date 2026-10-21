import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/services/crash_reporter.dart';
import 'core/services/engine_service.dart';
import 'core/services/performance_service.dart';
import 'features/onboarding/providers/onboarding_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['Inter'],
      await rootBundle.loadString('assets/fonts/Inter-LICENSE.txt'),
    );
  });
  const ffmpegLicenseProfile = String.fromEnvironment(
    'FFMPEG_LICENSE_PROFILE',
    defaultValue: 'legacy-test',
  );
  LicenseRegistry.addLicense(() async* {
    const licenseText = ffmpegLicenseProfile == 'lgpl-2.1'
        ? 'This app includes FFmpeg 7.1.5 shared libraries under LGPL-2.1-or-later. '
            'The corresponding source is available at '
            'https://ffmpeg.org/releases/ffmpeg-7.1.5.tar.xz. '
            'License text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.'
        : 'This local test build contains legacy FFmpeg Kit native libraries '
            'configured with GPL and version3 components. It is for local testing '
            'only and is not cleared for commercial or public distribution. '
            'The verified FFmpeg 7.1.5 LGPL build is selected only after the '
            'Android libraries have been rebuilt.';
    yield const LicenseEntryWithLineBreaks(
      ['FFmpeg'],
      licenseText,
    );
  });

  // Phase E.12: wire the crash reporter into Flutter's global error
  // handlers. By default this uses LocalCrashBackend (console + in-memory
  // ring buffer). To enable Sentry/Crashlytics, call
  // `CrashReporter.instance.init(SentryCrashBackend())` before `main()`
  // runs — see lib/core/services/crash_reporter.dart for examples.

  // ─── Flutter error handler ────────────────────────────────
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    developer.log(
      'Flutter error: ${details.exceptionAsString()}',
      name: 'FlutterError',
      error: details.exception,
      stackTrace: details.stack,
    );
    // Forward to crash reporter (non-blocking).
    CrashReporter.instance.reportError(
      details.exception,
      details.stack,
      context: {'library': details.library ?? 'unknown'},
      level: CrashLevel.error,
    );
  };

  // ─── Async error handler ──────────────────────────────────
  PlatformDispatcher.instance.onError = (error, stack) {
    developer.log(
      'Uncaught async error: $error',
      name: 'AsyncError',
      error: error,
      stackTrace: stack,
    );
    // Forward to crash reporter. Async errors that escape the Flutter
    // framework are typically fatal — use the `fatal` level so they
    // get priority in the backend's dashboard.
    CrashReporter.instance.reportError(error, stack, level: CrashLevel.fatal);
    return true;
  };

  _initializeAndRun();
}

Future<void> _initializeAndRun() async {
  final perf = PerformanceService.instance..markAppStart();

  // Initialise SharedPreferences eagerly so it is available for
  // the ProviderScope override.
  final sharedPreferences = await SharedPreferences.getInstance();

  try {
    final service = EngineService.instance;
    final success = await service.initialize();

    if (!success) {
      developer.log(
        'Engine initialization failed — app will run in degraded mode',
        name: 'main',
      );
    }

    perf.markEngineReady();

    developer.log(
      'Cold start → engine ready in ${perf.coldStartDuration?.inMilliseconds} ms',
      name: 'Performance',
    );
  } catch (e, st) {
    developer.log(
      'Engine initialization error: $e',
      name: 'main',
      error: e,
      stackTrace: st,
    );
  }

  // Always run the app. Widgets that depend on the engine will
  // gracefully handle the case where it is unavailable.
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const EditorsProApp(),
    ),
  );
}
