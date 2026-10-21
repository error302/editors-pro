import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';

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
  }) async {
    final extension = p.extension(fileName).toLowerCase();
    if (!_supportedExtensions.contains(extension)) {
      throw const FormatException(
        'The selected media format is not supported.',
      );
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException(
        'The selected file is no longer available.',
        sourcePath,
      );
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
    try {
      return await source.copy(destination.path);
    } catch (_) {
      if (await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
  }
}
