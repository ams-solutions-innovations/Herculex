import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/theme/app_theme.dart';
import 'package:herculex/theme/colors.dart';
import 'package:herculex/theme/tokens/tokens.dart';

/// Guards the UI-rework token migration: the `AppColors` shim must stay a
/// faithful view of [HxColors] while ~1,500 legacy call sites migrate, and the
/// light palette must keep card and sheet surfaces distinguishable.
void main() {
  group('AppColors shim mirrors HxColors', () {
    for (final colorTheme in AppColorTheme.values) {
      for (final brightness in Brightness.values) {
        test(
          '${colorTheme.label} ${brightness.name} palette matches token values',
          () {
            AppColors.brightness = brightness;
            AppColors.colorTheme = colorTheme;
            final p = HxColors.of(brightness, colorTheme);

            expect(AppColors.background, p.background);
            expect(AppColors.primary, p.primary);
            expect(AppColors.primaryContainer, p.primaryContainer);
            expect(AppColors.onSurface, p.onSurface);
            expect(AppColors.onSurfaceVariant, p.onSurfaceVariant);
            expect(AppColors.secondary, p.secondary);
            expect(AppColors.tertiary, p.tertiary);
            expect(AppColors.surfaceContainer, p.surfaceContainer);
            expect(AppColors.surfaceContainerLowest, p.surfaceContainerLowest);
            expect(AppColors.surfaceVariant, p.surfaceVariant);
            expect(AppColors.outline, p.outline);
            expect(AppColors.outlineVariant, p.outlineVariant);
            expect(AppColors.macroKcal, p.macroKcal);
            expect(AppColors.macroProtein, p.macroProtein);
            expect(AppColors.macroCarbs, p.macroCarbs);
            expect(AppColors.macroFat, p.macroFat);
            expect(AppColors.macroFatText, p.macroFatText);
            expect(AppColors.backgroundGradient.colors, [
              p.gradientTop,
              p.gradientMid,
              p.gradientBottom,
            ]);
          },
        );
      }
    }

    tearDown(() {
      AppColors.brightness = Brightness.dark;
      AppColors.colorTheme = AppColorTheme.classicBlue;
    });
  });

  group('surface separation', () {
    for (final colorTheme in AppColorTheme.values) {
      test(
        '${colorTheme.label} light keeps cards and sheets distinguishable',
        () {
          final p = HxColors.of(Brightness.light, colorTheme);
          expect(p.surfaceContainerLowest, isNot(p.surfaceContainer));
        },
      );

      test(
        '${colorTheme.label} dark keeps cards and sheets distinguishable',
        () {
          final p = HxColors.of(Brightness.dark, colorTheme);
          expect(p.surfaceContainerLowest, isNot(p.surfaceContainer));
        },
      );
    }
  });

  group('contrast', () {
    /// WCAG relative luminance.
    double luminance(Color c) => c.computeLuminance();

    double ratio(Color a, Color b) {
      final la = luminance(a);
      final lb = luminance(b);
      final light = la > lb ? la : lb;
      final dark = la > lb ? lb : la;
      return (light + 0.05) / (dark + 0.05);
    }

    for (final colorTheme in AppColorTheme.values) {
      test(
        '${colorTheme.label} primaryText clears 4.5:1 on light surfaces',
        () {
          final p = HxColors.of(Brightness.light, colorTheme);
          expect(
            ratio(p.primaryText, p.surfaceContainer),
            greaterThanOrEqualTo(4.5),
            reason: '${colorTheme.label} light primaryText',
          );
        },
      );

      test('${colorTheme.label} primaryText clears 4.5:1 on dark surfaces', () {
        final p = HxColors.of(Brightness.dark, colorTheme);
        expect(
          ratio(p.primaryText, p.surfaceContainerLowest),
          greaterThanOrEqualTo(4.5),
          reason: '${colorTheme.label} dark primaryText',
        );
      });

      test(
        '${colorTheme.label} body text clears 4.5:1 on card surfaces in both modes',
        () {
          for (final p in [
            HxColors.of(Brightness.light, colorTheme),
            HxColors.of(Brightness.dark, colorTheme),
          ]) {
            expect(
              ratio(p.onSurface, p.surfaceContainerLowest),
              greaterThanOrEqualTo(4.5),
              reason:
                  '${colorTheme.label} ${p.brightness.name} onSurface on card',
            );
          }
        },
      );
    }

    test('macroFatText is legible on light card surfaces', () {
      for (final colorTheme in AppColorTheme.values) {
        final p = HxColors.of(Brightness.light, colorTheme);
        expect(
          ratio(p.macroFatText, p.surfaceContainerLowest),
          greaterThanOrEqualTo(3.0),
          reason: '${colorTheme.label} light macroFatText',
        );
      }
    });
  });

  group('theme wiring', () {
    for (final colorTheme in AppColorTheme.values) {
      test(
        '${colorTheme.label} themes expose the palette as a ThemeExtension',
        () {
          expect(
            AppTheme.lightThemeWith(colorTheme).extension<HxColors>(),
            HxColors.of(Brightness.light, colorTheme),
          );
          expect(
            AppTheme.darkThemeWith(colorTheme).extension<HxColors>(),
            HxColors.of(Brightness.dark, colorTheme),
          );
        },
      );
    }

    test('default getters fallback to classicBlue', () {
      expect(
        AppTheme.lightTheme.extension<HxColors>(),
        HxColors.classicBlueLight,
      );
      expect(
        AppTheme.darkTheme.extension<HxColors>(),
        HxColors.classicBlueDark,
      );
    });

    test('bundled font families are applied', () {
      expect(
        AppTheme.darkTheme.textTheme.bodyLarge?.fontFamily,
        AppTheme.fontBody,
      );
      expect(
        AppTheme.darkTheme.textTheme.displayLarge?.fontFamily,
        AppTheme.fontDisplay,
      );
    });

    test('lerp interpolates rather than throwing', () {
      final mid = HxColors.light.lerp(HxColors.dark, 0.5);
      expect(mid.primary, isNotNull);
      expect(mid, isNot(HxColors.light));
    });
  });
}
