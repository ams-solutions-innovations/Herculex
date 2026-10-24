import 'dart:convert';

/// Why the deterministic weekly planner was asked to reconsider a schedule.
enum AdaptationTrigger { skippedWorkout, incompleteWorkout, lowRecovery }

enum AdaptationDecision { proposed, accepted, declined, expired }

/// A serializable, immutable planned working set.  This deliberately mirrors
/// the values that are copied into an active workout, rather than retaining a
/// pointer to a mutable program/template row.
class AdaptedSet {
  const AdaptedSet({
    required this.index,
    required this.isWarmup,
    required this.setType,
    required this.intent,
    this.repsMin,
    this.repsMax,
    this.weightKg,
    this.rpeX10,
    this.rir,
    this.percentOf1Rm,
    this.setTypeMetaJson,
  });

  final int index;
  final bool isWarmup;
  final String setType;
  final String intent;
  final int? repsMin;
  final int? repsMax;
  final double? weightKg;
  final int? rpeX10;
  final int? rir;
  final double? percentOf1Rm;
  final String? setTypeMetaJson;

  Map<String, Object?> toJson() => {
    'index': index,
    'isWarmup': isWarmup,
    'setType': setType,
    'intent': intent,
    'repsMin': repsMin,
    'repsMax': repsMax,
    'weightKg': weightKg,
    'rpeX10': rpeX10,
    'rir': rir,
    'percentOf1Rm': percentOf1Rm,
    'setTypeMetaJson': setTypeMetaJson,
  };

  factory AdaptedSet.fromJson(Map<String, dynamic> json) => AdaptedSet(
    index: json['index'] as int,
    isWarmup: json['isWarmup'] as bool,
    setType: json['setType'] as String,
    intent: json['intent'] as String,
    repsMin: json['repsMin'] as int?,
    repsMax: json['repsMax'] as int?,
    weightKg: (json['weightKg'] as num?)?.toDouble(),
    rpeX10: json['rpeX10'] as int?,
    rir: json['rir'] as int?,
    percentOf1Rm: (json['percentOf1Rm'] as num?)?.toDouble(),
    setTypeMetaJson: json['setTypeMetaJson'] as String?,
  );
}

class AdaptedExercise {
  const AdaptedExercise({
    required this.exerciseId,
    required this.orderIndex,
    required this.restSeconds,
    required this.slotRole,
    required this.trainingMethod,
    required this.why,
    required this.sets,
    required this.allowsAdvancedTechniques,
    this.programExerciseSlotId,
    this.rotationAssignmentId,
    this.equipmentVariant,
    this.sessionSegment,
    this.supersetGroup,
    this.waveIndex,
    this.waveCount,
  });

  final int exerciseId;
  final int orderIndex;
  final int restSeconds;
  final String slotRole;
  final String trainingMethod;
  final String why;
  final List<AdaptedSet> sets;
  final bool allowsAdvancedTechniques;
  final int? programExerciseSlotId;
  final int? rotationAssignmentId;
  final String? equipmentVariant;
  final String? sessionSegment;
  final int? supersetGroup;
  final int? waveIndex;
  final int? waveCount;

  int get workingSetCount => sets.where((set) => !set.isWarmup).length;

  Map<String, Object?> toJson() => {
    'exerciseId': exerciseId,
    'orderIndex': orderIndex,
    'restSeconds': restSeconds,
    'slotRole': slotRole,
    'trainingMethod': trainingMethod,
    'why': why,
    'sets': sets.map((set) => set.toJson()).toList(),
    'allowsAdvancedTechniques': allowsAdvancedTechniques,
    'programExerciseSlotId': programExerciseSlotId,
    'rotationAssignmentId': rotationAssignmentId,
    'equipmentVariant': equipmentVariant,
    'sessionSegment': sessionSegment,
    'supersetGroup': supersetGroup,
    'waveIndex': waveIndex,
    'waveCount': waveCount,
  };

