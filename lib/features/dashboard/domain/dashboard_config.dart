import 'package:flutter/material.dart';

/// Visual and compatibility kind for dashboard widgets.
enum DashboardWidgetKind { pill, card, large }

/// User-selectable shape style for dashboard widgets and pills.
enum DashboardCardShape {
  /// Modern squircle (28px radius) standardizing all cards and pills into a cohesive layout.
  squircle('squircle', 'Squircle', 28.0),

  /// Classic capsule pill (999px for pill-type widgets, 28px for standard cards).
  pill('pill', 'Pill', 999.0),

  /// Subtle compact rounded corners (16px).
  compact('compact', 'Compact', 16.0);

  const DashboardCardShape(this.id, this.label, this.pillRadius);
  final String id;
  final String label;
  final double pillRadius;

  double get cardRadius => switch (this) {
    DashboardCardShape.compact => 16.0,
    _ => 28.0,
  };

  static DashboardCardShape fromId(String? id) {
    for (final shape in values) {
      if (shape.id == id) return shape;
    }
    return DashboardCardShape.squircle;
  }
}

/// Grid footprint of a dashboard slot: half (1 of 2 columns) or full (both).
enum DashboardWidgetSize { half, full }

/// The widgets that can appear on the editable dashboard (V2 §18).
enum DashboardWidgetType {
  fastingTimer('fasting_timer', 'Fasting Timer'),
  macros('macros', 'Nutrition Overview'),
  calorieTrends('calorie_trends', 'Calorie Trends'),
  bodyweightTrends('bodyweight_trends', 'Bodyweight Trends'),
  todaysPlan('todays_plan', "Today's Plan"),
  miniWorkouts('mini_workouts', 'Mini Workouts Checklist'),
  workoutCalendar('workout_calendar', 'Workout Calendar'),
  recoverySummary('recovery_summary', 'Recovery'),
  cnsLoad('cns_load', 'CNS Load'),
  weeklyVolume('weekly_volume', 'Weekly Volume'),
  latestPrs('latest_prs', 'Latest PRs'),
  cycle('cycle', 'Cycle'),
  quickScan('quick_scan', 'Quick Food Scan'),
  supplements('supplements', 'Supplements Tracker'),
  remainingCalories('remaining_calories', 'Calories Remaining'),
  nutritionStreak('nutrition_streak', 'Nutrition Streak'),
  workoutStreak('workout_streak', 'Workout Streak'),
  herculInsights('hercul_insights', 'Hercul Insights');

  const DashboardWidgetType(this.id, this.label);
  final String id;
  final String label;

  /// Dedicated icon for the customization sheet and widget header badges.
  IconData get icon => switch (this) {
    DashboardWidgetType.fastingTimer => Icons.timer_outlined,
    DashboardWidgetType.macros => Icons.pie_chart_outline,
    DashboardWidgetType.calorieTrends => Icons.show_chart,
    DashboardWidgetType.bodyweightTrends => Icons.monitor_weight_outlined,
    DashboardWidgetType.todaysPlan => Icons.assignment_outlined,
    DashboardWidgetType.miniWorkouts => Icons.checklist_outlined,
    DashboardWidgetType.workoutCalendar => Icons.calendar_today_outlined,
    DashboardWidgetType.recoverySummary => Icons.battery_charging_full,
    DashboardWidgetType.cnsLoad => Icons.bolt_outlined,
    DashboardWidgetType.weeklyVolume => Icons.bar_chart,
    DashboardWidgetType.latestPrs => Icons.emoji_events_outlined,
    DashboardWidgetType.cycle => Icons.water_drop_outlined,
    DashboardWidgetType.quickScan => Icons.document_scanner_outlined,
    DashboardWidgetType.supplements => Icons.medication_outlined,
    DashboardWidgetType.remainingCalories => Icons.restaurant_menu,
    DashboardWidgetType.nutritionStreak => Icons.local_fire_department,
    DashboardWidgetType.workoutStreak => Icons.directions_run,
    DashboardWidgetType.herculInsights => Icons.psychology_outlined,
  };

