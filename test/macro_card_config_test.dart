import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/dashboard/domain/macro_card_config.dart';

/// Mirrors `phase6_dashboard_test.dart`'s coverage of `DashboardConfig` —
/// `MacroCardConfig` is the same encode/decode/toggle/reorder shape, scoped
/// to the fixed 4-macro dashboard grid (UI-rework P4).
void main() {
  group('MacroCardConfig', () {
    test('encode → decode round-trips visibility and order', () {
      final cfg = MacroCardConfig.defaults
          .toggle(DashboardMacro.carbs, false)
          .reorder(0, 3);
      final decoded = MacroCardConfig.decode(cfg.encode());
      expect(decoded.entries.map((e) => e.macro),
          cfg.entries.map((e) => e.macro));
      expect(decoded.entries.map((e) => e.visible),
          cfg.entries.map((e) => e.visible));
    });

    test('toggle flips a single macro without touching the others', () {
      final cfg = MacroCardConfig.defaults.toggle(DashboardMacro.fat, false);
      expect(
        cfg.entries.singleWhere((e) => e.macro == DashboardMacro.fat).visible,
        isFalse,
      );
      expect(
        cfg.entries
            .singleWhere((e) => e.macro == DashboardMacro.kcal)
            .visible,
        isTrue,
      );
    });

    test('reorder moves a macro without dropping any', () {
      final cfg = MacroCardConfig.defaults.reorder(0, 3);
      expect(cfg.entries, hasLength(4));
      expect(cfg.entries.map((e) => e.macro).toSet(),
          MacroCardConfig.defaults.entries.map((e) => e.macro).toSet());
      expect(cfg.entries.first.macro, isNot(DashboardMacro.kcal));
    });

    test('visibleMacros filters hidden entries, preserving order', () {
      final cfg = MacroCardConfig.defaults.toggle(DashboardMacro.protein, false);
      expect(cfg.visibleMacros.contains(DashboardMacro.protein), isFalse);
      expect(cfg.visibleMacros, [
        DashboardMacro.kcal,
        DashboardMacro.carbs,
        DashboardMacro.fat,
      ]);
    });

    test('decode of empty/garbage falls back to defaults', () {
      expect(MacroCardConfig.decode(null).entries.map((e) => e.macro),
          MacroCardConfig.defaults.entries.map((e) => e.macro));
      expect(MacroCardConfig.decode('   ').entries, isNotEmpty);
    });

    test('decode drops unknown ids and appends newly-added macros as hidden',
        () {
      final decoded = MacroCardConfig.decode('kcal:1,bogus:1,protein:0');
      final macros = decoded.entries.map((e) => e.macro).toList();
      expect(macros.first, DashboardMacro.kcal); // preserved first
      expect(macros.toSet().length, DashboardMacro.values.length);
      expect(
        decoded.entries
            .firstWhere((e) => e.macro == DashboardMacro.protein)
            .visible,
        isFalse,
      );
      // Never-stored macros (carbs, fat) are appended hidden, not dropped.
      expect(
        decoded.entries.firstWhere((e) => e.macro == DashboardMacro.carbs).visible,
        isFalse,
      );
    });
  });
}
