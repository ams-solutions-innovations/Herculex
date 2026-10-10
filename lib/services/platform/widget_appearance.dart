import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';

/// Corner shape of the small (2x1) home-screen widgets. Everything bigger
/// stays a squircle whatever this says.
enum WidgetCornerShape { squircle, pill }

/// How the Android home-screen widgets look, chosen under Profile > Widgets.
class WidgetAppearance {
  const WidgetAppearance({
    this.themeMode,
    this.transparency = defaultTransparency,
    this.shape = WidgetCornerShape.squircle,
  });

  static const minTransparency = 1;
  static const maxTransparency = 3;
  static const defaultTransparency = 1;

  /// Null until the user picks one: the widgets then follow the app's theme
  /// mode, as they did before this setting existed.
  final ThemeMode? themeMode;

  /// 1 (light glass) to 3 (most transparent).
  final int transparency;

  final WidgetCornerShape shape;

  /// The mode the widgets are drawn in, given the app's own [appMode].
  ThemeMode resolvedMode(ThemeMode appMode) => themeMode ?? appMode;

  WidgetAppearance copyWith({
    ThemeMode? themeMode,
    int? transparency,
    WidgetCornerShape? shape,
  }) => WidgetAppearance(
    themeMode: themeMode ?? this.themeMode,
    transparency: transparency ?? this.transparency,
    shape: shape ?? this.shape,
  );

  @override
  bool operator ==(Object other) =>
      other is WidgetAppearance &&
      other.themeMode == themeMode &&
      other.transparency == transparency &&
      other.shape == shape;

  @override
  int get hashCode => Object.hash(themeMode, transparency, shape);
}

/// Persisted in SharedPreferences. Anything unreadable falls back to the
/// default rather than throwing, since the value outlives app versions.
class WidgetAppearanceNotifier extends Notifier<WidgetAppearance> {
  // Prefixed so they can't be mistaken for the Kotlin-side `widget_theme_*`
  // keys that live in the same preferences file.
  static const themeModeKey = 'widget_appearance_theme_mode';
  static const transparencyKey = 'widget_appearance_transparency';
  static const shapeKey = 'widget_appearance_shape';

  @override
  WidgetAppearance build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final transparency = prefs.getInt(transparencyKey);
    return WidgetAppearance(
      themeMode: switch (prefs.getString(themeModeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      },
      transparency: transparency == null
          ? WidgetAppearance.defaultTransparency
          : _clamp(transparency),
      shape: prefs.getString(shapeKey) == 'pill'
          ? WidgetCornerShape.pill
          : WidgetCornerShape.squircle,
    );
  }

  static int _clamp(int level) => level.clamp(
    WidgetAppearance.minTransparency,
    WidgetAppearance.maxTransparency,
  );

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await ref.read(sharedPreferencesProvider).setString(
      themeModeKey,
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }

  Future<void> setTransparency(int level) async {
    final clamped = _clamp(level);
    state = state.copyWith(transparency: clamped);
    await ref.read(sharedPreferencesProvider).setInt(transparencyKey, clamped);
  }

  Future<void> setShape(WidgetCornerShape shape) async {
    state = state.copyWith(shape: shape);
    await ref.read(sharedPreferencesProvider).setString(shapeKey, shape.name);
  }
}

final widgetAppearanceProvider =
    NotifierProvider<WidgetAppearanceNotifier, WidgetAppearance>(
      WidgetAppearanceNotifier.new,
    );
