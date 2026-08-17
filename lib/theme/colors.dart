import 'package:flutter/material.dart';

import 'tokens/hx_colors.dart';

/// Compatibility shim over [HxColors].
///
/// Every value here delegates to the token palette, so the app has one source
/// of truth for color even while ~1,500 legacy call sites still read colors
/// from this global. The static [brightness] cannot see `Theme` overrides in a
/// subtree, which is why new and migrated code must use `context.hx` instead;
/// this class is deleted once the last call site moves over.
class AppColors {
  /// Kept in sync from `main()` (before the first frame), `ThemeNotifier.set`,
  /// and `HerculexApp.build` for the `system` case.
  static Brightness brightness = Brightness.dark;

  static HxColors get _p => HxColors.of(brightness);

  // ── Light Blue Background Gradient ──
  static LinearGradient get backgroundGradient => _p.backgroundGradient;

  // ── Core palette ──
  static Color get background => _p.background;
  static Color get primary => _p.primary;
  static Color get primaryContainer => _p.primaryContainer;
  static Color get onSurface => _p.onSurface;
  static Color get secondary => _p.secondary;
  static Color get tertiary => _p.tertiary;
  static Color get onSurfaceVariant => _p.onSurfaceVariant;

  // ── Elevated surfaces (Pills / Cards) ──
  static Color get surfaceContainer => _p.surfaceContainer;
  static Color get surfaceContainerLowest => _p.surfaceContainerLowest;
  static Color get surfaceVariant => _p.surfaceVariant;

  // ── Lines / borders ──
  static Color get outlineVariant => _p.outlineVariant;
  static Color get outline => _p.outline;

  // ── Legacy aliases ──
  static Color get earthBrown => _p.primary;

  // ── Macronutrients ──
  static Color get macroKcal => _p.macroKcal;
  static Color get macroProtein => _p.macroProtein;
  static Color get macroCarbs => _p.macroCarbs;
  static Color get macroFat => _p.macroFat;
  static Color get macroFatText => _p.macroFatText;
}