  /// Widget shape classification for stack compatibility.
  DashboardWidgetKind get kind => switch (this) {
    DashboardWidgetType.cnsLoad ||
    DashboardWidgetType.weeklyVolume ||
    DashboardWidgetType.nutritionStreak ||
    DashboardWidgetType.workoutStreak => DashboardWidgetKind.pill,
    DashboardWidgetType.calorieTrends ||
    DashboardWidgetType.bodyweightTrends ||
    DashboardWidgetType.recoverySummary ||
    DashboardWidgetType.latestPrs ||
    DashboardWidgetType.remainingCalories ||
    DashboardWidgetType.quickScan ||
    DashboardWidgetType.herculInsights ||
    DashboardWidgetType.supplements ||
    DashboardWidgetType.miniWorkouts ||
    DashboardWidgetType.todaysPlan ||
    DashboardWidgetType.cycle => DashboardWidgetKind.card,
    DashboardWidgetType.fastingTimer ||
    DashboardWidgetType.macros ||
    DashboardWidgetType.workoutCalendar => DashboardWidgetKind.large,
  };

  /// Whether this widget's layout tolerates shrinking to half the dashboard
  /// width. Full-bleed feature widgets (fasting timer, macros, calendar…)
  /// aren't built for it, so they never show a resize handle.
  bool get resizable => switch (this) {
    DashboardWidgetType.calorieTrends ||
    DashboardWidgetType.bodyweightTrends ||
    DashboardWidgetType.recoverySummary ||
    DashboardWidgetType.cnsLoad ||
    DashboardWidgetType.weeklyVolume ||
    DashboardWidgetType.latestPrs ||
    DashboardWidgetType.remainingCalories ||
    DashboardWidgetType.nutritionStreak ||
    DashboardWidgetType.workoutStreak => true,
    _ => false,
  };

