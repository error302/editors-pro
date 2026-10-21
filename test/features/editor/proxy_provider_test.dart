import 'package:editors_pro/features/editor/providers/proxy_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProxyState', () {
    test('has expected defaults', () {
      const state = ProxyState();
      expect(state.quality, '480p');
      expect(state.autoProxyEnabled, isTrue);
      expect(state.activeProxyCount, 0);
      expect(state.cacheSizeBytes, 0);
      expect(state.proxyInfo, isEmpty);
      expect(state.generatingAssetId, isNull);
      expect(state.isGenerating, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('copyWith updates only specified fields', () {
      const state = ProxyState();
      final updated = state.copyWith(
        quality: '720p',
        autoProxyEnabled: false,
        activeProxyCount: 5,
      );
      expect(updated.quality, '720p');
      expect(updated.autoProxyEnabled, isFalse);
      expect(updated.activeProxyCount, 5);
      // Unchanged fields
      expect(updated.cacheSizeBytes, 0);
      expect(updated.isGenerating, isFalse);
    });

    test('copyWith clearGeneratingAssetId clears the field', () {
      const state = ProxyState(generatingAssetId: 'asset-1');
      final cleared = state.copyWith(clearGeneratingAssetId: true);
      expect(cleared.generatingAssetId, isNull);
    });

    test('copyWith clearError clears the error message', () {
      const state = ProxyState(errorMessage: 'Something went wrong');
      final cleared = state.copyWith(clearError: true);
      expect(cleared.errorMessage, isNull);
    });

    test('copyWith can set generatingAssetId', () {
      const state = ProxyState();
      final updated = state.copyWith(generatingAssetId: 'asset-2');
      expect(updated.generatingAssetId, 'asset-2');
    });
  });

  group('ProxyInfoData', () {
    test('hasProxy returns true when proxyPath is set', () {
      const info = ProxyInfoData(
        assetId: 'a1',
        originalPath: '/original.mp4',
        proxyPath: '/proxy.mp4',
        quality: '480p',
        originalWidth: 1920,
        originalHeight: 1080,
        proxyWidth: 854,
        proxyHeight: 480,
        fileSizeBytes: 5242880,
      );
      expect(info.hasProxy, isTrue);
    });

    test('hasProxy returns false when proxyPath is null', () {
      const info = ProxyInfoData(
        assetId: 'a1',
        originalPath: '/original.mp4',
        quality: '480p',
        originalWidth: 1920,
        originalHeight: 1080,
      );
      expect(info.hasProxy, isFalse);
    });

    test('formattedSize formats bytes correctly', () {
      const info1 = ProxyInfoData(
        assetId: 'a1',
        originalPath: '/o.mp4',
        quality: '480p',
        originalWidth: 1920,
        originalHeight: 1080,
        fileSizeBytes: 5242880,
      );
      expect(info1.formattedSize, '5.0 MB');

      const info2 = ProxyInfoData(
        assetId: 'a2',
        originalPath: '/o.mp4',
        quality: '480p',
        originalWidth: 1920,
        originalHeight: 1080,
        fileSizeBytes: 1024,
      );
      expect(info2.formattedSize, '1.0 KB');

      const info3 = ProxyInfoData(
        assetId: 'a3',
        originalPath: '/o.mp4',
        quality: '480p',
        originalWidth: 1920,
        originalHeight: 1080,
        fileSizeBytes: 500,
      );
      expect(info3.formattedSize, '500 B');
    });

    test('formattedSize handles zero and null sizes', () {
      const infoNull = ProxyInfoData(
        assetId: 'a1',
        originalPath: '/o.mp4',
        quality: '480p',
        originalWidth: 1920,
        originalHeight: 1080,
        fileSizeBytes: null,
      );
      expect(infoNull.formattedSize, '—');

      const infoZero = ProxyInfoData(
        assetId: 'a1',
        originalPath: '/o.mp4',
        quality: '480p',
        originalWidth: 1920,
        originalHeight: 1080,
        fileSizeBytes: 0,
      );
      expect(infoZero.formattedSize, '—');
    });

    test('formattedSize handles GB sizes', () {
      const info = ProxyInfoData(
        assetId: 'a1',
        originalPath: '/o.mp4',
        quality: '480p',
        originalWidth: 1920,
        originalHeight: 1080,
        fileSizeBytes: 3221225472, // 3 GB
      );
      expect(info.formattedSize, '3.0 GB');
    });

    test('resolutionLabel maps common resolutions', () {
      expect(ProxyInfoData.resolutionLabel(3840, 2160), '4K');
      expect(ProxyInfoData.resolutionLabel(2560, 1440), '1440p');
      expect(ProxyInfoData.resolutionLabel(1920, 1080), '1080p');
      expect(ProxyInfoData.resolutionLabel(1280, 720), '720p');
      expect(ProxyInfoData.resolutionLabel(854, 480), '480p');
      expect(ProxyInfoData.resolutionLabel(640, 360), '360p');
      expect(ProxyInfoData.resolutionLabel(320, 240), '320x240');
    });

    test('resolutionDisplayLabel shows original only when no proxy', () {
      const info = ProxyInfoData(
        assetId: 'a1',
        originalPath: '/o.mp4',
        quality: '480p',
        originalWidth: 3840,
        originalHeight: 2160,
      );
      expect(info.resolutionDisplayLabel, '4K');
    });

    test('resolutionDisplayLabel shows arrow when proxy exists', () {
      const info = ProxyInfoData(
        assetId: 'a1',
        originalPath: '/o.mp4',
        quality: '480p',
        originalWidth: 3840,
        originalHeight: 2160,
        proxyWidth: 1280,
        proxyHeight: 720,
      );
      expect(info.resolutionDisplayLabel, '4K→720p');
    });
  });
}
