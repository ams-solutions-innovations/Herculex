import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';

/// The "Exercise wave X of Y · Weeks A–B" indicator shown alongside "Week N
/// of M" (D-05). Immutable result of [WaveLabel.compute].
class WaveLabelInfo {
  /// 1-based index of the wave containing the viewed week.
  final int waveIndex;

  /// Total number of contiguous waves the block has.
  final int waveCount;

  /// 0-based first week index of the wave containing the viewed week.
  final int waveStartWeek;

  /// 0-based last week index of the wave containing the viewed week.
  final int waveEndWeek;

  const WaveLabelInfo({
    required this.waveIndex,
    required this.waveCount,
    required this.waveStartWeek,
    required this.waveEndWeek,
  });

  /// Exact copy per 19-UI-SPEC.md's Copywriting Contract, e.g.
  /// "Exercise wave 2 of 4 · Weeks 3–4".
  String get label =>
      'Exercise wave $waveIndex of $waveCount · '
      'Weeks ${waveStartWeek + 1}–${waveEndWeek + 1}';
}

/// One block-wide wave: a run of weeks in which no slot swaps its exercise.
class WaveSegment {
  const WaveSegment({
    required this.index,
    required this.startWeek,
    required this.endWeek,
  });

  /// 1-based position among the block's waves.
  final int index;

  /// 0-based first and last week index (inclusive).
  final int startWeek;
  final int endWeek;

  int get weekCount => endWeek - startWeek + 1;

  bool contains(int weekIndex) =>
      weekIndex >= startWeek && weekIndex <= endWeek;

  /// "Weeks 1–3", or "Week 4" for a single week.
  String get weeksLabel => startWeek == endWeek
      ? 'Week ${startWeek + 1}'
      : 'Weeks ${startWeek + 1}–${endWeek + 1}';

  @override
  bool operator ==(Object other) =>
      other is WaveSegment &&
      other.index == index &&
      other.startWeek == startWeek &&
      other.endWeek == endWeek;

  @override
  int get hashCode => Object.hash(index, startWeek, endWeek);

  @override
  String toString() => 'WaveSegment($index, $startWeek–$endWeek)';
}

/// Splits a whole block into exercise waves.
///
/// [WaveLabel] follows one anchor slot; this looks at every slot, so a wave
/// ends as soon as *any* slot rotates. That is the unit the plan view shows,
/// and it uses the same "contiguous equal exercise" definition as
/// [WaveLabel] and `replaceProgramExerciseSlot`.
abstract final class WaveSegments {
  /// [exerciseIdByWeekBySlot] maps slot id → (0-based week → exercise id).
  /// Weeks a slot has no entry for are ignored for that slot, so a
  /// partly-materialized slot does not invent boundaries. With no rotation
  /// anywhere the result is a single segment covering every week.
  static List<WaveSegment> compute({
    required int totalWeeks,
    required Map<int, Map<int, int?>> exerciseIdByWeekBySlot,
  }) {
    if (totalWeeks <= 0) return const [];
    final starts = <int>[0];
    for (var week = 1; week < totalWeeks; week++) {
      final changed = exerciseIdByWeekBySlot.values.any((byWeek) {
        final previous = byWeek[week - 1];
        final current = byWeek[week];
        return previous != null && current != null && previous != current;
      });
      if (changed) starts.add(week);
    }
    return [
      for (var i = 0; i < starts.length; i++)
        WaveSegment(
          index: i + 1,
          startWeek: starts[i],
          endWeek: i + 1 < starts.length ? starts[i + 1] - 1 : totalWeeks - 1,
        ),
    ];
  }
}

/// Pure, in-memory domain functions for D-05's wave indicator. Neither
/// function touches drift or Riverpod — callers read the already-fetched
/// rows and pass plain data structures in.
abstract final class WaveLabel {
  /// Computes the wave containing [currentWeekIndex], anchored on one slot's
  /// per-week exercise assignment ([exerciseIdByWeek]).
  ///
  /// Returns `null` when [currentWeekIndex] is out of `0..totalWeeks-1`, or
  /// when [exerciseIdByWeek] has no resolved entry for [currentWeekIndex]
  /// (an unresolved/never-materialized week).
  static WaveLabelInfo? compute({
    required int totalWeeks,
    required int currentWeekIndex,
    required Map<int, int?> exerciseIdByWeek,
  }) {
    if (currentWeekIndex < 0 || currentWeekIndex >= totalWeeks) return null;
    final activeExerciseId = exerciseIdByWeek[currentWeekIndex];
    if (activeExerciseId == null) return null;

    // Wave-boundary walk around the viewed week, mirroring
    // programs_repository.dart's replaceProgramExerciseSlot walk — but this
    // map's keys are always in-range 0..totalWeeks-1, so out-of-range reads
    // are guarded explicitly rather than relying on a Map miss.
    var waveStart = currentWeekIndex;
    while (waveStart - 1 >= 0 &&
        exerciseIdByWeek[waveStart - 1] == activeExerciseId) {
      waveStart--;
    }
    var waveEnd = currentWeekIndex;
    while (waveEnd + 1 < totalWeeks &&
        exerciseIdByWeek[waveEnd + 1] == activeExerciseId) {
      waveEnd++;
    }

    // Total wave count: segment the entire 0..totalWeeks-1 range into
    // contiguous runs of equal exerciseIdByWeek values, then find which
    // 1-based run index contains currentWeekIndex.
    var waveCount = 0;
    var waveIndexForCurrent = 0;
    var w = 0;
    while (w < totalWeeks) {
      final runExerciseId = exerciseIdByWeek[w];
      var runEnd = w;
      while (runEnd + 1 < totalWeeks &&
          exerciseIdByWeek[runEnd + 1] == runExerciseId) {
        runEnd++;
      }
      waveCount++;
      if (currentWeekIndex >= w && currentWeekIndex <= runEnd) {
        waveIndexForCurrent = waveCount;
      }
      w = runEnd + 1;
    }

    return WaveLabelInfo(
      waveIndex: waveIndexForCurrent,
      waveCount: waveCount,
      waveStartWeek: waveStart,
      waveEndWeek: waveEnd,
    );
  }

  /// Selects the anchor slot for D-05's wave label: the first
  /// `SlotRole.main` slot encountered walking [daysInOrder] in order and,
  /// within each day, [allSlots] sorted by `orderIndex` ascending. Day order
  /// is the primary sort key; `orderIndex` only breaks ties within a day.
  ///
  /// Returns `null` when no slot in [allSlots] has `role == SlotRole.main.id`.
  static ProgramExerciseSlotData? selectAnchorSlot({
    required List<ProgramDayData> daysInOrder,
    required List<ProgramExerciseSlotData> allSlots,
  }) {
    for (final day in daysInOrder) {
      final label = day.slotLabel?.isNotEmpty == true
          ? day.slotLabel!
          : day.name;
      final matches = allSlots.where((s) => s.daySlotLabel == label).toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      for (final slot in matches) {
        if (slot.role == SlotRole.main.id) return slot;
      }
    }
    return null;
  }
}
