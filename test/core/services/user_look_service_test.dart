import 'dart:convert';
import 'package:editors_pro/core/services/user_look_service.dart';
import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late UserLookService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = UserLookService(prefs);
  });
  final effect = EffectInfo(id: 'look:warm:id', name: 'Temperature',
    effectType: 'Filter', enabled: true, parameters: [
      EffectParameterInfo(name: 'temperature', displayName: 'Temperature', value: 0.3,
        minValue: -1, maxValue: 1, defaultValue: 0),
      EffectParameterInfo(name: '__look_intensity', displayName: 'Strength', value: 0.5,
        minValue: 0, maxValue: 1, defaultValue: 1),
    ]);

  test('a saved look survives reload and contains reusable native values without clip IDs', () async {
    final saved = await service.save(name: '  My warm edit  ', effects: [effect]);
    final reloaded = (await UserLookService(prefs).load()).single;
    expect(reloaded.id, saved.id);
    expect(reloaded.name, 'My warm edit');
    final recipe = jsonDecode(reloaded.recipeJson) as Map<String, dynamic>;
    expect(recipe['version'], 1);
    final values = ((recipe['effects'] as List).single as Map)['parameters'];
    expect(values, {'temperature': 0.3});
    expect(reloaded.recipeJson, isNot(contains('look:warm:id')));
  });

  test('export and import make an independent reusable look without overwriting the original', () async {
    final original = await service.save(name: 'Warm', effects: [effect]);
    final copied = await service.importLook(service.exportLook(original));
    expect(copied.id, isNot(original.id));
    expect(copied.recipeJson, original.recipeJson);
    expect((await service.load()).length, 2);
    await service.delete(copied.id);
    expect((await service.load()).single.id, original.id);
  });

  test('untrusted imports reject unsupported effects, arbitrary data and invalid values without altering the library', () async {
    await service.save(name: 'Original', effects: [effect]);
    for (final entry in [
      {'name': 'Arbitrary shader', 'enabled': true, 'parameters': {}},
      {'name': 'Blur', 'enabled': true, 'parameters': {}, 'file': '/private/media'},
      {'name': 'Blur', 'enabled': true, 'parameters': {'radius': '5'}},
    ]) {
      final text = jsonEncode({'format': 'editors-pro.look', 'version': 1, 'name': 'Imported',
        'recipe': {'version': 1, 'effects': [entry]}});
      await expectLater(service.importLook(text), throwsFormatException);
    }
    expect((await service.load()).single.name, 'Original');
  });

  test('invalid names, empty stacks and oversized recipes are rejected', () async {
    await expectLater(service.save(name: ' ', effects: [effect]), throwsArgumentError);
    await expectLater(service.save(name: 'Empty', effects: []), throwsArgumentError);
    await expectLater(service.importLook(' ' * 131073), throwsFormatException);
    expect(await service.load(), isEmpty);
  });

  test('concurrent saves retain both creations', () async {
    await Future.wait([
      service.save(name: 'First', effects: [effect]),
      service.save(name: 'Second', effects: [effect]),
    ]);
    expect((await service.load()).map((look) => look.name), containsAll(['First', 'Second']));
  });
}
