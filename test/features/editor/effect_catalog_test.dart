import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:editors_pro/features/editor/providers/editor_provider.dart';
import 'package:editors_pro/features/editor/widgets/effect_catalog.dart';
import 'package:editors_pro/src/rust/api/bridge_api.dart';
import 'package:editors_pro/features/onboarding/providers/onboarding_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CatalogNotifier extends EditorNotifier {
  _CatalogNotifier(super.ref) {
    state = const EditorState(selectedClipId: 'clip');
  }
  bool unavailable = false;
  bool rejectLook = false;
  final List<String> applied = [];
  final List<String> added = [];
  bool manualAdded = false;
  double hue = 0;
  final List<(String?, double)> parameterCommits = [];
  final List<String> userRecipes = [];
  @override
  Future<String?> addEffect(String filterTypeName) async {
    added.add(filterTypeName);
    manualAdded = true;
    return 'adjustment';
  }

  @override
  Future<bool> setEffectParameter(String effectId, String paramName, double value) async {
    parameterCommits.add((state.selectedClipId, value));
    hue = value;
    return true;
  }

  @override
  Future<bool> applyUserLook(String recipeJson) async {
    userRecipes.add(recipeJson);
    return true;
  }

  String? active;
  double amount = 1;
  bool lookEnabled = true;
  @override
  Future<List<FilterTypeInfo>> getFilterCatalog() async {
    if (unavailable) throw StateError('Native catalog unavailable');
    return [
      FilterTypeInfo.fromJson({'name': 'Hue', 'icon': 'hue', 'parameters': []})
    ];
  }

  @override
  Future<List<FilterPresetInfo>> getFilterPresets() async => [
        FilterPresetInfo.fromJson({
          'id': 'warm',
          'name': 'Warm',
          'description': 'Gentle golden warmth'
        })
      ];
  @override
  Future<bool> setFilterLook(String presetId,
      {double intensity = 1, bool enabled = true}) async {
    applied.add(presetId);
    if (rejectLook) {
      state = state.copyWith(lastError: 'Native look rejected');
      return false;
    }
    active = presetId.isEmpty ? null : presetId;
    amount = intensity;
    lookEnabled = enabled;
    return true;
  }

  @override
  Future<List<EffectInfo>> getSelectedClipEffects() async => [
          if (manualAdded) EffectInfo(id: 'adjustment', name: 'Hue',
            effectType: 'Filter', enabled: true, parameters: [
              EffectParameterInfo(name: 'degrees', displayName: 'Hue angle', value: hue,
                minValue: -180, maxValue: 180, defaultValue: 0),
            ]),
          if (active != null)
          EffectInfo(
              id: 'look:$active:fixture',
              name: 'Temperature',
              effectType: 'Filter',
              enabled: lookEnabled,
              parameters: [
                EffectParameterInfo(
                    name: '__look_intensity',
                    displayName: 'Look intensity',
                    value: amount,
                    minValue: 0,
                    maxValue: 1,
                    defaultValue: 1)
              ])
        ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('rejected unavailable-engine edit retains the selected clip', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(editorProvider.notifier);
    notifier.selectClip('clip');
    expect(await notifier.setFilterLook('warm'), isFalse);
    expect(container.read(editorProvider).selectedClipId, 'clip');
    expect(container.read(editorProvider).lastError, isNotNull);
  });

  test('native filter payload parses without invented display_name/category',
      () {
    final filter = FilterTypeInfo.fromJson(
        {'name': 'Hue', 'icon': 'hue', 'parameters': []});
    expect(filter.name, 'Hue');
    expect(filter.displayName, 'Hue');
    expect(filter.icon, 'hue');
    expect(filter.category, 'Color');
  });

  Future<_CatalogNotifier> pump(WidgetTester tester,
      {bool unavailable = false,
      bool reject = false,
      TrackType trackType = TrackType.video,
      bool initialLook = false}) async {
    late _CatalogNotifier notifier;
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentProjectProvider.overrideWith((ref) => ProjectModel(
                id: 'project',
                name: 'Catalog fixture',
                createdAt: 0,
                updatedAt: 0,
                width: 1920,
                height: 1080,
                fps: 30,
                tracks: [
                  TrackModel(
                      id: 'track',
                      name: 'Selected track',
                      trackType: trackType,
                      orderIndex: 0,
                      clips: const [
                        ClipModel(
                            id: 'clip',
                            assetId: 'media',
                            startMs: 0,
                            durationMs: 1000)
                      ])
                ],
              )),
          editorProvider.overrideWith((ref) {
            notifier = _CatalogNotifier(ref)
              ..unavailable = unavailable
              ..rejectLook = reject
              ..active = initialLook ? 'warm' : null;
            return notifier;
          })
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 400, height: 700, child: EffectCatalog())))));
    await tester.pumpAndSettle();
    return notifier;
  }

  for (final type in [TrackType.audio, TrackType.text]) {
    testWidgets('looks and adjustments are disabled for ${type.name} clips',
        (tester) async {
      final notifier = await pump(tester, trackType: type, initialLook: true);
      final look = tester.widget<ListTile>(find.ancestor(
          of: find.text('Warm'), matching: find.byType(ListTile)));
      expect(look.onTap, isNull);
      expect(
          find.textContaining('Select a photo or video clip'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(
          tester
              .widget<TextButton>(find.ancestor(
                  of: find.text('Reset look'),
                  matching: find.byType(TextButton)))
              .onPressed,
          isNull);
      await tester.tap(find.text('Adjustments'));
      await tester.pumpAndSettle();
      final adjustment = tester.widget<ListTile>(find.byKey(const ValueKey('add-adjustment-Hue')));
      expect(adjustment.onTap, isNull);
      expect(notifier.applied, isEmpty);
      expect(notifier.added, isEmpty);
    });
  }

  testWidgets(
      'video-track clips support adjustments and unknown selections fail closed',
      (tester) async {
    final notifier = await pump(tester);
    await tester.tap(find.text('Adjustments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hue'));
    await tester.pumpAndSettle();
    expect(notifier.added, ['Hue']);
    notifier.selectClip('missing-clip');
    await tester.pumpAndSettle();
    final adjustment = tester.widget<ListTile>(find.byKey(const ValueKey('add-adjustment-Hue')));
    expect(adjustment.onTap, isNull);
    expect(find.textContaining('Select a photo or video clip'), findsOneWidget);
  });

  testWidgets('neutral adjustment opens real controls in the same dock and commits once', (tester) async {
    final notifier = await pump(tester);
    await tester.tap(find.text('Adjustments'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-adjustment-Hue')));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byKey(const ValueKey('adjustment-adjustment-degrees')));
    expect(find.text('Hue angle'), findsOneWidget);
    expect(slider.value, 0);
    slider.onChanged!(20);
    slider.onChanged!(40);
    expect(notifier.parameterCommits, isEmpty);
    slider.onChangeEnd!(40);
    await tester.pumpAndSettle();
    expect(notifier.parameterCommits, [('clip', 40.0)]);
    expect(tester.widget<Slider>(find.byKey(const ValueKey('adjustment-adjustment-degrees'))).value, 40);
  });

  testWidgets('an old slider gesture cannot edit a newly selected clip', (tester) async {
    final notifier = await pump(tester);
    await tester.tap(find.text('Adjustments'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-adjustment-Hue')));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byKey(const ValueKey('adjustment-adjustment-degrees')));
    notifier.selectClip('missing-clip');
    await tester.pumpAndSettle();
    slider.onChangeEnd!(50);
    await tester.pumpAndSettle();
    expect(notifier.parameterCommits, isEmpty);
  });

  testWidgets('a named current stack can be saved, applied and deleted locally', (tester) async {
    final notifier = await pump(tester);
    await tester.tap(find.text('Adjustments'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-adjustment-Hue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My looks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save current look'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('look-name')), 'My warm evening');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('My warm evening'), findsOneWidget);
    await tester.tap(find.text('My warm evening'));
    await tester.pumpAndSettle();
    expect(notifier.userRecipes, hasLength(1));
    expect(notifier.userRecipes.single, contains('Hue'));
    await tester.tap(find.byTooltip('Look options: My warm evening'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete look'));
    await tester.pumpAndSettle();
    expect(find.text('My warm evening'), findsNothing);
  });

  testWidgets('unavailable engine offers retry without fake presets',
      (tester) async {
    final notifier = await pump(tester, unavailable: true);
    expect(find.textContaining('Effects unavailable'), findsOneWidget);
    expect(find.text('Warm'), findsNothing);
    expect(find.text('Teal & Orange'), findsNothing);
    notifier.unavailable = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Warm'), findsOneWidget);
  });

  testWidgets('native rejection never claims the look was applied',
      (tester) async {
    final notifier = await pump(tester, reject: true);
    await tester.tap(find.text('Warm'));
    await tester.pumpAndSettle();
    expect(notifier.applied, ['warm']);
    expect(find.text('Native look rejected'), findsOneWidget);
    expect(find.text('Intensity'), findsNothing);
    expect(find.textContaining('Applied'), findsNothing);
  });

  testWidgets(
      'successful native look supports bypass reset and one commit per slider gesture',
      (tester) async {
    final notifier = await pump(tester);
    await tester.tap(find.text('Warm'));
    await tester.pumpAndSettle();
    expect(find.text('Intensity'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(0.3);
    slider.onChanged!(0.5);
    expect(notifier.applied.length, 1);
    slider.onChangeEnd!(0.5);
    await tester.pumpAndSettle();
    expect(notifier.applied.length, 2);
    expect(notifier.amount, 0.5);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(notifier.lookEnabled, isFalse);
    await tester.tap(find.text('Reset look'));
    await tester.pumpAndSettle();
    expect(notifier.active, isNull);
    expect(find.text('Intensity'), findsNothing);
  });
}
