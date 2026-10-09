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

  if (weeklyVolume != null) {
    series[HerculSignals.weeklySets] = {
      for (final v in weeklyVolume.byMuscle)
        v.muscle.toLowerCase().replaceAll(' ', '-'): v.sets,
    };
  }

  if (trainingSnapshot != null && trainingSnapshot.sets.isNotEmpty) {
    final lastWorkout = trainingSnapshot.sets.last.session.startedAt;
    scalars[HerculSignals.daysSinceLastWorkout] = now
        .difference(lastWorkout)
        .inDays
        .toDouble();

    // Calculate e1rmDeltaKg14d and e1rmRatioBelted
    final e1rmDelta14 = <String, double>{};
    final e1rmRatioBelted = <String, double>{};

    final setsByExercise = <int, List<ResolvedSet>>{};
    for (final rs in trainingSnapshot.sets) {
      setsByExercise.putIfAbsent(rs.exercise.id, () => []).add(rs);
    }

    for (final entry in setsByExercise.entries) {
      final slug = entry.value.first.exercise.slug;
      if (slug == null) continue;

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
      if (maxOld > 0) {
        e1rmDelta14[slug] = maxRecent - maxOld;
      }
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
      final twoWeeksAgoIso = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 14)));
      final old = weights
          .lastWhere(
            (w) => w.dateIso.compareTo(twoWeeksAgoIso) <= 0,
            orElse: () => weights.first,
          )
          .value;
      if (old > 0) {
        series[HerculSignals.weightDeltaKg] = {'14': latest - old};
      }
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
