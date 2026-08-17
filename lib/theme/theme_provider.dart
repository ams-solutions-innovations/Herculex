import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/providers.dart';
import 'colors.dart';

final themeModeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final saved = prefs.getString('theme_mode') ?? 'system';
  final initial = switch (saved) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
  
  // `main()` already resolved the brightness (including the platform value for
  // `system`) before the first frame, so only an explicit mode overrides it.
  _applyBrightness(initial);

  return ThemeNotifier(initial, prefs);
});

void _applyBrightness(ThemeMode mode) {
  AppColors.brightness = switch (mode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system => PlatformDispatcher.instance.platformBrightness,
  };
}

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier(super.initial, this._prefs);
  final SharedPreferences _prefs;

  void set(ThemeMode mode) {
    state = mode;
    _prefs.setString('theme_mode', switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      _ => 'system',
    });
    
    _applyBrightness(mode);
  }
}
