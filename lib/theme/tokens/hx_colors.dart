import 'package:flutter/material.dart';

/// The single source of truth for every color in the app.
///
/// Two const instances ([light] and [dark]) hold the full palette. They are
/// exposed to widgets as a [ThemeExtension] so colors resolve from the
/// `BuildContext` — see the `context.hx` extension at the bottom of this file.
/// `AppColors` remains as a compatibility shim that delegates here while the
/// ~1,500 legacy call sites migrate tab by tab.
///
/// Design notes:
/// * Light mode gives `surfaceContainerLowest` (cards) and `surfaceContainer`
///   (sheets/elevated) genuinely different values. They used to both be pure
///   white, which made every card-inside-a-sheet invisible.
/// * `primary` stays vivid for fills; `primaryText` is the darkened variant
///   that clears 4.5:1 on light surfaces.
/// * Domain accents color-code the four areas of the app so each section
///   reads as its own place.
@immutable
class HxColors extends ThemeExtension<HxColors> {
  const HxColors({
    required this.brightness,
    required this.gradientTop,
    required this.gradientMid,
    required this.gradientBottom,
    required this.background,
    required this.primary,
    required this.primaryText,
    required this.primaryContainer,
    required this.onPrimary,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.secondary,
    required this.tertiary,
    required this.surfaceContainer,
    required this.surfaceContainerLowest,
    required this.surfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.domainTraining,
    required this.domainNutrition,
    required this.domainFasting,
    required this.domainRecovery,
    required this.macroKcal,
    required this.macroProtein,
    required this.macroCarbs,
    required this.macroFat,
    required this.macroFatText,
    required this.success,
    required this.warning,
    required this.danger,
    required this.glassFill,
    required this.glassBorder,
    required this.quickAdd,
  });

  final Brightness brightness;

  // ── Page background ──
  final Color gradientTop;
  final Color gradientMid;
  final Color gradientBottom;
  final Color background;

  // ── Brand ──
  final Color primary;

  /// Darkened [primary] for text and small icons, where the vivid fill color
  /// would fall under the 4.5:1 contrast floor.
  final Color primaryText;
  final Color primaryContainer;
  final Color onPrimary;

  // ── Content ──
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color secondary;
  final Color tertiary;

  // ── Surfaces ──
  /// Elevated surface: sheets, dialogs, chips.
  final Color surfaceContainer;

  /// Card surface, one step closer to the page background than
  /// [surfaceContainer] so cards nested inside sheets stay distinguishable.
  final Color surfaceContainerLowest;

  /// Recessed fills: inputs, progress tracks, inactive segments.
  final Color surfaceVariant;

  // ── Lines ──
  final Color outline;
  final Color outlineVariant;

  // ── Domain accents ──
  final Color domainTraining;
  final Color domainNutrition;
  final Color domainFasting;
  final Color domainRecovery;

  // ── Macronutrients ──
  final Color macroKcal;
  final Color macroProtein;
  final Color macroCarbs;

  /// Fat fill. Yellow fails contrast as text/icon on light surfaces, so use
  /// [macroFatText] for anything smaller than a bar or chip.
  final Color macroFat;
  final Color macroFatText;

  // ── Status ──
  final Color success;
  final Color warning;
  final Color danger;

  // ── Frosted glass ──
  final Color glassFill;
  final Color glassBorder;

  /// The nav bar's quick-add button: a distinct warm accent so the "+" reads
  /// as its own thing, never confused with [primary] (the selected-tab fill)
  /// or a specific domain color — quick-add spans every domain at once.
  final Color quickAdd;

  bool get isDark => brightness == Brightness.dark;