  static DashboardWidgetType? fromId(String id) {
    if (id == 'trends') return DashboardWidgetType.calorieTrends;
    for (final t in values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// One configured dashboard slot: either a standalone widget or a stack of
/// compatible widgets (like Samsung One UI widget stacks).
class DashboardWidgetConfig {
  final List<DashboardWidgetType> types;
  final bool visible;
  final DashboardWidgetSize size;

  const DashboardWidgetConfig(
    this.types, {
    this.visible = true,
    this.size = DashboardWidgetSize.full,
  });

  DashboardWidgetType get type => types.first;
  bool get isStack => types.length > 1;
  String get id => types.map((t) => t.id).join('+');

  /// Resolved grid span, clamped to full for stacks and non-resizable types
  /// regardless of what [size] happens to hold.
  DashboardWidgetSize get effectiveSize =>
      !isStack && type.resizable ? size : DashboardWidgetSize.full;

  DashboardWidgetConfig copyWith({
    List<DashboardWidgetType>? types,
    bool? visible,
    DashboardWidgetSize? size,
  }) => DashboardWidgetConfig(
    types ?? this.types,
    visible: visible ?? this.visible,
    size: size ?? this.size,
  );
}

/// Ordered, toggleable dashboard layout (V2 §18). Pure value type with
/// stable string (de)serialization for SharedPreferences. Unknown ids are
/// dropped on load and any widget types missing from a stored config are
/// appended (hidden) so new app versions don't lose or hide existing slots.
class DashboardConfig {
  final List<DashboardWidgetConfig> widgets;

  const DashboardConfig(this.widgets);

  /// Default layout for a fresh install — Calorie & Bodyweight Trends ship
  /// stacked together as a Samsung-style widget stack.
  static const DashboardConfig defaults = DashboardConfig([
    DashboardWidgetConfig([DashboardWidgetType.fastingTimer]),
    DashboardWidgetConfig([DashboardWidgetType.supplements]),
    DashboardWidgetConfig([DashboardWidgetType.quickScan]),
    DashboardWidgetConfig([DashboardWidgetType.remainingCalories]),
    DashboardWidgetConfig([DashboardWidgetType.macros]),
    DashboardWidgetConfig([DashboardWidgetType.herculInsights]),
    DashboardWidgetConfig([
      DashboardWidgetType.calorieTrends,
      DashboardWidgetType.bodyweightTrends,
    ]),
    DashboardWidgetConfig([DashboardWidgetType.todaysPlan]),
    DashboardWidgetConfig([DashboardWidgetType.miniWorkouts]),
    DashboardWidgetConfig([DashboardWidgetType.workoutCalendar]),
    DashboardWidgetConfig([DashboardWidgetType.recoverySummary]),
    DashboardWidgetConfig([DashboardWidgetType.cnsLoad], visible: false),
    DashboardWidgetConfig([DashboardWidgetType.weeklyVolume], visible: false),
    DashboardWidgetConfig([DashboardWidgetType.latestPrs], visible: false),
    DashboardWidgetConfig([
      DashboardWidgetType.nutritionStreak,
    ], visible: false),
    DashboardWidgetConfig([DashboardWidgetType.workoutStreak], visible: false),
    DashboardWidgetConfig([DashboardWidgetType.cycle]),
  ]);

  DashboardConfig toggleSlot(int index, bool visible) {
    if (index < 0 || index >= widgets.length) return this;
    final list = [...widgets];
    list[index] = list[index].copyWith(visible: visible);
    return DashboardConfig(list);
  }

  /// Sets the grid span of the slot at [index] (half vs full width).
  DashboardConfig resize(int index, DashboardWidgetSize size) {
    if (index < 0 || index >= widgets.length) return this;
    final list = [...widgets];
    list[index] = list[index].copyWith(size: size);
    return DashboardConfig(list);
  }

  /// Moves the widget slot at [oldIndex] to [newIndex] (reorder).
  DashboardConfig reorder(int oldIndex, int newIndex) {
    final list = [...widgets];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
    return DashboardConfig(list);
  }

  /// Stacks [addedType] into the slot containing [targetType].
  DashboardConfig stackWidgets(
    DashboardWidgetType targetType,
    DashboardWidgetType addedType,
  ) {
    if (targetType == addedType) return this;
    final list = <DashboardWidgetConfig>[];
    for (final w in widgets) {
      if (w.types.contains(targetType)) {
        final newTypes = [...w.types];
        if (!newTypes.contains(addedType)) {
          newTypes.add(addedType);
        }
        list.add(w.copyWith(types: newTypes));
      } else if (w.types.contains(addedType)) {
        final remaining = w.types.where((t) => t != addedType).toList();
        if (remaining.isNotEmpty) {
          list.add(w.copyWith(types: remaining));
        }
      } else {
        list.add(w);
      }
    }
    return DashboardConfig(list);
  }

  /// Unstacks [type] from its current slot and places it as a standalone slot.
  DashboardConfig unstackWidget(DashboardWidgetType type) {
    final list = <DashboardWidgetConfig>[];
    for (final w in widgets) {
      if (w.isStack && w.types.contains(type)) {
        final remaining = w.types.where((t) => t != type).toList();
        list.add(w.copyWith(types: remaining));
        list.add(DashboardWidgetConfig([type], visible: w.visible));
      } else {
        list.add(w);
      }
    }
    return DashboardConfig(list);
  }

  /// Serializes to a compact string: `id1+id2:1,id3:0:h,…` (1 = visible,
  /// trailing `:h` = half-width; omitted = full-width, so pre-resize saves
  /// keep decoding unchanged).
  String encode() => widgets
      .map((w) {
        final base =
            '${w.types.map((t) => t.id).join('+')}:${w.visible ? 1 : 0}';
        return w.size == DashboardWidgetSize.half ? '$base:h' : base;
      })
      .join(',');

  /// Parses [encode]'s output. Drops unknown ids; appends any widget types
  /// that weren't stored (as hidden) so the set stays complete and ordered.
  static DashboardConfig decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults;
    final parsed = <DashboardWidgetConfig>[];
    final seen = <DashboardWidgetType>{};
    for (final token in raw.split(',')) {
      final parts = token.split(':');
      if (parts.isEmpty) continue;
      final typeIds = parts[0].trim().split('+');
      final slotTypes = <DashboardWidgetType>[];

      for (final tid in typeIds) {
        if (tid == 'trends') {
          // Legacy trends token: if neither calorie nor bodyweight trends seen, add both stacked
          if (!seen.contains(DashboardWidgetType.calorieTrends)) {
            slotTypes.add(DashboardWidgetType.calorieTrends);
            seen.add(DashboardWidgetType.calorieTrends);
          }
          if (!seen.contains(DashboardWidgetType.bodyweightTrends)) {
            slotTypes.add(DashboardWidgetType.bodyweightTrends);
            seen.add(DashboardWidgetType.bodyweightTrends);
          }
          continue;
        }

        final type = DashboardWidgetType.fromId(tid);
        if (type == null || seen.contains(type)) continue;
        slotTypes.add(type);
        seen.add(type);
      }

      if (slotTypes.isEmpty) continue;
      final visible = parts.length < 2 || parts[1].trim() != '0';
      final size = parts.length > 2 && parts[2].trim() == 'h'
          ? DashboardWidgetSize.half
          : DashboardWidgetSize.full;
      parsed.add(
        DashboardWidgetConfig(slotTypes, visible: visible, size: size),
      );
    }

    if (parsed.isEmpty) return defaults;

    // Append any newly-introduced widget types (hidden) in default order.
    for (final d in defaults.widgets) {
      for (final type in d.types) {
        if (!seen.contains(type)) {
          parsed.add(DashboardWidgetConfig([type], visible: d.visible));
          seen.add(type);
        }
      }
    }
    return DashboardConfig(parsed);
  }
}
