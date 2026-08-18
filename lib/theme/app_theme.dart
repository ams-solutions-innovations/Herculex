import 'package:flutter/material.dart';

import 'tokens/hx_colors.dart';
import 'tokens/hx_geometry.dart';

/// App theme, built entirely from the [HxColors] token palette.
///
/// The palette is also attached as a [ThemeExtension] so widgets can read
/// tokens from the context (`context.hx`) instead of the global `AppColors`.
class AppTheme {
  /// Universal pill shape used across buttons and containers.
  static const StadiumBorder _pill = StadiumBorder();

  /// Body/UI face: a humanist grotesque with excellent tabular numerals.
  static const String fontBody = 'Manrope';

  /// Display face for headlines and large stat numerals — the distinctive
  /// half of the pairing.
  static const String fontDisplay = 'SpaceGrotesk';

  static ThemeData get lightTheme => _buildTheme(Brightness.light);
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final p = HxColors.of(brightness);
    final isDark = p.isDark;

    final scheme = isDark
        ? ColorScheme.dark(
            primary: p.primary,
            onPrimary: p.onPrimary,
            secondary: p.primary,
            surface: p.background,
            onSurface: p.onSurface,
            surfaceContainer: p.surfaceContainer,
            surfaceContainerHighest: p.surfaceVariant,
            surfaceContainerLowest: p.surfaceContainerLowest,
            tertiary: p.tertiary,
            outline: p.outline,
            outlineVariant: p.outlineVariant,
            error: p.danger,
          )
        : ColorScheme.light(
            primary: p.primary,
            onPrimary: p.onPrimary,
            secondary: p.primary,
            surface: p.background,
            onSurface: p.onSurface,
            surfaceContainer: p.surfaceContainer,
            surfaceContainerHighest: p.surfaceVariant,
            surfaceContainerLowest: p.surfaceContainerLowest,
            tertiary: p.tertiary,
            outline: p.outline,
            outlineVariant: p.outlineVariant,
            error: p.danger,
          );

    final textTheme = _buildTextTheme(p);

