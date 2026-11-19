import 'package:editors_pro/features/settings/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('malformed saved choices normalize to usable settings', () async {
    SharedPreferences.setMockInitialValues({
      'settings_default_resolution': '8K',
      'settings_default_codec': 'unsupported',
      'settings_auto_save_interval': 999,
      'settings_theme_mode': 'sepia',
      'settings_proxy_quality': '8K',
      'settings_cache_size_mb': -10,
    });
    final notifier = SettingsNotifier(await SharedPreferences.getInstance());
    addTearDown(notifier.dispose);
    expect(notifier.state.defaultResolution, '1080p');
    expect(notifier.state.defaultCodec, 'H.264');
    expect(notifier.state.autoSaveIntervalMinutes, 10);
    expect(notifier.state.themeMode, 'system');
    expect(notifier.state.proxyQuality, '480p');
    expect(notifier.state.cacheSizeMb, 500);
  });

  test('invalid edits are rejected without changing saved defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifier = SettingsNotifier(prefs);
    addTearDown(notifier.dispose);
    await expectLater(notifier.setResolution('8K'), throwsArgumentError);
    await expectLater(notifier.setCodec('unsupported'), throwsArgumentError);
    await expectLater(notifier.setAutoSaveInterval(0), throwsArgumentError);
    await expectLater(notifier.setThemeMode('sepia'), throwsArgumentError);
    await expectLater(notifier.setCacheSizeMb(-1), throwsArgumentError);
    expect(notifier.state.defaultResolution, '1080p');
    expect(prefs.containsKey('settings_default_resolution'), isFalse);
  });

  test('a rejected preference write leaves visible and reload state unchanged',
      () async {
    SharedPreferences.setMockInitialValues({'settings_default_codec': 'H.264'});
    final prefs = await SharedPreferences.getInstance();
    SharedPreferencesStorePlatform.instance = _RejectingStore.withData({
      'flutter.settings_default_codec': 'H.264',
    });
    final notifier = SettingsNotifier(prefs);
    addTearDown(notifier.dispose);
    await expectLater(notifier.setCodec('H.265'), throwsStateError);
    expect(notifier.state.defaultCodec, 'H.264');
    await prefs.reload();
    expect(prefs.getString('settings_default_codec'), 'H.264');
  });

  test('legacy DB choices win once and later canonical edits survive restart',
      () async {
    SharedPreferences.setMockInitialValues({
      'settings_default_resolution': '720p',
      'settings_auto_save_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final legacy = <String, String>{
      'default_resolution': '4K',
      'default_fps': '25.0',
      'auto_save_enabled': 'false',
      'auto_save_interval': '6',
    };
    final notifier = SettingsNotifier(
      prefs,
      readLegacyPreference: (key) async => legacy[key],
    );
    addTearDown(notifier.dispose);
    await notifier.ensureLoaded();
    expect(notifier.state.defaultResolution, '4K');
    expect(notifier.state.defaultFps, 25);
    expect(notifier.state.autoSaveEnabled, isFalse);
    expect(notifier.state.autoSaveIntervalMinutes, 6);
    await notifier.setResolution('1080p');
    final restarted = SettingsNotifier(
      prefs,
      readLegacyPreference: (key) async => legacy[key],
    );
    addTearDown(restarted.dispose);
    await restarted.ensureLoaded();
    expect(restarted.state.defaultResolution, '1080p');
    expect(legacy['default_resolution'], '4K');
  });

  test('failed migration remains retryable and does not report loaded',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    SharedPreferencesStorePlatform.instance = _RejectingStore.withData({});
    final notifier = SettingsNotifier(
      prefs,
      readLegacyPreference: (key) async => key == 'default_fps' ? '120' : null,
    );
    addTearDown(notifier.dispose);
    await expectLater(notifier.ensureLoaded(), throwsStateError);
    expect(notifier.state.isLoaded, isFalse);
    expect(notifier.state.lastError, isNotNull);
    await prefs.reload();
    expect(prefs.containsKey('settings_legacy_migration_version'), isFalse);
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
    await notifier.ensureLoaded();
    expect(notifier.state.isLoaded, isTrue);
    expect(notifier.state.defaultFps, 120);
  });

  test('wrong storage types and invalid legacy values normalize safely',
      () async {
    SharedPreferences.setMockInitialValues({
      'settings_theme_mode': true,
      'settings_auto_save_interval': 'bad',
      'settings_default_fps': double.nan,
    });
    final notifier = SettingsNotifier(
      await SharedPreferences.getInstance(),
      readLegacyPreference: (key) async => switch (key) {
        'default_resolution' => '8K',
        'default_fps' => 'NaN',
        'auto_save_interval' => '-10',
        _ => null,
      },
    );
    addTearDown(notifier.dispose);
    await notifier.ensureLoaded();
    expect(notifier.state.defaultResolution, '1080p');
    expect(notifier.state.defaultFps, 30);
    expect(notifier.state.autoSaveIntervalMinutes, 1);
    expect(notifier.state.themeMode, 'system');
  });

  test('supported fps survives persistence and invalid fps is rejected',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifier = SettingsNotifier(prefs);
    addTearDown(notifier.dispose);
    await notifier.setDefaultFps(50);
    await notifier.setDefaultFps(120);
    await expectLater(notifier.setDefaultFps(0), throwsArgumentError);
    await expectLater(notifier.setDefaultFps(double.nan), throwsArgumentError);
    final restarted = SettingsNotifier(prefs);
    addTearDown(restarted.dispose);
    expect(restarted.state.defaultFps, 120);
  });
}

class _RejectingStore extends InMemorySharedPreferencesStore {
  _RejectingStore.withData(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}