  factory AdaptedExercise.fromJson(Map<String, dynamic> json) =>
      AdaptedExercise(
        exerciseId: json['exerciseId'] as int,
        orderIndex: json['orderIndex'] as int,
        restSeconds: json['restSeconds'] as int,
        slotRole: json['slotRole'] as String,
        trainingMethod: json['trainingMethod'] as String,
        why: json['why'] as String,
        sets: (json['sets'] as List<dynamic>)
            .map((set) => AdaptedSet.fromJson(set as Map<String, dynamic>))
            .toList(growable: false),
        allowsAdvancedTechniques: json['allowsAdvancedTechniques'] as bool,
        programExerciseSlotId: json['programExerciseSlotId'] as int?,
        rotationAssignmentId: json['rotationAssignmentId'] as int?,
        equipmentVariant: json['equipmentVariant'] as String?,
        sessionSegment: json['sessionSegment'] as String?,
        supersetGroup: json['supersetGroup'] as int?,
        waveIndex: json['waveIndex'] as int?,
        waveCount: json['waveCount'] as int?,
      );
}

class AdaptedSessionPlan {
  const AdaptedSessionPlan({required this.name, required this.exercises});

  final String name;
  final List<AdaptedExercise> exercises;

  int get workingSetCount =>
      exercises.fold(0, (total, exercise) => total + exercise.workingSetCount);

  String encode() => jsonEncode({
    'name': name,
    'exercises': exercises.map((exercise) => exercise.toJson()).toList(),
  });

