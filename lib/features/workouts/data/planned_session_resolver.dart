import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/prescription_resolver.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/programs/domain/slot_prescription_codec.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workouts/domain/warmup_resolver.dart';
import 'package:uuid/uuid.dart';

/// A set target frozen at the moment a workout starts.
class PlannedSetSnapshot {
  const PlannedSetSnapshot({
    required this.index,
    required this.repsMin,
    required this.repsMax,
    required this.isWarmup,
    required this.setType,
    required this.intent,
    this.weightKg,
    this.rpeX10,
    this.rir,
    this.percentOf1Rm,
    this.setTypeMetaJson,
  });

  final int index;
  final int? repsMin;
  final int? repsMax;
  final double? weightKg;
  final int? rpeX10;
  final int? rir;
  final double? percentOf1Rm;
  final bool isWarmup;
  final String setType;
  final String intent;
  final String? setTypeMetaJson;

  PlannedSetSnapshot copyWith({int? index}) => PlannedSetSnapshot(
    index: index ?? this.index,
    repsMin: repsMin,
    repsMax: repsMax,
    isWarmup: isWarmup,
    setType: setType,
    intent: intent,
    weightKg: weightKg,
    rpeX10: rpeX10,
    rir: rir,
    percentOf1Rm: percentOf1Rm,
    setTypeMetaJson: setTypeMetaJson,
  );
}

