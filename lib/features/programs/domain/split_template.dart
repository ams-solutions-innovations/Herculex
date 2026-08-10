/// Split definitions and the generator that turns "PPL, 6 days a week" into a
/// concrete weekly skeleton (or a rotating cycle).
///
/// Pure Dart — no Flutter, no drift. The repository maps a [SplitPlan] onto
/// `ProgramDays` rows; `ScheduleWalker` (schedule_walk.dart) turns those rows
/// into calendar dates.
library;

/// How a program's days repeat.
enum ScheduleMode {
  /// Days map to weekdays 1–7 and repeat every calendar week.
  weekly('weekly'),

  /// Days map to a 0-based position in a cycle of [SplitPlan.cycleLength] days
  /// and repeat on that period, independently of the calendar week. A 4-day
  /// cycle drifts across weekdays; a 7-day one happens to line up with weeks.
  cycle('cycle');

  const ScheduleMode(this.id);
  final String id;

  static ScheduleMode fromId(String? id) =>
      values.firstWhere((m) => m.id == id, orElse: () => ScheduleMode.weekly);
}

/// The training splits the builder can generate.
enum SplitType {
  fullBody('full_body', 'Full Body', ['Full Body A', 'Full Body B',
      'Full Body C'], 3),
  upperLower('upper_lower', 'Upper / Lower', ['Upper', 'Lower'], 4),
  ppl('ppl', 'Push / Pull / Legs', ['Push', 'Pull', 'Legs'], 6),
  ab('ab', 'A / B', ['A', 'B'], 4),
  abc('abc', 'A / B / C', ['A', 'B', 'C'], 3),
  broSplit('bro', 'Bro Split',
      ['Chest', 'Back', 'Legs', 'Shoulders', 'Arms'], 5),

  /// Slots come from the caller; with none supplied they are numbered.
  custom('custom', 'Custom', [], 3);

  const SplitType(this.id, this.label, this.slots, this.defaultDaysPerWeek);

  final String id;
  final String label;

  /// The slot names, assigned to training days round-robin. PPL over 6 days
  /// therefore yields Push/Pull/Legs/Push/Pull/Legs.
  final List<String> slots;
  final int defaultDaysPerWeek;

  static SplitType fromId(String? id) =>
      values.firstWhere((s) => s.id == id, orElse: () => SplitType.custom);
}

/// One generated day of the skeleton.
class SplitDaySpec {
  const SplitDaySpec({
    required this.index,
    required this.slotIndex,
    required this.label,
    this.isRest = false,
  });

  /// Weekly: `dayOfWeek - 1`, so 0 = Monday. Cycle: `cycleDayIndex`.
  final int index;

  /// Position in [SplitType.slots]. Repeats when a split cycles within a week
  /// (PPL over 6 days uses slot 0 twice), which is what lets both Push days
  /// share one template. `-1` for rest days.
  final int slotIndex;

  final String label;
  final bool isRest;

  /// `dayOfWeek` for weekly plans. For cycle plans this is the filler value the
  /// NOT NULL column requires — see the note on `ProgramDays.dayOfWeek`.
  int get dayOfWeek => (index % 7) + 1;

  @override
  String toString() =>
      'SplitDaySpec(index: $index, slot: $slotIndex, $label'
      '${isRest ? ', rest' : ''})';
}

/// A generated skeleton, ready to be written as `ProgramDays`.
class SplitPlan {
  const SplitPlan({
    required this.type,
    required this.mode,
    required this.cycleLength,
    required this.days,
  });

  final SplitType type;
  final ScheduleMode mode;

  /// 7 for weekly plans; the rotation period for cycle plans.
  final int cycleLength;

  /// Ordered by [SplitDaySpec.index]. Weekly plans list training days only
  /// (rest is any weekday without a day); cycle plans list rest slots too, so
  /// the rotation length is explicit.
  final List<SplitDaySpec> days;

  List<SplitDaySpec> get trainingDays =>
      days.where((d) => !d.isRest).toList(growable: false);

