import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

typedef _DispatchNative = ffi.Pointer<Utf8> Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);
typedef _DispatchDart = ffi.Pointer<Utf8> Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);
typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8>);

class FfiDispatchWorker {
  FfiDispatchWorker._() : _responses = ReceivePort() {
    _subscription = _responses.listen(_handleMessage);
  }

  final ReceivePort _responses;
  final Completer<SendPort> _ready = Completer<SendPort>();
  final Map<int, Completer<String>> _pending = {};
  late final StreamSubscription<dynamic> _subscription;
  Isolate? _isolate;
  SendPort? _commands;
  int _nextRequestId = 0;
  bool _closed = false;

  static Future<FfiDispatchWorker> start(String? libraryName) async {
    final worker = FfiDispatchWorker._();
    try {
      worker._isolate = await Isolate.spawn<_WorkerBootstrap>(
        _ffiWorkerMain,
        _WorkerBootstrap(libraryName, worker._responses.sendPort),
        onError: worker._responses.sendPort,
        onExit: worker._responses.sendPort,
      );
      worker._commands = await worker._ready.future.timeout(
        const Duration(seconds: 10),
      );
      return worker;
    } catch (_) {
      worker.dispose(force: true);
      rethrow;
    }
  }

  Future<String> dispatch(String method, String argsJson) async {
    if (_closed) throw StateError('Native dispatch worker is closed.');
    final commands = _commands ?? await _ready.future;
    final id = ++_nextRequestId;
    final response = Completer<String>();
    _pending[id] = response;
    commands.send({'id': id, 'method': method, 'args': argsJson});
    return response.future;
  }

  void _handleMessage(dynamic message) {
    if (message == null && _closed) {
      _closeResponsePort();
      return;
    }
    if (message == null) {
      final error = StateError('Native dispatch worker exited unexpectedly.');
      if (!_ready.isCompleted) _ready.completeError(error);
      _failAll(error);
      _closeResponsePort();
      return;
    }
    if (message is SendPort) {
      if (!_ready.isCompleted) _ready.complete(message);
      return;
    }
    if (message is List && message.isNotEmpty) {
      final error =
          StateError('Native dispatch worker failed: ${message.first}');
      if (!_ready.isCompleted) _ready.completeError(error);
      _failAll(error);
      return;
    }
    if (message is! Map) return;

    final startupError = message['startup_error'];
    if (startupError is String) {
      final error = StateError(startupError);
      if (!_ready.isCompleted) _ready.completeError(error);
      _failAll(error);
      return;
    }

    final id = message['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    final error = message['error'];
    if (error is String) {
      completer.completeError(StateError(error));
    } else {
      completer.complete(message['result'] as String);
    }
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  void dispose({bool force = false}) {
    if (_closed) return;
    _closed = true;
    _failAll(StateError('Native dispatch worker was disposed.'));
    if (force) {
      _isolate?.kill(priority: Isolate.immediate);
      _closeResponsePort();
    } else if (_commands != null) {
      _commands!.send({'type': 'dispose'});
    } else {
      _closeResponsePort();
    }
  }

  void _closeResponsePort() {
    unawaited(_subscription.cancel());
    _responses.close();
  }
}

class _WorkerBootstrap {
  const _WorkerBootstrap(this.libraryName, this.responses);

  final String? libraryName;
  final SendPort responses;
}

void _ffiWorkerMain(_WorkerBootstrap bootstrap) {
  final commands = ReceivePort();
  try {
    final dylib = bootstrap.libraryName == null
        ? ffi.DynamicLibrary.process()
        : ffi.DynamicLibrary.open(bootstrap.libraryName!);
    final dispatch = dylib.lookupFunction<_DispatchNative, _DispatchDart>(
      'editors_pro_dispatch',
    );
    final freeString = dylib.lookupFunction<_FreeStringNative, _FreeStringDart>(
      'editors_pro_free_string',
    );

    bootstrap.responses.send(commands.sendPort);
    commands.listen((dynamic message) {
      if (message is! Map) return;
      if (message['type'] == 'dispose') {
        commands.close();
        if (bootstrap.libraryName != null) dylib.close();
        return;
      }

      final id = message['id'];
      final method = message['method'];
      final argsJson = message['args'];
      if (id is! int || method is! String || argsJson is! String) return;

      try {
        final methodPtr = method.toNativeUtf8(allocator: calloc);
        final argsPtr = argsJson.toNativeUtf8(allocator: calloc);
        try {
          final resultPtr = dispatch(methodPtr, argsPtr);
          if (resultPtr == ffi.nullptr) {
            throw StateError('Native dispatch returned null for "$method"');
          }
          try {
            bootstrap.responses.send({
              'id': id,
              'result': resultPtr.toDartString(),
            });
          } finally {
            freeString(resultPtr);
          }
        } finally {
          calloc.free(methodPtr);
          calloc.free(argsPtr);
        }
      } catch (error) {
        bootstrap.responses.send({'id': id, 'error': '$error'});
      }
    });
  } catch (error) {
    bootstrap.responses.send({'startup_error': '$error'});
    commands.close();
  }
}
