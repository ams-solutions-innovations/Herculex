/// Which macro stat tiles show on the dashboard's macro grid, and in what
/// order. Sibling to [DashboardConfig] but scoped to the fixed 4-item macro
/// set `DailyTotals` actually tracks (kcal/protein/carbs/fat) — there is no
/// vegetable/fruit tracking to offer yet.
enum DashboardMacro {
  kcal('kcal', 'Calories'),
  protein('protein', 'Protein'),
  carbs('carbs', 'Carbs'),
  fat('fat', 'Fats');

  const DashboardMacro(this.id, this.label);
  final String id;
  final String label;

  static DashboardMacro? fromId(String id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return null;
  }
}

class MacroCardEntry {
  final DashboardMacro macro;
  final bool visible;

  const MacroCardEntry(this.macro, {this.visible = true});

  MacroCardEntry copyWith({bool? visible}) =>
      MacroCardEntry(macro, visible: visible ?? this.visible);
}

/// Ordered, toggleable macro-tile layout. Same encode/decode shape as
/// [DashboardConfig]: unknown ids are dropped, missing ones are appended
/// hidden, so the set of four macros never shrinks across app updates.
class MacroCardConfig {
  final List<MacroCardEntry> entries;

  const MacroCardConfig(this.entries);

  static const MacroCardConfig defaults = MacroCardConfig([
    MacroCardEntry(DashboardMacro.kcal),
    MacroCardEntry(DashboardMacro.protein),
    MacroCardEntry(DashboardMacro.carbs),
    MacroCardEntry(DashboardMacro.fat),
  ]);

  List<DashboardMacro> get visibleMacros =>
      [for (final e in entries) if (e.visible) e.macro];

  MacroCardConfig toggle(DashboardMacro macro, bool visible) {
    return MacroCardConfig([
      for (final e in entries)
        if (e.macro == macro) e.copyWith(visible: visible) else e,
    ]);
  }

  MacroCardConfig reorder(int oldIndex, int newIndex) {
    final list = [...entries];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
    return MacroCardConfig(list);
  }

  String encode() =>
      entries.map((e) => '${e.macro.id}:${e.visible ? 1 : 0}').join(',');

  static MacroCardConfig decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults;
    final parsed = <MacroCardEntry>[];
    final seen = <DashboardMacro>{};
    for (final token in raw.split(',')) {
      final parts = token.split(':');
      if (parts.isEmpty) continue;
      final macro = DashboardMacro.fromId(parts[0].trim());
      if (macro == null || seen.contains(macro)) continue;
      final visible = parts.length < 2 || parts[1].trim() != '0';
      parsed.add(MacroCardEntry(macro, visible: visible));
      seen.add(macro);
    }
    if (parsed.isEmpty) return defaults;
    for (final d in defaults.entries) {
      if (!seen.contains(d.macro)) {
        parsed.add(MacroCardEntry(d.macro, visible: false));
      }
    }
    return MacroCardConfig(parsed);
  }
}
