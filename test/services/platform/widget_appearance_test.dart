import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/services/platform/widget_appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container([
  Map<String, Object> stored = const {},
]) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('defaults: follow the app theme, level 1, squircle', () async {
    final c = await _container();
    final a = c.read(widgetAppearanceProvider);

    expect(a.themeMode, isNull);
    expect(a.transparency, 1);
    expect(a.shape, WidgetCornerShape.squircle);
  });

  test('follows the app theme mode until one is chosen', () async {
    final c = await _container();
    final a = c.read(widgetAppearanceProvider);
    expect(a.resolvedMode(ThemeMode.dark), ThemeMode.dark);

    await c
        .read(widgetAppearanceProvider.notifier)
        .setThemeMode(ThemeMode.light);

    final chosen = c.read(widgetAppearanceProvider);
    expect(chosen.resolvedMode(ThemeMode.dark), ThemeMode.light);
  });

  test('"system" is a choice of its own, not the same as unset', () async {
    final c = await _container();
    await c
        .read(widgetAppearanceProvider.notifier)
        .setThemeMode(ThemeMode.system);

    expect(
      c.read(widgetAppearanceProvider).resolvedMode(ThemeMode.dark),
      ThemeMode.system,
    );
  });

  test('every setting survives a restart', () async {
    final c = await _container();
    final n = c.read(widgetAppearanceProvider.notifier);
    await n.setThemeMode(ThemeMode.dark);
    await n.setTransparency(3);
    await n.setShape(WidgetCornerShape.pill);

    final prefs = c.read(sharedPreferencesProvider);
    final restarted = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(restarted.dispose);

    expect(
      restarted.read(widgetAppearanceProvider),
      const WidgetAppearance(
        themeMode: ThemeMode.dark,
        transparency: 3,
        shape: WidgetCornerShape.pill,
      ),
    );
  });

  test('transparency is kept within 1-3', () async {
    final c = await _container();
    final n = c.read(widgetAppearanceProvider.notifier);

    await n.setTransparency(0);
    expect(c.read(widgetAppearanceProvider).transparency, 1);
    await n.setTransparency(9);
    expect(c.read(widgetAppearanceProvider).transparency, 3);
  });

  test('unreadable stored values fall back instead of throwing', () async {
    final c = await _container({
      WidgetAppearanceNotifier.themeModeKey: 'purple',
      WidgetAppearanceNotifier.transparencyKey: 42,
      WidgetAppearanceNotifier.shapeKey: 'hexagon',
    });
    final a = c.read(widgetAppearanceProvider);

    expect(a.themeMode, isNull);
    expect(a.transparency, 3);
    expect(a.shape, WidgetCornerShape.squircle);
  });
}
