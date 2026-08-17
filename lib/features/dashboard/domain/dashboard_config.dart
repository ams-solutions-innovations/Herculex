/// The widgets that can appear on the editable dashboard (V2 §18).
enum DashboardWidgetType {
  fastingTimer('fasting_timer', 'Fasting Timer'),
  macros('macros', 'Nutrition Overview'),
  trends('trends', 'Trend Charts'),
  todaysPlan('todays_plan', "Today's Plan"),
  miniWorkouts('mini_workouts', 'Mini Workouts Checklist'),
  workoutCalendar('workout_calendar', 'Workout Calendar'),
  recoverySummary('recovery_summary', 'Recovery'),
  cnsLoad('cns_load', 'CNS Load'),
  weeklyVolume('weekly_volume', 'Weekly Volume'),
  latestPrs('latest_prs', 'Latest PRs'),
  bodyweight('bodyweight', 'Bodyweight'),
  cycle('cycle', 'Cycle'),
  quickScan('quick_scan', 'Quick Food Scan'),
  supplements('supplements', 'Supplements Tracker'),
  remainingCalories('remaining_calories', 'Calories Remaining'),
  nutritionStreak('nutrition_streak', 'Nutrition Streak'),
  workoutStreak('workout_streak', 'Workout Streak');

  const DashboardWidgetType(this.id, this.label);
  final String id;
  final String label;

  static DashboardWidgetType? fromId(String id) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// One configured dashboard slot: which widget, and whether it's shown.
class DashboardWidgetConfig {
  final DashboardWidgetType type;
  final bool visible;

  const DashboardWidgetConfig(this.type, {this.visible = true});

  DashboardWidgetConfig copyWith({bool? visible}) =>
      DashboardWidgetConfig(type, visible: visible ?? this.visible);
}

/// Ordered, toggleable dashboard layout (V2 §18). Pure value type with
/// stable string (de)serialization for SharedPreferences. Unknown ids are
/// dropped on load and any widget types missing from a stored config are
/// appended (hidden) so new app versions don't lose or hide existing slots.
class DashboardConfig {
  final List<DashboardWidgetConfig> widgets;

  const DashboardConfig(this.widgets);

  /// Default layout for a fresh install — the order the dashboard ships with.
  static const DashboardConfig defaults = DashboardConfig([
    DashboardWidgetConfig(DashboardWidgetType.fastingTimer),
    DashboardWidgetConfig(DashboardWidgetType.supplements),
    DashboardWidgetConfig(DashboardWidgetType.quickScan),
    DashboardWidgetConfig(DashboardWidgetType.remainingCalories),
    DashboardWidgetConfig(DashboardWidgetType.macros),
    DashboardWidgetConfig(DashboardWidgetType.trends),
    DashboardWidgetConfig(DashboardWidgetType.todaysPlan),
    DashboardWidgetConfig(DashboardWidgetType.miniWorkouts),
    DashboardWidgetConfig(DashboardWidgetType.workoutCalendar),
    DashboardWidgetConfig(DashboardWidgetType.recoverySummary),
    DashboardWidgetConfig(DashboardWidgetType.cnsLoad, visible: false),
    DashboardWidgetConfig(DashboardWidgetType.weeklyVolume, visible: false),
    DashboardWidgetConfig(DashboardWidgetType.latestPrs, visible: false),
    DashboardWidgetConfig(DashboardWidgetType.bodyweight, visible: false),
    DashboardWidgetConfig(DashboardWidgetType.nutritionStreak, visible: false),
    DashboardWidgetConfig(DashboardWidgetType.workoutStreak, visible: false),
    DashboardWidgetConfig(DashboardWidgetType.cycle),
  ]);

  List<DashboardWidgetConfig> get visibleWidgets =>
      [for (final w in widgets) if (w.visible) w];

  DashboardConfig toggle(DashboardWidgetType type, bool visible) {
    return DashboardConfig([
      for (final w in widgets)
        if (w.type == type) w.copyWith(visible: visible) else w,
    ]);
  }

  /// Moves the widget at [oldIndex] to [newIndex] (reorder).
  DashboardConfig reorder(int oldIndex, int newIndex) {
    final list = [...widgets];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
    return DashboardConfig(list);
  }

  /// Serializes to a compact string: `id:1,id:0,…` (1 = visible).
  String encode() =>
      widgets.map((w) => '${w.type.id}:${w.visible ? 1 : 0}').join(',');

  /// Parses [encode]'s output. Drops unknown ids; appends any widget types
  /// that weren't stored (as hidden) so the set stays complete and ordered.
  static DashboardConfig decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults;
    final parsed = <DashboardWidgetConfig>[];
    final seen = <DashboardWidgetType>{};
    for (final token in raw.split(',')) {
      final parts = token.split(':');
      if (parts.isEmpty) continue;
      final type = DashboardWidgetType.fromId(parts[0].trim());
      if (type == null || seen.contains(type)) continue;
      final visible = parts.length < 2 || parts[1].trim() != '0';
      parsed.add(DashboardWidgetConfig(type, visible: visible));
      seen.add(type);
    }
    if (parsed.isEmpty) return defaults;
    // Append any newly-introduced widget types (hidden) in default order.
    for (final d in defaults.widgets) {
      if (!seen.contains(d.type)) {
        parsed.add(DashboardWidgetConfig(d.type, visible: false));
      }
    }
    return DashboardConfig(parsed);
  }
}
