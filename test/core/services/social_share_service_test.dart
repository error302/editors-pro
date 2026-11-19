import 'dart:io';

import 'package:editors_pro/core/services/social_share_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.editorspro/social_share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temporary;
  late File video;
  late List<MethodCall> calls;
  late SocialShareService service;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('editors-pro-share-');
    video = await File('${temporary.path}/completed.mp4')
        .writeAsBytes([0, 0, 0, 24, 102, 116, 121, 112]);
    calls = [];
    service = SocialShareService(isAndroid: true);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'getAvailableTargets'
          ? ['youtube', 'tiktok', 'instagram', 'facebook', 'x']
          : 'handoff_started';
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await temporary.delete(recursive: true);
  });

  test('missing and empty exports fail before any app is opened', () async {
    for (final path in [
      '${temporary.path}/missing.mp4',
      (await File('${temporary.path}/empty.mp4').create()).path,
    ]) {
      await expectLater(
        service.share(filePath: path, target: SocialShareTarget.youtube),
        throwsA(isA<StateError>()),
      );
    }
    expect(calls, isEmpty);
  });

  test('non-video exports fail before any app is opened', () async {
    final gif = await File('${temporary.path}/animation.gif').writeAsBytes([1]);
    await expectLater(
      service.share(filePath: gif.path, target: SocialShareTarget.more),
      throwsA(isA<ArgumentError>()),
    );
    expect(calls, isEmpty);
  });

  test('hands every selected target and the edited caption to Android',
      () async {
    const targetIds = [
      'youtube',
      'tiktok',
      'instagram',
      'facebook',
      'x',
      'more',
    ];
    for (var index = 0; index < targetIds.length; index++) {
      final result = await service.share(
        filePath: video.path,
        target: SocialShareTarget.values[index],
        caption: 'My edit 🎬\n#Nairobi',
      );
      expect(result, SocialShareOutcome.handoffStarted);
      expect(calls.last.method, 'shareVideo');
      expect(calls.last.arguments, {
        'filePath': video.path,
        'target': targetIds[index],
        'caption': 'My edit 🎬\n#Nairobi',
      });
    }
    expect(await video.readAsBytes(), [0, 0, 0, 24, 102, 116, 121, 112]);
  });

  test('native failure is propagated instead of reporting handoff', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'APP_UNAVAILABLE',
        message: 'App unavailable',
      );
    });
    await expectLater(
      service.share(filePath: video.path, target: SocialShareTarget.youtube),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'APP_UNAVAILABLE',
        ),
      ),
    );
  });

  test('missing native acknowledgement cannot report handoff', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    await expectLater(
      service.share(filePath: video.path, target: SocialShareTarget.more),
      throwsA(isA<StateError>()),
    );
  });

  test('availability filters unknown native targets and always offers More',
      () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => ['youtube', 'x', 'unknown'],
    );
    expect(await service.availableTargets(), {
      SocialShareTarget.youtube,
      SocialShareTarget.x,
      SocialShareTarget.more,
    });
  });

  test('non-Android only offers generic sharing and preserves cancellation',
      () async {
    List<XFile>? sharedFiles;
    String? sharedCaption;
    final genericService = SocialShareService(
      isAndroid: false,
      genericShare: (files, caption, origin) async {
        sharedFiles = files;
        sharedCaption = caption;
        return const ShareResult('', ShareResultStatus.dismissed);
      },
    );
    expect(await genericService.availableTargets(), {SocialShareTarget.more});
    expect(
      await genericService.share(
        filePath: video.path,
        target: SocialShareTarget.more,
        caption: 'Edited caption',
      ),
      SocialShareOutcome.dismissed,
    );
    expect(sharedFiles?.single.path, video.path);
    expect(sharedCaption, 'Edited caption');
    expect(calls, isEmpty);
    await expectLater(
      genericService.share(filePath: video.path, target: SocialShareTarget.x),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
