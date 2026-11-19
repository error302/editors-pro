import 'dart:async';
import 'dart:typed_data';

import 'package:editors_pro/core/services/audio_player_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.editorspro/audio');
  final service = AudioPlayerService.instance;
  late List<List<double>> writes;
  late List<double> accepted;
  late bool playing;
  late FutureOr<int?> Function(Float32List) accept;

  setUp(() {
    writes = [];
    accepted = [];
    playing = false;
    accept = (samples) => samples.length;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'play':
          playing = true;
          return null;
        case 'pause':
          playing = false;
          return null;
        case 'stop':
          playing = false;
          return null;
        case 'seekTo':
          return null;
        case 'getPlaybackPositionFrames':
          return 2205;
        case 'writeSamples':
          final bytes = (call.arguments as Map)['samples'] as Uint8List;
          final samples = Float32List.fromList(List.generate(
              bytes.lengthInBytes ~/ 4,
              (index) => ByteData.sublistView(bytes)
                  .getFloat32(index * 4, Endian.little)));
          writes.add(samples.toList());
          final count = await accept(samples);
          if (count != null && count >= 0 && count <= samples.length)
            accepted.addAll(samples.take(count));
          return count;
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    await service.release();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'partial and zero native writes retain exact stereo tails and view bounds',
      (tester) async {
    await service.initialize();
    final backing = Float32List.fromList([99, 0.1, 0.2, 0.3, 0.4, 99]);
    final view = Float32List.sublistView(backing, 1, 5);
    final counts = [2, 0, 2];
    accept = (_) => counts.removeAt(0);
    await service.writeSamples(view);
    await tester.pump();
    expect(service.pendingSampleCount, 2);
    expect(accepted, view.take(2));
    await tester.pump(const Duration(milliseconds: 8));
    expect(service.pendingSampleCount, 0);
    expect(accepted, view.toList());
    expect(writes, [view.toList(), view.sublist(2), view.sublist(2)]);
  });

  testWidgets('priming completes before play even while hardware returns zero',
      (tester) async {
    await service.initialize();
    var first = true;
    accept = (samples) {
      if (first) {
        first = false;
        return 2;
      }
      return playing ? samples.length : 0;
    };
    final samples = Float32List.fromList([1, -1, 0.5, -0.5, 0.25, -0.25]);
    await service
        .writeSamples(samples); // Queue ownership, no hardware-drain await.
    await tester.pump();
    expect(service.isPlaying, isFalse);
    expect(service.pendingSampleCount, 4);
    await service.play();
    await tester.pump();
    expect(service.pendingSampleCount, 0);
    expect(accepted, samples.toList());
  });

  testWidgets('pause suspends retries and resume preserves queued samples',
      (tester) async {
    await service.initialize();
    accept = (samples) => playing ? samples.length : 0;
    final samples = Float32List.fromList([0.1, 0.2, 0.3, 0.4]);
    await service.writeSamples(samples);
    await tester.pump();
    await service.pause();
    final before = writes.length;
    await tester.pump(const Duration(milliseconds: 100));
    expect(writes.length, before);
    expect(service.pendingSampleCount, 4);
    await service.play();
    await tester.pump();
    expect(accepted, samples.toList());
    expect(service.pendingSampleCount, 0);
  });

  testWidgets('stop cancels in-flight old tails without corrupting a new queue',
      (tester) async {
    await service.initialize();
    final response = Completer<int>();
    var first = true;
    accept = (samples) {
      if (first) {
        first = false;
        return response.future;
      }
      return samples.length;
    };
    await service.writeSamples(Float32List.fromList([1, 2, 3, 4]));
    await tester.pump();
    await service.stop();
    expect(service.pendingSampleCount, 0);
    await service.writeSamples(Float32List.fromList([5, 6]));
    await tester.pump();
    response.complete(2);
    await tester.pump(const Duration(milliseconds: 20));
    expect(service.pendingSampleCount, 0);
    expect(writes, [
      [1.0, 2.0, 3.0, 4.0],
      [5.0, 6.0]
    ]);
    expect(service.isPlaying, isFalse);
  });

  testWidgets('bounded queue rejects overflow before admitting or losing PCM',
      (tester) async {
    await service.initialize(sampleRate: 1000, channels: 2);
    await expectLater(
        service.writeSamples(Float32List(6002)), throwsStateError);
    expect(service.pendingSampleCount, 0);
    expect(writes, isEmpty);
  });

  testWidgets(
      'null accepted-count contract never pretends that PCM was written',
      (tester) async {
    await service.initialize();
    accept = (_) => null;
    await service.writeSamples(Float32List.fromList([0.1, 0.2]));
    await tester.pump();
    expect(service.pendingSampleCount, 2);
    expect(service.lastWriteError, contains('accepted-sample count'));
    await expectLater(service.writeSamples(Float32List.fromList([0.3, 0.4])),
        throwsStateError);
  });

  testWidgets(
      'hardware position is measured in channel frames relative to seek',
      (tester) async {
    await service.initialize();
    await service.seekTo(1234);
    expect(await service.refreshPlaybackPosition(), 1284);
    expect(service.currentPositionMs, 1284);
    expect(service.hasPlaybackPosition, isTrue);
    await service.stop();
    expect(service.hasPlaybackPosition, isFalse);
    expect(service.currentPositionMs, 0);
  });
}
