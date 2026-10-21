import 'dart:async';

/// Phase E.12: Crash reporting backend abstraction.
///
/// Defines a common interface for crash reporting services (Sentry,
/// Firebase Crashlytics, Bugsnag, etc.) so the engine can report
/// errors without depending on any specific vendor.
///
/// The default implementation is [LocalCrashBackend] which simply
/// logs to console and stores reports in-memory. When the team is
/// ready to integrate a real service, implement this interface and
/// call `CrashReporter.init(backend)` at app startup.
///
/// ## Sentry integration example
///
/// ```dart
/// import 'package:sentry_flutter/sentry_flutter.dart';
///
/// class SentryCrashBackend implements CrashBackend {
///   @override
///   Future<void> reportError(Object error, StackTrace? stackTrace,
///       {Map<String, dynamic>? context}) async {
///     await Sentry.captureException(error, stackTrace: stackTrace);
///   }
///
///   @override
///   Future<void> reportMessage(String message, {CrashLevel level =
///       CrashLevel.info}) async {
///     await Sentry.captureMessage(message, level: _sentryLevel(level));
///   }
/// }
///
/// // In main.dart:
/// await SentryFlutter.init(
///   (options) => options.dsn = 'https://...@sentry.io/...',
///   appRunner: () => runApp(EditorsProApp()),
/// );
/// CrashReporter.init(SentryCrashBackend());
/// ```
///
/// ## Firebase Crashlytics integration example
///
/// ```dart
/// import 'package:firebase_crashlytics/firebase_crashlytics.dart';
///
/// class CrashlyticsBackend implements CrashBackend {
///   @override
///   Future<void> reportError(Object error, StackTrace? stackTrace,
///       {Map<String, dynamic>? context}) async {
///     await FirebaseCrashlytics.instance.recordError(error, stackTrace);
///   }
///
///   @override
///   Future<void> reportMessage(String message,
///       {CrashLevel level = CrashLevel.info}) async {
///     await FirebaseCrashlytics.instance.log(message);
///   }
/// }
/// ```
///
/// Until a backend is configured, [CrashReporter] uses
/// [LocalCrashBackend] which prints to console and accumulates the
/// last 50 errors in memory — enough for debugging during development
/// without sending data to any external service.

/// Severity level for crash reports.
enum CrashLevel {
  /// Debugging information, no action needed.
  debug,

  /// Informational message.
  info,

  /// Warning — something unexpected happened but the app recovered.
  warning,

  /// Error — a non-fatal error occurred.
  error,

  /// Fatal — the app crashed or will crash.
  fatal,
}

/// Backend interface that vendors (Sentry, Crashlytics, etc.) implement.
abstract class CrashBackend {
  /// Report an exception with optional stack trace and context.
  Future<void> reportError(
    Object error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    CrashLevel level = CrashLevel.error,
  });

  /// Report a non-exception message (e.g., a log message that doesn't
  /// have an associated exception).
  Future<void> reportMessage(
    String message, {
    CrashLevel level = CrashLevel.info,
    Map<String, dynamic>? context,
  });

  /// Whether this backend sends data to an external service.
  /// `false` for [LocalCrashBackend], `true` for Sentry/Crashlytics.
  bool get sendsDataExternally;
}

/// Default backend that just logs to console and stores reports in-memory.
///
/// Used during development and when no DSN is configured. Safe to call
/// from any isolate.
class LocalCrashBackend implements CrashBackend {
  final List<CrashRecord> _records = [];
  static const int _maxRecords = 50;

  List<CrashRecord> get records => List.unmodifiable(_records);

  @override
  Future<void> reportError(
    Object error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    CrashLevel level = CrashLevel.error,
  }) async {
    final record = CrashRecord(
      timestamp: DateTime.now(),
      level: level,
      error: error.toString(),
      stackTrace: stackTrace?.toString(),
      context: context ?? {},
      kind: 'error',
    );
    _addRecord(record);
    // Print to console for development visibility.
    // ignore: avoid_print
    print('[CRASH:$level] ${record.error}');
    if (stackTrace != null) {
      // ignore: avoid_print
      print(stackTrace);
    }
  }

  @override
  Future<void> reportMessage(
    String message, {
    CrashLevel level = CrashLevel.info,
    Map<String, dynamic>? context,
  }) async {
    final record = CrashRecord(
      timestamp: DateTime.now(),
      level: level,
      error: message,
      stackTrace: null,
      context: context ?? {},
      kind: 'message',
    );
    _addRecord(record);
    // ignore: avoid_print
    print('[CRASH:$level] $message');
  }

  @override
  bool get sendsDataExternally => false;

  void _addRecord(CrashRecord record) {
    _records.add(record);
    if (_records.length > _maxRecords) {
      _records.removeAt(0);
    }
  }
}

class CrashRecord {
  CrashRecord({
    required this.timestamp,
    required this.level,
    required this.error,
    required this.stackTrace,
    required this.context,
    required this.kind,
  });
  final DateTime timestamp;
  final CrashLevel level;
  final String error;
  final String? stackTrace;
  final Map<String, dynamic> context;
  final String kind;
}

/// Singleton crash reporter that delegates to the configured backend.
///
/// Call `CrashReporter.init(backend)` once at app startup to switch
/// from the default [LocalCrashBackend] to a real backend (Sentry,
/// Crashlytics, etc.). All subsequent calls to [reportError] and
/// [reportMessage] will be forwarded to the configured backend.
class CrashReporter {
  CrashReporter._();
  static final CrashReporter instance = CrashReporter._();

  CrashBackend _backend = LocalCrashBackend();

  /// The currently-configured backend.
  CrashBackend get backend => _backend;

  /// Switch to a different backend. Should be called once at app
  /// startup before any errors are reported.
  // Keep the documented initialization API for backend integrations.
  // ignore: use_setters_to_change_properties
  void init(CrashBackend backend) {
    _backend = backend;
  }

  /// Report an exception. Safe to call from anywhere.
  Future<void> reportError(
    Object error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    CrashLevel level = CrashLevel.error,
  }) async {
    try {
      await _backend.reportError(
        error,
        stackTrace,
        context: context,
        level: level,
      );
    } catch (e) {
      // Don't let the crash reporter itself crash the app.
      // ignore: avoid_print
      print('CrashReporter.reportError failed: $e');
    }
  }

  /// Report a non-exception message.
  Future<void> reportMessage(
    String message, {
    CrashLevel level = CrashLevel.info,
    Map<String, dynamic>? context,
  }) async {
    try {
      await _backend.reportMessage(message, level: level, context: context);
    } catch (e) {
      // ignore: avoid_print
      print('CrashReporter.reportMessage failed: $e');
    }
  }

  /// Convenience: wrap an async callback so any thrown exception is
  /// automatically reported. Returns a Future that resolves to the
  /// callback's result, or `null` if an error was caught and reported.
  Future<T?> guard<T>(
    Future<T> Function() callback, {
    Map<String, dynamic>? context,
    CrashLevel level = CrashLevel.error,
  }) async {
    try {
      return await callback();
    } catch (e, st) {
      await reportError(e, st, context: context, level: level);
      return null;
    }
  }

  /// Convenience: wrap a sync callback so any thrown exception is
  /// automatically reported. Returns the callback's result, or `null`
  /// if an error was caught and reported.
  T? guardSync<T>(
    T Function() callback, {
    Map<String, dynamic>? context,
    CrashLevel level = CrashLevel.error,
  }) {
    try {
      return callback();
    } catch (e, st) {
      reportError(e, st, context: context, level: level);
      return null;
    }
  }
}
