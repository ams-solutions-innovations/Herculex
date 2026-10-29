import 'dart:convert';
import 'dart:math' as math;

import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

class WorkoutHeartRate {
  final DateTime at;
  final double bpm;
  const WorkoutHeartRate(this.at, this.bpm);
}

/// Net energy above rest, within the recorded session only. The estimates and
/// conservative policy are documented in docs/workout-energy-estimation.md.
/// These are field estimates, not calorimetry or validated confidence bounds.
class WorkoutEnergyEstimate {
  final double workKcal;
  final double recoveryKcal;
  final double workSeconds;
  final double restSeconds;
  final bool inferredTiming;
  final bool usedFallbackWeight;
  final bool usedHeartRate;

  const WorkoutEnergyEstimate({
    this.workKcal = 0,
    this.recoveryKcal = 0,
    this.workSeconds = 0,
    this.restSeconds = 0,
    this.inferredTiming = false,
    this.usedFallbackWeight = false,
    this.usedHeartRate = false,
  });

  /// A policy discount, then rounding DOWN to whole 5 kcal. No minimum burn.
  double get conservativeKcal =>
      (workKcal + recoveryKcal) * (usedFallbackWeight ? 0.8 : 0.9);
  int get activeKcal => (conservativeKcal / 5).floor() * 5;
}

abstract final class WorkoutEnergyEstimator {
  static bool validWeight(double? kg) =>
      kg != null && kg.isFinite && kg >= 25 && kg <= 350;

  /// Alternative RMR predictors, not stacked demographic multipliers. BF is
  /// optional and never inferred from appearance, BMI, or biological sex.
  static double restingKcalPerMinute({
    required double weightKg,
    Profile? profile,
    double? bodyFatPercent,
  }) {
    double daily;
    if (bodyFatPercent != null &&
        bodyFatPercent.isFinite &&
        bodyFatPercent >= 3 &&
        bodyFatPercent <= 65) {
      daily = 19.7 * weightKg * (1 - bodyFatPercent / 100) + 413;
    } else if (profile?.sex != null &&
        profile?.ageYears != null &&
        profile!.ageYears! >= 18 &&
        profile.ageYears! <= 100 &&
        profile.heightCm != null &&
        profile.heightCm!.isFinite &&
        profile.heightCm! >= 120 &&
        profile.heightCm! <= 230) {
      daily =
          10 * weightKg +
          6.25 * profile.heightCm! -
          5 * profile.ageYears! +
          (profile.sex == BiologicalSex.male ? 5 : -161);
    } else {
      daily = 15.1 * weightKg + 371;
    }
    return daily.clamp(600, 5000) / 1440;
  }

