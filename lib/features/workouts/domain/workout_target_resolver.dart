import 'dart:math' as math;
import 'package:herculex/features/workouts/domain/one_rep_max.dart';
import 'package:herculex/features/workouts/domain/progression_engine.dart';

/// Inputs are values, not database rows: the same calculation serves every UI.
class WorkoutTargetSet {
  const WorkoutTargetSet({
    required this.id,
    this.weightKg = 0,
    this.reps = 0,
    this.rpeX10,
    this.bodyweightKg,
    this.completed = false,
    this.warmup = false,
    this.type = 'standard',
    this.repsMin,
    this.repsMax,
    this.plannedWeightKg,
    this.targetRpeX10,
    this.percentOf1Rm,
    this.assistance = '',
    this.automaticWarmup = false,
    this.relativeToTopSet,
  });

  final int id;
  final double weightKg;
  final double? bodyweightKg;
  final int reps;
  final int? rpeX10;
  final bool completed, warmup, automaticWarmup;
  final String type, assistance;
  final int? repsMin, repsMax, targetRpeX10;
  final double? plannedWeightKg, percentOf1Rm, relativeToTopSet;
  bool get planned =>
      repsMin != null ||
      plannedWeightKg != null ||
      percentOf1Rm != null ||
      targetRpeX10 != null;
}

enum WorkoutTargetSource {
  prescription,
  percentage,
  progression,
  history,
  adaptation,
  warmup,
}

class WorkoutTarget {
  const WorkoutTarget({
    this.weightKg,
    this.reps,
    this.rpeX10,
    required this.source,
    required this.reason,
    this.isAssistance = false,
  });
  final double? weightKg;
  final int? reps, rpeX10;
  final WorkoutTargetSource source;
  final String reason;
  final bool isAssistance;
}

class WorkoutTargetSettings {
  const WorkoutTargetSettings({
    this.goal = ProgressionGoal.muscleGain,
    this.model = 'linear',
    this.weeklyPct,
    this.targetSets,
    this.repsMin,
    this.repsMax,
    this.stepKg,
    this.assisted = false,
    this.repOnly = false,
    this.nextMode = true,
    this.repBased = true,
    this.method,
  });
  final ProgressionGoal goal;
  final String model;
  final String? method;
  final double? weeklyPct, stepKg;
  final int? targetSets, repsMin, repsMax;
  final bool assisted, repOnly, nextMode, repBased;
}

abstract final class WorkoutTargetResolver {
  /// Product model for a submaximal set; deliberately separate from historical
  /// unadjusted 1RM analytics. Missing RPE never means failure or RPE 10.
  static double? capacity(double weight, int reps, int? rpeX10) {
    if (weight <= 0 ||
        reps < 1 ||
        rpeX10 == null ||
        rpeX10 < 60 ||
        rpeX10 > 100)
      return null;
    final effectiveReps = reps + 10 - rpeX10 / 10;
    if (effectiveReps > 12) return null;
    return weight * (1 + effectiveReps / 30);
  }

  static double? loadAt(double capacity, int reps, int? rpeX10) {
    if (rpeX10 == null || rpeX10 < 60 || rpeX10 > 100 || reps < 1) return null;
    final effectiveReps = reps + 10 - rpeX10 / 10;
    return effectiveReps <= 12 ? capacity / (1 + effectiveReps / 30) : null;
  }

