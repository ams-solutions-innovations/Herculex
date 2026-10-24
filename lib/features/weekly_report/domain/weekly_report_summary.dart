import 'package:herculex/features/weekly_report/domain/weekly_report_payload.dart';

/// How the week went, in one word.
enum WeekVerdict {
  great('Great week'),
  good('Good week'),
  mixed('Mixed week'),
  quiet('Quiet week');

  const WeekVerdict(this.label);
  final String label;
}

/// The top of a weekly report: a verdict and the handful of numbers behind
/// it. Deterministic and computed from the frozen payload plus the planned
/// session count; never interpreted by AI.
class WeeklyReportSummary {
  const WeeklyReportSummary({
    required this.verdict,
    required this.sessions,
    required this.plannedSessions,
    required this.avgKcal,
    required this.targetKcal,
    required this.adherenceDays,
    required this.daysLogged,
    required this.avgSleepHours,
    required this.bodyweightDeltaKg,
  });

  final WeekVerdict verdict;
  final int sessions;
  final int? plannedSessions;
  final int? avgKcal;
  final int? targetKcal;
  final int? adherenceDays;
  final int daysLogged;
  final double? avgSleepHours;
  final double? bodyweightDeltaKg;

  /// Sleep at or above this counts as a good week for recovery.
  static const goodSleepHours = 7.0;

  static WeeklyReportSummary from(
    WeeklyReportPayload payload, {
    int? plannedSessions,
  }) {
    final sessions = payload.training?.sessions ?? 0;
    final nutrition = payload.nutrition;
    final daysLogged = nutrition?.daysLogged ?? 0;
    final sleep = payload.recovery?.avgSleepHours;

    // One point per pillar that went well; a pillar without data scores
    // nothing rather than counting against the week.
    var points = 0;
    var pillars = 0;
    if (plannedSessions != null && plannedSessions > 0) {
      pillars++;
      if (sessions >= plannedSessions) points++;
    } else if (sessions > 0) {
      pillars++;
      if (sessions >= 3) points++;
    }
    final adherence = nutrition?.adherenceDays;
    if (daysLogged > 0 && adherence != null) {
      pillars++;
      if (adherence >= 5 || adherence >= daysLogged - 1) points++;
    }
    if (sleep != null) {
      pillars++;
      if (sleep >= goodSleepHours) points++;
    }

    final verdict = pillars == 0
        ? WeekVerdict.quiet
        : points == pillars
        ? WeekVerdict.great
        : points * 2 >= pillars
        ? WeekVerdict.good
        : WeekVerdict.mixed;

    return WeeklyReportSummary(
      verdict: verdict,
      sessions: sessions,
      plannedSessions: plannedSessions,
      avgKcal: daysLogged > 0 ? nutrition?.avgKcal : null,
      targetKcal: nutrition?.targetKcal,
      adherenceDays: adherence,
      daysLogged: daysLogged,
      avgSleepHours: sleep,
      bodyweightDeltaKg: payload.physique?.bodyweightDeltaKg,
    );
  }

  /// "4/4 workouts · on target 5 of 7 days · 7.2 h sleep".
  String get detail {
    final parts = <String>[
      plannedSessions != null && plannedSessions! > 0
          ? '$sessions/$plannedSessions workouts'
          : '$sessions ${sessions == 1 ? 'workout' : 'workouts'}',
      if (adherenceDays != null && daysLogged > 0)
        'on target $adherenceDays of $daysLogged days',
      if (avgSleepHours != null) '${avgSleepHours!.toStringAsFixed(1)} h sleep',
    ];
    return parts.join(' · ');
  }
}