  static WorkoutEnergyEstimate estimate({
    required TrainingSnapshot snapshot,
    required int sessionId,
    required DateTime startedAt,
    required DateTime endedAt,
    Profile? profile,
    double? userWeightKg,
    double? bodyFatPercent,
    List<WorkoutHeartRate> heartRates = const [],
  }) {
    final elapsed = endedAt.difference(startedAt).inMilliseconds / 1000;
    if (elapsed <= 0) return const WorkoutEnergyEstimate();
    final sets = snapshot.sets
        .where((s) => s.session.id == sessionId && s.set.isCompleted)
        .toList();
    if (sets.isEmpty) {
      return WorkoutEnergyEstimate(restSeconds: elapsed);
    }
    final suppliedWeight = userWeightKg ?? profile?.weightKg;
    final fallbackWeight = !validWeight(suppliedWeight);
    // Missing mass must not silently invent a 75 kg athlete.
    final weight = fallbackWeight ? 60.0 : suppliedWeight!;
    final restRate = restingKcalPerMinute(
      weightKg: weight,
      profile: profile,
      bodyFatPercent: bodyFatPercent,
    );
    final inferred = sets.any((s) => s.set.completedAt == null);
    sets.sort((a, b) {
      if (!inferred) return a.set.completedAt!.compareTo(b.set.completedAt!);
      final byExercise = a.workoutExercise.orderIndex.compareTo(
        b.workoutExercise.orderIndex,
      );
      return byExercise != 0
          ? byExercise
          : a.set.setIndex.compareTo(b.set.setIndex);
    });

    final durations = [for (final s in sets) _workSeconds(s, weight)];
    final totalWork = durations.fold(0.0, (a, b) => a + b);
    final scale = inferred && totalWork > elapsed ? elapsed / totalWork : 1.0;
    final availableRest = math.max(0.0, elapsed - totalWork * scale);
    final inferredRest = availableRest / sets.length;
    var cursor = 0.0;
    var workKcal = 0.0;
    var recoveryKcal = 0.0;
    var workSeconds = 0.0;
    var previousNetRate = 0.0;
    var usedHeartRate = false;

    // Integrate one timeline. Work and recovery cannot overlap. Each recovery
    // tail ends after 180 s; leaving the logger open adds no indefinite burn.
    for (var i = 0; i < sets.length; i++) {
      final s = sets[i];
      final intended = durations[i] * scale;
      if (intended <= 0) continue;
      double start;
      double end;
      if (inferred) {
        start = cursor;
        end = math.min(elapsed, start + intended);
      } else {
        end = s.set.completedAt!.difference(startedAt).inMilliseconds / 1000;
        if (end <= 0 || end > elapsed) continue;
        start = math.max(cursor, end - intended);
        if (start >= end) continue;
      }
      recoveryKcal += _recovery(previousNetRate, start - cursor);
      final seconds = end - start;
      final met = _workMet(s, weight, seconds);
      // Standard MET is an absolute oxygen-cost proxy. Subtract the person's
      // estimated rest; do not multiply standard MET by a corrected RMR again.
      var netRate = math.max(0.0, met * 3.5 * weight / 200 - restRate);
      final cardioName = '${s.exercise.slug ?? ''} ${s.exercise.name}'
          .toLowerCase();
      final hrSupported =
          cardioName.contains('run') ||
          cardioName.contains('treadmill') ||
          cardioName.contains('bike') ||
          cardioName.contains('cycl');
      if (_isCardio(s) && hrSupported && seconds >= 120) {
        final hrRate = _cardioHeartRate(
          samples: heartRates,
          start: startedAt.add(Duration(milliseconds: (start * 1000).round())),
          end: startedAt.add(Duration(milliseconds: (end * 1000).round())),
          profile: profile,
          weight: weight,
          restRate: restRate,
        );
        if (hrRate != null) {
          // Population HR equations only inform sustained aerobic work. Keep
          // their contribution small and bounded in the absence of calibration.
          netRate = (0.8 * netRate + 0.2 * hrRate).clamp(
            netRate * 0.85,
            netRate * 1.1,
          );
          usedHeartRate = true;
        }
      }
      var energy = netRate * seconds / 60;
      final console = s.set.calories;
      if (s.metric.has(SetField.calories) && console != null && console > 0) {
        // Console kcal may be gross, miscalibrated, or cumulative. Never add
        // them on top of this interval or let them exceed its plausible cost.
        energy = math.min(
          energy,
          math.max(0.0, console * 0.8 - restRate * seconds / 60),
        );
      }
      workKcal += energy;
      workSeconds += seconds;
      previousNetRate = seconds > 0 ? energy * 60 / seconds : 0;
      cursor = end;
      if (inferred) {
        // Planned rest is only a bounded fallback when completion stamps are
        // unavailable. It is never interpreted as active exercise.
        final rest = math.min(
          inferredRest,
          (s.workoutExercise.targetRestSeconds ?? s.exercise.defaultRestSeconds)
              .clamp(0, 600)
              .toDouble(),
        );
        recoveryKcal += _recovery(previousNetRate, rest);
        cursor = math.min(elapsed, cursor + rest);
        previousNetRate = 0;
      }
    }
    recoveryKcal += _recovery(previousNetRate, elapsed - cursor);
    return WorkoutEnergyEstimate(
      workKcal: workKcal,
      recoveryKcal: recoveryKcal,
      workSeconds: workSeconds,
      restSeconds: math.max(0, elapsed - workSeconds),
      inferredTiming:
          inferred || sets.any((s) => s.set.durationSeconds == null),
      usedFallbackWeight: fallbackWeight,
      usedHeartRate: usedHeartRate,
    );
  }

  /// A bounded recovery heuristic, not a claim that rest has zero cost. The
  /// integral saturates after 3 min and includes no post-session EPOC bonus.
  static double _recovery(double netRate, double seconds) => seconds <= 0
      ? 0
      : netRate * 0.25 * (1 - math.exp(-math.min(seconds, 180) / 60));

  static bool _isCardio(ResolvedSet s) => s.exercise.category == 'cardio';

  static double _workSeconds(ResolvedSet s, double weight) {
    final duration = s.set.durationSeconds;
    if (s.metric.has(SetField.duration) && duration != null && duration > 0) {
      return duration.clamp(1, 14400).toDouble();
    }
    if (s.metric.isRepBased) {
      final reps = s.countedReps.clamp(0, 1000);
      var tempo = s.setType == SetType.negatives ? 4.0 : 3.0;
      if (s.setType == SetType.partials) tempo = 1.5;
      if (s.setType == SetType.pause && s.set.setTypeMetaJson != null) {
        try {
          final meta = jsonDecode(s.set.setTypeMetaJson!) as Map;
          final pause = meta['pauseSeconds'];
          if (pause is num && pause.isFinite) tempo += pause.clamp(0, 10);
        } catch (_) {
          // Old or invalid metadata does not create extra work.
        }
      }
      return reps * tempo;
    }
    final distance = s.set.distanceM;
    if (s.metric.has(SetField.distance) &&
        distance != null &&
        distance.isFinite &&
        distance > 0) {
      final name = '${s.exercise.slug} ${s.exercise.name}'.toLowerCase();
      final speed = name.contains('cycl') || name.contains('bike')
          ? 4.4
          : name.contains('run')
          ? 2.2
          : 1.0;
      return (distance / speed).clamp(0, 14400);
    }
    if (s.metric.has(SetField.calories) && (s.set.calories ?? 0) > 0) {
      return (s.set.calories! / (5 * 3.5 * weight / 200) * 60).clamp(0, 14400);
    }
    // No observed reps, duration, distance or console output: no invented set.
    return 0;
  }

