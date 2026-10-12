import 'package:flutter_test/flutter_test.dart';
import 'package:editors_pro/src/rust/api/bridge_api.dart';

void main() {
  test('clip bridge metadata parses the Rust track identifier', () {
    final clip = ClipInfo.fromJson({
      'id': 'clip-1',
      'track_id': 'track-1',
      'asset_id': 'asset-1',
      'start_ms': 250,
      'duration_ms': 5000,
    });

    expect(clip.trackId, 'track-1');
    expect(clip.assetId, 'asset-1');
    expect(clip.startMs, 250);
    expect(clip.durationMs, 5000);
  });
}
