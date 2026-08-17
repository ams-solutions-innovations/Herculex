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
    for (final brightness in Brightness.values) {
      test('${brightness.name} palette matches token values', () {
        AppColors.brightness = brightness;
        final p = HxColors.of(brightness);

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
        expect(AppColors.backgroundGradient.colors,
            [p.gradientTop, p.gradientMid, p.gradientBottom]);
      });
    }

    tearDown(() => AppColors.brightness = Brightness.dark);
  });

  group('surface separation', () {
    test('light mode keeps cards and sheets distinguishable', () {
      // The pre-rework bug: both were pure white, so every card nested in a
      // sheet vanished.
      expect(
        HxColors.light.surfaceContainerLowest,
        isNot(HxColors.light.surfaceContainer),
      );
    });

    test('dark mode keeps cards and sheets distinguishable', () {
      expect(
        HxColors.dark.surfaceContainerLowest,
        isNot(HxColors.dark.surfaceContainer),
      );
    });
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

    test('primaryText clears 4.5:1 on light surfaces', () {
      expect(
        ratio(HxColors.light.primaryText, HxColors.light.surfaceContainer),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('primaryText clears 4.5:1 on dark surfaces', () {
      expect(
        ratio(HxColors.dark.primaryText, HxColors.dark.surfaceContainerLowest),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('body text clears 4.5:1 on card surfaces in both modes', () {
      for (final p in [HxColors.light, HxColors.dark]) {
        expect(
          ratio(p.onSurface, p.surfaceContainerLowest),
          greaterThanOrEqualTo(4.5),
          reason: '${p.brightness.name} onSurface on card',
        );
      }
    });

    test('macroFatText is legible on light card surfaces', () {
      expect(
        ratio(HxColors.light.macroFatText, HxColors.light.surfaceContainerLowest),
        greaterThanOrEqualTo(3.0),
      );
    });
  });

  group('theme wiring', () {
    test('both themes expose the palette as a ThemeExtension', () {
      expect(AppTheme.lightTheme.extension<HxColors>(), HxColors.light);
      expect(AppTheme.darkTheme.extension<HxColors>(), HxColors.dark);
    });

    test('bundled font families are applied', () {
      expect(AppTheme.darkTheme.textTheme.bodyLarge?.fontFamily,
          AppTheme.fontBody);
      expect(AppTheme.darkTheme.textTheme.displayLarge?.fontFamily,
          AppTheme.fontDisplay);
    });

    test('lerp interpolates rather than throwing', () {
      final mid = HxColors.light.lerp(HxColors.dark, 0.5);
      expect(mid.primary, isNotNull);
      expect(mid, isNot(HxColors.light));
    });
  });
}
