import 'package:herculex/features/nutrition/domain/diet_phase.dart';

/// One phase as the schedule sees it: plain values, no drift types.
class SchedulePhaseInput {
  const SchedulePhaseInput({
    required this.phase,
    required this.plannedWeeks,
    this.targetWeightKg,
    this.targetBfPercent,
    this.status = 'upcoming',
    this.startedAt,
    this.completedAt,
  });

  final DietPhase phase;
  final int plannedWeeks;
  final double? targetWeightKg;
  final double? targetBfPercent;

  /// `done`, `current` or `upcoming`.
  final String status;
  final DateTime? startedAt;
  final DateTime? completedAt;
}

/// A phase placed on the calendar with the weight it starts and ends at.
class ScheduledPhase {
  const ScheduledPhase({
    required this.index,
    required this.phase,
    required this.plannedWeeks,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.startKg,
    required this.endKg,
    required this.targetBfPercent,
  });

  final int index;
  final DietPhase phase;
  final int plannedWeeks;
  final String status;

  /// Calendar days (local midnight). [endDate] is the day after the last day
  /// of the phase, so `endDate - startDate` is exactly `plannedWeeks * 7` days
  /// for a phase that has not been closed early.
  final DateTime startDate;
  final DateTime endDate;
  final double? startKg;
  final double? endKg;
  final double? targetBfPercent;

  /// Signed kg per week implied by the start and end weight; null when either
  /// is unknown.
  double? get weeklyKg {
    final s = startKg;
    final e = endKg;
    if (s == null || e == null || plannedWeeks <= 0) return null;
    return (e - s) / plannedWeeks;
  }
}

class RoadmapSchedule {
  const RoadmapSchedule({required this.phases});

  final List<ScheduledPhase> phases;

  bool get isEmpty => phases.isEmpty;

  DateTime? get startDate => phases.isEmpty ? null : phases.first.startDate;
  DateTime? get endDate => phases.isEmpty ? null : phases.last.endDate;

  int get totalWeeks => phases.fold(0, (sum, p) => sum + p.plannedWeeks);

  /// Whole months the roadmap spans, rounded to the nearest month.
  int get totalMonths => (totalWeeks / 4.345).round();

  double? get startWeightKg => phases.isEmpty ? null : phases.first.startKg;

  /// Where the last phase ends: the weight the whole roadmap is heading to.
  double? get dreamWeightKg {
    for (final p in phases.reversed) {
      final kg = p.endKg;
      if (kg != null) return kg;
    }
    return null;
  }

  /// The running phase, else the first one that has not finished.
  ScheduledPhase? get current {
    for (final p in phases) {
      if (p.status == 'current') return p;
    }
    for (final p in phases) {
      if (p.status != 'done') return p;
    }
    return null;
  }

  /// Planned weight on [date], linear inside each phase. Before the roadmap it
  /// is the starting weight, after it the dream weight.
  double? weightAt(DateTime date) {
    if (phases.isEmpty) return null;
    final day = DateTime(date.year, date.month, date.day);
    final first = phases.first;
    if (!day.isAfter(first.startDate)) return first.startKg;
    for (final p in phases) {
      if (day.isBefore(p.endDate)) {
        final s = p.startKg;
        final e = p.endKg;
        if (s == null || e == null) return e ?? s;
        final span = p.endDate.difference(p.startDate).inDays;
        if (span <= 0) return e;
        final t = day.difference(p.startDate).inDays / span;
        return s + (e - s) * t.clamp(0.0, 1.0);
      }
    }
    return dreamWeightKg;
  }
}

abstract final class RoadmapScheduleCalculator {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _plus(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  /// Places [phases] on the calendar.
  ///
  /// A phase that has started uses its recorded start. One that has not
  /// starts when the previous one is due to end, but never in the past: when
  /// the current phase is overdue, what follows is shown starting [now].
  /// [anchor] starts the first phase when nothing has started yet (a roadmap
  /// proposal). Weights chain from [startWeightKg]; a phase with no target
  /// ends where it started.
  static RoadmapSchedule build({
    required List<SchedulePhaseInput> phases,
    required DateTime anchor,
    required DateTime now,
    double? startWeightKg,
  }) {
    final out = <ScheduledPhase>[];
    var cursor = _day(anchor);
    var kg = startWeightKg;
    final today = _day(now);

    for (var i = 0; i < phases.length; i++) {
      final p = phases[i];
      final started = p.startedAt;
      DateTime start;
      if (started != null && p.status != 'upcoming') {
        start = _day(started);
      } else {
        start = cursor;
        if (i > 0 && start.isBefore(today)) start = today;
      }
      var end = _plus(start, p.plannedWeeks * 7);
      final done = p.completedAt;
      if (p.status == 'done' && done != null) {
        final closed = _day(done);
        end = closed.isAfter(start) ? closed : end;
      }
      final endKg = p.targetWeightKg ?? kg;
      out.add(
        ScheduledPhase(
          index: i,
          phase: p.phase,
          plannedWeeks: p.plannedWeeks,
          status: p.status,
          startDate: start,
          endDate: end,
          startKg: kg,
          endKg: endKg,
          targetBfPercent: p.targetBfPercent,
        ),
      );
      cursor = end;
      kg = endKg;
    }
    return RoadmapSchedule(phases: List.unmodifiable(out));
  }
}
