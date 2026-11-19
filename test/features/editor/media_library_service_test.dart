import 'dart:io';

import 'package:editors_pro/features/editor/services/media_library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testDirectory;
  late Directory sourceDirectory;
  late MediaLibraryService service;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp('editors-pro-media-');
    sourceDirectory = Directory('${testDirectory.path}/picked');
    await sourceDirectory.create();
    service = MediaLibraryService(storageDirectory: testDirectory);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.editorspro/storage'), null);
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test('copies selected media into persistent app storage with a unique name',
      () async {
    final source = File('${sourceDirectory.path}/clip.mp4');
    final contents = List<int>.generate(64, (index) => index);
    await source.writeAsBytes(contents);

    final first = await service.copyIntoLibrary(
      sourcePath: source.path,
      fileName: 'clip.mp4',
    );
    final second = await service.copyIntoLibrary(
      sourcePath: source.path,
      fileName: 'clip.mp4',
    );

    expect(
      first.parent.path,
      '${testDirectory.path}${Platform.pathSeparator}media',
    );
    expect(first.path, isNot(source.path));
    expect(second.path, isNot(first.path));
    expect(await first.readAsBytes(), contents);
    expect(await second.readAsBytes(), contents);
  });

  test('rejects formats that the media engine does not support', () async {
    final source = File('${sourceDirectory.path}/photo.heic');
    await source.writeAsBytes([1, 2, 3]);

    await expectLater(
      service.copyIntoLibrary(sourcePath: source.path, fileName: 'photo.heic'),
      throwsFormatException,
    );
  });

  test('reports when the picker temporary file is no longer available',
      () async {
    await expectLater(
      service.copyIntoLibrary(
        sourcePath: '${sourceDirectory.path}/missing.jpg',
        fileName: 'missing.jpg',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('imports provider audio through its content URI into durable storage',
      () async {
    final source = File('${sourceDirectory.path}/provider-song.mp3');
    final contents = List<int>.generate(128, (index) => index);
    await source.writeAsBytes(contents);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.editorspro/storage'),
            (call) async {
      expect(call.method, 'copyContentUriToTempFile');
      expect(call.arguments, {'uri': 'content://qa.provider/audio/1'});
      return source.path;
    });
    final imported = await service.copyIntoLibrary(
      sourcePath: 'content://qa.provider/audio/1',
      fileName: 'My song.mp3',
    );
    expect(imported.path, isNot(source.path));
    expect(await imported.readAsBytes(), contents);
    expect(await source.exists(), isTrue);
  });

  test('rejects an empty provider file instead of publishing an imported asset',
      () async {
    final source = File('${sourceDirectory.path}/empty.wav');
    await source.writeAsBytes([]);
    await expectLater(
      service.copyIntoLibrary(sourcePath: source.path, fileName: 'empty.wav'),
      throwsA(isA<FileSystemException>()),
    );
    final media = Directory('${testDirectory.path}/media');
    expect(await media.exists() ? await media.list().length : 0, 0);
  });

  test(
      'copies a stream-only provider selection completely before publishing it',
      () async {
    final imported = await service.copyIntoLibrary(
      sourcePath: '',
      fileName: 'stream-only.mp3',
      readStream: Stream.fromIterable([
        [1, 2],
        [3, 4, 5]
      ]),
    );
    expect(await imported.readAsBytes(), [1, 2, 3, 4, 5]);
    expect(await imported.parent.list().length, 1);
  });

  test('a provider stream failure leaves no partial or published asset',
      () async {
    Stream<List<int>> failingStream() async* {
      yield [1, 2, 3];
      throw const FileSystemException('Provider disconnected');
    }

    await expectLater(
      service.copyIntoLibrary(
        sourcePath: '',
        fileName: 'interrupted.wav',
        readStream: failingStream(),
      ),
      throwsA(isA<FileSystemException>()),
    );
    final media = Directory('${testDirectory.path}/media');
    expect(await media.list().length, 0);
  });
}
