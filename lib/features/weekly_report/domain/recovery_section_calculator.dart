/// Recovery, sleep and activity card calculator for the weekly report
/// (RPT-01, RPT-02, RPT-05).
///
/// The analytics providers behind the recovery and CNS screens read all history
/// and call `DateTime.now()`, so a report for a past week would change with the
/// day it is generated (Pitfall 1). This calculator therefore calls
/// [CnsTrends.compute] and [MuscleRecoveryV3.compute] directly with
/// `asOf: windowEnd` over a snapshot restricted to sets completed on or before
/// `windowEnd`, and builds correlations over a trailing window anchored at
/// `windowEnd` too. It holds no clock.
///
/// Relationships between sleep, heart rate and training are stated only through
/// [CorrelationStatement], never through free text (D-12).
///
/// Pure Dart: no Flutter or Riverpod.
library;

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/biometric_correlations.dart';
import 'package:herculex/features/analytics/domain/cns_trends.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/weekly_report/domain/correlation_statement.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';

abstract final class RecoverySectionCalculator {
  /// Recovery warnings listed in the section.
  static const int maxWarnings = 5;

  /// Length of the trailing correlation window, in weeks.
  static const int correlationWeeks = 8;

  /// Returns null when there is neither a health sample nor a completed set
  /// inside the week (D-06: "No data this week").
  ///
  /// [windowEnd] is `week.windowEnd(now)` computed by the caller. [weekHealth]
  /// and [trailingHealth] may be generous supersets: both are filtered here by
  /// `dateIso`, so a past report never depends on what the caller loaded.
  /// [snapshot] may hold all history; sets after [windowEnd] are dropped.
  static RecoverySection? compute({
    required IsoWeek week,
    required DateTime windowEnd,
    required List<HealthSampleData> weekHealth,
    required List<HealthSampleData> trailingHealth,
    required TrainingSnapshot snapshot,
  }) {
    final endIso = _iso(windowEnd);

    final inWeekHealth = [
      for (final h in weekHealth)
        if (h.value.isFinite &&
            h.dateIso.compareTo(week.startIso) >= 0 &&
            h.dateIso.compareTo(week.endIso) <= 0 &&
            h.dateIso.compareTo(endIso) <= 0)
          h,
    ];

    // Never let the engines see a set that had not happened at windowEnd.
    final sets = [
      for (final s in snapshot.sets)
        if (_completedByWindowEnd(s, windowEnd)) s,
    ];
    final filtered = TrainingSnapshot(
      sets: sets,
      exerciseMuscles: snapshot.exerciseMuscles,
    );

    final weekStart = week.start;
    final weekEnd = week.endExclusive;
    final hasWeekSets = sets.any((s) {
      final at = s.set.completedAt!;
      return !at.isBefore(weekStart) && at.isBefore(weekEnd);
    });
    if (inWeekHealth.isEmpty && !hasWeekSets) return null;

    int? readinessPct;
    var deload = false;
    if (sets.isNotEmpty) {
      final cns = CnsTrends.compute(snapshot: filtered, asOf: windowEnd);
      final readiness = cns.readiness;
      if (readiness.isFinite) readinessPct = (readiness * 100).round();
      deload = cns.deloadSuggested;
    }

    final warnings = [
      for (final w in MuscleRecoveryV3.warnings(
        MuscleRecoveryV3.compute(
          snapshot: filtered,
          // No live Health Connect reads at generation time.
          externalWorkouts: const [],
          asOf: windowEnd,
          daysOfHealthHistory: 0,
        ),
      ))
        w.message,
    ].take(maxWarnings).toList();

    return RecoverySection(
      avgSleepHours: _mean1(inWeekHealth, 'sleep_hours'),
      avgSteps: _meanInt(inWeekHealth, 'steps'),
      avgRestingHr: _mean1(inWeekHealth, 'resting_hr'),
      cnsReadinessPct: readinessPct,
      cnsDeloadSuggested: deload,
      recoveryWarnings: warnings,
      correlations: _correlations(
        windowEnd: windowEnd,
        trailingHealth: trailingHealth,
        sets: sets,
      ),
    );
  }

  static List<CorrelationLine> _correlations({
    required DateTime windowEnd,
    required List<HealthSampleData> trailingHealth,
    required List<ResolvedSet> sets,
  }) {
    // DateTime(y, m, d - n) keeps local midnight across DST changes.
    final from = DateTime(
      windowEnd.year,
      windowEnd.month,
      windowEnd.day - 7 * correlationWeeks,
    );
    final fromIso = _iso(from);
    final toIso = _iso(windowEnd);

    final health = [
      for (final h in trailingHealth)
        if (h.value.isFinite &&
            h.dateIso.compareTo(fromIso) >= 0 &&
            h.dateIso.compareTo(toIso) <= 0)
          h,
    ];
    final window = [
      for (final s in sets)
        if (!s.session.startedAt.isBefore(from) &&
            !s.session.startedAt.isAfter(windowEnd))
          s,
    ];

    final sleep = BiometricCorrelations.sleepVsRpe(
      healthSamples: health,
      resolvedSets: window,
    );
    final hr = BiometricCorrelations.restingHrVsTonnage(
      healthSamples: health,
      resolvedSets: window,
    );

    return [
      for (final (kind, result) in [
        (CorrelationKind.sleepRpe, sleep),
        (CorrelationKind.hrTonnage, hr),
      ])
        _line(CorrelationStatement.from(kind: kind, result: result)),
    ];
  }

  static CorrelationLine _line(CorrelationStatement s) => CorrelationLine(
    kind: s.kind.wireName,
    statement: s.text,
    sampleSize: s.sampleSize,
  );

  static bool _completedByWindowEnd(ResolvedSet s, DateTime windowEnd) {
    final at = s.set.completedAt;
    return at != null && !at.isAfter(windowEnd);
  }

  static List<double> _values(List<HealthSampleData> rows, String kind) => [
    for (final r in rows)
      if (r.kind == kind) r.value,
  ];

  /// Mean rounded to one decimal, or null with no rows of [kind].
  static double? _mean1(List<HealthSampleData> rows, String kind) {
    final v = _values(rows, kind);
    if (v.isEmpty) return null;
    final mean = v.reduce((a, b) => a + b) / v.length;
    return (mean * 10).round() / 10;
  }

  static int? _meanInt(List<HealthSampleData> rows, String kind) {
    final v = _values(rows, kind);
    if (v.isEmpty) return null;
    return (v.reduce((a, b) => a + b) / v.length).round();
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
