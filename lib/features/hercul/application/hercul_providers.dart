import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/analytics/domain/biometric_correlations.dart';
import 'package:herculex/features/analytics/domain/cns_trends.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/analytics/domain/variant_performance.dart';
import 'package:herculex/features/analytics/domain/weekly_muscle_volume.dart';
import 'package:herculex/features/hercul/data/hercul_repository.dart';
import 'package:herculex/features/hercul/domain/hercul_context.dart';
import 'package:herculex/features/hercul/domain/hercul_engine.dart';
import 'package:herculex/features/hercul/domain/hercul_rule.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/domain/daily_totals.dart';
import 'package:herculex/features/physique/application/effective_goal_provider.dart';
import 'package:herculex/features/profile/domain/anthropometry.dart';
import 'package:herculex/features/workouts/domain/one_rep_max.dart';
import 'package:intl/intl.dart';

final herculRulesProvider = FutureProvider<List<HerculRule>>((ref) {
  return ref.watch(herculRepositoryProvider).fetchRules();
});

final herculMessageLogProvider = FutureProvider<Map<String, DateTime>>((ref) {
  return ref.watch(herculRepositoryProvider).fetchMessageLog();
});

final herculContextProvider = FutureProvider<HerculContext>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  final now = ref.watch(clockProvider).now();

  CnsTrendsResult? cns;
  try {
    cns = await ref.watch(cnsTrendsProvider.future);
  } catch (_) {}

  List<MuscleGroupRecovery>? recovery;
  try {
    recovery = await ref.watch(recoveryV3Provider.future);
  } catch (_) {}

  WeeklyMuscleVolume? weeklyVolume;
  try {
    weeklyVolume = await ref.watch(weeklyMuscleVolumeProvider.future);
  } catch (_) {}

  TrainingSnapshot? trainingSnapshot;
  try {
    trainingSnapshot = await ref.watch(trainingSnapshotProvider.future);
  } catch (_) {}

  final scalars = <String, double>{};
  final series = <String, Map<String, double>>{};
  final labels = <String, String>{};

  if (profile != null) {
    if (profile.heightCm != null)
      scalars[HerculSignals.heightCm] = profile.heightCm!;
    if (profile.weightKg != null)
      scalars[HerculSignals.weightKg] = profile.weightKg!;
    if (profile.ageYears != null)
      scalars[HerculSignals.ageYears] = profile.ageYears!.toDouble();
    labels[HerculSignals.goal] =
        (ref.watch(effectiveFitnessGoalProvider) ?? profile.goal).name;
    if (profile.sex != null) labels[HerculSignals.sex] = profile.sex!.name;

    final anthropometry = AnthropometryRatios(profile);
    if (anthropometry.legProportion != null) {
      labels[HerculSignals.ergoLegProportion] =
          anthropometry.legProportion!.name;
    }
    if (anthropometry.armProportion != null) {
      labels[HerculSignals.ergoArmProportion] =
          anthropometry.armProportion!.name;
    }
    if (anthropometry.torsoProportion != null) {
      labels[HerculSignals.ergoTorsoProportion] =
          anthropometry.torsoProportion!.name;
    }
  }

  if (cns != null) {
    scalars[HerculSignals.cnsLoad] = cns.currentLoad;
    scalars[HerculSignals.cnsReadiness] = 1.0 - cns.currentLoad;
    scalars[HerculSignals.cnsAcwr] = cns.chronicWeeklyLoad > 0
        ? cns.acuteWeeklyLoad / cns.chronicWeeklyLoad
        : 0.0;
    scalars[HerculSignals.cnsDeloadSuggested] = cns.deloadSuggested ? 1.0 : 0.0;

    if (cns.currentLoad > 0.8) {
      labels[HerculSignals.cnsStatus] = 'HIGH';
    } else if (cns.currentLoad > 0.4) {
      labels[HerculSignals.cnsStatus] = 'MODERATE';
    } else {
      labels[HerculSignals.cnsStatus] = 'FRESH';
    }
  }

  if (recovery != null) {
    series[HerculSignals.recoveryScore] = {
      for (final g in recovery)
        g.muscle.toLowerCase().replaceAll(' ', '-'): g.recoveryScore.toDouble(),
    };
  }

  scalars[HerculSignals.weekday] = now.weekday.toDouble();

  if (weeklyVolume != null) {
    // Keyed by the display name ("Rear Delts"), which is what the rules and
    // their copy ask for. A lowercased key made every volume rule a no-op.
    final byMuscle = {for (final v in weeklyVolume.byMuscle) v.muscle: v.sets};

    // Once the user has trained this week, an untouched muscle is a real zero
    // ("no hamstring sets"), not a missing signal. Before any training the
    // series stays absent so a fresh week does not announce every gap.
    if (weeklyVolume.totalSets > 0) {
      series[HerculSignals.weeklySets] = {
        for (final g in MuscleRecoveryV3.groups) g: byMuscle[g] ?? 0,
      };
    }

    double sumOf(Iterable<String> muscles) =>
        muscles.fold(0.0, (sum, m) => sum + (byMuscle[m] ?? 0));
    final push = sumOf(const ['Chest', 'Front Delts', 'Side Delts', 'Triceps']);
    final pull = sumOf(const ['Back', 'Lats', 'Traps', 'Rear Delts', 'Biceps']);
    // Below ten sets a ratio is noise: one chest day early in the week reads
    // as "100% push".
    if (push + pull >= 10) {
      scalars[HerculSignals.pushPct] = push / (push + pull) * 100;
      scalars[HerculSignals.pullPct] = pull / (push + pull) * 100;
    }
  }

  if (trainingSnapshot != null && trainingSnapshot.sets.isNotEmpty) {
    final lastWorkout = trainingSnapshot.sets.last.session.startedAt;
    scalars[HerculSignals.daysSinceLastWorkout] = now
        .difference(lastWorkout)
        .inDays
        .toDouble();

    // Session cadence, counted in distinct sessions rather than sets.
    final weekStart = WeeklyMuscleVolume.weekStartOf(now);
    final fourWeeksAgo = now.subtract(const Duration(days: 28));
    final sessionStarts = <int, DateTime>{
      for (final rs in trainingSnapshot.sets)
        rs.session.id: rs.session.startedAt,
    };
    scalars[HerculSignals.sessionsThisWeek] = sessionStarts.values
        .where((t) => !t.isBefore(weekStart))
        .length
        .toDouble();
    scalars[HerculSignals.sessionsPerWeek4w] =
        sessionStarts.values.where((t) => t.isAfter(fourWeeksAgo)).length / 4;

    // Calculate e1rmDeltaKg14d and e1rmRatioBelted
    final e1rmDelta14 = <String, double>{};
    final e1rmRatioBelted = <String, double>{};
    final lastPerformed = <String, double>{};
    final performed30d = <String, double>{};

    final setsByExercise = <int, List<ResolvedSet>>{};
    for (final rs in trainingSnapshot.sets) {
      setsByExercise.putIfAbsent(rs.exercise.id, () => []).add(rs);
    }

    for (final entry in setsByExercise.entries) {
      final slug = entry.value.first.exercise.slug;
      if (slug == null) continue;

      // Recency and frequency per lift.
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final sessionDates = <int, DateTime>{
        for (final rs in entry.value) rs.session.id: rs.session.startedAt,
      };
      final latest = sessionDates.values.reduce((a, b) => a.isAfter(b) ? a : b);
      lastPerformed[slug] = now.difference(latest).inDays.toDouble();
      performed30d[slug] = sessionDates.values
          .where((t) => t.isAfter(thirtyDaysAgo))
          .length
          .toDouble();

      // Belt ratio
      final byCombo = VariantPerformance.byAccessoryCombo(
        trainingSnapshot,
        entry.key,
      );
      double rawMax = 0;
      double beltedMax = 0;
      for (final record in byCombo) {
        if (record.label.toLowerCase().contains('belt') &&
            record.bestE1RmKg != null) {
          if (record.bestE1RmKg! > beltedMax) beltedMax = record.bestE1RmKg!;
        } else if (record.label.toLowerCase() == 'raw' &&
            record.bestE1RmKg != null) {
          if (record.bestE1RmKg! > rawMax) rawMax = record.bestE1RmKg!;
        }
      }
      if (rawMax > 0 && beltedMax > 0) {
        e1rmRatioBelted[slug] = beltedMax / rawMax;
      }

      // 14d Delta
      final twoWeeksAgo = now.subtract(const Duration(days: 14));
      double maxRecent = 0;
      double maxOld = 0;
      for (final rs in entry.value) {
        final est =
            OneRepMax.estimate(weightKg: rs.effectiveKg, reps: rs.set.reps) ??
            0.0;
        if (rs.session.startedAt.isAfter(twoWeeksAgo)) {
          if (est > maxRecent) maxRecent = est;
        } else {
          if (est > maxOld) maxOld = est;
        }
      }
      // A lift not touched for two weeks has no recent best, which would read
      // as a 100% strength loss rather than as "not trained".
      if (maxOld > 0 && maxRecent > 0) {
        e1rmDelta14[slug] = maxRecent - maxOld;
      }
    }

    if (lastPerformed.isNotEmpty) {
      series[HerculSignals.lastPerformedDays] = lastPerformed;
      series[HerculSignals.performedLast30d] = performed30d;
    }
    if (e1rmRatioBelted.isNotEmpty) {
      series[HerculSignals.e1rmRatioBelted] = e1rmRatioBelted;
    }
    if (e1rmDelta14.isNotEmpty) {
      series[HerculSignals.e1rmDeltaKg14d] = e1rmDelta14;
    }
  }

  try {
    // Biometrics
    BiometricCorrelationResult? sleepVsRpe;
    try {
      sleepVsRpe = await ref.watch(sleepVsRpeProvider.future);
    } catch (_) {}
    if (sleepVsRpe != null) {
      scalars[HerculSignals.sleepVsRpeR2] = sleepVsRpe.r2;
    }

    // Bodyweight 14d delta
    final measurementsRepo = ref.watch(measurementsRepositoryProvider);
    final weights = await measurementsRepo.watchMetric('bodyweight').first;
    if (weights.isNotEmpty) {
      final latest = weights.last.value;
      final deltas = <String, double>{};
      for (final days in const [14, 21]) {
        final cutoffIso = DateFormat(
          'yyyy-MM-dd',
        ).format(now.subtract(Duration(days: days)));
        // Only compare against a weigh-in at least that old; falling back to
        // the first entry would call a one-week-old history a three-week trend.
        final older = weights.where((w) => w.dateIso.compareTo(cutoffIso) <= 0);
        if (older.isEmpty) continue;
        final old = older.last.value;
        if (old > 0) deltas['$days'] = latest - old;
      }
      if (deltas.isNotEmpty) series[HerculSignals.weightDeltaKg] = deltas;
    }

    // Nutrition 14d history
    final nutritionRepo = ref.read(nutritionRepositoryProvider);
    final baseline = ref.read(baselineTargetsProvider);
    if (baseline != null) {
      final endDate = DateTime(now.year, now.month, now.day);
      final startDate = endDate.subtract(const Duration(days: 14));
      final history = await nutritionRepo
          .watchDailyTotalsForRange(startDate, endDate)
          .first;
      if (history.isNotEmpty) {
        double sumPct = 0;
        int count = 0;
        for (final totals in history.values) {
          sumPct += totals.kcal / baseline.kcal;
          count++;
        }
        scalars[HerculSignals.kcalPct14d] = sumPct / count;
      }

      // Last seven completed days. Today is left out: it is still being eaten,
      // and a half-logged Tuesday would read as an under-eating week.
      final fmt = DateFormat('yyyy-MM-dd');
      final todayIso = fmt.format(endDate);
      final weekAgoIso = fmt.format(
        DateTime(endDate.year, endDate.month, endDate.day - 7),
      );
      final week = [
        for (final e in history.entries)
          if (e.key.compareTo(weekAgoIso) >= 0 &&
              e.key.compareTo(todayIso) < 0 &&
              e.value.kcal > 0)
            e.value,
      ];
      scalars[HerculSignals.daysLogged7d] = week.length.toDouble();
      if (week.isNotEmpty) {
        double avg(double Function(DailyTotals t) pick) =>
            week.fold(0.0, (sum, t) => sum + pick(t)) / week.length;
        final avgKcal = avg((t) => t.kcal);
        final avgProtein = avg((t) => t.proteinG);
        final avgFiber = avg((t) => t.fiberG);

        if (baseline.kcal > 0) {
          scalars[HerculSignals.kcalTarget] = baseline.kcal.toDouble();
          scalars[HerculSignals.kcalAvg7d] = avgKcal;
          scalars[HerculSignals.kcalPct7d] = avgKcal / baseline.kcal;
          scalars[HerculSignals.kcalShortfall7d] = (baseline.kcal - avgKcal)
              .clamp(0, double.infinity)
              .toDouble();
          scalars[HerculSignals.kcalOver7d] = (avgKcal - baseline.kcal)
              .clamp(0, double.infinity)
              .toDouble();
        }
        if (baseline.proteinG > 0) {
          scalars[HerculSignals.proteinTargetG] = baseline.proteinG.toDouble();
          scalars[HerculSignals.proteinAvg7dG] = avgProtein;
          scalars[HerculSignals.proteinPct7d] = avgProtein / baseline.proteinG;
          scalars[HerculSignals.proteinGap7dG] =
              (baseline.proteinG - avgProtein)
                  .clamp(0, double.infinity)
                  .toDouble();
        }
        // Foods logged without fibre data would read as a zero-fibre diet.
        if (avgFiber > 0) scalars[HerculSignals.fiberAvg7dG] = avgFiber;
      }
    }
  } catch (_) {
    // Tolerate failures in secondary metrics gracefully so the rest of Hercul still works
  }

  return HerculContext(
    scalars: scalars,
    series: series,
    labels: labels,
    now: now,
  );
});

final herculMessagesProvider = FutureProvider<List<HerculMessage>>((ref) async {
  final rules = await ref.watch(herculRulesProvider.future);
  final log = await ref.watch(herculMessageLogProvider.future);
  final context = await ref.watch(herculContextProvider.future);
  final profile = await ref.watch(profileProvider.future);

  final tone = HerculTone.fromId(profile?.herculTone);

  return HerculEngine.evaluate(
    context: context,
    rules: rules,
    tone: tone,
    lastFiredAt: log,
  );
});

final herculLogFiredProvider = Provider((ref) {
  return (String ruleId) {
    ref
        .read(herculRepositoryProvider)
        .logFired(ruleId, ref.read(clockProvider).now());
    ref.invalidate(herculMessageLogProvider);
  };
});
