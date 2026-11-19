import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../features/onboarding/providers/onboarding_provider.dart';
import '../../src/rust/api/bridge_api.dart';

class UserLook {
  const UserLook({required this.id, required this.name,
    required this.createdAt, required this.recipeJson});
  final String id;
  final String name;
  final int createdAt;
  final String recipeJson;
}

/// Portable numerical recipes contain no media, code, credentials or file paths.
/// Native validation remains authoritative before any clip is changed.
class UserLookService {
  UserLookService(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'editors_pro_user_looks_v1';
  static const _maximumBytes = 131072;
  static const _names = {
    'Brightness', 'Contrast', 'Saturation', 'Hue', 'Blur', 'Sharpen',
    'Grayscale', 'Sepia', 'Invert', 'Vignette', 'Temperature', 'Chroma Key',
  };
  Future<void> _writes = Future<void>.value();

  Future<List<UserLook>> load() async {
    await _writes;
    return _read();
  }

  List<UserLook> _read() {
    final raw = _prefs.get(_key);
    if (raw == null) return [];
    if (raw is! String) throw const FormatException('Saved looks could not be read.');
    final data = jsonDecode(raw);
    if (data is! Map || data['version'] != 1 || data['looks'] is! List ||
        (data['looks'] as List).length > 100) {
      throw const FormatException('Saved look library has an unsupported format.');
    }
    final ids = <String>{};
    return (data['looks'] as List).map((entry) {
      if (entry is! Map || entry['id'] is! String || entry['created_at'] is! int ||
          !ids.add(entry['id'] as String)) {
        throw const FormatException('A saved look could not be read.');
      }
      final name = _name(entry['name']);
      return UserLook(id: entry['id'] as String, name: name,
        createdAt: entry['created_at'] as int,
        recipeJson: jsonEncode(_recipe(entry['recipe'])));
    }).toList(growable: false);
  }

  static String _name(Object? value) {
    if (value is! String || value.trim().isEmpty || value.trim().length > 64 ||
        value.contains(RegExp(r'[\x00-\x1f]'))) {
      throw ArgumentError('Use a look name between 1 and 64 characters.');
    }
    return value.trim();
  }

  static Map<String, Object?> _recipe(Object? value) {
    if (value is! Map || value['version'] != 1 || value['effects'] is! List ||
        value.keys.any((key) => !const {'version', 'effects'}.contains(key))) {
      throw const FormatException('Unsupported look recipe.');
    }
    final input = value['effects'] as List;
    if (input.isEmpty || input.length > 32) {
      throw const FormatException('A look must contain 1 to 32 adjustments.');
    }
    final effects = <Map<String, Object?>>[];
    for (final entry in input) {
      if (entry is! Map || !_names.contains(entry['name']) || entry['enabled'] is! bool ||
          entry['parameters'] is! Map ||
          entry.keys.any((key) => !const {'name', 'enabled', 'parameters'}.contains(key))) {
        throw const FormatException('The look contains an unsupported adjustment.');
      }
      final values = entry['parameters'] as Map;
      if (values.length > 32) throw const FormatException('Too many adjustment parameters.');
      final parameters = <String, double>{};
      for (final pair in values.entries) {
        final key = pair.key;
        final number = pair.value;
        if (key is! String || !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(key) ||
            number is! num || !number.isFinite || number.abs() > 100000) {
          throw const FormatException('The look contains invalid adjustment values.');
        }
        parameters[key] = number.toDouble();
      }
      effects.add({'name': entry['name'], 'enabled': entry['enabled'], 'parameters': parameters});
    }
    return {'version': 1, 'effects': effects};
  }

  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }

  Future<void> _persist(List<UserLook> looks) async {
    final text = jsonEncode({'version': 1, 'looks': [
      for (final look in looks) {'id': look.id, 'name': look.name,
        'created_at': look.createdAt, 'recipe': jsonDecode(look.recipeJson)},
    ]});
    try {
      if (!await _prefs.setString(_key, text)) {
        throw StateError('Could not save your look. Please try again.');
      }
    } catch (_) {
      await _prefs.reload();
      rethrow;
    }
  }

  Future<UserLook> _save(String name, Map<String, Object?> recipe) => _mutate(() async {
    final looks = _read();
    if (looks.length >= 100) throw StateError('Your library holds 100 looks. Remove one before saving another.');
    final look = UserLook(id: const Uuid().v4(), name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch, recipeJson: jsonEncode(recipe));
    await _persist([...looks, look]);
    return look;
  });

  Future<UserLook> save({required String name, required List<EffectInfo> effects}) async {
    final title = _name(name);
    if (effects.isEmpty) throw ArgumentError('Add a look or adjustment before saving.');
    final entries = <Map<String, Object?>>[];
    for (final effect in effects) {
      if (!const {'Filter', 'ChromaKey', 'filter', 'chroma_key'}.contains(effect.effectType)) {
        throw ArgumentError('Only rendered looks and adjustments can be saved here.');
      }
      entries.add({'name': effect.name, 'enabled': effect.enabled, 'parameters': {
        for (final parameter in effect.parameters)
          if (!parameter.name.startsWith('__')) parameter.name: parameter.value,
      }});
    }
    return _save(title, _recipe({'version': 1, 'effects': entries}));
  }

  Future<void> delete(String id) => _mutate(() async {
    final looks = _read();
    if (!looks.any((look) => look.id == id)) return;
    await _persist(looks.where((look) => look.id != id).toList());
  });

  String exportLook(UserLook look) => jsonEncode({
    'format': 'editors-pro.look', 'version': 1, 'name': look.name,
    'recipe': _recipe(jsonDecode(look.recipeJson)),
  });

  Future<UserLook> importLook(String jsonText) async {
    if (utf8.encode(jsonText).length > _maximumBytes) {
      throw const FormatException('Look files must be smaller than 128 KB.');
    }
    final data = jsonDecode(jsonText);
    if (data is! Map || data['format'] != 'editors-pro.look' || data['version'] != 1 ||
        data.keys.any((key) => !const {'format', 'version', 'name', 'recipe'}.contains(key))) {
      throw const FormatException('This is not an Editors Pro look.');
    }
    final String title;
    try { title = _name(data['name']); }
    on ArgumentError { throw const FormatException('The imported look needs a valid name.'); }
    return _save(title, _recipe(data['recipe']));
  }
}

final userLookServiceProvider = Provider<UserLookService>((ref) =>
  UserLookService(ref.watch(sharedPreferencesProvider)));
