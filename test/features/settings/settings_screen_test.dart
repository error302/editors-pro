import 'package:editors_pro/features/cloud/providers/cloud_provider.dart';
import 'package:editors_pro/features/settings/providers/settings_provider.dart';
import 'package:editors_pro/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  testWidgets('failed changes show an error and keep the saved codec selected',
      (tester) async {
    SharedPreferences.setMockInitialValues({'settings_default_codec': 'H.264'});
    final prefs = await SharedPreferences.getInstance();
    SharedPreferencesStorePlatform.instance = _RejectingStore.withData({
      'flutter.settings_default_codec': 'H.264',
    });
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => SettingsNotifier(prefs)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Default Export Codec'), 250);
    final dropdown = find.descendant(
      of: find.ancestor(
        of: find.text('Default Export Codec'),
        matching: find.byType(ListTile),
      ),
      matching: find.byType(DropdownButton<String>),
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('H.265').last);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).defaultCodec, 'H.264');
    expect(tester.widget<DropdownButton<String>>(dropdown).value, 'H.264');
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'settings reflects canonical defaults and persists resolution edits',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings_default_resolution': '4K',
      'settings_default_fps': 120.0,
      'settings_auto_save_enabled': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => SettingsNotifier(prefs)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('120 fps'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
      isFalse,
    );
    final resolution = find.byType(DropdownButton<String>).first;
    expect(tester.widget<DropdownButton<String>>(resolution).value, '4K');
    await tester.tap(resolution);
    await tester.pumpAndSettle();
    await tester.tap(find.text('720p').last);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).defaultResolution, '720p');
    expect(prefs.getString('settings_default_resolution'), '720p');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cloud selection reflects the active cloud provider',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      {'settings_experimental_cloud_sync': true},
    );
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => SettingsNotifier(prefs)),
      ],
    );
    addTearDown(container.dispose);
    container.read(cloudSyncProvider.notifier).setProvider('Google Drive');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Cloud Provider'), 300);
    expect(find.text('Google Drive'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RejectingStore extends InMemorySharedPreferencesStore {
  _RejectingStore.withData(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}
