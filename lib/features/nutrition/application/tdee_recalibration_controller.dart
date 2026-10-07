import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/data/tdee_estimates_repository.dart';
import 'package:herculex/features/nutrition/data/tdee_inputs_repository.dart';
import 'package:herculex/features/nutrition/domain/activity_classifier.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/domain/meal.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimator.dart';
import 'package:herculex/features/profile/domain/profile.dart';

// NOTE: imported only by app.dart and tests. nutrition_providers.dart must
// never import this file (it needs nutritionRepositoryProvider from there).

final tdeeInputsRepositoryProvider = Provider<TdeeInputsRepository>((ref) {
  return TdeeInputsRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(nutritionRepositoryProvider),
    ref.watch(clockProvider),
  );
});

/// Runs one adaptive-TDEE recalibration and appends the result to history.
///
/// Background work: every failure is swallowed (D-08, never an error state).
/// It never reads or writes `nutrition_targets` (TDEE-05); a saved manual
/// target is only ever surfaced against the estimate, never rewritten.
class TdeeRecalibrator {
  TdeeRecalibrator(this._readProfile, this._history, this._inputs, this._clock);

  final Future<Profile?> Function() _readProfile;
  final TdeeEstimatesRepository _history;
  final TdeeInputsRepository _inputs;
  final Clock _clock;

  bool _running = false;

  /// Returns the recorded estimate, or null when nothing was written (already
  /// running, no usable profile, not due, or a swallowed failure). [force]
  /// bypasses the cadence gate (manual ActivityLevel reset, D-13/D-14).
  Future<TdeeEstimateResult?> run({bool force = false}) async {
    if (_running) return null;
    _running = true;
    try {
      final profile = await _readProfile();
      if (profile == null) return null;
      final bmr = MacroTargets.bmr(profile);
      final seed = MacroTargets.seedMaintenanceKcal(profile);
      if (bmr == null || seed == null) return null;

      final asOf = _clock.now();
      final past = await _history.recent();
      final data = await _inputs.load();

      final reason = TdeeEstimator.shouldRecalibrate(
        asOf: asOf,
        history: past,
        weightLogs: data.weightLogs,
        stepsByDate: data.stepsByDate,
        force: force,
      );
      if (reason == RecalibrationReason.none) return null;

      final level = profile.activityLevel;
      final multiplier = MacroTargets.multiplierFor(level);
      final result = TdeeEstimator.recalibrate(
        asOf: asOf,
        foodLoggedDays: data.foodLoggedDays,
        dailyKcalByDate: data.dailyKcalByDate,
        weightLogs: data.weightLogs,
        classification: ActivityClassifier.classify(
          dailySteps: _recentSteps(data.stepsByDate, asOf),
          workoutsPerWeek: data.workoutsPerWeek,
          seedMultiplier: multiplier,
          activeKcalPerDay: data.avgActiveKcal,
          sleepHoursPerNight: data.avgSleepHours,
          restingHr: data.avgRestingHr,
        ),
        bmrKcal: bmr,
        seedMaintenanceKcal: seed,
        seedInputs: {
          'onboarding_level': level.label,
          'activity_factor': multiplier,
        },
        history: past,
      );
      await _history.record(result);
      return result;
    } catch (_) {
      return null;
    } finally {
      _running = false;
    }
  }

  /// Step values for the last [ActivityClassifier.windowDays] days ending on
  /// [asOf]'s calendar day.
  static List<double> _recentSteps(Map<String, double> steps, DateTime asOf) {
    final day = DateTime(asOf.year, asOf.month, asOf.day);
    final from = dateIso(
      DateTime(
        day.year,
        day.month,
        day.day - (ActivityClassifier.windowDays - 1),
      ),
    );
    final to = dateIso(day);
    return [
      for (final e in steps.entries)
        if (e.key.compareTo(from) >= 0 && e.key.compareTo(to) <= 0) e.value,
    ];
  }
}

final tdeeRecalibratorProvider = Provider<TdeeRecalibrator>((ref) {
  return TdeeRecalibrator(
    // The latest emitted value, not `.future`: a forced run right after an
    // ActivityLevel reset must see the new level, not the first profile.
    () async =>
        ref.read(profileProvider).asData?.value ??
        await ref.read(profileProvider.future),
    ref.watch(tdeeEstimatesRepositoryProvider),
    ref.watch(tdeeInputsRepositoryProvider),
    ref.watch(clockProvider),
  );
});

/// Calls [onResumed] when the app returns to the foreground. A user who keeps
/// the app open for days never hits the process-start path, so this is the
/// second recalibration trigger (TDEE-03).
class TdeeResumeObserver with WidgetsBindingObserver {
  TdeeResumeObserver(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}

/// Registered once from `app.dart`. Recalibrates when a profile first becomes
/// available (app open), on every foreground resume, and forced when the user
/// manually resets their ActivityLevel. There is no background scheduler in
/// this project, so a user who never opens or resumes the app is not
/// recalibrated. Resume calls are non-forced, so they are gated to once per
/// calendar day by `TdeeEstimator.shouldRecalibrate`.
final tdeeRecalibrationControllerProvider = Provider<void>((ref) {
  // Keep the estimate stream warm without rebuilding this provider: a
  // `ref.watch` here would rebuild (and loop) every time a row is recorded.
  ref.listen(latestTdeeEstimateProvider, (_, _) {});

  ref.listen<AsyncValue<Profile?>>(profileProvider, (previous, next) {
    final before = previous?.asData?.value;
    final after = next.asData?.value;
    if (after == null) return;
    final recalibrator = ref.read(tdeeRecalibratorProvider);
    if (before == null) {
      unawaited(recalibrator.run());
    } else if (before.activityLevel != after.activityLevel) {
      unawaited(recalibrator.run(force: true));
    }
  }, fireImmediately: true);

  final observer = TdeeResumeObserver(
    () => unawaited(ref.read(tdeeRecalibratorProvider).run()),
  );
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
});
