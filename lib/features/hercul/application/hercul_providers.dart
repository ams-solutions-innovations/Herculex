import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/analytics/domain/biometric_correlations.dart';
import 'package:herculex/features/analytics/domain/cns_trends.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/analytics/domain/variant_performance.dart';
import 'package:herculex/features/analytics/domain/weekly_muscle_volume.dart';
import 'package:herculex/features/fasting/application/fasting_providers.dart';
import 'package:herculex/features/hercul/data/hercul_repository.dart';
import 'package:herculex/features/hercul/domain/hercul_assessment.dart';
import 'package:herculex/features/hercul/domain/hercul_context.dart';
import 'package:herculex/features/hercul/domain/hercul_engine.dart';
import 'package:herculex/features/hercul/domain/hercul_rule.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/physique/application/effective_goal_provider.dart';
import 'package:herculex/features/profile/domain/anthropometry.dart';
import 'package:herculex/features/sleep/application/sleep_providers.dart';
import 'package:herculex/features/supplements/data/supplement_repository.dart';
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
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

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
    if (profile.heightCm != null) {
      scalars[HerculSignals.heightCm] = profile.heightCm!;
    }
    if (profile.weightKg != null) {
      scalars[HerculSignals.weightKg] = profile.weightKg!;
    }
    if (profile.ageYears != null) {
      scalars[HerculSignals.ageYears] = profile.ageYears!.toDouble();
    }
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
    scalars[HerculSignals.cnsReadiness] = (1.0 - cns.currentLoad).clamp(
      0.0,
      1.0,
    );
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

  double? avgMuscleRecovery;
  if (recovery != null && recovery.isNotEmpty) {
    final map = <String, double>{};
    double sum = 0;
    for (final g in recovery) {
      final score = g.recoveryScore.toDouble();
      map[g.muscle] = score;
      map[g.muscle.toLowerCase().replaceAll(' ', '-')] = score;
      sum += score;
    }
    series[HerculSignals.recoveryScore] = map;
    avgMuscleRecovery = sum / recovery.length;
  }

  if (weeklyVolume != null && weeklyVolume.totalSets > 0) {
    final setMap = <String, double>{
      for (final g in MuscleRecoveryV3.groups) g: 0.0,
      for (final g in MuscleRecoveryV3.groups)
        g.toLowerCase().replaceAll(' ', '-'): 0.0,
    };
    double pushSets = 0;
    double pullSets = 0;
    for (final v in weeklyVolume.byMuscle) {
      setMap[v.muscle] = v.sets;
      setMap[v.muscle.toLowerCase().replaceAll(' ', '-')] = v.sets;
      final m = v.muscle.toLowerCase();
      if (m.contains('chest') ||
          m.contains('shoulder') ||
          m.contains('front delt') ||
          m.contains('tricep')) {
        pushSets += v.sets;
      } else if (m.contains('back') ||
          m.contains('lat') ||
          m.contains('rear delt') ||
          m.contains('bicep') ||
          m.contains('trap')) {
        pullSets += v.sets;
      }
    }
    series[HerculSignals.weeklySets] = setMap;
    scalars[HerculSignals.weeklyTonnageKg] = weeklyVolume.totalTonnageKg;
    final pushPullTotal = pushSets + pullSets;
    if (pushPullTotal > 0) {
      scalars[HerculSignals.pushPct] = (pushSets / pushPullTotal) * 100.0;
      scalars[HerculSignals.pullPct] = (pullSets / pushPullTotal) * 100.0;
    }
  }

  if (trainingSnapshot != null && trainingSnapshot.sets.isNotEmpty) {
    final lastWorkout = trainingSnapshot.sets.last.session.startedAt;
    scalars[HerculSignals.daysSinceLastWorkout] = now
        .difference(lastWorkout)
        .inDays
        .toDouble();

    // Sessions this week and 4-week rolling average
    final weekStart = WeeklyMuscleVolume.weekStartOf(now);
    final fourWeeksAgo = now.subtract(const Duration(days: 28));
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    final sessionIdsThisWeek = <int>{};
    final sessionIds4w = <int>{};
    double tonnage7d = 0;
    double tonnage28d = 0;

    for (final rs in trainingSnapshot.sets) {
      final started = rs.session.startedAt;
      if (!started.isBefore(weekStart)) {
        sessionIdsThisWeek.add(rs.session.id);
      }
      if (!started.isBefore(fourWeeksAgo)) {
        sessionIds4w.add(rs.session.id);
        tonnage28d += rs.tonnageKg;
      }
      if (!started.isBefore(sevenDaysAgo)) {
        tonnage7d += rs.tonnageKg;
      }
    }
    scalars[HerculSignals.sessionsThisWeek] = sessionIdsThisWeek.length
        .toDouble();
    scalars[HerculSignals.sessionsPerWeek4w] = sessionIds4w.length / 4.0;
    if (tonnage28d > 0) {
      final weeklyAvg4w = tonnage28d / 4.0;
      if (weeklyAvg4w > 0) {
        scalars[HerculSignals.tonnageDeltaPct7d] =
            ((tonnage7d - weeklyAvg4w) / weeklyAvg4w) * 100.0;
      }
    }

    // Last session RPE and load delta
    final lastSessionId = trainingSnapshot.sets.last.session.id;
    double rpeSum = 0;
    int rpeCount = 0;
    for (final rs in trainingSnapshot.sets) {
      if (rs.session.id == lastSessionId && rs.set.rpeX10 != null) {
        rpeSum += rs.set.rpeX10! / 10.0;
        rpeCount++;
      }
    }
    if (rpeCount > 0) {
      scalars[HerculSignals.lastSessionAvgRpe] = rpeSum / rpeCount;
    }

    // Calculate exercise-level signals & lifting weight deltas
    final e1rmDelta14 = <String, double>{};
    final e1rmBest = <String, double>{};
    final e1rmRatioBelted = <String, double>{};
    final performed30d = <String, double>{};
    final lastPerfDays = <String, double>{};

    final setsByExercise = <int, List<ResolvedSet>>{};
    for (final rs in trainingSnapshot.sets) {
      setsByExercise.putIfAbsent(rs.exercise.id, () => []).add(rs);
    }

    final liftDeltaPcts7d = <double>[];
    final lastSessionDeltaPcts = <double>[];

    for (final entry in setsByExercise.entries) {
      final slug = entry.value.first.exercise.slug;
      if (slug == null) continue;

      final sessions30d = <int>{};
      DateTime? latestSetDate;
      double bestOverall = 0;

      for (final rs in entry.value) {
        final d = rs.session.startedAt;
        if (!d.isBefore(thirtyDaysAgo)) {
          sessions30d.add(rs.session.id);
        }
        if (latestSetDate == null || d.isAfter(latestSetDate)) {
          latestSetDate = d;
        }
        final est =
            OneRepMax.estimate(weightKg: rs.effectiveKg, reps: rs.set.reps) ??
            0.0;
        if (est > bestOverall) bestOverall = est;
      }

      performed30d[slug] = sessions30d.length.toDouble();
      if (latestSetDate != null) {
        lastPerfDays[slug] = now.difference(latestSetDate).inDays.toDouble();
      }
      if (bestOverall > 0) {
        e1rmBest[slug] = bestOverall;
      }

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

      // 14d & 7d Deltas
      final twoWeeksAgo = now.subtract(const Duration(days: 14));
      double maxRecent14 = 0;
      double maxOld14 = 0;
      double maxRecent7 = 0;
      double maxPrior7to35 = 0;
      double maxLastSession = 0;
      double maxBeforeLastSession = 0;

      for (final rs in entry.value) {
        final est =
            OneRepMax.estimate(weightKg: rs.effectiveKg, reps: rs.set.reps) ??
            0.0;
        if (est <= 0) continue;

        final started = rs.session.startedAt;
        if (started.isAfter(twoWeeksAgo)) {
          if (est > maxRecent14) maxRecent14 = est;
        } else {
          if (est > maxOld14) maxOld14 = est;
        }

        if (started.isAfter(sevenDaysAgo)) {
          if (est > maxRecent7) maxRecent7 = est;
        } else if (started.isAfter(now.subtract(const Duration(days: 35)))) {
          if (est > maxPrior7to35) maxPrior7to35 = est;
        }

        if (rs.session.id == lastSessionId) {
          if (est > maxLastSession) maxLastSession = est;
        } else if (started.isAfter(now.subtract(const Duration(days: 35)))) {
          if (est > maxBeforeLastSession) maxBeforeLastSession = est;
        }
      }

      if (maxOld14 > 0 && maxRecent14 > 0) {
        e1rmDelta14[slug] = maxRecent14 - maxOld14;
      }
      if (maxRecent7 > 0 && maxPrior7to35 > 0) {
        liftDeltaPcts7d.add(
          ((maxRecent7 - maxPrior7to35) / maxPrior7to35) * 100.0,
        );
      }
      if (maxLastSession > 0 && maxBeforeLastSession > 0) {
        lastSessionDeltaPcts.add(
          ((maxLastSession - maxBeforeLastSession) / maxBeforeLastSession) *
              100.0,
        );
      }
    }

    if (performed30d.isNotEmpty) {
      series[HerculSignals.performedLast30d] = performed30d;
    }
    if (lastPerfDays.isNotEmpty) {
      series[HerculSignals.lastPerformedDays] = lastPerfDays;
    }
    if (e1rmBest.isNotEmpty) {
      series[HerculSignals.e1rmKg] = e1rmBest;
      final ratios = <String, double>{};
      for (final a in e1rmBest.entries) {
        for (final b in e1rmBest.entries) {
          if (a.key != b.key && b.value > 0) {
            ratios['${a.key}:${b.key}'] = a.value / b.value;
          }
        }
      }
      if (ratios.isNotEmpty) {
        series[HerculSignals.e1rmRatio] = ratios;
      }
    }
    if (e1rmRatioBelted.isNotEmpty) {
      series[HerculSignals.e1rmRatioBelted] = e1rmRatioBelted;
    }
    if (e1rmDelta14.isNotEmpty) {
      series[HerculSignals.e1rmDeltaKg14d] = e1rmDelta14;
    }
    if (liftDeltaPcts7d.isNotEmpty) {
      final avgDelta =
          liftDeltaPcts7d.reduce((a, b) => a + b) / liftDeltaPcts7d.length;
      scalars[HerculSignals.liftingDeltaPct7d] = avgDelta;
    }
    if (lastSessionDeltaPcts.isNotEmpty) {
      final avgLast =
          lastSessionDeltaPcts.reduce((a, b) => a + b) /
          lastSessionDeltaPcts.length;
      scalars[HerculSignals.lastSessionLoadDeltaPct] = avgLast;
    }
  }

  try {
    // ── Biometrics & Sleep ──
    BiometricCorrelationResult? sleepVsRpe;
    try {
      sleepVsRpe = await ref.watch(sleepVsRpeProvider.future);
    } catch (_) {}
    if (sleepVsRpe != null) {
      scalars[HerculSignals.sleepVsRpeR2] = sleepVsRpe.r2;
    }

    try {
      final sleepRepo = ref.watch(sleepRepositoryProvider);
      final sleepHistory = await sleepRepo.getSleepHistory(7);
      if (sleepHistory.isNotEmpty) {
        final todayIso = DateFormat('yyyy-MM-dd').format(today);
        final yesterdayIso = DateFormat('yyyy-MM-dd').format(yesterday);
        final lastNight = sleepHistory
            .where((r) => r.dateIso == todayIso || r.dateIso == yesterdayIso)
            .firstOrNull;
        if (lastNight != null) {
          scalars[HerculSignals.sleepYesterdayHours] = lastNight.totalHours;
        }
        final avgSleep =
            sleepHistory.map((r) => r.totalHours).reduce((a, b) => a + b) /
            sleepHistory.length;
        scalars[HerculSignals.sleepAvg7dHours] = avgSleep;
      }
    } catch (_) {}

    // ── Bodyweight multi-window deltas (1d, 2d, 3d, 7d, 14d, 21d, 30d) ──
    try {
      final measurementsRepo = ref.watch(measurementsRepositoryProvider);
      final weights = await measurementsRepo.watchMetric('bodyweight').first;
      if (weights.isNotEmpty) {
        final latest = weights.last.value;
        scalars[HerculSignals.weightKg] = latest;
        final deltas = <String, double>{};
        for (final days in const [1, 2, 3, 7, 14, 21, 30]) {
          final targetIso = DateFormat(
            'yyyy-MM-dd',
          ).format(today.subtract(Duration(days: days)));
          final candidates = weights
              .where((w) => w.dateIso.compareTo(targetIso) <= 0)
              .toList();
          if (candidates.isNotEmpty) {
            final refWeight = candidates.last.value;
            if (refWeight > 0) {
              deltas['$days'] = latest - refWeight;
            }
          }
        }
        if (deltas.isNotEmpty) {
          series[HerculSignals.weightDeltaKg] = deltas;
        }
      }
    } catch (_) {}

    // ── Fasting history & active fast ──
    try {
      final fastingRepo = ref.watch(fastingRepositoryProvider);
      final activeFast = await fastingRepo.activeSession();
      final fastHistory = await fastingRepo.history(limit: 30);

      if (activeFast != null || fastHistory.isNotEmpty) {
        if (activeFast != null) {
          scalars[HerculSignals.fastingIsFasting] = 1.0;
          final activeH = now.difference(activeFast.startedAt).inMinutes / 60.0;
          scalars[HerculSignals.fastingActiveHours] = activeH.clamp(0.0, 240.0);
        } else {
          scalars[HerculSignals.fastingIsFasting] = 0.0;
        }

        final cutoff36h = now.subtract(const Duration(hours: 36));
        final cutoff7d = now.subtract(const Duration(days: 7));

        double? recentFastHours;
        int count7d = 0;
        double sumHours7d = 0;

        for (final f in fastHistory) {
          final ended = f.endedAt;
          if (ended == null) continue;
          final hrs = ended.difference(f.startedAt).inMinutes / 60.0;
          if (hrs <= 0) continue;

          if (recentFastHours == null && ended.isAfter(cutoff36h)) {
            recentFastHours = hrs;
          }
          if (ended.isAfter(cutoff7d)) {
            count7d++;
            sumHours7d += hrs;
          }
        }

        if (recentFastHours != null) {
          scalars[HerculSignals.fastingYesterdayHours] = recentFastHours;
        } else if (activeFast != null) {
          scalars[HerculSignals.fastingYesterdayHours] =
              (now.difference(activeFast.startedAt).inMinutes / 60.0).clamp(
                0.0,
                240.0,
              );
        }

        scalars[HerculSignals.fastingCompleted7d] = count7d.toDouble();
        if (count7d > 0) {
          scalars[HerculSignals.fastingAvgHours7d] = sumHours7d / count7d;
        }
      }
    } catch (_) {}

    // ── Supplements (Creatine intake) ──
    try {
      final prefs = ref.watch(sharedPreferencesProvider);
      final suppRepo = SupplementRepository(prefs);
      final supplements = suppRepo.loadSupplements();
      final creatineSupps = supplements.where((s) {
        final n = s.name.toLowerCase();
        return n.contains('creatin') || n.contains('kreatin');
      }).toList();

      if (creatineSupps.isNotEmpty) {
        final creatineIds = creatineSupps.map((s) => s.id).toSet();
        final hist14 = suppRepo.loadHistory(days: 14, anchor: now);
        final todayIso = DateFormat('yyyy-MM-dd').format(today);
        final yesterdayIso = DateFormat('yyyy-MM-dd').format(yesterday);

        final takenToday = (hist14[todayIso] ?? const {}).intersection(
          creatineIds,
        );
        final takenYesterday = (hist14[yesterdayIso] ?? const {}).intersection(
          creatineIds,
        );
        scalars[HerculSignals.creatineTakenYesterday] =
            (takenYesterday.isNotEmpty || takenToday.isNotEmpty) ? 1.0 : 0.0;

        int days7 = 0;
        int daysPrior7 = 0;
        for (int i = 0; i < 14; i++) {
          final dIso = DateFormat(
            'yyyy-MM-dd',
          ).format(today.subtract(Duration(days: i)));
          final taken = (hist14[dIso] ?? const {}).intersection(creatineIds);
          if (taken.isNotEmpty) {
            if (i < 7) {
              days7++;
            } else {
              daysPrior7++;
            }
          }
        }
        scalars[HerculSignals.creatineDays7d] = days7.toDouble();
        scalars[HerculSignals.creatineDays14d] = (days7 + daysPrior7)
            .toDouble();
        scalars[HerculSignals.creatineLoadingPhase] =
            (days7 >= 4 && daysPrior7 <= 2) ? 1.0 : 0.0;
      }
    } catch (_) {}

    // ── Nutrition: 7d/14d adherence, Carbs Before Bed, Sodium, Water, Alcohol ──
    try {
      final nutritionRepo = ref.read(nutritionRepositoryProvider);
      final baseline = ref.read(baselineTargetsProvider);
      final start14 = today.subtract(const Duration(days: 14));
      final start7 = today.subtract(const Duration(days: 7));
      final history14 = await nutritionRepo
          .watchDailyTotalsForRange(start14, today)
          .first;

      if (history14.isNotEmpty) {
        double sumKcalPct14 = 0;
        int count14 = 0;
        double sumKcalPct7 = 0;
        double sumProteinPct7 = 0;
        int count7 = 0;
        final start7Iso = DateFormat('yyyy-MM-dd').format(start7);

        for (final entry in history14.entries) {
          final totals = entry.value;
          if (totals.kcal <= 0 && totals.proteinG <= 0) continue;
          if (baseline != null && baseline.kcal > 0) {
            sumKcalPct14 += totals.kcal / baseline.kcal;
            count14++;
          }
          if (entry.key.compareTo(start7Iso) >= 0) {
            count7++;
            if (baseline != null) {
              if (baseline.kcal > 0) sumKcalPct7 += totals.kcal / baseline.kcal;
              if (baseline.proteinG > 0) {
                sumProteinPct7 += totals.proteinG / baseline.proteinG;
              }
            }
          }
        }

        scalars[HerculSignals.daysLogged7d] = count7.toDouble();
        if (count14 > 0) {
          scalars[HerculSignals.kcalPct14d] = sumKcalPct14 / count14;
        }
        if (count7 > 0 && baseline != null) {
          scalars[HerculSignals.kcalPct7d] = sumKcalPct7 / count7;
          scalars[HerculSignals.proteinPct7d] = sumProteinPct7 / count7;
        }
      }

      // Yesterday's detailed entries: Carbs before bed, Alcohol, Sodium, Water
      final yesterdayEntries = await nutritionRepo
          .watchEntriesForDate(yesterday)
          .first;
      final waterYest = await nutritionRepo.waterMlFor(yesterday);
      if (waterYest > 0) {
        scalars[HerculSignals.waterYesterdayMl] = waterYest.toDouble();
      }

      if (yesterdayEntries.isNotEmpty) {
        double totalCarbsYest = 0;
        double lateCarbsYest = 0;
        double sodiumYest = 0;
        double alcoholYestG = 0;

        for (final e in yesterdayEntries) {
          final macros = await nutritionRepo.macrosForEntry(e);
          totalCarbsYest += macros.carbsG;
          sodiumYest += macros.sodiumMg;

          final mealLower = e.meal.toLowerCase();
          final isLateMeal =
              mealLower == 'dinner' ||
              mealLower == 'snack' ||
              mealLower.contains('evening') ||
              mealLower.contains('night') ||
              mealLower.contains('bed') ||
              e.loggedAt.hour >= 20;
          if (isLateMeal) {
            lateCarbsYest += macros.carbsG;
          }

          alcoholYestG += _estimateEntryAlcoholGrams(e, macros.kcal, macros);
        }

        scalars[HerculSignals.carbsYesterdayG] = totalCarbsYest;
        scalars[HerculSignals.carbsBeforeBedYesterdayG] = lateCarbsYest;
        scalars[HerculSignals.carbsBeforeBedPctYesterday] = totalCarbsYest > 0
            ? (lateCarbsYest / totalCarbsYest).clamp(0.0, 1.0)
            : 0.0;
        if (baseline != null && baseline.carbsG > 0) {
          scalars[HerculSignals.carbsPctYesterday] =
              totalCarbsYest / baseline.carbsG;
        }
        scalars[HerculSignals.sodiumYesterdayMg] = sodiumYest;
        scalars[HerculSignals.alcoholYesterdayG] = alcoholYestG;
        scalars[HerculSignals.alcoholYesterdayDrinks] = alcoholYestG / 14.0;
      }

      // Check 7-day alcohol frequency
      int alcoholDays = 0;
      for (int i = 1; i <= 7; i++) {
        final d = today.subtract(Duration(days: i));
        final entries = i == 1
            ? yesterdayEntries
            : await nutritionRepo.watchEntriesForDate(d).first;
        if (entries.isEmpty) continue;
        double dayAlc = 0;
        for (final e in entries) {
          final m = await nutritionRepo.macrosForEntry(e);
          dayAlc += _estimateEntryAlcoholGrams(e, m.kcal, m);
        }
        if (dayAlc >= 7.0) {
          alcoholDays++;
        }
      }
      if (yesterdayEntries.isNotEmpty || alcoholDays > 0) {
        scalars[HerculSignals.alcoholDays7d] = alcoholDays.toDouble();
      }
    } catch (_) {}

    // ── Composite Water Retention Index (-100 to +100) & Regeneration Score (0–100) ──
    double waterIdx = 0;
    bool hasWaterInput = false;
    final lateCarbs = scalars[HerculSignals.carbsBeforeBedYesterdayG];
    if (lateCarbs != null) {
      hasWaterInput = true;
      if (lateCarbs >= 90) {
        waterIdx += 30;
      } else if (lateCarbs >= 50) {
        waterIdx += 15;
      } else if (lateCarbs < 25) {
        waterIdx -= 20;
      }
    }
    final cre7d = scalars[HerculSignals.creatineDays7d];
    if (cre7d != null) {
      hasWaterInput = true;
      if (cre7d >= 5) {
        waterIdx += 25;
      } else if (cre7d <= 1) {
        waterIdx -= 15;
      }
    }
    final fastH =
        scalars[HerculSignals.fastingActiveHours] ??
        scalars[HerculSignals.fastingYesterdayHours];
    if (fastH != null) {
      hasWaterInput = true;
      if (fastH >= 20) {
        waterIdx -= 40;
      } else if (fastH >= 15) {
        waterIdx -= 20;
      }
    }
    final alcG = scalars[HerculSignals.alcoholYesterdayG];
    if (alcG != null && alcG >= 14) {
      hasWaterInput = true;
      waterIdx += 30; // Post-alcohol cortisol water retention rebound
    }
    final naMg = scalars[HerculSignals.sodiumYesterdayMg];
    if (naMg != null && naMg >= 3200) {
      hasWaterInput = true;
      waterIdx += 20;
    }
    if (hasWaterInput) {
      scalars[HerculSignals.waterRetentionIndex] = waterIdx.clamp(
        -100.0,
        100.0,
      );
    }

    // Regeneration Score (0–100)
    final cnsReady = scalars[HerculSignals.cnsReadiness];
    final sleepH =
        scalars[HerculSignals.sleepYesterdayHours] ??
        scalars[HerculSignals.sleepAvg7dHours];
    final protPct = scalars[HerculSignals.proteinPct7d];
    if (cnsReady != null ||
        avgMuscleRecovery != null ||
        sleepH != null ||
        protPct != null ||
        alcG != null) {
      double regen = 78.0;
      if (cnsReady != null) {
        regen = (regen * 0.5) + ((cnsReady * 100.0) * 0.5);
      }
      if (avgMuscleRecovery != null) {
        regen = (regen * 0.65) + (avgMuscleRecovery * 0.35);
      }
      if (sleepH != null) {
        if (sleepH >= 7.5) {
          regen += 8;
        } else if (sleepH < 6.0) {
          regen -= 16;
        } else if (sleepH < 6.8) {
          regen -= 7;
        }
      }
      if (protPct != null) {
        if (protPct >= 0.95) {
          regen += 5;
        } else if (protPct < 0.8) {
          regen -= 10;
        }
      }
      if (alcG != null && alcG >= 14) {
        regen -= (alcG >= 28 ? 22 : 12);
      }
      if (fastH != null && fastH >= 22) {
        regen -= 8;
      }
      scalars[HerculSignals.regenerationScore] = regen.clamp(0.0, 100.0);
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

double _estimateEntryAlcoholGrams(dynamic entry, double kcal, dynamic macros) {
  // 1. Check explicit alcohol micronutrient key if present
  try {
    final microsJson = entry.snapshotMicrosJson as String?;
    if (microsJson != null && microsJson.isNotEmpty) {
      final decoded = jsonDecode(microsJson);
      if (decoded is Map) {
        for (final k in const ['alcohol', 'ethanol', 'alcohol_g']) {
          final v = decoded[k];
          if (v is num && v > 0) return v.toDouble();
        }
      }
    }
  } catch (_) {}

  // 2. Check food/recipe name for alcoholic beverages
  final name = ((entry.snapshotName as String?) ?? '').toLowerCase();
  const alcoholKeywords = [
    'beer',
    'wine',
    'vodka',
    'whiskey',
    'whisky',
    'bourbon',
    'gin',
    'rum',
    'tequila',
    'cocktail',
    'margarita',
    'mojito',
    'cider',
    'prosecco',
    'champagne',
    'ipa',
    'lager',
    'stout',
    'ale',
    'liquor',
    'liqueur',
    'brandy',
    'cognac',
    'schnapps',
    'sake',
    'soju',
    'pivo',
    'vino',
    'žganje',
    'alcohol',
  ];

  final matchesKeyword = alcoholKeywords.any((kw) {
    if (kw == 'ale' || kw == 'gin' || kw == 'rum' || kw == 'ipa') {
      return RegExp('\\b$kw\\b').hasMatch(name);
    }
    return name.contains(kw);
  });

  final macroKcal =
      (macros.proteinG as double) * 4.0 +
      (macros.carbsG as double) * 4.0 +
      (macros.fatG as double) * 9.0;
  final unattributedKcal = kcal - macroKcal;

  if (matchesKeyword) {
    if (unattributedKcal > 25) {
      return unattributedKcal / 7.0;
    }
    // Fallback estimate if macros absorbed the calories
    return kcal > 0 ? (kcal * 0.6) / 7.0 : 14.0;
  }

  return 0.0;
}

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

/// Evaluates all matching insights across all domains (without the 3-card cap)
/// for the dedicated Hercul Insights Report page.
final herculReportMessagesProvider = FutureProvider<List<HerculMessage>>((
  ref,
) async {
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
    limit: 50,
    onePerDomain: false,
  );
});

/// Synthesizes the complete [HerculInsightsReport] (4-tier status: Great, Good,
/// Not Good, Bad + Bodyweight, Lifting Weight, Water Retention, and
/// Regeneration logical assessments + active insight library).
final herculInsightsReportProvider = FutureProvider<HerculInsightsReport>((
  ref,
) async {
  final context = await ref.watch(herculContextProvider.future);
  final messages = await ref.watch(herculReportMessagesProvider.future);
  return HerculInsightsReport.build(context: context, messages: messages);
});

final herculLogFiredProvider = Provider((ref) {
  return (String ruleId) {
    ref
        .read(herculRepositoryProvider)
        .logFired(ruleId, ref.read(clockProvider).now());
    ref.invalidate(herculMessageLogProvider);
  };
});
