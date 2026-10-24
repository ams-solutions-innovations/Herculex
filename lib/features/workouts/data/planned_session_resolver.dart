import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/measurements/data/measurements_repository.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/prescription_resolver.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/programs/domain/slot_prescription_codec.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/programs/domain/time_saving_policy.dart';
import 'package:herculex/features/programs/domain/weekly_adaptation_engine.dart';
import 'package:herculex/features/workout_report/data/workout_report_journal.dart';
import 'package:herculex/features/workouts/data/calisthenics_progression_repository.dart';
import 'package:herculex/features/workouts/data/workout_targets_repository.dart';
import 'package:herculex/features/workouts/domain/calisthenics_progression.dart';
import 'package:herculex/features/workouts/domain/calisthenics_set_plan.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/set_prescription_metadata.dart';
import 'package:herculex/features/workouts/domain/warmup_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

part 'planned_session_resolver/target_preparation.dart';
part 'planned_session_resolver/time_saving_validation.dart';

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

  PlannedSetSnapshot copyWith({
    int? index,
    int? repsMin,
    int? repsMax,
    double? weightKg,
    int? rpeX10,
    int? rir,
    String? setTypeMetaJson,
  }) => PlannedSetSnapshot(
    index: index ?? this.index,
    repsMin: repsMin ?? this.repsMin,
    repsMax: repsMax ?? this.repsMax,
    isWarmup: isWarmup,
    setType: setType,
    intent: intent,
    weightKg: weightKg ?? this.weightKg,
    rpeX10: rpeX10 ?? this.rpeX10,
    rir: rir ?? this.rir,
    percentOf1Rm: percentOf1Rm,
    setTypeMetaJson: setTypeMetaJson ?? this.setTypeMetaJson,
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

extension PlannedExerciseTargetRows on PlannedExerciseSnapshot {
  WorkoutExerciseData get targetExercise => WorkoutExerciseData(
    id: -1,
    sessionId: -1,
    exerciseId: exerciseId,
    orderIndex: orderIndex,
    equipmentVariant: equipmentVariant,
    plannedTrainingMethod: trainingMethod,
    plannedAllowsAdvancedTechniques: allowsAdvancedTechniques,
  );

  List<SetEntryData> get targetRows => [
    for (final s in sets)
      SetEntryData(
        id: -s.index - 1,
        workoutExerciseId: -1,
        setIndex: s.index,
        weightKg: 0,
        reps: 0,
        isWarmup: s.isWarmup,
        isCompleted: false,
        setType: s.setType,
        setTypeMetaJson: s.setTypeMetaJson,
        plannedWeightKg: s.weightKg,
        plannedRepsMin: s.repsMin,
        plannedRepsMax: s.repsMax,
        plannedRpeX10: s.rpeX10,
        plannedRir: s.rir,
        plannedPercentOf1Rm: s.percentOf1Rm,
        plannedIntent: s.intent,
      ),
  ];
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

  /// Resolves an occurrence, preferring a user-confirmed current-week
  /// adaptation over its mutable program/template source.
  Future<PlannedSessionSnapshot> resolveScheduledWorkout(
    ScheduledWorkoutData schedule,
  ) async {
    final override =
        await (_db.select(_db.adaptationOverrides).join([
                innerJoin(
                  _db.adaptationProposals,
                  _db.adaptationProposals.id.equalsExp(
                    _db.adaptationOverrides.proposalId,
                  ),
                ),
              ])
              ..where(_db.adaptationOverrides.scheduleId.equals(schedule.id))
              ..where(_db.adaptationProposals.decision.equals('accepted'))
              ..where(_db.adaptationOverrides.deletedAt.isNull())
              ..where(_db.adaptationProposals.deletedAt.isNull())
              ..orderBy([
                OrderingTerm.desc(_db.adaptationProposals.decidedAt),
                OrderingTerm.desc(_db.adaptationProposals.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    final proposal = override?.readTable(_db.adaptationProposals);
    final planJson = override?.readTable(_db.adaptationOverrides).planJson;
    final weekStart = proposal == null
        ? null
        : DateTime.tryParse(proposal.weekStartIso);
    final scheduledDate = DateTime.tryParse(schedule.dateIso);
    final isCurrentWeekOverride =
        weekStart != null &&
        scheduledDate != null &&
        !scheduledDate.isBefore(weekStart) &&
        !scheduledDate.isAfter(weekStart.add(const Duration(days: 6)));
    if (planJson != null && isCurrentWeekOverride) {
      return _fromAdapted(AdaptedSessionPlan.decode(planJson));
    }
    return resolveProgramDay(
      schedule.programDayId,
      templateOverride: schedule.templateIdOverride,
    );
  }

  PlannedSessionSnapshot _fromAdapted(AdaptedSessionPlan plan) =>
      PlannedSessionSnapshot(
        name: plan.name,
        exercises: [
          for (final exercise in plan.exercises)
            PlannedExerciseSnapshot(
              exerciseId: exercise.exerciseId,
              orderIndex: exercise.orderIndex,
              restSeconds: exercise.restSeconds,
              slotRole: exercise.slotRole,
              trainingMethod: exercise.trainingMethod,
              why: exercise.why,
              programExerciseSlotId: exercise.programExerciseSlotId,
              rotationAssignmentId: exercise.rotationAssignmentId,
              equipmentVariant: exercise.equipmentVariant,
              sessionSegment: exercise.sessionSegment,
              supersetGroup: exercise.supersetGroup,
              waveIndex: exercise.waveIndex,
              waveCount: exercise.waveCount,
              allowsAdvancedTechniques: exercise.allowsAdvancedTechniques,
              sets: [
                for (final set in exercise.sets)
                  PlannedSetSnapshot(
                    index: set.index,
                    repsMin: set.repsMin,
                    repsMax: set.repsMax,
                    weightKg: set.weightKg,
                    rpeX10: set.rpeX10,
                    rir: set.rir,
                    percentOf1Rm: set.percentOf1Rm,
                    isWarmup: set.isWarmup,
                    setType: set.setType,
                    intent: set.intent,
                    setTypeMetaJson: set.setTypeMetaJson,
                  ),
              ],
            ),
        ],
      );

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
          trainingMethod: selected.isEmpty
              ? SlotTrainingMethod.straightSets.id
              : SetPrescriptionMetadata.decode(
                          selected.first.metaJson,
                        )['trainingMethod']
                        as String? ??
                    SlotTrainingMethod.straightSets.id,
          why: 'Copied from the workout template when this session started.',
          equipmentVariant: selected.isEmpty
              ? null
              : CalisthenicsSetPlan.decode(selected.first.metaJson)?.variant ??
                    SetPrescriptionMetadata.decode(
                          selected.first.metaJson,
                        )['equipmentVariant']
                        as String?,
          supersetGroup: te.supersetGroup,
          allowsAdvancedTechniques: false,
          sets: [
            for (final (index, set) in selected.indexed)
              _templateSetSnapshot(index, set, te),
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
    if (templateId != null) {
      return resolveTemplate(templateId);
    }

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
      var why =
          pde.prescriptionWhy ??
          (assignment?.reason == null
              ? prescription.why
              : '${assignment!.reason} ${prescription.why}');
      final isFirstHeavy = role.isHeavy && !sawHeavyLiftInSession;
      if (role.isHeavy) {
        sawHeavyLiftInSession = true;
      }
      final decodedPrescription = SlotPrescriptionCodec.decode(
        pde.prescriptionCodecJson,
      );
      final (
        checkedPrescription,
        isolationPrimer,
        rejectedCompression,
      ) = _checkedTimeSavingPrescription(
        pde,
        program,
        catalog,
        role,
        weekPrescription,
        decodedPrescription,
      );
      if (rejectedCompression) {
        why =
            'Time-saving work was replaced with controlled straight sets '
            'because the current exercise or training week does not meet its requirements.';
      }
      final workingSets = method == SlotTrainingMethod.maxEffort
          ? _maxEffortWorkingSets()
          : checkedPrescription != null
          ? _setsFromPrescription(checkedPrescription)
          : _setsFromPrescription(prescription.prescription);
      final warmupEligible =
          method == SlotTrainingMethod.maxEffort ||
          _hasAutomaticWarmups(pde.variantConfigJson) ||
          isolationPrimer;
      final warmupTarget = method == SlotTrainingMethod.maxEffort
          ? 0.90
          : (prescription.prescription.segments.isEmpty
                ? null
                : workingSets.firstOrNull?.percentOf1Rm);
      final warmups = warmupEligible
          ? _warmupSnapshots(
              role: role,
              mechanics: catalog.mechanics,
              modality: catalog.modality,
              targetPercentOf1Rm: warmupTarget,
              isFirstHeavyLiftInSession: isFirstHeavy,
              singleIsolationPrimer: isolationPrimer,
            )
          : const <PlannedSetSnapshot>[];
      final sets = [...warmups, ...workingSets].indexed
          .map((entry) => entry.$2.copyWith(index: entry.$1 + 1))
          .toList(growable: false);

      exercises.add(
        PlannedExerciseSnapshot(
          exerciseId: exerciseId,
          orderIndex: pde.orderIndex,
          restSeconds: rejectedCompression
              ? checkedPrescription!.segments.first.restSeconds!
              : pde.restSeconds ?? prescription.restSeconds,
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

  /// Read-only preparation used by previews, phone starts and watch libraries.
  Future<PlannedSessionSnapshot> prepare(
    PlannedSessionSnapshot plan, {
    DateTime? at,
  }) => _prepareTargets(plan, at ?? const SystemClock().now());

  Future<int> materialize(
    PlannedSessionSnapshot plan, {
    DateTime? startedAt,
    int? gymId,
    String? notes,
    String? sessionUuid,
  }) async {
    plan = await _prepareTargets(plan, startedAt ?? const SystemClock().now());
    final bodyweight = await MeasurementsRepository(_db).latestBodyweightKg();
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
        final catalog = await (_db.select(
          _db.exerciseCatalog,
        )..where((t) => t.id.equals(exercise.exerciseId))).getSingle();
        final includesBodyweight =
            catalog.supportsWeightedBodyweight ||
            isMachineAssistedPullup(catalog.slug);
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
                  bodyweightKg: Value(includesBodyweight ? bodyweight : null),
                  isWarmup: Value(set.isWarmup),
                  isCompleted: const Value(false),
                  setType: Value(set.setType),
                  setTypeMetaJson: Value(set.setTypeMetaJson),
                  plannedRepsMin: Value(set.repsMin),
                  durationSeconds: Value(
                    CalisthenicsSetPlan.decode(
                      set.setTypeMetaJson,
                    )?.durationSeconds,
                  ),
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
      await WorkoutReportJournal(
        _db,
        const SystemClock(),
      ).capture(sessionId, prescribed: true);
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
            intent: _intentFromRir(
              explicit.targetRir ??
                  (explicit.targetRpe == null
                      ? null
                      : 10 - explicit.targetRpe!),
            ),
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
    4 => Intent.rir4,
    5 => Intent.technical,
    _ => Intent.rir2,
  };

  static bool _hasAutomaticWarmups(String? raw) {
    if (raw == null || raw.isEmpty) {
      return false;
    }
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
    bool singleIsolationPrimer = false,
  }) {
    final steps = WarmupResolver.resolve(
      role: role,
      mechanics: mechanics,
      modality: modality,
      targetPercentOf1Rm: targetPercentOf1Rm,
      isFirstHeavyLiftInSession: isFirstHeavyLiftInSession,
      singleIsolationPrimer: singleIsolationPrimer,
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
          setTypeMetaJson: jsonEncode({'automaticWarmup': true}),
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
      final meta = {...segment.meta};
      if (segment.setType.id == 'myo_reps' && meta['miniSets'] is num) {
        meta['plannedMiniSets'] = meta['miniSets'];
        meta['miniSets'] = <int>[];
      }
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
            setTypeMetaJson: meta.isEmpty ? null : jsonEncode(meta),
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