class PlannedExerciseSnapshot {
  const PlannedExerciseSnapshot({
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
  final List<PlannedSetSnapshot> sets;
  final bool allowsAdvancedTechniques;
  final int? programExerciseSlotId;
  final int? rotationAssignmentId;
  final String? equipmentVariant;
  final String? sessionSegment;
  final int? supersetGroup;
  final int? waveIndex;
  final int? waveCount;
}

class PlannedSessionSnapshot {
  const PlannedSessionSnapshot({
    required this.name,
    required this.exercises,
    this.templateId,
  });

  final String name;
  final List<PlannedExerciseSnapshot> exercises;
  final int? templateId;
}

/// Single source of truth for Program/Template -> active workout.
///
/// It resolves exercise rotation, per-slot training method, periodization and
/// prescription before writing anything. [materialize] then copies that
/// result into immutable `planned_*` columns; later program edits cannot alter
/// a workout that has already started.
class PlannedSessionResolver {
  PlannedSessionResolver(this._db);

  final AppDatabase _db;

  Future<PlannedSessionSnapshot> resolveTemplate(
    int templateId, {
    double volumeFactor = 1,
  }) async {
    final template = await (_db.select(
      _db.workoutTemplates,
    )..where((t) => t.id.equals(templateId))).getSingleOrNull();
    final exercises =
        await (_db.select(_db.templateExercises)
              ..where((t) => t.templateId.equals(templateId))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();

    final resolved = <PlannedExerciseSnapshot>[];
    for (final te in exercises) {
      final rows =
          await (_db.select(_db.templateSets)
                ..where((t) => t.templateExerciseId.equals(te.id))
                ..orderBy([(t) => OrderingTerm(expression: t.setOrder)]))
              .get();
      final source = rows.isEmpty
          ? [
              for (var i = 0; i < te.targetSets; i++)
                _TemplateTarget(
                  order: i + 1,
                  repsMin: te.targetRepsMin,
                  repsMax: te.targetRepsMax,
                ),
            ]
          : [
              for (final row in rows)
                _TemplateTarget(
                  order: row.setOrder,
                  repsMin: row.targetRepsMin ?? row.targetReps,
                  repsMax:
                      row.targetRepsMax ?? row.targetReps ?? te.targetRepsMax,
                  weightKg: row.targetWeightKg,
                  isWarmup: row.isWarmup,
                  setType: row.setType,
                  metaJson: row.setTypeMetaJson,
                ),
            ];
      final warmups = source.where((s) => s.isWarmup).toList();
      final working = source.where((s) => !s.isWarmup).toList();
      final workingCount = volumeFactor < 1 && working.isNotEmpty
          ? (working.length * volumeFactor).ceil().clamp(1, working.length)
          : working.length;
      final selected = [...warmups, ...working.take(workingCount)]
        ..sort((a, b) => a.order.compareTo(b.order));

      resolved.add(
        PlannedExerciseSnapshot(
          exerciseId: te.exerciseId,
          orderIndex: te.orderIndex,
          restSeconds: te.targetRestSeconds ?? 120,
          slotRole: SlotRole.accessory.id,
          trainingMethod: SlotTrainingMethod.straightSets.id,
          why: 'Copied from the workout template when this session started.',
          equipmentVariant: null,
          supersetGroup: te.supersetGroup,
          allowsAdvancedTechniques: false,
          sets: [
            for (final (index, set) in selected.indexed)
              PlannedSetSnapshot(
                index: index + 1,
                repsMin: set.repsMin ?? te.targetRepsMin,
                repsMax: set.repsMax ?? te.targetRepsMax ?? te.targetRepsMin,
                weightKg: set.weightKg,
                isWarmup: set.isWarmup,
                setType: set.setType,
                intent: set.isWarmup ? Intent.technical.id : Intent.rir2.id,
                rir: set.isWarmup ? Intent.technical.rir : Intent.rir2.rir,
                rpeX10: set.isWarmup
                    ? (Intent.technical.rpe * 10).round()
                    : (Intent.rir2.rpe * 10).round(),
                setTypeMetaJson: set.metaJson,
              ),
          ],
        ),
      );
    }
    return PlannedSessionSnapshot(
      name: template?.name ?? 'Workout',
      exercises: resolved,
      templateId: templateId,
    );
  }

  Future<PlannedSessionSnapshot> resolveProgramDay(
    int programDayId, {
    int? templateOverride,
  }) async {
    final day = await (_db.select(
      _db.programDays,
    )..where((t) => t.id.equals(programDayId))).getSingle();
    final templateId = templateOverride ?? day.templateId;
    if (templateId != null) return resolveTemplate(templateId);

    final week = await (_db.select(
      _db.programWeeks,
    )..where((t) => t.id.equals(day.programWeekId))).getSingle();
    final program = await (_db.select(
      _db.programs,
    )..where((t) => t.id.equals(week.programId))).getSingle();
    final weekPrescription = WeekPrescription(
      weekIndex: week.weekIndex,
      intensityFactor: week.intensityFactor,
      volumeFactor: week.adjustmentFactor,
      blockPhase: week.blockPhase,
      isDeload: Periodization.isPlannedDeload(
        model: PeriodizationModel.fromId(program.periodizationModel),
        totalWeeks: program.weeks,
        weekIndex: week.weekIndex,
      ),
    );
    final rows =
        await (_db.select(_db.programDayExercises)
              ..where((t) => t.programDayId.equals(programDayId))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();

    final exercises = <PlannedExerciseSnapshot>[];
    var sawHeavyLiftInSession = false;
    for (final pde in rows) {
      ProgramExerciseSlotData? slot;
      if (pde.programExerciseSlotId != null) {
        slot =
            await (_db.select(_db.programExerciseSlots)
                  ..where((t) => t.id.equals(pde.programExerciseSlotId!)))
                .getSingleOrNull();
      }
      RotationAssignmentData? assignment;
      if (slot != null) {
        assignment =
            await (_db.select(_db.rotationAssignments)..where(
                  (t) =>
                      t.slotId.equals(slot!.id) &
                      t.weekIndex.equals(week.weekIndex),
                ))
                .getSingleOrNull();
      }
      final exerciseId = assignment?.exerciseId ?? pde.exerciseId;
      final catalog = await (_db.select(
        _db.exerciseCatalog,
      )..where((t) => t.id.equals(exerciseId))).getSingle();
      final role = SlotRole.fromId(slot?.role ?? pde.slotRole);
      final rawMethod = _methodFrom(slot?.trainingMethod ?? pde.trainingMethod);
      final model = PeriodizationModel.fromId(program.periodizationModel);
      final method =
          (rawMethod == SlotTrainingMethod.dynamicEffort &&
              model == PeriodizationModel.linear)
          ? SlotTrainingMethod.straightSets
          : rawMethod;
      final prescription = _resolvePrescription(
        method: method,
        explicit: pde,
        role: role,
        model: model,
        week: weekPrescription,
        mechanics: catalog.mechanics,
        modality: catalog.modality,
      );
      final why =
          pde.prescriptionWhy ??
          (assignment?.reason == null
              ? prescription.why
              : '${assignment!.reason} ${prescription.why}');
      final isFirstHeavy = role.isHeavy && !sawHeavyLiftInSession;
      if (role.isHeavy) sawHeavyLiftInSession = true;
      final decodedPrescription = SlotPrescriptionCodec.decode(
        pde.prescriptionCodecJson,
      );
      final workingSets = method == SlotTrainingMethod.maxEffort
          ? _maxEffortWorkingSets()
          : decodedPrescription != null
          ? _setsFromPrescription(decodedPrescription)
          : _setsFromPrescription(prescription.prescription);
      final warmupEligible =
          method == SlotTrainingMethod.maxEffort ||
          _hasAutomaticWarmups(pde.variantConfigJson);
      final warmupTarget = method == SlotTrainingMethod.maxEffort
          ? 0.90
          : (prescription.prescription.segments.isEmpty
                ? null
                : prescription.prescription.segments.first.percentOf1Rm);
      final warmups = warmupEligible
          ? _warmupSnapshots(
              role: role,
              mechanics: catalog.mechanics,
              modality: catalog.modality,
              targetPercentOf1Rm: warmupTarget,
              isFirstHeavyLiftInSession: isFirstHeavy,
            )
          : const <PlannedSetSnapshot>[];
      final sets = [...warmups, ...workingSets].indexed
          .map((entry) => entry.$2.copyWith(index: entry.$1 + 1))
          .toList(growable: false);

      exercises.add(
        PlannedExerciseSnapshot(
          exerciseId: exerciseId,
          orderIndex: pde.orderIndex,
          restSeconds: pde.restSeconds ?? prescription.restSeconds,
          slotRole: role.id,
          trainingMethod: method.id,
          why: why,
          programExerciseSlotId: slot?.id,
          rotationAssignmentId: assignment?.id,
          equipmentVariant: pde.equipmentVariant,
          sessionSegment: pde.sessionSegment,
          supersetGroup: pde.supersetGroup,
          waveIndex: week.weekIndex,
          waveCount: program.weeks,
          sets: sets,
          allowsAdvancedTechniques: program.allowTimeSavingSetTechniques,
        ),
      );
    }
    return PlannedSessionSnapshot(name: day.name, exercises: exercises);
  }

  Future<int> materialize(
    PlannedSessionSnapshot plan, {
    DateTime? startedAt,
    int? gymId,
    String? notes,
    String? sessionUuid,
  }) {
    return _db.transaction(() async {
      final sessionId = await _db
          .into(_db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              name: Value(plan.name),
              startedAt: startedAt ?? DateTime.now(),
              gymId: Value(gymId),
              notes: Value(notes),
              sessionUuid: Value(sessionUuid ?? const Uuid().v4()),
            ),
          );
      for (final exercise in plan.exercises) {
        final workoutExerciseId = await _db
            .into(_db.workoutExercises)
            .insert(
              WorkoutExercisesCompanion.insert(
                sessionId: sessionId,
                exerciseId: exercise.exerciseId,
                orderIndex: exercise.orderIndex,
                targetRestSeconds: Value(exercise.restSeconds),
                plannedSessionSegment: Value(exercise.sessionSegment),
                supersetGroup: Value(exercise.supersetGroup),
                equipmentVariant: Value(exercise.equipmentVariant),
                programExerciseSlotId: Value(exercise.programExerciseSlotId),
                rotationAssignmentId: Value(exercise.rotationAssignmentId),
                plannedSlotRole: Value(exercise.slotRole),
                plannedTrainingMethod: Value(exercise.trainingMethod),
                plannedPrescriptionWhy: Value(exercise.why),
                plannedWaveIndex: Value(exercise.waveIndex),
                plannedWaveCount: Value(exercise.waveCount),
                plannedAllowsAdvancedTechniques: Value(
                  exercise.allowsAdvancedTechniques,
                ),
              ),
            );
        for (final set in exercise.sets) {
          await _db
              .into(_db.setEntries)
              .insert(
                SetEntriesCompanion.insert(
                  workoutExerciseId: workoutExerciseId,
                  setIndex: set.index,
                  // Completed values intentionally start empty/zero. The
                  // immutable target lives only in planned_*.
                  reps: 0,
                  weightKg: 0,
                  isWarmup: Value(set.isWarmup),
                  isCompleted: const Value(false),
                  setType: Value(set.setType),
                  setTypeMetaJson: Value(set.setTypeMetaJson),
                  plannedRepsMin: Value(set.repsMin),
                  plannedRepsMax: Value(set.repsMax),
                  plannedWeightKg: Value(set.weightKg),
                  plannedRpeX10: Value(set.rpeX10),
                  plannedRir: Value(set.rir),
                  plannedPercentOf1Rm: Value(set.percentOf1Rm),
                  plannedIntent: Value(set.intent),
                ),
              );
        }
      }
      if (plan.templateId != null) {
        await (_db.update(
          _db.workoutTemplates,
        )..where((t) => t.id.equals(plan.templateId!))).write(
          WorkoutTemplatesCompanion(lastUsedAt: Value(DateTime.now())),
        );
      }
      return sessionId;
    });
  }

  static SlotTrainingMethod _methodFrom(String? raw) {
    final byId = SlotTrainingMethod.fromId(raw);
    if (byId != SlotTrainingMethod.auto || raw == SlotTrainingMethod.auto.id) {
      return byId;
    }
    final normalized = (raw ?? 'auto').replaceAll('_', '').toLowerCase();
    return SlotTrainingMethod.values.firstWhere(
      (m) => m.name.toLowerCase() == normalized,
      orElse: () => SlotTrainingMethod.auto,
    );
  }

  static ResolvedPrescription _resolvePrescription({
    required SlotTrainingMethod method,
    required ProgramDayExerciseData explicit,
    required SlotRole role,
    required PeriodizationModel model,
    required WeekPrescription week,
    required String mechanics,
    required String modality,
  }) {
    final effectiveMethod =
        (method == SlotTrainingMethod.dynamicEffort &&
            model == PeriodizationModel.linear)
        ? SlotTrainingMethod.straightSets
        : method;
    final methodTemplate = switch (effectiveMethod) {
      SlotTrainingMethod.maxEffort => SlotPrescription.builtIns.firstWhere(
        (p) => p.name == 'Westside ME',
      ),
      SlotTrainingMethod.dynamicEffort => SlotPrescription.builtIns.firstWhere(
        (p) => p.name.startsWith('Dynamic Effort'),
      ),
      SlotTrainingMethod.repetition => const SlotPrescription(
        name: 'Repetition method',
        segments: [
          WorkSegment(sets: 3, repsMin: 8, repsMax: 12, intent: Intent.rir1),
        ],
      ),
      SlotTrainingMethod.topSetBackoff => const SlotPrescription(
        name: 'Top set + back-off',
        segments: [
          WorkSegment(sets: 1, repsMin: 4, repsMax: 6, intent: Intent.rir1),
          WorkSegment(sets: 3, repsMin: 6, repsMax: 8, intent: Intent.rir2),
        ],
      ),
      SlotTrainingMethod.volumeWave => SlotPrescription(
        name: 'Volume wave',
        segments: [
          WorkSegment(
            sets: explicit.targetSets,
            repsMin: explicit.targetRepsMin ?? 10,
            repsMax: explicit.targetRepsMax ?? 10,
            intent: Intent.rir2,
          ),
        ],
      ),
      SlotTrainingMethod.technique => const SlotPrescription(
        name: 'Technique / tempo',
        segments: [WorkSegment(sets: 3, repsMin: 5, intent: Intent.technical)],
      ),
      SlotTrainingMethod.straightSets ||
      SlotTrainingMethod.doubleProgression => SlotPrescription(
        name: effectiveMethod == SlotTrainingMethod.doubleProgression
            ? 'Double progression'
            : 'Straight sets',
        segments: [
          WorkSegment(
            sets: explicit.targetSets,
            repsMin: explicit.targetRepsMin ?? 8,
            repsMax: explicit.targetRepsMax ?? explicit.targetRepsMin ?? 12,
            intent: _intentFromRir(explicit.targetRir),
            percentOf1Rm: explicit.percentOf1Rm,
            restSeconds: explicit.restSeconds,
          ),
        ],
      ),
      SlotTrainingMethod.auto => null,
    };
    return PrescriptionResolver.resolve(
      model: effectiveMethod == SlotTrainingMethod.maxEffort
          ? PeriodizationModel.maxEffort
          : model,
      role: role,
      week: week,
      template: methodTemplate,
      mechanics: mechanics,
      modality: modality,
    );
  }

  static Intent _intentFromRir(int? rir) => switch (rir) {
    0 => Intent.toFailure,
    1 => Intent.rir1,
    2 => Intent.rir2,
    3 => Intent.rir3,
    _ => Intent.rir2,
  };

  static bool _hasAutomaticWarmups(String? raw) {
    if (raw == null || raw.isEmpty) return false;
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)['autoWarmups'] == true;
    } catch (_) {
      return false;
    }
  }

  static List<PlannedSetSnapshot> _warmupSnapshots({
    required SlotRole role,
    required String mechanics,
    required String modality,
    required double? targetPercentOf1Rm,
    required bool isFirstHeavyLiftInSession,
  }) {
    final steps = WarmupResolver.resolve(
      role: role,
      mechanics: mechanics,
      modality: modality,
      targetPercentOf1Rm: targetPercentOf1Rm,
      isFirstHeavyLiftInSession: isFirstHeavyLiftInSession,
    );
    return [
      for (final (index, step) in steps.indexed)
        PlannedSetSnapshot(
          index: index + 1,
          repsMin: step.reps,
          repsMax: step.reps,
          isWarmup: true,
          setType: 'standard',
          intent: Intent.technical.id,
          rir: Intent.technical.rir,
          rpeX10: (Intent.technical.rpe * 10).round(),
          percentOf1Rm: step.percentOf1Rm,
        ),
    ];
  }

  static List<PlannedSetSnapshot> _setsFromPrescription(
    SlotPrescription prescription,
  ) {
    final out = <PlannedSetSnapshot>[];
    var index = 1;
    for (final segment in prescription.segments) {
      for (var i = 0; i < segment.sets; i++) {
        out.add(
          PlannedSetSnapshot(
            index: index++,
            repsMin: segment.repsMin,
            repsMax: segment.repsMax,
            isWarmup: false,
            setType: segment.setType.id,
            intent: segment.intent.id,
            rpeX10: (segment.intent.rpe * 10).round(),
            rir: segment.intent.rir,
            percentOf1Rm: segment.percentOf1Rm,
            setTypeMetaJson: segment.meta.isEmpty
                ? null
                : jsonEncode(segment.meta),
          ),
        );
      }
    }
    return out;
  }

  /// Max Effort is represented explicitly rather than as one vague ramp set,
  /// so phone and Wear OS can display and log the complete safe sequence.
  ///
  /// This returns only the top single and its back-off sets; the warmup ramp
  /// leading into it now comes from [WarmupResolver] (D-10), prepended by the
  /// caller alongside every other eligible slot's warmups.
  static List<PlannedSetSnapshot> _maxEffortWorkingSets() {
    final out = <PlannedSetSnapshot>[];
    var index = 1;
    out.add(
      PlannedSetSnapshot(
        index: index++,
        repsMin: 1,
        repsMax: 3,
        isWarmup: false,
        setType: 'standard',
        intent: Intent.rampToMax.id,
        rpeX10: 90,
        rir: 1,
        setTypeMetaJson: jsonEncode({'rpeMin': 8.5, 'rpeMax': 9.5}),
      ),
    );
    for (var i = 0; i < 3; i++) {
      out.add(
        PlannedSetSnapshot(
          index: index++,
          repsMin: 3,
          repsMax: 6,
          isWarmup: false,
          setType: 'down_sets',
          intent: Intent.rir2.id,
          rpeX10: 80,
          rir: 2,
          setTypeMetaJson: jsonEncode({
            'relativeToTopSetMin': .85,
            'relativeToTopSetMax': .92,
          }),
        ),
      );
    }
    return out;
  }
}

class _TemplateTarget {
  const _TemplateTarget({
    required this.order,
    this.repsMin,
    this.repsMax,
    this.weightKg,
    this.isWarmup = false,
    this.setType = 'standard',
    this.metaJson,
  });

  final int order;
  final int? repsMin;
  final int? repsMax;
  final double? weightKg;
  final bool isWarmup;
  final String setType;
  final String? metaJson;
}
