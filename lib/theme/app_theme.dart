import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// iOS-inspired theme with Light and Dark mode support.
class AppTheme {
  /// Universal pill shape used across buttons and containers.
  static const StadiumBorder _pill = StadiumBorder();

  static ThemeData get lightTheme => _buildTheme(Brightness.light);
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final primary = isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
    final background = isDark ? const Color(0xFF091322) : const Color(0xFFEBF4FE);
    final scaffoldBackground = Colors.transparent;
    final onSurface = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    final onSurfaceVariant = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
    final secondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final tertiary = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
    final surfaceContainer = isDark ? const Color(0xFF161E2E) : const Color(0xFFFFFFFF);
    final surfaceContainerLowest = isDark ? const Color(0xFF111824) : const Color(0xFFFFFFFF);
    final surfaceVariant = isDark ? const Color(0xFF202A3C) : const Color(0xFFE8F1FA);
    final outlineVariant = isDark ? const Color(0xFF2B374E) : const Color(0xFFD6E3F2);
    final outline = isDark ? const Color(0xFF3B4C69) : const Color(0xFFCBD5E1);

    final scheme = isDark
        ? ColorScheme.dark(
            primary: primary,
            onPrimary: Colors.white,
            secondary: primary,
            surface: background,
            onSurface: onSurface,
            surfaceContainer: surfaceContainer,
            surfaceContainerHighest: surfaceVariant,
            surfaceContainerLowest: surfaceContainerLowest,
            tertiary: tertiary,
            outline: outline,
            outlineVariant: outlineVariant,
          )
        : ColorScheme.light(
            primary: primary,
            onPrimary: Colors.white,
            secondary: primary,
            surface: background,
            onSurface: onSurface,
            surfaceContainer: surfaceContainer,
            surfaceContainerHighest: surfaceVariant,
            surfaceContainerLowest: surfaceContainerLowest,
            tertiary: tertiary,
            outline: outline,
            outlineVariant: outlineVariant,
          );

    final textTheme = _buildTextTheme(onSurface, onSurfaceVariant, secondary);

    final base = ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: scaffoldBackground,
      primaryColor: primary,
      colorScheme: scheme,
      fontFamily: 'Inter',
      splashFactory: NoSplash.splashFactory, // iOS has no ripple
      highlightColor: Colors.transparent,
    );

    return base.copyWith(
      textTheme: textTheme,

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: onSurface,
          letterSpacing: -0.2,
        ),
      ),

      // ── Pill-shaped buttons ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: _pill,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
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
          foregroundColor: primary,
          shape: _pill,
          minimumSize: const Size(0, 50),
          side: BorderSide(color: outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: _pill,
          textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.2),
        ),
      ),

      // ── Pill-shaped chips ──
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainer,
        selectedColor: primary,
        disabledColor: surfaceContainer,
        labelStyle: TextStyle(
          color: onSurface, fontSize: 14, fontWeight: FontWeight.w500),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        side: BorderSide.none,
        shape: _pill,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        showCheckmark: false,
      ),

      // ── Inputs: pill text fields ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        hintStyle: TextStyle(color: secondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        color: surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: primary,
        textColor: onSurface,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? primary
                : surfaceVariant),
        trackOutlineColor:
            const WidgetStatePropertyAll(Colors.transparent),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: surfaceVariant,
        thumbColor: Colors.white,
        overlayColor: primary.withValues(alpha: 0.2),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(_pill),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? primary
                  : surfaceContainer),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? Colors.white
                  : onSurface),
          side: const WidgetStatePropertyAll(BorderSide.none),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: StadiumBorder(),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceContainerLowest,
        modalBackgroundColor: surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Inter', fontSize: 15, color: onSurfaceVariant),
      ),

      dividerTheme: DividerThemeData(
        color: outlineVariant,
        thickness: 0.5,
        space: 0.5,
      ),

      iconTheme: IconThemeData(color: onSurface),

      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: secondary,
        indicatorColor: primary,
        dividerColor: Colors.transparent,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceContainerLowest,
        selectedItemColor: primary,
        unselectedItemColor: secondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceContainerLowest,
        indicatorColor: primary.withValues(alpha: 0.18),
        elevation: 0,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceVariant,
        contentTextStyle: TextStyle(color: onSurface),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  static TextTheme _buildTextTheme(Color onSurface, Color onSurfaceVariant, Color secondary) => TextTheme(
    displayLarge: TextStyle(
        fontSize: 34, fontWeight: FontWeight.w700, color: onSurface, letterSpacing: -0.6),
    displayMedium: TextStyle(
        fontSize: 28, fontWeight: FontWeight.w700, color: onSurface, letterSpacing: -0.5),
    headlineLarge: TextStyle(
        fontSize: 32, fontWeight: FontWeight.w700, color: onSurface),
    headlineMedium: TextStyle(
        fontSize: 28, fontWeight: FontWeight.w700, color: onSurface),
    headlineSmall: TextStyle(
        fontSize: 24, fontWeight: FontWeight.w700, color: onSurface),
    titleLarge: TextStyle(
        fontSize: 22, fontWeight: FontWeight.w700, color: onSurface, letterSpacing: -0.4),
    titleMedium: TextStyle(
        fontSize: 17, fontWeight: FontWeight.w600, color: onSurface, letterSpacing: -0.2),
    titleSmall: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w600, color: onSurface, letterSpacing: -0.1),
    bodyLarge: TextStyle(fontSize: 17, color: onSurface, letterSpacing: -0.2),
    bodyMedium: TextStyle(fontSize: 15, color: onSurfaceVariant, letterSpacing: -0.1),
    bodySmall: TextStyle(fontSize: 13, color: secondary),
    labelLarge: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w600, color: onSurface),
    labelMedium: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w500, color: secondary),
    labelSmall: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w500, color: secondary),
  );
}