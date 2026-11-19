import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/storage_service.dart';

class MediaLibraryService {
  MediaLibraryService({Directory? storageDirectory})
      : _storageDirectory = storageDirectory;
  static const _supportedExtensions = {
    '.mp4',
    '.mov',
    '.mkv',
    '.webm',
    '.avi',
    '.m4v',
    '.wmv',
    '.flv',
    '.3gp',
    '.mpg',
    '.mpeg',
    '.ts',
    '.mp3',
    '.wav',
    '.aac',
    '.m4a',
    '.ogg',
    '.flac',
    '.opus',
    '.wma',
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.bmp',
    '.gif',
  };

  final Directory? _storageDirectory;

  Future<File> copyIntoLibrary({
    required String sourcePath,
    required String fileName,
    Stream<List<int>>? readStream,
  }) async {
    final extension = p.extension(fileName).toLowerCase();
    if (!_supportedExtensions.contains(extension)) {
      throw const FormatException(
        'The selected media format is not supported.',
      );
    }

    var input = readStream;
    if (input == null) {
      var localPath = sourcePath;
      final uri = Uri.tryParse(sourcePath);
      if (uri?.scheme == 'content') {
        localPath =
            await StorageService.copyContentUriToTempFile(sourcePath) ?? '';
      } else if (uri?.scheme == 'file') {
        localPath = uri!.toFilePath();
      }
      final source = File(localPath);
      if (localPath.isEmpty || !await source.exists()) {
        throw FileSystemException(
            'The selected file is no longer available.', sourcePath);
      }
      if (await source.length() == 0) {
        throw FileSystemException('The selected file is empty.', sourcePath);
      }
      input = source.openRead();
    }

    var storageDirectory = _storageDirectory;
    if (storageDirectory == null && Platform.isAndroid) {
      storageDirectory = await getExternalStorageDirectory();
    }
    storageDirectory ??= await getApplicationSupportDirectory();
    final mediaDirectory =
        Directory(p.join(storageDirectory.path, AppConstants.mediaDir));
    await mediaDirectory.create(recursive: true);

    final destination = File(
      p.join(mediaDirectory.path, '${const Uuid().v4()}$extension'),
    );
    final partial = File('${destination.path}.partial');
    try {
      final sink = partial.openWrite();
      try {
        await sink.addStream(input);
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (await partial.length() == 0) {
        throw FileSystemException('The selected file is empty.', sourcePath);
      }
      return await partial.rename(destination.path);
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      if (await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
  }
}