  static List<WorkoutTarget> resolve({
    required List<WorkoutTargetSet> sets,
    required List<WorkoutTargetSet> history,
    required String equipment,
    WorkoutTargetSettings settings = const WorkoutTargetSettings(),
  }) {
    final step = settings.stepKg ?? ProgressionEngine.stepFor(equipment);
    final special = {'max_effort', 'dynamic_effort'}.contains(settings.method);
    final out = <WorkoutTarget>[];
    for (var i = 0; i < sets.length; i++) {
      final set = sets[i];
      final priorSets = history
          .where(
            (s) =>
                s.completed &&
                s.warmup == set.warmup &&
                s.type == set.type &&
                s.assistance == set.assistance,
          )
          .toList();
      final ordinal = sets
          .take(i)
          .where(
            (s) =>
                s.warmup == set.warmup &&
                s.type == set.type &&
                s.assistance == set.assistance,
          )
          .length;
      final prior = priorSets.isEmpty
          ? null
          : priorSets[math.min(ordinal, priorSets.length - 1)];
      var reps = set.repsMin ?? prior?.reps;
      var weight = set.plannedWeightKg;
      if (weight == null && set.relativeToTopSet != null) {
        final top = sets
            .take(i)
            .where((s) => s.completed && !s.warmup && s.type == 'standard')
            .lastOrNull;
        if (top != null && top.weightKg > 0)
          weight = roundDownTo(top.weightKg * set.relativeToTopSet!, step);
      }
      var source = WorkoutTargetSource.prescription;
      var reason = 'Program prescription';
      final minReps = set.repsMin ?? settings.repsMin ?? settings.goal.repsMin;
      final maxReps =
          set.repsMax ??
          set.repsMin ??
          settings.repsMax ??
          settings.goal.repsMax;
      final requiredSets = sets
          .where(
            (s) =>
                !s.warmup &&
                s.type == set.type &&
                s.repsMin == set.repsMin &&
                s.repsMax == set.repsMax,
          )
          .length;
      final progressive =
          settings.repBased &&
          !set.warmup &&
          !special &&
          set.type == 'standard' &&
          (settings.nextMode || set.planned);

      if (weight == null &&
          set.percentOf1Rm != null &&
          !settings.assisted &&
          !settings.repOnly) {
        final estimates = priorSets
            .where((s) => !s.warmup)
            .map(
              (s) =>
                  capacity(s.weightKg, s.reps, s.rpeX10) ??
                  OneRepMax.estimate(weightKg: s.weightKg, reps: s.reps),
            )
            .whereType<double>();
        if (estimates.isNotEmpty) {
          weight = roundDownTo(
            estimates.reduce(math.max) * set.percentOf1Rm!,
            step,
          );
          source = WorkoutTargetSource.percentage;
          reason = 'Program percentage of comparable estimated 1RM';
        }
      }
      if (weight == null && prior != null) {
        weight = prior.weightKg;
        source = WorkoutTargetSource.history;
        reason = 'Matching equipment, set type and assistance';
        if (progressive) {
          // Prior working sets count whatever rep range they were prescribed:
          // periodization moves the range between weeks and waves, and
          // demanding an identical range would leave the load frozen for good.
          // Success is still judged against *today's* [maxReps].
          final comparable = priorSets;
          final count = set.planned
              ? requiredSets
              : settings.targetSets ?? math.max(1, comparable.length);
          final allSucceeded =
              comparable.length >= count &&
              comparable.every(
                (s) =>
                    s.reps >= maxReps &&
                    s.weightKg == prior.weightKg &&
                    (s.rpeX10 == null ||
                        set.targetRpeX10 == null ||
                        s.rpeX10! <= set.targetRpeX10!),
              );
          if (settings.assisted) {
            if (allSucceeded) weight = math.max(0, prior.weightKg - step);
            reps =
                set.repsMin ??
                (allSucceeded
                    ? minReps
                    : (prior.reps + 1).clamp(minReps, maxReps));
          } else if (set.planned || settings.model == 'double') {
            if (allSucceeded && !settings.repOnly) {
              weight = math.max(
                prior.weightKg + step,
                roundToNearest(
                  prior.weightKg *
                      (1 +
                          (settings.weeklyPct ??
                                  settings.goal.weeklyIncreasePct) /
                              100),
                  step,
                ),
              );
            }
            reps =
                set.repsMin ??
                (allSucceeded
                    ? minReps
                    : (prior.reps + 1).clamp(minReps, maxReps));
          } else {
            final suggestion = ProgressionEngine.suggestNext(
              lastWeightKg: prior.weightKg,
              lastReps: prior.reps,
              goal: settings.goal,
              equipmentVariant: equipment,
              weeklyIncreasePctOverride: settings.weeklyPct,
              targetRepsMin: minReps,
              targetRepsMax: maxReps,
            );
            weight = settings.repOnly ? null : suggestion.weightKg;
            reps = suggestion.reps;
          }
          if (!settings.assisted &&
              !settings.repOnly &&
              !allSucceeded &&
              set.targetRpeX10 != null) {
            final estimated = capacity(
              prior.weightKg,
              prior.reps,
              prior.rpeX10,
            );
            final atTarget = estimated == null
                ? null
                : loadAt(estimated, reps, set.targetRpeX10);
            if (atTarget != null)
              weight = math.min(
                weight ?? atTarget,
                roundDownTo(atTarget, step),
              );
          }
          source = WorkoutTargetSource.progression;
          reason =
              'Progress from actual completed sets within the prescribed rep range';
        }
      }
      // A first-ever workout can acquire its baseline from today's actual work.
      final completed = sets
          .take(i)
          .where(
            (s) =>
                s.completed &&
                !s.warmup &&
                s.type == set.type &&
                s.assistance == set.assistance,
          )
          .lastOrNull;
      if (progressive && weight == null && completed != null) {
        weight = completed.weightKg;
        reps ??= set.repsMin ?? completed.reps;
      }
      if (settings.repOnly) weight = null;

      // Every reduction is derived from actual preceding work. Rebuilds, undo,
      // late RPE and restarts cannot compound a previously suggested reduction.
      if (progressive && weight != null && reps != null) {
        for (final done
            in sets
                .take(i)
                .where(
                  (s) =>
                      s.completed &&
                      !s.warmup &&
                      s.type == set.type &&
                      s.assistance == set.assistance,
                )) {
          double? adjusted;
          if (settings.assisted) {
            final body = done.bodyweightKg;
            final effective = body == null
                ? null
                : capacity(body - done.weightKg, done.reps, done.rpeX10);
            final desired = effective == null
                ? null
                : loadAt(effective, reps, set.targetRpeX10);
            if (body != null && desired != null)
              adjusted = math.max(0, body - desired);
            if (adjusted == null &&
                done.rpeX10 != null &&
                set.targetRpeX10 != null &&
                done.rpeX10! > set.targetRpeX10!)
              adjusted = done.weightKg + step;
          } else {
            final estimate = capacity(done.weightKg, done.reps, done.rpeX10);
            if (estimate != null)
              adjusted = loadAt(estimate, reps, set.targetRpeX10);
          }
          if (adjusted == null &&
              done.reps < (done.repsMin ?? minReps) &&
              (done.weightKg > 0 || settings.assisted)) {
            adjusted = settings.assisted
                ? math.max(
                    done.weightKg + step,
                    (done.weightKg * 1.05 / step).ceil() * step,
                  )
                : math.max(
                    0,
                    math.min(
                      done.weightKg - step,
                      roundDownTo(done.weightKg * .95, step),
                    ),
                  );
          }
          if (adjusted != null) {
            final rounded = settings.assisted
                ? (adjusted / step).ceil() * step
                : roundDownTo(adjusted, step);
            final next = settings.assisted
                ? math.max(weight!, rounded)
                : math.min(weight!, rounded);
            if (next != weight) {
              weight = next;
              source = WorkoutTargetSource.adaptation;
              reason =
                  'Reduced effort after completed set: ${done.reps} reps${done.rpeX10 == null ? '' : ' @ RPE ${done.rpeX10! / 10}'}';
            }
          }
        }
      }
      out.add(
        WorkoutTarget(
          weightKg: weight,
          reps: reps,
          rpeX10: set.targetRpeX10,
          source: source,
          reason: reason,
          isAssistance: settings.assisted,
        ),
      );
    }

    // Percentages on automatic warmups share the first work set's reference.
    final workIndex = sets.indexWhere((s) => !s.warmup);
    if (workIndex >= 0 &&
        out[workIndex].weightKg != null &&
        !settings.assisted &&
        !settings.repOnly) {
      final work = out[workIndex].weightKg!;
      final workPercent = sets[workIndex].percentOf1Rm;
      final reference = workPercent != null && workPercent > 0
          ? work / workPercent
          : work;
      double? previous;
      for (var i = 0; i < workIndex; i++) {
        final set = sets[i];
        if (!set.automaticWarmup || set.percentOf1Rm == null) continue;
        final load = roundDownTo(reference * set.percentOf1Rm!, step);
        final valid = load > 0 && load < work && load != previous;
        out[i] = WorkoutTarget(
          weightKg: valid ? load : null,
          reps: valid ? set.repsMin : null,
          source: WorkoutTargetSource.warmup,
          reason: valid
              ? 'Warmup towards first working load'
              : 'Warmup step omitted after equipment rounding',
        );
        if (valid) previous = load;
      }
    }
    return out;
  }
}