  int get trainingDayCount => trainingDays.length;

  /// The distinct slots in play, in slot order — what the builder asks the user
  /// to attach templates to.
  List<({int slotIndex, String label})> get slotSummary {
    final seen = <int, String>{};
    for (final d in trainingDays) {
      seen.putIfAbsent(d.slotIndex, () => d.label);
    }
    final keys = seen.keys.toList()..sort();
    return [for (final k in keys) (slotIndex: k, label: seen[k]!)];
  }
}

/// Generates weekly skeletons and rotating cycles from a split.
abstract final class SplitTemplates {
  /// Weekday placement by training frequency, chosen for recovery spacing.
  /// Values are `dayOfWeek` (1 = Monday); Sunday is the last day given away.
  static const Map<int, List<int>> weekdaySpacing = {
    1: [3],
    2: [1, 4],
    3: [1, 3, 5],
    4: [1, 2, 4, 5],
    5: [1, 2, 3, 5, 6],
    6: [1, 2, 3, 4, 5, 6],
    7: [1, 2, 3, 4, 5, 6, 7],
  };

  /// Builds a skeleton.
  ///
  /// [daysPerWeek] is the number of training days — per week in
  /// [ScheduleMode.weekly], per cycle in [ScheduleMode.cycle]. In cycle mode
  /// [cycleLength] defaults to `daysPerWeek + 1` (one trailing rest day) and the
  /// remaining slots become rest days.
  ///
  /// [preferredWeekdays] (1–7) overrides [weekdaySpacing] in weekly mode.
  /// [customSlots] supplies the slot names for [SplitType.custom].
  static SplitPlan generate({
    required SplitType type,
    required int daysPerWeek,
    ScheduleMode mode = ScheduleMode.weekly,
    int? cycleLength,
    List<String>? customSlots,
    List<int>? preferredWeekdays,
  }) {
    final slots = _slotsFor(type, customSlots, daysPerWeek);

    if (mode == ScheduleMode.weekly) {
      final days = daysPerWeek.clamp(1, 7);
      final weekdays = (preferredWeekdays == null || preferredWeekdays.isEmpty)
          ? weekdaySpacing[days]!
          : (preferredWeekdays.toSet().toList()..sort())
                .where((d) => d >= 1 && d <= 7)
                .take(days)
                .toList();

      return SplitPlan(
        type: type,
        mode: mode,
        cycleLength: 7,
        days: [
          for (var i = 0; i < weekdays.length; i++)
            SplitDaySpec(
              index: weekdays[i] - 1,
              slotIndex: i % slots.length,
              label: slots[i % slots.length],
            ),
        ],
      );
    }

    // Cycle mode: training days occupy 0..daysPerWeek-1, the rest is rest.
    final training = daysPerWeek < 1 ? 1 : daysPerWeek;
    final length = (cycleLength == null || cycleLength < training)
        ? training + 1
        : cycleLength;

    return SplitPlan(
      type: type,
      mode: mode,
      cycleLength: length,
      days: [
        for (var i = 0; i < length; i++)
          if (i < training)
            SplitDaySpec(
              index: i,
              slotIndex: i % slots.length,
              label: slots[i % slots.length],
            )
          else
            SplitDaySpec(
              index: i,
              slotIndex: -1,
              label: 'Rest',
              isRest: true,
            ),
      ],
    );
  }

  static List<String> _slotsFor(
    SplitType type,
    List<String>? customSlots,
    int daysPerWeek,
  ) {
    final supplied = customSlots?.where((s) => s.trim().isNotEmpty).toList();
    if (supplied != null && supplied.isNotEmpty) return supplied;
    if (type.slots.isNotEmpty) return type.slots;
    // Custom with nothing supplied: one numbered slot per training day.
    final count = daysPerWeek < 1 ? 1 : daysPerWeek;
    return [for (var i = 1; i <= count; i++) 'Day $i'];
  }
}
