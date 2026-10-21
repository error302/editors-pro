import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media asset bridge metadata round-trips for project restoration', () {
    const asset = MediaAssetInfo(
      id: 'stable-asset-id',
      filePath: '/app/media/still.png',
      fileName: 'still.png',
      mediaType: 'image',
      width: 1920,
      height: 1080,
      fileSizeBytes: 4096,
    );

    expect(MediaAssetInfo.fromJson(asset.toJson()).toJson(), asset.toJson());
  });
}
