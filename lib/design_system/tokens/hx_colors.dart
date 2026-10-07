import 'package:flutter/material.dart';

/// The single source of truth for every color in the app.
///
/// Two const instances ([light] and [dark]) hold the full palette. They are
/// exposed to widgets as a [ThemeExtension] so colors resolve from the
/// `BuildContext` — see the `context.hx` extension at the bottom of this file.
/// `AppColors` remains as a compatibility shim that delegates here while the
/// ~1,500 legacy call sites migrate tab by tab.
///
enum AppColorTheme {
  classicBlue('Classic Blue'),
  siriousBlack('Sirious Black'),
  vividGreen('Vivid Green'),
  sunnyYellow('Sunny Yellow'),
  pinky('Pinky');

  const AppColorTheme(this.label);
  final String label;
}

/// The single source of truth for every color in the app.
///
/// Five theme palettes ([classicBlue], [siriousBlack], [vividGreen], [sunnyYellow], [pinky])
/// each provide both [light] and [dark] instances. They are
/// exposed to widgets as a [ThemeExtension] so colors resolve from the
/// `BuildContext` — see the `context.hx` extension at the bottom of this file.
/// `AppColors` remains as a compatibility shim that delegates here while the
/// ~1,500 legacy call sites migrate tab by tab.
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

  // ── 1. Classic Blue (Default) ──
  static const HxColors classicBlueDark = HxColors(
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

  static const HxColors classicBlueLight = HxColors(
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
    macroFat: Color(0xFFD97706),
    macroFatText: Color(0xFFB45309),
    success: Color(0xFF1E7A34),
    warning: Color(0xFFB36A00),
    danger: Color(0xFFC7261C),
    glassFill: Color(0xFFFFFFFF),
    glassBorder: Color(0xFFCFE0F3),
    quickAdd: Color(0xFFCC7A00),
  );

  // ── 2. Sirious Black ──
  static const HxColors siriousBlackDark = HxColors(
    brightness: Brightness.dark,
    gradientTop: Color(0xFF121214),
    gradientMid: Color(0xFF08080A),
    gradientBottom: Color(0xFF000000),
    background: Color(0xFF000000),
    primary: Color(0xFF3B82F6),
    primaryText: Color(0xFF60A5FA),
    primaryContainer: Color(0xFF1E293B),
    onPrimary: Color(0xFFFFFFFF),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFF9CA3AF),
    secondary: Color(0xFF71717A),
    tertiary: Color(0xFF52525B),
    surfaceContainer: Color(0xFF18181B),
    surfaceContainerLowest: Color(0xFF09090B),
    surfaceVariant: Color(0xFF27272A),
    outline: Color(0xFF3F3F46),
    outlineVariant: Color(0xFF27272A),
    domainTraining: Color(0xFF3B82F6),
    domainNutrition: Color(0xFF22C55E),
    domainFasting: Color(0xFF06B6D4),
    domainRecovery: Color(0xFFA855F7),
    macroKcal: Color(0xFFEF4444),
    macroProtein: Color(0xFF3B82F6),
    macroCarbs: Color(0xFF22C55E),
    macroFat: Color(0xFFEAB308),
    macroFatText: Color(0xFFFACC15),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    glassFill: Color(0xFF18181B),
    glassBorder: Color(0xFF27272A),
    quickAdd: Color(0xFF3B82F6),
  );

  static const HxColors siriousBlackLight = HxColors(
    brightness: Brightness.light,
    gradientTop: Color(0xFFE4E4E7),
    gradientMid: Color(0xFFF4F4F5),
    gradientBottom: Color(0xFFFAFAFA),
    background: Color(0xFFF4F4F5),
    primary: Color(0xFF18181B),
    primaryText: Color(0xFF09090B),
    primaryContainer: Color(0xFFE4E4E7),
    onPrimary: Color(0xFFFFFFFF),
    onSurface: Color(0xFF09090B),
    onSurfaceVariant: Color(0xFF52525B),
    secondary: Color(0xFF71717A),
    tertiary: Color(0xFFA1A1AA),
    surfaceContainer: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFAFAFA),
    surfaceVariant: Color(0xFFE4E4E7),
    outline: Color(0xFFA1A1AA),
    outlineVariant: Color(0xFFD4D4D8),
    domainTraining: Color(0xFF18181B),
    domainNutrition: Color(0xFF166534),
    domainFasting: Color(0xFF0E7490),
    domainRecovery: Color(0xFF7E22CE),
    macroKcal: Color(0xFFDC2626),
    macroProtein: Color(0xFF2563EB),
    macroCarbs: Color(0xFF16A34A),
    macroFat: Color(0xFFCA8A04),
    macroFatText: Color(0xFFA16207),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    glassFill: Color(0xFFFFFFFF),
    glassBorder: Color(0xFFD4D4D8),
    quickAdd: Color(0xFF18181B),
  );

  // ── 3. Vivid Green ──
  static const HxColors vividGreenDark = HxColors(
    brightness: Brightness.dark,
    gradientTop: Color(0xFF062319),
    gradientMid: Color(0xFF031610),
    gradientBottom: Color(0xFF010B07),
    background: Color(0xFF031610),
    primary: Color(0xFF10B981),
    primaryText: Color(0xFF34D399),
    primaryContainer: Color(0xFF064E3B),
    onPrimary: Color(0xFFFFFFFF),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFFA7F3D0),
    secondary: Color(0xFF6EE7B7),
    tertiary: Color(0xFF34D399),
    surfaceContainer: Color(0xFF0B251D),
    surfaceContainerLowest: Color(0xFF071C15),
    surfaceVariant: Color(0xFF13362B),
    outline: Color(0xFF1E5242),
    outlineVariant: Color(0xFF163E32),
    domainTraining: Color(0xFF10B981),
    domainNutrition: Color(0xFF34D399),
    domainFasting: Color(0xFF2DD4BF),
    domainRecovery: Color(0xFFA7F3D0),
    macroKcal: Color(0xFFFF453A),
    macroProtein: Color(0xFF38BDF8),
    macroCarbs: Color(0xFF34D399),
    macroFat: Color(0xFFFFD60A),
    macroFatText: Color(0xFFFFD60A),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFFF453A),
    glassFill: Color(0xFF0B251D),
    glassBorder: Color(0xFF163E32),
    quickAdd: Color(0xFF10B981),
  );

  static const HxColors vividGreenLight = HxColors(
    brightness: Brightness.light,
    gradientTop: Color(0xFFD1FAE5),
    gradientMid: Color(0xFFE6F9F0),
    gradientBottom: Color(0xFFF0FDF4),
    background: Color(0xFFE6F9F0),
    primary: Color(0xFF059669),
    primaryText: Color(0xFF047857),
    primaryContainer: Color(0xFFA7F3D0),
    onPrimary: Color(0xFFFFFFFF),
    onSurface: Color(0xFF06281E),
    onSurfaceVariant: Color(0xFF065F46),
    secondary: Color(0xFF047857),
    tertiary: Color(0xFF059669),
    surfaceContainer: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFF0FDF4),
    surfaceVariant: Color(0xFFDCFCE7),
    outline: Color(0xFF86EFAC),
    outlineVariant: Color(0xFFBBF7D0),
    domainTraining: Color(0xFF059669),
    domainNutrition: Color(0xFF15803D),
    domainFasting: Color(0xFF0F766E),
    domainRecovery: Color(0xFF6B21A8),
    macroKcal: Color(0xFFDC2626),
    macroProtein: Color(0xFF0284C7),
    macroCarbs: Color(0xFF16A34A),
    macroFat: Color(0xFFD97706),
    macroFatText: Color(0xFFB45309),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    glassFill: Color(0xFFFFFFFF),
    glassBorder: Color(0xFFBBF7D0),
    quickAdd: Color(0xFF059669),
  );

  // ── 4. Sunny Yellow ──
  static const HxColors sunnyYellowDark = HxColors(
    brightness: Brightness.dark,
    gradientTop: Color(0xFF261A04),
    gradientMid: Color(0xFF1A1202),
    gradientBottom: Color(0xFF0D0901),
    background: Color(0xFF1A1202),
    primary: Color(0xFFF59E0B),
    primaryText: Color(0xFFFBBF24),
    primaryContainer: Color(0xFF78350F),
    onPrimary: Color(0xFF000000),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFFFDE68A),
    secondary: Color(0xFFFCD34D),
    tertiary: Color(0xFFF59E0B),
    surfaceContainer: Color(0xFF281D0B),
    surfaceContainerLowest: Color(0xFF1F1608),
    surfaceVariant: Color(0xFF382910),
    outline: Color(0xFF785924),
    outlineVariant: Color(0xFF4D3815),
    domainTraining: Color(0xFFF59E0B),
    domainNutrition: Color(0xFF34D399),
    domainFasting: Color(0xFF38BDF8),
    domainRecovery: Color(0xFFA78BFA),
    macroKcal: Color(0xFFFF453A),
    macroProtein: Color(0xFF60A5FA),
    macroCarbs: Color(0xFF34D399),
    macroFat: Color(0xFFFBBF24),
    macroFatText: Color(0xFFFBBF24),
    success: Color(0xFF34D399),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFFF453A),
    glassFill: Color(0xFF281D0B),
    glassBorder: Color(0xFF4D3815),
    quickAdd: Color(0xFFF59E0B),
  );

  static const HxColors sunnyYellowLight = HxColors(
    brightness: Brightness.light,
    gradientTop: Color(0xFFFEF3C7),
    gradientMid: Color(0xFFFFFBEB),
    gradientBottom: Color(0xFFFFFDF5),
    background: Color(0xFFFFFBEB),
    primary: Color(0xFFD97706),
    primaryText: Color(0xFFB45309),
    primaryContainer: Color(0xFFFDE68A),
    onPrimary: Color(0xFFFFFFFF),
    onSurface: Color(0xFF2D1E04),
    onSurfaceVariant: Color(0xFF78350F),
    secondary: Color(0xFF92400E),
    tertiary: Color(0xFFB45309),
    surfaceContainer: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFDF5),
    surfaceVariant: Color(0xFFFEF3C7),
    outline: Color(0xFFFCD34D),
    outlineVariant: Color(0xFFFDE68A),
    domainTraining: Color(0xFFD97706),
    domainNutrition: Color(0xFF16A34A),
    domainFasting: Color(0xFF0284C7),
    domainRecovery: Color(0xFF7E22CE),
    macroKcal: Color(0xFFDC2626),
    macroProtein: Color(0xFF2563EB),
    macroCarbs: Color(0xFF16A34A),
    macroFat: Color(0xFFD97706),
    macroFatText: Color(0xFFB45309),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    glassFill: Color(0xFFFFFFFF),
    glassBorder: Color(0xFFFDE68A),
    quickAdd: Color(0xFFD97706),
  );

  // ── 5. Pinky ──
  static const HxColors pinkyDark = HxColors(
    brightness: Brightness.dark,
    gradientTop: Color(0xFF260D1E),
    gradientMid: Color(0xFF1A0814),
    gradientBottom: Color(0xFF0D030A),
    background: Color(0xFF1A0814),
    primary: Color(0xFFFF2D55),
    primaryText: Color(0xFFF472B6),
    primaryContainer: Color(0xFF831843),
    onPrimary: Color(0xFFFFFFFF),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFFFBCFE8),
    secondary: Color(0xFFF472B6),
    tertiary: Color(0xFFEC4899),
    surfaceContainer: Color(0xFF2B1323),
    surfaceContainerLowest: Color(0xFF200C19),
    surfaceVariant: Color(0xFF3C1C32),
    outline: Color(0xFF6E2856),
    outlineVariant: Color(0xFF4A1F3E),
    domainTraining: Color(0xFFFF2D55),
    domainNutrition: Color(0xFF34D399),
    domainFasting: Color(0xFF38BDF8),
    domainRecovery: Color(0xFFA78BFA),
    macroKcal: Color(0xFFFF453A),
    macroProtein: Color(0xFF60A5FA),
    macroCarbs: Color(0xFF34D399),
    macroFat: Color(0xFFFFD60A),
    macroFatText: Color(0xFFFFD60A),
    success: Color(0xFF34D399),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF453A),
    glassFill: Color(0xFF2B1323),
    glassBorder: Color(0xFF4A1F3E),
    quickAdd: Color(0xFFFF2D55),
  );

  static const HxColors pinkyLight = HxColors(
    brightness: Brightness.light,
    gradientTop: Color(0xFFFCE7F3),
    gradientMid: Color(0xFFFDF2F8),
    gradientBottom: Color(0xFFFFF5F9),
    background: Color(0xFFFDF2F8),
    primary: Color(0xFFDB2777),
    primaryText: Color(0xFFBE185D),
    primaryContainer: Color(0xFFFBCFE8),
    onPrimary: Color(0xFFFFFFFF),
    onSurface: Color(0xFF2E081B),
    onSurfaceVariant: Color(0xFF831843),
    secondary: Color(0xFF9D174D),
    tertiary: Color(0xFFBE185D),
    surfaceContainer: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFF5F9),
    surfaceVariant: Color(0xFFFCE7F3),
    outline: Color(0xFFF9A8D4),
    outlineVariant: Color(0xFFFBCFE8),
    domainTraining: Color(0xFFDB2777),
    domainNutrition: Color(0xFF16A34A),
    domainFasting: Color(0xFF0284C7),
    domainRecovery: Color(0xFF7E22CE),
    macroKcal: Color(0xFFDC2626),
    macroProtein: Color(0xFF2563EB),
    macroCarbs: Color(0xFF16A34A),
    macroFat: Color(0xFFD97706),
    macroFatText: Color(0xFFB45309),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    glassFill: Color(0xFFFFFFFF),
    glassBorder: Color(0xFFFBCFE8),
    quickAdd: Color(0xFFDB2777),
  );

  // Backward-compatible dark/light aliases (classic blue)
  static const HxColors dark = classicBlueDark;
  static const HxColors light = classicBlueLight;

  static HxColors of(
    Brightness brightness, [
    AppColorTheme theme = AppColorTheme.classicBlue,
  ]) {
    final isDark = brightness == Brightness.dark;
    return switch (theme) {
      AppColorTheme.classicBlue => isDark ? classicBlueDark : classicBlueLight,
      AppColorTheme.siriousBlack =>
        isDark ? siriousBlackDark : siriousBlackLight,
      AppColorTheme.vividGreen => isDark ? vividGreenDark : vividGreenLight,
      AppColorTheme.sunnyYellow => isDark ? sunnyYellowDark : sunnyYellowLight,
      AppColorTheme.pinky => isDark ? pinkyDark : pinkyLight,
    };
  }

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
      surfaceContainerLowest: c(
        surfaceContainerLowest,
        other.surfaceContainerLowest,
      ),
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