  static double _workMet(ResolvedSet s, double weight, double seconds) {
    final name = '${s.exercise.slug ?? ''} ${s.exercise.name}'.toLowerCase();
    if (_isCardio(s)) {
      final distance = s.set.distanceM;
      if (distance != null &&
          distance.isFinite &&
          distance > 0 &&
          s.set.durationSeconds != null &&
          s.set.durationSeconds! > 0 &&
          seconds > 0 &&
          (name.contains('run') ||
              name.contains('walk') ||
              name.contains('treadmill'))) {
        final metresPerMinute = distance / s.set.durationSeconds! * 60;
        final walking = name.contains('walk');
        return (1 + (walking ? 0.1 : 0.2) * metresPerMinute / 3.5).clamp(2, 18);
      }
      if (name.contains('run')) return 8.5;
      if (name.contains('walk')) return 3.8;
      if (name.contains('row')) return 5.0;
      if (name.contains('ellipt')) return 5.0;
      if (name.contains('stair')) return 6.8;
      return 5.8;
    }
    if (s.exercise.category == 'mobility') return 2.3;
    if (name.contains('kettlebell') && name.contains('swing')) return 9.8;
    if (name.contains('burpee') || name.contains('thruster')) return 7.5;
    if (s.exercise.force == 'static' || name.contains('plank')) return 2.8;
    final lower =
        const {
          'squat',
          'hinge',
          'lunge',
          'carry',
        }.contains(s.exercise.movementPattern) ||
        const {
          'Quads',
          'Glutes',
          'Hamstrings',
        }.contains(s.exercise.primaryMuscle);
    var met = s.exercise.mechanics == 'isolation' ? 3.5 : (lower ? 6.0 : 5.0);
    // A modest load correction; machine stack kg is not mechanical work and
    // neither height nor an assumed ROM can turn it into measured joules.
    final effective = s.effectiveKg;
    if (effective.isFinite && effective >= 0) {
      met += (effective / weight).clamp(0, 2) * 0.5;
    }
    final rpe = s.set.rpeX10;
    if (rpe != null && rpe >= 10 && rpe <= 100) {
      met *= (1 + (rpe / 10 - 8) * 0.025).clamp(0.85, 1.05);
    }
    if (s.set.isWarmup) met *= 0.85;
    return met;
  }

  static double? _cardioHeartRate({
    required List<WorkoutHeartRate> samples,
    required DateTime start,
    required DateTime end,
    required Profile? profile,
    required double weight,
    required double restRate,
  }) {
    final age = profile?.ageYears;
    // Keytel's development population: 18–45 y, 47–120 kg; cycling/running.
    if (age == null ||
        age < 18 ||
        age > 45 ||
        profile?.sex == null ||
        weight < 47 ||
        weight > 120) {
      return null;
    }
    final maxHr = math.min(205, 208 - 0.7 * age + 5);
    // Ten-second bins prevent duplicates or two sources multiplying coverage.
    final bins = <int, List<double>>{};
    for (final sample in samples) {
      if (sample.at.isBefore(start) ||
          !sample.at.isBefore(end) ||
          !sample.bpm.isFinite ||
          sample.bpm < 90 ||
          sample.bpm > maxHr) {
        continue;
      }
      final bin = sample.at.difference(start).inSeconds ~/ 10;
      bins.putIfAbsent(bin, () => []).add(sample.bpm);
    }
    final seconds = end.difference(start).inMilliseconds / 1000;
    if (bins.length < 6 || bins.length * 10 / seconds < 0.6) return null;
    final hr =
        bins.values.fold(0.0, (sum, values) {
          values.sort();
          return sum + values[values.length ~/ 2];
        }) /
        bins.length;
    final gross = profile!.sex == BiologicalSex.male
        ? (-55.0969 + 0.6309 * hr + 0.1988 * weight + 0.2017 * age) / 4.184
        : (-20.4022 + 0.4472 * hr - 0.1263 * weight + 0.074 * age) / 4.184;
    return math.max(0, gross - restRate);
  }
}