  LinearGradient get backgroundGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [gradientTop, gradientMid, gradientBottom],
      );

  static const HxColors dark = HxColors(
    brightness: Brightness.dark,
    gradientTop: Color(0xFF0D1B2A),
    gradientMid: Color(0xFF091322),
    gradientBottom: Color(0xFF040913),
    background: Color(0xFF091322),
    primary: Color(0xFF0A84FF),
    primaryText: Color(0xFF4DA3FF),
    primaryContainer: Color(0xFF1C4A7E),
    onPrimary: Color(0xFFFFFFFF),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFFCBD5E1),
    secondary: Color(0xFF94A3B8),
    tertiary: Color(0xFF64748B),
    surfaceContainer: Color(0xFF161E2E),
    surfaceContainerLowest: Color(0xFF111824),
    surfaceVariant: Color(0xFF202A3C),
    outline: Color(0xFF3B4C69),
    outlineVariant: Color(0xFF2B374E),
    domainTraining: Color(0xFF0A84FF),
    domainNutrition: Color(0xFF30D158),
    domainFasting: Color(0xFF64D2FF),
    domainRecovery: Color(0xFFBF5AF2),
    macroKcal: Color(0xFFFF453A),
    macroProtein: Color(0xFF4DA3FF),
    macroCarbs: Color(0xFF34C759),
    macroFat: Color(0xFFFFD60A),
    macroFatText: Color(0xFFFFD60A),
    success: Color(0xFF30D158),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF453A),
    glassFill: Color(0xFF161E2E),
    glassBorder: Color(0xFF2B374E),
    quickAdd: Color(0xFFFF9F0A),
  );

  static const HxColors light = HxColors(
    brightness: Brightness.light,
    gradientTop: Color(0xFFDCEBFB),
    gradientMid: Color(0xFFE4EFFC),
    gradientBottom: Color(0xFFEDF4FD),
    background: Color(0xFFE4EFFC),
    primary: Color(0xFF0A84FF),
    primaryText: Color(0xFF0063CC),
    primaryContainer: Color(0xFFD0E3FF),
    onPrimary: Color(0xFFFFFFFF),
    onSurface: Color(0xFF0B1526),
    onSurfaceVariant: Color(0xFF334155),
    secondary: Color(0xFF64748B),
    tertiary: Color(0xFF94A3B8),
    surfaceContainer: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFF5F9FF),
    surfaceVariant: Color(0xFFDDE9F7),
    outline: Color(0xFFA9C2DC),
    outlineVariant: Color(0xFFCFE0F3),
    domainTraining: Color(0xFF0A84FF),
    domainNutrition: Color(0xFF1E7A34),
    domainFasting: Color(0xFF0083A8),
    domainRecovery: Color(0xFF8036B8),
    macroKcal: Color(0xFFE0362C),
    macroProtein: Color(0xFF1F6FD6),
    macroCarbs: Color(0xFF248A3D),
    macroFat: Color(0xFFFFD60A),
    macroFatText: Color(0xFFB08900),
    success: Color(0xFF1E7A34),
    warning: Color(0xFFB36A00),
    danger: Color(0xFFC7261C),
    glassFill: Color(0xFFFFFFFF),
    glassBorder: Color(0xFFCFE0F3),
    quickAdd: Color(0xFFCC7A00),
  );

  static HxColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Tokens are a fixed set per brightness, so there is nothing to override.
  @override
  HxColors copyWith() => this;

  @override
  HxColors lerp(covariant ThemeExtension<HxColors>? other, double t) {
    if (other is! HxColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return HxColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      gradientTop: c(gradientTop, other.gradientTop),
      gradientMid: c(gradientMid, other.gradientMid),
      gradientBottom: c(gradientBottom, other.gradientBottom),
      background: c(background, other.background),
      primary: c(primary, other.primary),
      primaryText: c(primaryText, other.primaryText),
      primaryContainer: c(primaryContainer, other.primaryContainer),
      onPrimary: c(onPrimary, other.onPrimary),
      onSurface: c(onSurface, other.onSurface),
      onSurfaceVariant: c(onSurfaceVariant, other.onSurfaceVariant),
      secondary: c(secondary, other.secondary),
      tertiary: c(tertiary, other.tertiary),
      surfaceContainer: c(surfaceContainer, other.surfaceContainer),
      surfaceContainerLowest:
          c(surfaceContainerLowest, other.surfaceContainerLowest),
      surfaceVariant: c(surfaceVariant, other.surfaceVariant),
      outline: c(outline, other.outline),
      outlineVariant: c(outlineVariant, other.outlineVariant),
      domainTraining: c(domainTraining, other.domainTraining),
      domainNutrition: c(domainNutrition, other.domainNutrition),
      domainFasting: c(domainFasting, other.domainFasting),
      domainRecovery: c(domainRecovery, other.domainRecovery),
      macroKcal: c(macroKcal, other.macroKcal),
      macroProtein: c(macroProtein, other.macroProtein),
      macroCarbs: c(macroCarbs, other.macroCarbs),
      macroFat: c(macroFat, other.macroFat),
      macroFatText: c(macroFatText, other.macroFatText),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      glassFill: c(glassFill, other.glassFill),
      glassBorder: c(glassBorder, other.glassBorder),
      quickAdd: c(quickAdd, other.quickAdd),
    );
  }
}

/// Resolves the palette from the widget tree: `context.hx.domainFasting`.
///
/// Prefer this over `AppColors.*` in all new and migrated code — it respects
/// `Theme` overrides in subtrees, which the global static cannot.
extension HxColorsContext on BuildContext {
  HxColors get hx =>
      Theme.of(this).extension<HxColors>() ??
      HxColors.of(Theme.of(this).brightness);
}
