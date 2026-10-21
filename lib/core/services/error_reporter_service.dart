import 'dart:async';
import 'dart:developer' as developer;

/// Error severity level
enum ErrorSeverity { info, warning, error, critical }

/// Error category
enum ErrorCategory {
  decode,
  render,
  export,
  storage,
  memory,
  project,
  bridge,
  gpu,
  network,
  config,
}

/// A structured error with full context from the engine
class EngineError {
  const EngineError({
    required this.category,
    required this.severity,
    required this.code,
    required this.message,
    required this.timestampMs,
    this.context = const {},
    this.cause,
    this.recoverable = true,
    this.recoveryHint,
  });

  factory EngineError.fromJson(Map<String, dynamic> json) => EngineError(
        category: _parseCategory(json['category'] as String? ?? 'bridge'),
        severity: _parseSeverity(json['severity'] as String? ?? 'error'),
        code: json['code'] as String? ?? 'UNKNOWN',
        message: json['message'] as String? ?? 'Unknown error',
        context: (json['context'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v.toString())) ??
            {},
        cause: json['cause'] as String?,
        timestampMs: json['timestamp_ms'] as int? ?? 0,
        recoverable: json['recoverable'] as bool? ?? true,
        recoveryHint: json['recovery_hint'] as String?,
      );
  final ErrorCategory category;
  final ErrorSeverity severity;
  final String code;
  final String message;
  final Map<String, String> context;
  final String? cause;
  final int timestampMs;
  final bool recoverable;
  final String? recoveryHint;

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'severity': severity.name,
        'code': code,
        'message': message,
        'context': context,
        'cause': cause,
        'timestamp_ms': timestampMs,
        'recoverable': recoverable,
        'recovery_hint': recoveryHint,
      };

  /// Get a user-friendly error message
  String get userMessage {
    switch (severity) {
      case ErrorSeverity.info:
        return message;
      case ErrorSeverity.warning:
        return 'Warning: $message';
      case ErrorSeverity.error:
        return message;
      case ErrorSeverity.critical:
        return 'Critical: $message';
    }
  }

  /// Whether this error should be shown to the user
  bool get shouldShowToUser => severity != ErrorSeverity.info;

  @override
  String toString() => 'EngineError([$severity][$category] $code: $message)';

  static ErrorCategory _parseCategory(String s) {
    return ErrorCategory.values.firstWhere(
      (e) => e.name == s.toLowerCase(),
      orElse: () => ErrorCategory.bridge,
    );
  }

  static ErrorSeverity _parseSeverity(String s) {
    return ErrorSeverity.values.firstWhere(
      (e) => e.name == s.toLowerCase(),
      orElse: () => ErrorSeverity.error,
    );
  }
}

/// Error reporter that collects and manages engine errors
class ErrorReporterService {
  ErrorReporterService._();
  static final ErrorReporterService instance = ErrorReporterService._();

  final List<EngineError> _recentErrors = [];
  static const int _maxRecentErrors = 100;
  final Map<ErrorCategory, int> _errorCounts = {};

  final _errorController = StreamController<EngineError>.broadcast();

  /// Stream of all reported errors
  Stream<EngineError> get onError => _errorController.stream;

  /// Get recent errors
  List<EngineError> get recentErrors => List.unmodifiable(_recentErrors);

  /// Get error count by category
  int errorCount(ErrorCategory category) => _errorCounts[category] ?? 0;

  /// Get total error count
  int get totalErrors => _errorCounts.values.fold(0, (a, b) => a + b);

  /// Report an error from the engine
  void report(EngineError error) {
    // Add to recent errors
    if (_recentErrors.length >= _maxRecentErrors) {
      _recentErrors.removeAt(0);
    }
    _recentErrors.add(error);

    // Update counts
    _errorCounts[error.category] = (_errorCounts[error.category] ?? 0) + 1;

    // Emit to stream
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }

    // Log
    switch (error.severity) {
      case ErrorSeverity.info:
        // Skip logging info-level errors
        break;
      case ErrorSeverity.warning:
        developer.log('[WARNING] ${error.formatLog()}');
        break;
      case ErrorSeverity.error:
        developer.log('[ERROR] ${error.formatLog()}');
        break;
      case ErrorSeverity.critical:
        developer.log('[CRITICAL] ${error.formatLog()}');
        break;
    }
  }

  /// Report a simple error
  void reportSimple(
    ErrorCategory category,
    ErrorSeverity severity,
    String code,
    String message, {
    String? cause,
    Map<String, String>? context,
    bool recoverable = true,
    String? recoveryHint,
  }) {
    report(
      EngineError(
        category: category,
        severity: severity,
        code: code,
        message: message,
        context: context ?? {},
        cause: cause,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        recoverable: recoverable,
        recoveryHint: recoveryHint,
      ),
    );
  }

  /// Clear all errors
  void clear() {
    _recentErrors.clear();
    _errorCounts.clear();
  }

  /// Generate a crash report
  String crashReport() {
    final buffer = StringBuffer();
    buffer.writeln('=== EDITORS-PRO Error Report ===');
    buffer.writeln('Total errors: $totalErrors');
    buffer.writeln('Errors by category:');
    for (final entry in _errorCounts.entries) {
      buffer.writeln('  ${entry.key.name}: ${entry.value}');
    }
    buffer.writeln();
    buffer.writeln('Recent errors:');
    for (final error in _recentErrors.reversed) {
      buffer.writeln('  ${error.formatLog()}');
    }
    buffer.writeln('================================');
    return buffer.toString();
  }

  /// Dispose the service
  void dispose() {
    _errorController.close();
  }
}

/// Extension for formatting EngineError
extension EngineErrorFormatting on EngineError {
  String formatLog() {
    final ctx = context.isEmpty
        ? ''
        : ' [${context.entries.map((e) => '${e.key}=${e.value}').join(', ')}]';
    final causeStr = cause != null ? ' (caused by: $cause)' : '';
    final recoveryStr =
        recoveryHint != null ? ' [recovery: $recoveryHint]' : '';

    return '[$severity][$category] $code: $message$ctx$causeStr$recoveryStr';
  }
}
