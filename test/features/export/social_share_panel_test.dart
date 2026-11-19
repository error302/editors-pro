import 'dart:async';
import 'dart:io';

import 'package:editors_pro/core/services/social_share_service.dart';
import 'package:editors_pro/features/export/presentation/social_share_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.editorspro/social_share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temporary;
  late File video;
  late List<MethodCall> calls;
  late _ObservedSocialShareService service;

  setUp(() async {
    temporary =
        await Directory.systemTemp.createTemp('editors-pro-share-panel-');
    video =
        await File('${temporary.path}/completed.mp4').writeAsBytes([1, 2, 3]);
    calls = [];
    service = _ObservedSocialShareService();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'getAvailableTargets'
          ? ['youtube', 'tiktok', 'instagram', 'facebook', 'x']
          : 'handoff_started';
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    await temporary.delete(recursive: true);
  });

  Future<void> showPanel(
    WidgetTester tester, {
    SocialShareService? shareService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SocialSharePanel(
              filePath: video.path,
              service: shareService ?? service,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('edits and copies caption without opening a social app',
      (tester) async {
    String? copied;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    await showPanel(tester);
    await tester.enterText(find.byType(TextField), 'My caption #edit');
    await tester.tap(find.byTooltip('Copy caption'));
    await tester.pumpAndSettle();
    expect(copied, 'My caption #edit');
    expect(calls.where((call) => call.method == 'shareVideo'), isEmpty);
    expect(find.text('Caption copied'), findsOneWidget);
  });

  testWidgets('hands caption to chosen app and leaves publishing to that app',
      (tester) async {
    await showPanel(tester);
    await tester.enterText(find.byType(TextField), 'New edited caption');
    await tester.runAsync(() async {
      await tester.tap(find.text('YouTube'));
      await service.pending;
    });
    await tester.pumpAndSettle();
    final shared = calls.singleWhere((call) => call.method == 'shareVideo');
    expect(shared.arguments, {
      'filePath': video.path,
      'target': 'youtube',
      'caption': 'New edited caption',
    });
    expect(find.textContaining('Finish sharing in YouTube'), findsOneWidget);
    expect(
      find.textContaining(
        RegExp(
          r'\b(posted|published|uploaded successfully)\b',
          caseSensitive: false,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('missing apps have an explicit More fallback', (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async => <String>[]);
    await showPanel(tester);
    final youtube = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'YouTube'),
    );
    expect(youtube.onPressed, isNull);
    expect(find.text('More share options'), findsOneWidget);
    expect(find.textContaining('Unavailable apps'), findsOneWidget);
  });

  testWidgets('native failure stays visible and never becomes success',
      (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAvailableTargets') return ['youtube'];
      throw PlatformException(code: 'APP_UNAVAILABLE', message: 'App removed');
    });
    await showPanel(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('YouTube'));
      await service.pending
          ?.catchError((Object _) => SocialShareOutcome.unknown);
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Use More share options'), findsWidgets);
    expect(find.textContaining('Finish sharing in YouTube'), findsNothing);
  });

  testWidgets('invalid export surfaces error before native share',
      (tester) async {
    await tester.runAsync(() => video.writeAsBytes([]));
    await showPanel(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('YouTube'));
      await service.pending
          ?.catchError((Object _) => SocialShareOutcome.unknown);
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('empty'), findsOneWidget);
    expect(calls.where((call) => call.method == 'shareVideo'), isEmpty);
  });

  testWidgets('a previous export cannot show handoff feedback on a new export',
      (tester) async {
    final delayed = _DelayedShareService();
    await showPanel(tester, shareService: delayed);
    await tester.tap(find.text('YouTube'));
    // Same mounted panel, different completed export, while the old handoff waits.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SocialSharePanel(
              filePath: '${temporary.path}/another.mp4',
              service: delayed,
            ),
          ),
        ),
      ),
    );
    delayed.response.complete(SocialShareOutcome.handoffStarted);
    await tester.pumpAndSettle();
    expect(find.textContaining('Finish sharing in YouTube'), findsNothing);
  });
}

class _DelayedShareService extends SocialShareService {
  final response = Completer<SocialShareOutcome>();

  @override
  Future<Set<SocialShareTarget>> availableTargets() async => {
        SocialShareTarget.youtube,
        SocialShareTarget.more,
      };

  @override
  Future<SocialShareOutcome> share({
    required String filePath,
    required SocialShareTarget target,
    String caption = '',
    Rect? sharePositionOrigin,
  }) =>
      response.future;
}

// Observe the real operation so widget tests await filesystem I/O outside the
// fake clock. The production service, native boundary and validation remain real.
class _ObservedSocialShareService extends SocialShareService {
  _ObservedSocialShareService() : super(isAndroid: true);

  Future<SocialShareOutcome>? pending;

  @override
  Future<SocialShareOutcome> share({
    required String filePath,
    required SocialShareTarget target,
    String caption = '',
    Rect? sharePositionOrigin,
  }) {
    return pending = super.share(
      filePath: filePath,
      target: target,
      caption: caption,
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}
