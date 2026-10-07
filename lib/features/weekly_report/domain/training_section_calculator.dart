/// Training card calculator for the weekly report (RPT-01, RPT-02).
///
/// A pure function of the resolved sets, an [IsoWeek] and an explicit
/// `windowEnd`. It reuses the same engines the analytics screens wrap
/// ([ResolvedSet.tonnageKg], [OneRepMax.estimate]) but deliberately not the
/// analytics providers, which read all history and call the wall clock. The
/// window therefore never depends on when the report is generated (D-05).
library;

import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/one_rep_max.dart';

abstract final class TrainingSectionCalculator {
  /// Movers listed in the section.
  static const int maxMovers = 3;

  /// Exercise names are capped to this many characters.
  static const int maxNameLength = 60;

  /// Returns null when no set was completed inside the window (D-06: "No data
  /// this week").
  ///
  /// [windowEnd] is `week.windowEnd(now)` computed by the caller; the
  /// calculator itself holds no clock.
  static TrainingSection? compute({
    required IsoWeek week,
    required DateTime windowEnd,
    required List<ResolvedSet> sets,
  }) {
    final weekStart = week.start;
    final weekEnd = week.endExclusive;
    final prev = week.previous;
    final prevStart = prev.start;
    final prevEnd = prev.endExclusive;

    final inWeek = <ResolvedSet>[];
    final inPrevWeek = <ResolvedSet>[];
    final prior = <ResolvedSet>[];
    for (final s in sets) {
      final at = s.set.completedAt;
      if (at == null) continue;
      if (at.isBefore(weekStart)) {
        prior.add(s);
        if (!at.isBefore(prevStart) && at.isBefore(prevEnd)) {
          inPrevWeek.add(s);
        }
      } else if (at.isBefore(weekEnd) && !at.isAfter(windowEnd)) {
        inWeek.add(s);
      }
    }
    if (inWeek.isEmpty) return null;

    final sessionIds = <int>{
      for (final s in inWeek)
        if (s.session.endedAt != null) s.session.id,
    };

    final tonnage = _tonnage(inWeek);
    final prevTonnage = inPrevWeek.isEmpty ? null : _tonnage(inPrevWeek);

    return TrainingSection(
      sessions: sessionIds.length,
      tonnageKg: tonnage,
      prevWeekTonnageKg: prevTonnage,
      e1rmMovers: _movers(inWeek: inWeek, prior: prior),
    );
  }

  static double _tonnage(List<ResolvedSet> sets) {
    var total = 0.0;
    for (final s in sets) {
      final t = s.tonnageKg;
      if (t.isFinite) total += t;
    }
    return total;
  }

  static List<E1rmMover> _movers({
    required List<ResolvedSet> inWeek,
    required List<ResolvedSet> prior,
  }) {
    final weekBest = _bestByExercise(inWeek);
    final priorBest = _bestByExercise(prior);

    final movers = <E1rmMover>[];
    for (final entry in weekBest.entries) {
      final before = priorBest[entry.key];
      if (before == null) continue;
      final e1rm = _round1(entry.value.e1rm);
      final delta = _round1(entry.value.e1rm - before.e1rm);
      if (delta <= 0) continue;
      movers.add(
        E1rmMover(
          exerciseName: _name(entry.value.name),
          e1rmKg: e1rm,
          deltaKg: delta,
        ),
      );
    }
    movers.sort((a, b) {
      final byDelta = b.deltaKg.compareTo(a.deltaKg);
      return byDelta != 0 ? byDelta : a.exerciseName.compareTo(b.exerciseName);
    });
    return movers.take(maxMovers).toList();
  }

  /// Best estimated 1RM per exercise id, behind the same gate as
  /// `AnalyticsRepository.topOneRms`: a 1RM is a weight for a rep, so only
  /// rep-based loaded metrics qualify (EXR-05).
  static Map<int, ({double e1rm, String name})> _bestByExercise(
    List<ResolvedSet> sets,
  ) {
    final best = <int, ({double e1rm, String name})>{};
    for (final s in sets) {
      final metric = LoggingMetric.fromId(s.exercise.loggingMetric);
      if (!metric.isRepBased || !metric.isLoaded) continue;
      final est = OneRepMax.estimate(
        weightKg: s.set.weightKg,
        reps: s.set.reps,
      );
      if (est == null || !est.isFinite) continue;
      final existing = best[s.exercise.id];
      if (existing == null || est > existing.e1rm) {
        best[s.exercise.id] = (e1rm: est, name: s.exercise.name);
      }
    }
    return best;
  }

  static double _round1(double v) => (v * 10).round() / 10;

  static String _name(String raw) {
    final t = raw.trim();
    return t.length <= maxNameLength ? t : t.substring(0, maxNameLength);
  }
}