    final base = ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: Colors.transparent,
      primaryColor: p.primary,
      colorScheme: scheme,
      fontFamily: fontBody,
      splashFactory: NoSplash.splashFactory, // iOS has no ripple
      highlightColor: Colors.transparent,
      extensions: <ThemeExtension<dynamic>>[p],
    );

    return base.copyWith(
      textTheme: textTheme,

      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontDisplay,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: p.onSurface,
          letterSpacing: -0.2,
        ),
      ),

      // ── Pill-shaped buttons ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          shape: _pill,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          elevation: 0,
          shape: _pill,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primaryText,
          shape: _pill,
          minimumSize: const Size(0, 50),
          side: BorderSide(color: p.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primaryText,
          shape: _pill,
          textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.2),
        ),
      ),

      // ── Pill-shaped chips ──
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceContainer,
        selectedColor: p.primary,
        disabledColor: p.surfaceContainer,
        labelStyle: TextStyle(
          color: p.onSurface, fontSize: 14, fontWeight: FontWeight.w500),
        secondaryLabelStyle: TextStyle(color: p.onPrimary),
        side: BorderSide.none,
        shape: _pill,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        showCheckmark: false,
      ),

      // ── Inputs: pill text fields ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceVariant,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        hintStyle: TextStyle(color: p.secondary),
        border: OutlineInputBorder(
          borderRadius: HxRadius.xlAll,
          borderSide: BorderSide(color: p.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: HxRadius.xlAll,
          borderSide: BorderSide(color: p.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: HxRadius.xlAll,
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        color: p.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: HxRadius.lgAll),
        margin: EdgeInsets.zero,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: p.primaryText,
        textColor: p.onSurface,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.primary : p.surfaceVariant),
        trackOutlineColor:
            const WidgetStatePropertyAll(Colors.transparent),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: p.primary,
        inactiveTrackColor: p.surfaceVariant,
        thumbColor: Colors.white,
        overlayColor: p.primary.withValues(alpha: 0.2),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(_pill),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? p.primary
                  : p.surfaceContainer),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? p.onPrimary : p.onSurface),
          side: const WidgetStatePropertyAll(BorderSide.none),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        elevation: 0,
        shape: const StadiumBorder(),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceContainer,
        modalBackgroundColor: p.surfaceContainer,
        shape: const RoundedRectangleBorder(
          borderRadius: HxRadius.sheetTop,
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: HxRadius.lgAll),
        titleTextStyle: TextStyle(
          fontFamily: fontDisplay,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: p.onSurface,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontBody, fontSize: 15, color: p.onSurfaceVariant),
      ),

      dividerTheme: DividerThemeData(
        color: p.outlineVariant,
        thickness: 0.5,
        space: 0.5,
      ),

      iconTheme: IconThemeData(color: p.onSurface),

      tabBarTheme: TabBarThemeData(
        labelColor: p.primaryText,
        unselectedLabelColor: p.secondary,
        indicatorColor: p.primary,
        dividerColor: Colors.transparent,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surfaceContainerLowest,
        selectedItemColor: p.primaryText,
        unselectedItemColor: p.secondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surfaceContainerLowest,
        indicatorColor: p.primary.withValues(alpha: 0.18),
        elevation: 0,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceVariant,
        contentTextStyle: TextStyle(color: p.onSurface),
        shape: RoundedRectangleBorder(borderRadius: HxRadius.mdAll),
        behavior: SnackBarBehavior.floating,
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Numerals line up in columns — essential for stat grids, set tables and
  /// running timers, where proportional digits visibly jitter.
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static TextTheme _buildTextTheme(HxColors p) => TextTheme(
    // Display + headline carry the distinctive face.
    displayLarge: TextStyle(
        fontFamily: fontDisplay, fontSize: 34, fontWeight: FontWeight.w700,
        color: p.onSurface, letterSpacing: -0.6, fontFeatures: _tabular),
    displayMedium: TextStyle(
        fontFamily: fontDisplay, fontSize: 28, fontWeight: FontWeight.w700,
        color: p.onSurface, letterSpacing: -0.5, fontFeatures: _tabular),
    displaySmall: TextStyle(
        fontFamily: fontDisplay, fontSize: 24, fontWeight: FontWeight.w700,
        color: p.onSurface, letterSpacing: -0.4, fontFeatures: _tabular),
    headlineLarge: TextStyle(
        fontFamily: fontDisplay, fontSize: 32, fontWeight: FontWeight.w700,
        color: p.onSurface, letterSpacing: -0.5, fontFeatures: _tabular),
    headlineMedium: TextStyle(
        fontFamily: fontDisplay, fontSize: 28, fontWeight: FontWeight.w700,
        color: p.onSurface, letterSpacing: -0.4, fontFeatures: _tabular),
    headlineSmall: TextStyle(
        fontFamily: fontDisplay, fontSize: 24, fontWeight: FontWeight.w600,
        color: p.onSurface, letterSpacing: -0.3, fontFeatures: _tabular),

    // Titles and below stay on the body face for legibility at small sizes.
    // Every style names its family explicitly: `ThemeData.fontFamily` does not
    // reach a `textTheme` supplied through copyWith, which is why the app
    // silently rendered in the platform default before this pass.
    titleLarge: TextStyle(
        fontFamily: fontBody, fontSize: 22, fontWeight: FontWeight.w700,
        color: p.onSurface, letterSpacing: -0.4, fontFeatures: _tabular),
    titleMedium: TextStyle(
        fontFamily: fontBody, fontSize: 17, fontWeight: FontWeight.w600,
        color: p.onSurface, letterSpacing: -0.2),
    titleSmall: TextStyle(
        fontFamily: fontBody, fontSize: 15, fontWeight: FontWeight.w600,
        color: p.onSurface, letterSpacing: -0.1),
    bodyLarge: TextStyle(
        fontFamily: fontBody, fontSize: 17, color: p.onSurface,
        letterSpacing: -0.2),
    bodyMedium: TextStyle(
        fontFamily: fontBody, fontSize: 15, color: p.onSurfaceVariant,
        letterSpacing: -0.1),
    bodySmall: TextStyle(
        fontFamily: fontBody, fontSize: 13, color: p.secondary),
    labelLarge: TextStyle(
        fontFamily: fontBody, fontSize: 15, fontWeight: FontWeight.w600,
        color: p.onSurface),
    labelMedium: TextStyle(
        fontFamily: fontBody, fontSize: 13, fontWeight: FontWeight.w500,
        color: p.secondary),
    labelSmall: TextStyle(
        fontFamily: fontBody, fontSize: 12, fontWeight: FontWeight.w500,
        color: p.secondary),
  );
}
