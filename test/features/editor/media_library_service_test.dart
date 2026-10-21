import 'dart:io';

import 'package:editors_pro/features/editor/services/media_library_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
