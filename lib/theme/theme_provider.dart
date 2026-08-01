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
  
  // Set initial brightness based on mode. 
  // We don't have BuildContext here, so for 'system' we default to dark, 
  // but it will be overridden in the app if needed.
  if (initial == ThemeMode.light) {
    AppColors.brightness = Brightness.light;
  } else {
    AppColors.brightness = Brightness.dark;
  }

  return ThemeNotifier(initial, prefs);
});

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
    
    if (mode == ThemeMode.light) {
      AppColors.brightness = Brightness.light;
    } else {
      AppColors.brightness = Brightness.dark;
    }
  }
}
