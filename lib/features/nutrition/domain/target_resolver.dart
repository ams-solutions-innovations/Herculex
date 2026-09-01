import 'package:herculex/features/nutrition/domain/macro_targets.dart';

/// A stored nutrition target plus its scope key (mirrors NutritionTargetData
/// without depending on the generated DB class, so the resolver stays pure /
/// unit-testable).
class TargetRule {
  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final int? fiberG;

  /// `global` | `training_day` | `rest_day` | `weekday:N` | `date:yyyy-mm-dd`
  final String appliesTo;

  const TargetRule({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.fiberG,
    required this.appliesTo,
  });

  MacroTargets get macros =>
      MacroTargets(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG);
}

/// An automated diet schedule snapshot (mirrors DietScheduleData).
class DietScheduleRule {
  final DateTime startDate;
  final double reducePct;
  final int intervalDays;
  final bool active;

  const DietScheduleRule({
    required this.startDate,
    required this.reducePct,
    required this.intervalDays,
    this.active = true,
  });
}

/// Resolves the effective daily nutrition target for a date (§19), applying:
/// 1. the most specific matching target rule (date > weekday > training/rest
///    > global), then
/// 2. any active automated diet schedule (compounding calorie reduction).
class TargetResolver {
  /// Specificity rank — higher wins.
  static int _rank(String appliesTo) {
    if (appliesTo.startsWith('date:')) return 4;
    if (appliesTo.startsWith('weekday:')) return 3;
    if (appliesTo == 'training_day' || appliesTo == 'rest_day') return 2;
    if (appliesTo == 'global') return 1;
    return 0;
  }

  static bool _matches(String appliesTo, DateTime date, bool isTrainingDay) {
    if (appliesTo == 'global') return true;
    if (appliesTo == 'training_day') return isTrainingDay;
    if (appliesTo == 'rest_day') return !isTrainingDay;
    if (appliesTo.startsWith('weekday:')) {
      final wd = int.tryParse(appliesTo.substring(8));
      return wd != null && date.weekday == wd;
    }
    if (appliesTo.startsWith('date:')) {
      final s = appliesTo.substring(5);
      return s ==
          '${date.year.toString().padLeft(4, '0')}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}';
    }
    return false;
  }

  /// Picks the highest-specificity matching rule. Returns null when nothing
  /// matches (caller falls back to the profile-derived target).
  static TargetRule? resolveRule({
    required List<TargetRule> rules,
    required DateTime date,
    required bool isTrainingDay,
  }) {
    TargetRule? best;
    var bestRank = -1;
    for (final r in rules) {
      if (!_matches(r.appliesTo, date, isTrainingDay)) continue;
      final rank = _rank(r.appliesTo);
      if (rank > bestRank) {
        best = r;
        bestRank = rank;
      }
    }
    return best;
  }

  /// Number of completed reduction steps elapsed under [schedule] by [date].
  static int reductionSteps(DietScheduleRule schedule, DateTime date) {
    if (!schedule.active || schedule.intervalDays <= 0) return 0;
    final start = DateTime(
      schedule.startDate.year,
      schedule.startDate.month,
      schedule.startDate.day,
    );
    final today = DateTime(date.year, date.month, date.day);
    final days = today.difference(start).inDays;
    if (days < schedule.intervalDays) return 0;
    return days ~/ schedule.intervalDays;
  }

  /// Applies the schedule's compounding calorie reduction to [base]. Each
  /// elapsed interval cuts calories by reducePct; macros scale with calories,
  /// but protein is preserved (standard cut behaviour) so the deficit comes
  /// out of carbs/fat.
  static MacroTargets applySchedule({
    required MacroTargets base,
    required DietScheduleRule schedule,
    required DateTime date,
  }) {
    final steps = reductionSteps(schedule, date);
    if (steps == 0) return base;
    final factor = _pow(1 - schedule.reducePct / 100, steps);
    final newKcal = (base.kcal * factor).round();
    final protein = base.proteinG; // preserved on a cut
    final remainingKcal = (newKcal - protein * 4).clamp(0, newKcal).toDouble();
    // Hold the original carb:fat energy split.
    final baseCarbKcal = base.carbsG * 4.0;
    final baseFatKcal = base.fatG * 9.0;
    final splitTotal = baseCarbKcal + baseFatKcal;
    final carbShare = splitTotal == 0 ? 0.5 : baseCarbKcal / splitTotal;
    return MacroTargets(
      kcal: newKcal,
      proteinG: protein,
      carbsG: (remainingKcal * carbShare / 4).round(),
      fatG: (remainingKcal * (1 - carbShare) / 9).round(),
    );
  }

  /// Full resolution: pick the rule (or [fallback]), then apply the schedule.
  static MacroTargets? resolve({
    required List<TargetRule> rules,
    required DateTime date,
    required bool isTrainingDay,
    DietScheduleRule? schedule,
    MacroTargets? fallback,
  }) {
    final rule = resolveRule(
      rules: rules,
      date: date,
      isTrainingDay: isTrainingDay,
    );
    final base = rule?.macros ?? fallback;
    if (base == null) return null;
    if (schedule == null) return base;
    return applySchedule(base: base, schedule: schedule, date: date);
  }

  static double _pow(double base, int exp) {
    var r = 1.0;
    for (var i = 0; i < exp; i++) {
      r *= base;
    }
    return r;
  }
}