  static AdaptedSessionPlan decode(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return AdaptedSessionPlan(
      name: json['name'] as String,
      exercises: (json['exercises'] as List<dynamic>)
          .map(
            (exercise) =>
                AdaptedExercise.fromJson(exercise as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

/// One potential addition to a future scheduled session.
class AdaptationCandidate {
  const AdaptationCandidate({
    required this.scheduleId,
    required this.date,
    required this.plan,
    required this.addition,
    required this.muscleCredit,
    required this.recoveryScore,
    required this.conflictsNextWeek,
    this.priority = 1,
    this.originalWorkingSets,
  });

  final int scheduleId;
  final DateTime date;
  final AdaptedSessionPlan plan;
  final AdaptedExercise addition;
  final Map<String, double> muscleCredit;
  final int recoveryScore;
  final bool conflictsNextWeek;
  final double priority;
  final int? originalWorkingSets;
}

class AdaptationChange {
  const AdaptationChange({
    required this.scheduleId,
    required this.plan,
    this.addedExercise,
    required this.coveredVolume,
  });

  final int scheduleId;
  final AdaptedSessionPlan plan;
  final AdaptedExercise? addedExercise;
  final Map<String, double> coveredVolume;
}

class AdaptationProposal {
  const AdaptationProposal({
    required this.trigger,
    required this.weekStart,
    required this.reason,
    required this.changes,
    required this.uncoveredVolume,
    required this.inputFingerprint,
  });

  final AdaptationTrigger trigger;
  final DateTime weekStart;
  final String reason;
  final List<AdaptationChange> changes;
  final Map<String, double> uncoveredVolume;
  final String inputFingerprint;

  bool get hasChanges => changes.isNotEmpty;
}

/// Pure, deterministic selection of the least disruptive safe additions.
///
/// Database reads, recovery calculation and plan resolution deliberately live
/// in the repository.  Keeping this class data-only makes every safety rule
/// independently testable and prevents a UI path from quietly changing it.
abstract final class WeeklyAdaptationEngine {
  static const minimumRecoveryScore = 70;
  static const maxAddedSetsPerSession = 4;
  static const maxSessionGrowth = 0.20;

  static AdaptationProposal propose({
    required AdaptationTrigger trigger,
    required DateTime weekStart,
    required Map<String, double> targetVolume,
    required Map<String, double> actualVolume,
    required List<AdaptationCandidate> candidates,
    required String inputFingerprint,
  }) {
    final deficit = <String, double>{
      for (final entry in targetVolume.entries)
        if ((entry.value - (actualVolume[entry.key] ?? 0)) > 0.01)
          entry.key: entry.value - (actualVolume[entry.key] ?? 0),
    };
    final remaining = Map<String, double>.from(deficit);
    final changes = <AdaptationChange>[];
    final usedSchedules = <int>{};

    final ordered =
        candidates.where((candidate) {
          final planned =
              candidate.originalWorkingSets ?? candidate.plan.workingSetCount;
          final alreadyAdded = (candidate.plan.workingSetCount - planned).clamp(
            0,
            999,
          );
          final growthCap = (planned * maxSessionGrowth).floor() - alreadyAdded;
          return candidate.recoveryScore >= minimumRecoveryScore &&
              !candidate.conflictsNextWeek &&
              candidate.addition.workingSetCount + alreadyAdded <=
                  maxAddedSetsPerSession &&
              candidate.addition.workingSetCount <= growthCap &&
              candidate.muscleCredit.keys.any(
                (m) => (remaining[m] ?? 0) > 0.01,
              );
        }).toList()..sort((a, b) {
          final aCoverage = _coverage(a.muscleCredit, remaining) * a.priority;
          final bCoverage = _coverage(b.muscleCredit, remaining) * b.priority;
          final coverage = bCoverage.compareTo(aCoverage);
          if (coverage != 0) {
            return coverage;
          }
          final date = a.date.compareTo(b.date);
          if (date != 0) {
            return date;
          }
          return a.scheduleId.compareTo(b.scheduleId);
        });

    for (final candidate in ordered) {
      if (usedSchedules.contains(candidate.scheduleId)) {
        continue;
      }
      if (_coverage(candidate.muscleCredit, remaining) <= 0.01) {
        continue;
      }
      // Never use a whole exercise addition when it would overshoot any
      // affected muscle's remaining prescribed volume. The repository can
      // offer smaller candidates on a later run; otherwise we explicitly
      // leave that final deficit rather than silently over-programming it.
      if (candidate.muscleCredit.entries.any(
        (entry) => entry.value > (remaining[entry.key] ?? 0) + 0.01,
      )) {
        continue;
      }
      usedSchedules.add(candidate.scheduleId);
      changes.add(
        AdaptationChange(
          scheduleId: candidate.scheduleId,
          plan: AdaptedSessionPlan(
            name: candidate.plan.name,
            exercises: [
              ...candidate.plan.exercises,
              AdaptedExercise.fromJson({
                ...candidate.addition.toJson(),
                'orderIndex': candidate.plan.exercises.length,
              }),
            ],
          ),
          addedExercise: candidate.addition,
          coveredVolume: candidate.muscleCredit,
        ),
      );
      for (final entry in candidate.muscleCredit.entries) {
        remaining[entry.key] = ((remaining[entry.key] ?? 0) - entry.value)
            .clamp(0.0, 999.0)
            .toDouble();
      }
    }

    final reason = changes.isEmpty
        ? 'No safe volume catch-up fits the remaining scheduled workouts.'
        : 'Adjusted only recovered muscles in existing workouts this week.';
    return AdaptationProposal(
      trigger: trigger,
      weekStart: weekStart,
      reason: reason,
      changes: changes,
      uncoveredVolume: {
        for (final entry in remaining.entries)
          if (entry.value > 0.01) entry.key: entry.value,
      },
      inputFingerprint: inputFingerprint,
    );
  }

  static double _coverage(
    Map<String, double> credit,
    Map<String, double> deficit,
  ) => credit.entries.fold<double>(
    0,
    (sum, entry) =>
        sum + (deficit[entry.key] ?? 0).clamp(0.0, entry.value).toDouble(),
  );
}
