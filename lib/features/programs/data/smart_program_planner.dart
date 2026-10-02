import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/crossfit_program_planner.dart';
import 'package:herculex/features/programs/domain/crossfit_scaling_policy.dart';
import 'package:herculex/features/programs/domain/exercise_programming_eligibility.dart';
import 'package:herculex/features/programs/domain/exercise_scaling_resolver.dart';
import 'package:herculex/features/programs/domain/exercise_scorer.dart';
import 'package:herculex/features/programs/domain/gpp_program_planner.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';
import 'package:herculex/features/programs/domain/program_guardrails.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/rotation_policy.dart';
import 'package:herculex/features/programs/domain/selection_explanation.dart';
import 'package:herculex/features/programs/domain/session_segment.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/programs/domain/slot_prescription_codec.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/domain/warmup_resolver.dart';
import 'package:herculex/features/workouts/domain/workout_duration_estimator.dart';

part 'smart_program_planner/anchor_lock.part.dart';
part 'smart_program_planner/selection_explanation_writer.part.dart';
part 'smart_program_planner/slot_candidate_resolution.part.dart';

class SmartProgramConfiguration {
  const SmartProgramConfiguration({
    required this.goal,
    required this.experience,
    this.buildMode = ProgramBuildMode.smart,
    this.gymId,
    this.mainMethodByDayLabel = const {},
    this.dayRoles = const {},
    this.musclePriorities = const {},
    this.muscleVolumeWeights = const {},
    this.weeklySetCaps = const {},
    this.muscleFocusWave = MuscleFocusWave.steady,
    this.waveOverrideWeeks,
    this.trainingStyle = TrainingStyle.weightlifting,
    this.includeGppConditioning,
    this.workoutDurationMinutes = 60,
    this.allowTimeSavingSetTechniques = false,
    this.includeAutomaticWarmups = false,
    this.primaryLiftSpecialization,
    this.excludedMuscles = const {},
  });

  final TrainingGoal goal;
  final ExperienceLevel experience;
  final ProgramBuildMode buildMode;
  final int? gymId;

  /// Per-day main-slot override. Supplemental/accessory slots keep their own
  /// goal-appropriate method, so one Max Effort lift never turns the entire
  /// day into max work.
  final Map<String, SlotTrainingMethod> mainMethodByDayLabel;

  /// The stress role is a property of the *day*, not a global intensity
  /// multiplier. This is what lets Concurrent mean e.g. Full Body A/B
  /// (volume/intensity) or A/B/C (heavy/medium/light).
  final Map<String, DayStressRole> dayRoles;

  /// An explicit plan from the builder takes precedence over an optional AI
  /// physique profile. Values use the same safe high/medium/maintenance
  /// vocabulary as the persisted profile.
  final Map<String, String> musclePriorities;
  final Map<String, double> muscleVolumeWeights;

  /// Per-muscle weekly hard-set ceilings selected by the user (10/15/20).
  final Map<String, int> weeklySetCaps;
  final MuscleFocusWave muscleFocusWave;

  /// Optional user-facing exercise-rotation interval. `null` keeps the
  /// model-specific policy; the override is intentionally not used for block
  /// phases or Max Effort, where the rotation is part of the method itself.
  final int? waveOverrideWeeks;
  final TrainingStyle trainingStyle;

  /// Explicit opt-in/out for a short GPP conditioning finish. `null` follows
  /// the selected training style, so existing programs remain unchanged.
  final bool? includeGppConditioning;

  bool get shouldIncludeGppConditioning =>
      includeGppConditioning ?? trainingStyle.includesGppConditioning;

  /// A realistic cap chosen by the user. The planner only uses a time-saving
  /// technique on isolation work and only when the user explicitly permits it.
  final int workoutDurationMinutes;
  final bool allowTimeSavingSetTechniques;

  /// When enabled, the resolver prepends ramp-up sets to eligible compound
  /// barbell/dumbbell/kettlebell work. These are never counted as work sets.
  final bool includeAutomaticWarmups;
  final PrimaryLiftSpecialization? primaryLiftSpecialization;

  /// Precomputed once by the caller from
  /// `JointPainRepository.watchCurrentStatuses()` (D-07) — the planner never
  /// queries live joint-pain state itself, keeping `populate()` pure and
  /// deterministic for a fixed input.
  final Set<String> excludedMuscles;
}

/// Deterministic local planner used by both Smart and Guided builder modes.
/// Gemini may provide muscle priorities, but final exercise selection remains
/// here where equipment, preferences and safety rules are enforceable.
class SmartProgramPlanner {
  SmartProgramPlanner(this._db);

  final AppDatabase _db;

  Future<void> populate(
    int programId,
    SmartProgramConfiguration configuration,
  ) async {
    final program = await (_db.select(
      _db.programs,
    )..where((t) => t.id.equals(programId))).getSingle();
    // Persist the generation-time opt-in onto the durable Programs row so it
    // survives past generation for 18-03's live-workout gate and 18-04's
    // resolver to read (PRES-04).
    await (_db.update(
      _db.programs,
    )..where((t) => t.id.equals(programId))).write(
      ProgramsCompanion(
        allowTimeSavingSetTechniques: Value(
          configuration.allowTimeSavingSetTechniques,
        ),
      ),
    );
    final model = PeriodizationModel.fromId(program.periodizationModel);
    final weeks =
        await (_db.select(_db.programWeeks)
              ..where((t) => t.programId.equals(programId))
              ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
            .get();
    final catalog =
        await (_db.select(_db.exerciseCatalog)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.name)]))
            .get();
    if (catalog.isEmpty) {
      throw StateError('The exercise catalogue is empty.');
    }
    final affinities = await _affinities(programId);
    final equipment = await _equipment(configuration.gymId);
    final physiquePriorities = configuration.musclePriorities.isNotEmpty
        ? configuration.musclePriorities
        : await _physiquePriorities();
    final catalogById = {for (final exercise in catalog) exercise.id: exercise};
    final catalogBySlug = {
      for (final exercise in catalog)
        if (exercise.slug != null && exercise.slug!.isNotEmpty)
          exercise.slug!: exercise,
    };
    final (completedExerciseSlugs, completedMovementSlugs) =
        await _completedMovementHistory(catalogById);
    final slotCache = <String, List<_ResolvedSmartSlot>>{};

    await _db.transaction(() async {
      await (_db.update(
        _db.programs,
      )..where((t) => t.id.equals(programId))).write(
        ProgramsCompanion(
          buildMode: Value(configuration.buildMode.id),
          trainingGoal: Value(configuration.goal.id),
          experienceLevel: Value(configuration.experience.id),
        ),
      );

      // Regenerating the same program (D-12: e.g. a new joint-pain exclusion
      // discovered after week 1) must not leave stale ProgramExerciseSlots
      // behind — `_createStableSlots` always inserts fresh rows keyed by
      // `(programId, slotKey)`, so a prior generation's rows would otherwise
      // violate that unique constraint. Cascades to
      // ProgramSlotPoolMembers/RotationAssignments/ProgramSlotExplanations.
      await (_db.delete(
        _db.programExerciseSlots,
      )..where((t) => t.programId.equals(programId))).go();

      for (final week in weeks) {
        final weeklySetsByMuscle = <String, int>{};
        final days =
            await (_db.select(_db.programDays)
                  ..where((t) => t.programWeekId.equals(week.id))
                  ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
                .get();
        // D-06/CF-03: back-to-back CrossFit/GPP day-spacing is advisory-only
        // and weekly-mode-only (CrossfitScalingPolicy.recoveryReserveWarning
        // docs). Accumulated across this week's non-rest days, keyed by
        // dayOfWeek so adjacency mirrors SplitDaySpec.dayOfWeek.
        final labelsByDayOfWeek = <int, String>{};
        int? firstSegmentDaySlotId;
        for (final day in days) {
          if (day.isRest || day.templateId != null) continue;
          final inferredStress = _stressRole(
            splitType: program.splitType,
            label: day.slotLabel ?? day.name,
            orderIndex: day.orderIndex,
            daysPerWeek: program.daysPerWeek ?? days.length,
            model: model,
          );
          final stress =
              configuration.dayRoles[day.slotLabel ?? day.name] ??
              inferredStress;
          await (_db.update(_db.programDays)..where((t) => t.id.equals(day.id)))
              .write(ProgramDaysCompanion(stressRole: Value(stress.id)));

          final label = day.slotLabel ?? day.name;
          labelsByDayOfWeek[day.dayOfWeek] = label;
          // CrossFit/GPP days re-derive their needs every week (metcon
          // format rotates via CrossfitProgramPlanner's variationSeed), so
          // their cache key must be week-scoped too — otherwise every week
          // after the first silently reuses week 1's cached slot list and
          // the format never actually rotates.
          final usesWeeklySegments =
              configuration.trainingStyle.isConditioningFirst ||
              label.trim().toLowerCase() == 'gpp';
          final cacheKey = usesWeeklySegments
              ? '$label|${stress.id}|${week.weekIndex}'
              : '$label|${stress.id}';
          var slots = slotCache[cacheKey];
          if (slots == null) {
            slots = await _createStableSlots(
              program: program,
              weeks: weeks,
              dayLabel: label,
              stressRole: stress,
              catalog: catalog,
              affinities: affinities,
              equipment: equipment,
              configuration: configuration,
              model: model,
              physiquePriorities: physiquePriorities,
              completedExerciseSlugs: completedExerciseSlugs,
              completedMovementSlugs: completedMovementSlugs,
              catalogBySlug: catalogBySlug,
              weekIndex: week.weekIndex,
            );
            slotCache[cacheKey] = slots;
          }
          if (usesWeeklySegments &&
              firstSegmentDaySlotId == null &&
              slots.isNotEmpty &&
              slots.first.id != -1) {
            firstSegmentDaySlotId = slots.first.id;
          }

          // The new builder writes a stable owned blueprint. Re-running the
          // planner replaces only untouched inline program content.
          await (_db.delete(
            _db.programDayExercises,
          )..where((t) => t.programDayId.equals(day.id))).go();

          // Pass 1: compute each slot's target/timePlan, tracking movement
          // order (`sawHeavyLift`) the same way `resolveProgramDay`'s
          // materialize-time resolver does, without inserting yet.
          var sawHeavyLift = false;
          final dayPlans = <_DaySlotPlan>[];
          for (final slot in slots) {
            final assignment = slot.assignments[week.weekIndex];
            final exerciseId = assignment?.exerciseId ?? slot.anchorExerciseId;
            if (exerciseId == null) continue;
            var target = _targetFor(
              slot.role,
              slot.method,
              slot.priorityLevel,
              configuration.muscleVolumeWeights[slot.muscleId],
            );
            final focusNote = _focusNoteForWeek(
              configuration: configuration,
              muscleId: slot.muscleId,
              weekIndex: week.weekIndex,
            );
            if (focusNote.isHighFocus) {
              target = target.copyWith(sets: target.sets + 1);
            } else if (focusNote.isLightFocus && !slot.role.isHeavy) {
              target = target.copyWith(
                sets: (target.sets - 1).clamp(1, target.sets).toInt(),
              );
            }
            final weeklyCap = configuration.weeklySetCaps[slot.muscleId];
            if (weeklyCap != null) {
              final assigned = weeklySetsByMuscle[slot.muscleId] ?? 0;
              final remaining = weeklyCap - assigned;
              if (remaining <= 0 && slot.role != SlotRole.main) continue;
              target = target.copyWith(sets: remaining.clamp(1, target.sets));
            }
            // CrossFit metcon slots bypass the normal per-rep-target time
            // plan entirely: a metcon's duration comes from its capped
            // segment estimator (below), not a sets×reps formula, and its
            // prescription is a single AMRAP/EMOM/For Time work segment
            // rather than a straight-sets/myo-reps target (21-06).
            final timePlan = slot.metconFormat != null
                ? _TimePlan(
                    // A minimal placeholder — the real duration comes from
                    // the capped-segment estimator below, not sets/reps.
                    target: const _Target(1, 1, 1, 0, 0),
                    setType: slot.metconFormat!,
                    segment: slot.segment,
                    metconCapSeconds: slot.metconCapSeconds,
                    why: 'CrossFit metcon, ${slot.metconFormat!.label} format.',
                    prescriptionCodecJson: SlotPrescriptionCodec.encode(
                      SlotPrescription(
                        name: 'Metcon',
                        segments: [
                          WorkSegment(
                            sets: 1,
                            repsMin: 1,
                            setType: slot.metconFormat!,
                            meta: {
                              if (slot.metconCapSeconds != null)
                                'capSeconds': slot.metconCapSeconds,
                              if (slot.metconMinutes != null)
                                'minutes': slot.metconMinutes,
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : _timePlanFor(
                    role: slot.role,
                    target: target,
                    configuration: configuration,
                  );
            final isFirstHeavy = slot.role.isHeavy && !sawHeavyLift;
            if (slot.role.isHeavy) sawHeavyLift = true;
            dayPlans.add(
              _DaySlotPlan(
                slot: slot,
                exerciseId: exerciseId,
                target: target,
                timePlan: timePlan,
                isFirstHeavy: isFirstHeavy,
                focusNote: focusNote,
              ),
            );
          }

          // Between pass 1 and pass 2: trim accessory/isolation slots until
          // the day's projected duration fits the user's time budget (D-05,
          // D-06, D-07), or no more trimmable slots remain. Never trims
          // SlotRole.main/supplemental.
          final budget = Duration(
            minutes: (configuration.workoutDurationMinutes * 1.10).ceil(),
          );
          bool isTrimmableRole(SlotRole role) =>
              role == SlotRole.isolation || role == SlotRole.accessory;
          while (_estimateDayDuration(dayPlans, catalogById) > budget) {
            // A metcon slot's duration is fixed (capped-segment estimate),
            // never per-rep-trimmed like a normal accessory slot (21-06).
            final shrinkable = dayPlans.where(
              (plan) =>
                  isTrimmableRole(plan.slot.role) &&
                  plan.timePlan.target.sets > 1 &&
                  plan.timePlan.segment != SessionSegment.metcon,
            );
            final isolationShrinkable = shrinkable.where(
              (plan) => plan.slot.role == SlotRole.isolation,
            );
            final shrinkTarget = isolationShrinkable.isNotEmpty
                ? isolationShrinkable.first
                : (shrinkable.isNotEmpty ? shrinkable.first : null);
            if (shrinkTarget != null) {
              shrinkTarget.timePlan = shrinkTarget.timePlan.copyWith(
                target: shrinkTarget.timePlan.target.copyWith(
                  sets: shrinkTarget.timePlan.target.sets - 1,
                ),
              );
              continue;
            }
            final trimmable = dayPlans.where(
              (plan) =>
                  isTrimmableRole(plan.slot.role) &&
                  plan.timePlan.segment != SessionSegment.metcon,
            );
            final isolationTrimmable = trimmable.where(
              (plan) => plan.slot.role == SlotRole.isolation,
            );
            final dropTarget = isolationTrimmable.isNotEmpty
                ? isolationTrimmable.first
                : (trimmable.isNotEmpty ? trimmable.first : null);
            if (dropTarget == null) break;
            dayPlans.remove(dropTarget);
          }

          // Pass 2: insert exactly as the previous single-pass code did, now
          // sourced from the post-trim plan list.
          final metconGroupIds = <String, int>{};
          for (final plan in dayPlans) {
            final slot = plan.slot;
            final exerciseId = plan.exerciseId;
            final target = plan.target;
            final timePlan = plan.timePlan;
            final focusNote = plan.focusNote;
            final supersetGroup = slot.metconGroupKey == null
                ? null
                : metconGroupIds.putIfAbsent(
                    slot.metconGroupKey!,
                    () => metconGroupIds.length + 1,
                  );
            await _db
                .into(_db.programDayExercises)
                .insert(
                  ProgramDayExercisesCompanion.insert(
                    programDayId: day.id,
                    exerciseId: exerciseId,
                    orderIndex: slot.orderIndex,
                    targetSets: Value(timePlan.target.sets),
                    targetRepsMin: Value(timePlan.target.repsMin),
                    targetRepsMax: Value(timePlan.target.repsMax),
                    targetRir: Value(timePlan.target.rir),
                    targetRpe: Value((10 - timePlan.target.rir)),
                    restSeconds: Value(target.restSeconds),
                    setType: Value(timePlan.setType.id),
                    slotRole: Value(slot.role.id),
                    sessionSegment: Value(slot.segment?.id),
                    supersetGroup: Value(supersetGroup),
                    trainingMethod: Value(slot.method.id),
                    equipmentVariant: Value(
                      _equipmentVariantFor(
                        catalogById[exerciseId],
                        slot.loadingPreference,
                      ),
                    ),
                    programExerciseSlotId: Value(slot.id),
                    prescriptionWhy: Value(
                      '${slot.why}${focusNote.message}${timePlan.why}',
                    ),
                    prescriptionCodecJson: Value(
                      timePlan.prescriptionCodecJson,
                    ),
                    variantConfigJson: Value(
                      configuration.includeAutomaticWarmups
                          ? jsonEncode({'autoWarmups': true})
                          : null,
                    ),
                  ),
                );
            weeklySetsByMuscle[slot.muscleId] =
                (weeklySetsByMuscle[slot.muscleId] ?? 0) + target.sets;
          }
        }

        final recoveryWarnings = CrossfitScalingPolicy.recoveryReserveWarning(
          labelsByDayOfWeek: labelsByDayOfWeek,
        );
        if (recoveryWarnings.isNotEmpty && firstSegmentDaySlotId != null) {
          final existing = await (_db.select(_db.programSlotExplanations)..where(
            (t) =>
                t.slotId.equals(firstSegmentDaySlotId!) &
                t.weekIndex.equals(week.weekIndex),
          )).getSingleOrNull();
          if (existing != null) {
            await (_db.update(_db.programSlotExplanations)
                  ..where((t) => t.id.equals(existing.id)))
                .write(
                  ProgramSlotExplanationsCompanion(
                    rationale: Value(
                      '${existing.rationale} ${recoveryWarnings.first}',
                    ),
                  ),
                );
          }
        }
      }
    });
  }

  Future<List<_ResolvedSmartSlot>> _createStableSlots({
    required ProgramData program,
    required List<ProgramWeekData> weeks,
    required String dayLabel,
    required DayStressRole stressRole,
    required List<ExerciseCatalogData> catalog,
    required Map<int, int> affinities,
    required _EquipmentProfile equipment,
    required SmartProgramConfiguration configuration,
    required PeriodizationModel model,
    required Map<String, String> physiquePriorities,
    required Set<String> completedExerciseSlugs,
    required Set<String> completedMovementSlugs,
    required Map<String, ExerciseCatalogData> catalogBySlug,
    required int weekIndex,
  }) async {
    final needs = _needsFor(
      dayLabel,
      primaryLiftSpecialization: configuration.primaryLiftSpecialization,
      trainingStyle: configuration.trainingStyle,
      includeGppConditioning: configuration.shouldIncludeGppConditioning,
      experience: configuration.experience,
      weekIndex: weekIndex,
    );
    // CrossFit/GPP days re-derive their needs every week (metcon format
    // rotates via variationSeed), so their slotKey must be week-scoped too —
    // otherwise the second week's insert collides with the first week's
    // ProgramExerciseSlots.slotKey unique constraint. Mirrors the slotCache
    // key change in populate().
    final usesWeeklySegments =
        configuration.trainingStyle.isConditioningFirst ||
        dayLabel.trim().toLowerCase() == 'gpp';
    final catalogById = {for (final exercise in catalog) exercise.id: exercise};
    final result = <_ResolvedSmartSlot>[];
    final used = <int>{};
    final lockedAnchors = <String, int>{};
    // D-06 hard rule tracking: per-metcon-group movement/advanced-movement
    // counts, incremented once per resolved metcon slot below. Scoped to
    // this single call (one day/week resolution), matching `used`.
    final metconGroupMovementCount = <String, int>{};
    final metconGroupAdvancedCount = <String, int>{};

    for (final (order, need) in needs.indexed) {
      var method = _methodFor(
        role: need.role,
        stressRole: stressRole,
        goal: configuration.goal,
        experience: configuration.experience,
        model: model,
      );
      // Categorical guard closing RESEARCH.md's Pitfall 2 (T-21-01): every
      // segment-tagged (CrossFit/GPP) slot is forced to `technique`
      // regardless of role, periodization model, or day-label override, so
      // no future codepath can reopen Dynamic-Effort eligibility for segment
      // content even if a role mistake is made elsewhere.
      if (need.segment != null) method = SlotTrainingMethod.technique;
      final override = configuration.mainMethodByDayLabel[dayLabel];
      if (need.role == SlotRole.main && override != null) {
        // A repeated Upper/Lower/PPL volume day stays a volume day even when
        // its intensity counterpart uses Max Effort.
        if (override == SlotTrainingMethod.dynamicEffort &&
            (configuration.experience == ExperienceLevel.novice ||
                model == PeriodizationModel.linear)) {
          method = SlotTrainingMethod.straightSets;
        } else if (override == SlotTrainingMethod.maxEffort &&
            stressRole == DayStressRole.volume) {
          method = _methodFor(
            role: need.role,
            stressRole: stressRole,
            goal: configuration.goal,
            experience: configuration.experience,
            model: PeriodizationModel.none,
          );
        } else {
          method = override;
        }
      }

      var candidates = catalog.where((exercise) {
        if (used.contains(exercise.id)) return false;
        if (!equipment.allows(exercise)) return false;
        if (!_isEligibleForAutomaticProgramming(exercise, configuration)) {
          return false;
        }
        if (!ExerciseProgrammingEligibility.verifyPrerequisites(
          prerequisiteSlugsJson: exercise.prerequisiteSlugs,
          userExperience: configuration.experience,
          completedExerciseSlugs: completedExerciseSlugs,
          completedMovementSlugs: completedMovementSlugs,
          catalogBySlug: catalogBySlug,
        )) {
          return false;
        }
        final patternMatches =
            need.pattern == null || exercise.movementPattern == need.pattern;
        final muscleMatches =
            need.muscle == null ||
            exercise.primaryMuscle.toLowerCase().contains(need.muscle!);
        if (!patternMatches || !muscleMatches) return false;
        final mask = SlotRoleEligibility.derive(
          mechanics: exercise.mechanics,
          modality: exercise.modality,
          cnsScore: exercise.cnsScore,
          loggingMetric: exercise.loggingMetric,
          category: exercise.category,
        );
        if (!SlotRoleEligibility.allows(mask, need.role)) return false;
        if (method == SlotTrainingMethod.maxEffort &&
            exercise.maxEffortEligibility != MaxEffortEligibility.eligible.id) {
          return false;
        }
        return true;
      }).toList();
      if (candidates.isEmpty) {
        // Never leave a Smart slot empty: keep the role gate, then relax the
        // requested pattern/muscle. Equipment remains a hard filter in scorer.
        candidates = catalog.where((exercise) {
          if (used.contains(exercise.id)) return false;
          if (!equipment.allows(exercise)) return false;
          // Pattern/muscle may relax only after this hard curation gate. In
          // particular, a fallback must never re-introduce advanced,
          // specialty basic-style, or manual-only exercises.
          if (!_isEligibleForAutomaticProgramming(exercise, configuration)) {
            return false;
          }
          // Prerequisites are one of the five named hard filters (D-02) — it
          // must never relax in the fallback, unlike pattern/muscle.
          if (!ExerciseProgrammingEligibility.verifyPrerequisites(
            prerequisiteSlugsJson: exercise.prerequisiteSlugs,
            userExperience: configuration.experience,
            completedExerciseSlugs: completedExerciseSlugs,
            completedMovementSlugs: completedMovementSlugs,
            catalogBySlug: catalogBySlug,
          )) {
            return false;
          }
          final mask = SlotRoleEligibility.derive(
            mechanics: exercise.mechanics,
            modality: exercise.modality,
            cnsScore: exercise.cnsScore,
            loggingMetric: exercise.loggingMetric,
            category: exercise.category,
          );
          return SlotRoleEligibility.allows(mask, need.role) &&
              (method != SlotTrainingMethod.maxEffort ||
                  exercise.maxEffortEligibility ==
                      MaxEffortEligibility.eligible.id);
        }).toList();
      }

      if (candidates.isEmpty) {
        // Both the primary and pattern/muscle-relaxed fallback passes came
        // up empty — every hard filter (injury/pain, equipment, style,
        // experience, prerequisites) is legitimately exhausted for this
        // slot. Consult the scaling ladder for a safer regression (D-03)
        // before accepting the slot is genuinely, safely empty (D-01):
        // this one slot no longer aborts the whole populate() transaction.
        final resolution = _resolveEmptyCandidatePool(
          needPattern: need.pattern,
          catalog: catalog,
          equipment: equipment,
          configuration: configuration,
          completedExerciseSlugs: completedExerciseSlugs,
          completedMovementSlugs: completedMovementSlugs,
          catalogBySlug: catalogBySlug,
        );
        if (!resolution.isFilled) {
          // The slot still needs a stable ProgramExerciseSlots row (so the
          // ProgramSlotExplanations FK below has something to reference)
          // even though it has no pool members, no rotation assignments,
          // and no ProgramDayExercises row. Every field here describes the
          // SLOT, not the chosen exercise, so it is computable identically
          // to the filled path below — mirror that insert exactly.
          var emptyPolicy = RotationPolicy.forSlot(
            model: method == SlotTrainingMethod.maxEffort
                ? PeriodizationModel.maxEffort
                : model,
            role: need.role,
            blockPhase: weeks.firstOrNull?.blockPhase,
          );
          if (configuration.waveOverrideWeeks != null &&
              method != SlotTrainingMethod.maxEffort &&
              model != PeriodizationModel.block) {
            emptyPolicy = RotationPolicy(
              everyWeeks: configuration.waveOverrideWeeks!,
              minGapWeeks: emptyPolicy.minGapWeeks,
              minPoolSize: emptyPolicy.minPoolSize,
              tier: emptyPolicy.tier,
              lockedInPhase: emptyPolicy.lockedInPhase,
              forceOnPhaseChange: emptyPolicy.forceOnPhaseChange,
            );
          }
          if (method == SlotTrainingMethod.maxEffort &&
              need.role == SlotRole.main &&
              configuration.experience == ExperienceLevel.advanced) {
            emptyPolicy = const RotationPolicy(
              everyWeeks: 1,
              minGapWeeks: 4,
              minPoolSize: 3,
            );
          }
          final emptySlotKey = _slug(
            usesWeeklySegments
                ? '$dayLabel-${stressRole.id}-${need.role.id}-$order-w$weekIndex'
                : '$dayLabel-${stressRole.id}-${need.role.id}-$order',
          );
          final emptySlotId = await _db
              .into(_db.programExerciseSlots)
              .insert(
                ProgramExerciseSlotsCompanion.insert(
                  programId: program.id,
                  slotKey: emptySlotKey,
                  daySlotLabel: dayLabel,
                  orderIndex: order,
                  role: Value(need.role.id),
                  movementPattern: Value(need.pattern),
                  primaryMuscle: Value(need.muscle),
                  trainingMethod: Value(method.id),
                  sessionSegment: Value(need.segment?.id),
                  rotationPolicyJson: Value(
                    jsonEncode({
                      'everyWeeks': emptyPolicy.everyWeeks,
                      'minGapWeeks': emptyPolicy.minGapWeeks,
                      'minPoolSize': emptyPolicy.minPoolSize,
                      'tier': emptyPolicy.tier.id,
                    }),
                  ),
                  fatigueBudget: Value(
                    method == SlotTrainingMethod.maxEffort ? 8 : 3,
                  ),
                  waveOverrideWeeks: Value(configuration.waveOverrideWeeks),
                ),
              );
          await _writeSlotExplanations(
            db: _db,
            slotId: emptySlotId,
            weeks: weeks,
            assignments: const {},
            emptyExplanation: resolution,
          );
          result.add(
            _ResolvedSmartSlot.empty(
              orderIndex: order,
              role: need.role,
              method: method,
              explanation: resolution,
            ),
          );
          continue;
        }
        candidates = [catalogById[resolution.exerciseId]!];
      }

      // A specialization may express a preferred *basic* movement. It is a
      // preference after all hard eligibility gates, so a gym that cannot
      // support it still receives a safe, eligible squat pattern instead.
      if (need.preferredSlugs.isNotEmpty) {
        final preferred = candidates
            .where(
              (exercise) => need.preferredSlugs.contains(exercise.movementSlug),
            )
            .toList(growable: false);
        if (preferred.isNotEmpty) candidates = preferred;
      }

      // D-06 hard rule: never let the scorer be offered a second
      // advanced/just-unlocked movement for the same metcon group once one
      // is already committed. This is a real candidate-pool substitution,
      // not a passive/logged-only check -- it only applies when a safe
      // (non-advanced) alternative actually exists in this slot's own pool;
      // otherwise `candidates` is left as-is and the forced exception is
      // recorded explicitly below once `complexityCheck` runs.
      if (need.segment == SessionSegment.metcon &&
          need.metconGroupKey != null &&
          (metconGroupAdvancedCount[need.metconGroupKey!] ?? 0) >= 1) {
        final safeCandidates = candidates
            .where((exercise) => !_isCrossfitAdvancedOrJustUnlocked(exercise))
            .toList(growable: false);
        if (safeCandidates.isNotEmpty) candidates = safeCandidates;
      }

      var policy = RotationPolicy.forSlot(
        model: method == SlotTrainingMethod.maxEffort
            ? PeriodizationModel.maxEffort
            : model,
        role: need.role,
        blockPhase: weeks.firstOrNull?.blockPhase,
      );
      if (configuration.waveOverrideWeeks != null &&
          method != SlotTrainingMethod.maxEffort &&
          model != PeriodizationModel.block) {
        policy = RotationPolicy(
          everyWeeks: configuration.waveOverrideWeeks!,
          minGapWeeks: policy.minGapWeeks,
          minPoolSize: policy.minPoolSize,
          tier: policy.tier,
          lockedInPhase: policy.lockedInPhase,
          forceOnPhaseChange: policy.forceOnPhaseChange,
        );
      }
      if (method == SlotTrainingMethod.maxEffort &&
          need.role == SlotRole.main &&
          configuration.experience == ExperienceLevel.advanced) {
        policy = const RotationPolicy(
          everyWeeks: 1,
          minGapWeeks: 4,
          minPoolSize: 3,
        );
      }
      final scorerPool = [
        for (final exercise in candidates)
          ScorerCandidate(
            exerciseId: exercise.id,
            name: exercise.name,
            fingerprint: MovementFingerprint(
              pattern: exercise.movementPattern,
              force: exercise.force,
              plane: exercise.plane,
              modality: exercise.modality,
              slug: exercise.movementSlug,
            ),
            mechanics: exercise.mechanics,
            cnsScore: exercise.cnsScore,
            recoveryImpact: exercise.recoveryImpact,
            eligibleRoles: SlotRoleEligibility.derive(
              mechanics: exercise.mechanics,
              modality: exercise.modality,
              cnsScore: exercise.cnsScore,
              loggingMetric: exercise.loggingMetric,
              category: exercise.category,
            ),
            affinity: affinities[exercise.id] ?? 0,
            equipmentAvailable: true,
          ),
      ];
      final loadingPreference = _loadingPreference(
        candidates: candidates,
        role: need.role,
        method: method,
        goal: configuration.goal,
        experience: configuration.experience,
      );
      final ranked =
          [
            ...ExerciseScorer.rank(
              pool: scorerPool,
              context: SlotScoringContext(
                role: need.role,
                muscleGroup: need.muscle ?? need.pattern ?? 'general',
                weekIndex: 0,
                policy: policy,
                seed: _stableSeed(
                  '${program.splitType}|${configuration.goal.id}|$dayLabel|${stressRole.id}|$order',
                ),
              ),
            ).ranked,
          ]..sort(
            (a, b) =>
                (_loadingBonus(
                          b.candidate.exerciseId,
                          candidates,
                          loadingPreference,
                        ) +
                        b.score)
                    .compareTo(
                      _loadingBonus(
                            a.candidate.exerciseId,
                            candidates,
                            loadingPreference,
                          ) +
                          a.score,
                    ),
          );
      if (ranked.isEmpty) {
        throw StateError(
          'No ${need.role.label.toLowerCase()} exercise is available for $dayLabel with the selected equipment.',
        );
      }
      final pool = ranked.take(6).toList(growable: false);
      if (method == SlotTrainingMethod.maxEffort && pool.length < 3) {
        throw StateError(
          'Max Effort rotation for $dayLabel needs at least three suitable variations.',
        );
      }
      final anchor = pool.first;
      used.add(anchor.candidate.exerciseId);
      // D-06 hard rule enforcement: run `complexityCheck` once per resolved
      // metcon slot, against this slot's just-committed anchor. The
      // group-scoped counts are incremented here (not before the guard
      // filter above) because they must reflect the slot that was actually
      // *chosen*, not merely offered.
      String? complexityExceptionNote;
      if (need.segment == SessionSegment.metcon &&
          need.metconGroupKey != null) {
        final groupKey = need.metconGroupKey!;
        final anchorExercise = candidates.firstWhere(
          (exercise) => exercise.id == anchor.candidate.exerciseId,
        );
        final isAdvanced = _isCrossfitAdvancedOrJustUnlocked(anchorExercise);
        final movementCount = (metconGroupMovementCount[groupKey] ?? 0) + 1;
        final advancedCount =
            (metconGroupAdvancedCount[groupKey] ?? 0) + (isAdvanced ? 1 : 0);
        metconGroupMovementCount[groupKey] = movementCount;
        metconGroupAdvancedCount[groupKey] = advancedCount;
        final complexityResult = CrossfitScalingPolicy.complexityCheck(
          movementCount: movementCount,
          hasAdvancedMovement: isAdvanced,
          advancedMovementCount: advancedCount,
          level: configuration.experience,
        );
        if (!complexityResult.isSafe) {
          complexityExceptionNote =
              ' ${complexityResult.rationale} No safe non-advanced '
              'substitute existed in this slot\'s own candidate pool, so '
              'this exception was accepted explicitly rather than silently.';
        }
      }
      final slotKey = _slug(
        usesWeeklySegments
            ? '$dayLabel-${stressRole.id}-${need.role.id}-$order-w$weekIndex'
            : '$dayLabel-${stressRole.id}-${need.role.id}-$order',
      );
      final slotId = await _db
          .into(_db.programExerciseSlots)
          .insert(
            ProgramExerciseSlotsCompanion.insert(
              programId: program.id,
              slotKey: slotKey,
              daySlotLabel: dayLabel,
              orderIndex: order,
              role: Value(need.role.id),
              movementPattern: Value(need.pattern),
              primaryMuscle: Value(need.muscle),
              trainingMethod: Value(method.id),
              sessionSegment: Value(need.segment?.id),
              rotationPolicyJson: Value(
                jsonEncode({
                  'everyWeeks': policy.everyWeeks,
                  'minGapWeeks': policy.minGapWeeks,
                  'minPoolSize': policy.minPoolSize,
                  'tier': policy.tier.id,
                }),
              ),
              fatigueBudget: Value(
                method == SlotTrainingMethod.maxEffort ? 8 : 3,
              ),
              waveOverrideWeeks: Value(configuration.waveOverrideWeeks),
            ),
          );
      for (final (poolIndex, scored) in pool.indexed) {
        await _db
            .into(_db.programSlotPoolMembers)
            .insert(
              ProgramSlotPoolMembersCompanion.insert(
                slotId: slotId,
                exerciseId: scored.candidate.exerciseId,
                orderIndex: Value(poolIndex),
                pinned: Value(poolIndex == 0),
              ),
            );
      }

      final assignments = <int, RotationAssignmentData>{};
      final phases = RotationPolicy.phasesFor(model, program.weeks);
      for (final week in weeks) {
        final epoch = policy.epochFor(week.weekIndex, phases: phases);
        final selected = _resolveWeeklyAssignment(
          role: need.role,
          weekIndex: week.weekIndex,
          epoch: epoch,
          pool: pool,
          lockedAnchors: lockedAnchors,
          slotKey: slotKey,
        );
        final id = await _db
            .into(_db.rotationAssignments)
            .insert(
              RotationAssignmentsCompanion.insert(
                slotId: slotId,
                exerciseId: selected.candidate.exerciseId,
                weekIndex: week.weekIndex,
                reason: selected.why,
              ),
            );
        assignments[week.weekIndex] = await (_db.select(
          _db.rotationAssignments,
        )..where((t) => t.id.equals(id))).getSingle();
      }
      await _writeSlotExplanations(
        db: _db,
        slotId: slotId,
        weeks: weeks,
        assignments: assignments,
      );

      result.add(
        _ResolvedSmartSlot(
          id: slotId,
          orderIndex: order,
          anchorExerciseId: anchor.candidate.exerciseId,
          role: need.role,
          method: method,
          poolSize: pool.length,
          priorityLevel: _priorityForExercise(
            anchor.candidate.name,
            candidates
                .firstWhere(
                  (exercise) => exercise.id == anchor.candidate.exerciseId,
                )
                .primaryMuscle,
            physiquePriorities,
          ),
          muscleId: _canonicalMuscleId(
            candidates
                .firstWhere(
                  (exercise) => exercise.id == anchor.candidate.exerciseId,
                )
                .primaryMuscle,
          ),
          why:
              '${anchor.why} ${_loadingReason(loadingPreference)} ${method.label} matches the ${stressRole.label.toLowerCase()} role of this day.'
              '${complexityExceptionNote ?? ''}',
          loadingPreference: loadingPreference,
          assignments: assignments,
          segment: need.segment,
          metconGroupKey: need.metconGroupKey,
          metconFormat: need.metconFormat,
          metconCapSeconds: need.metconCapSeconds,
          metconMinutes: need.metconMinutes,
        ),
      );
    }

    final guarded = result
        .where((slot) => slot.method == SlotTrainingMethod.maxEffort)
        .map(
          (slot) => GuardedProgramSlot(
            slotKey: '$dayLabel-${slot.orderIndex}',
            sessionKey: '$dayLabel-${stressRole.id}',
            startsAt: DateTime(2026, 1, 1),
            role: slot.role,
            method: slot.method,
            movementPattern: needs[slot.orderIndex].pattern ?? 'other',
            poolSize: slot.poolSize,
            rotates: true,
          ),
        );
    final issues = ProgramGuardrails.validateMaxEffortWeek(guarded);
    final blocking = issues.where((issue) => issue.isBlocking);
    if (blocking.isNotEmpty) throw StateError(blocking.first.message);
    return result;
  }

  /// Full "ever completed" exercise/movement history (D-08), not a
  /// recency-bounded set — mirrors `getRecentExerciseIds`'s join/where
  /// pattern without its `orderBy`/`limit(50)`.
  Future<(Set<String>, Set<String>)> _completedMovementHistory(
    Map<int, ExerciseCatalogData> catalogById,
  ) async {
    final rows =
        await (_db.selectOnly(_db.workoutExercises, distinct: true)
              ..addColumns([_db.workoutExercises.exerciseId])
              ..join([
                innerJoin(
                  _db.workoutSessions,
                  _db.workoutSessions.id.equalsExp(
                    _db.workoutExercises.sessionId,
                  ),
                ),
              ])
              ..where(_db.workoutSessions.endedAt.isNotNull()))
            .get();
    final completedIds = rows
        .map((row) => row.read(_db.workoutExercises.exerciseId)!)
        .toSet();
    final completedExerciseSlugs = {
      for (final id in completedIds)
        if (catalogById[id]?.slug != null) catalogById[id]!.slug!,
    };
    final completedMovementSlugs = {
      for (final id in completedIds)
        if (catalogById[id]?.movementSlug != null)
          catalogById[id]!.movementSlug!,
    };
    return (completedExerciseSlugs, completedMovementSlugs);
  }

  Future<Map<int, int>> _affinities(int programId) async {
    final rows = await _db.select(_db.exercisePreferences).get();
    final result = <int, int>{};
    for (final row in rows.where((r) => r.programId == null)) {
      result[row.exerciseId] = _affinityScore(row.affinity);
    }
    for (final row in rows.where((r) => r.programId == programId)) {
      result[row.exerciseId] = _affinityScore(row.affinity);
    }
    return result;
  }

  Future<Map<String, String>> _physiquePriorities() async {
    final row =
        await (_db.select(_db.physiqueProgrammingProfiles)
              ..where((t) => t.active.equals(true))
              ..orderBy([(t) => OrderingTerm.desc(t.confirmedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return const {};
    try {
      final decoded = jsonDecode(row.prioritiesJson) as Map<String, dynamic>;
      final priorities = decoded['musclePriorities'] as List? ?? const [];
      return {
        for (final item in priorities.whereType<Map>())
          if (item['muscleId'] is String && item['priority'] is String)
            item['muscleId'] as String: item['priority'] as String,
      };
    } catch (_) {
      return const {};
    }
  }

  static String _priorityForExercise(
    String exerciseName,
    String primaryMuscle,
    Map<String, String> priorities,
  ) {
    final haystack = '$exerciseName $primaryMuscle'.toLowerCase();
    const aliases = <String, List<String>>{
      'chest': ['chest', 'pec'],
      'back': ['back', 'erector'],
      'lats': ['lat'],
      'traps': ['trap'],
      'front_delts': ['front delt', 'anterior delt'],
      'side_delts': ['side delt', 'lateral delt', 'shoulder'],
      'rear_delts': ['rear delt', 'posterior delt'],
      'biceps': ['bicep'],
      'triceps': ['tricep'],
      'forearms': ['forearm'],
      'abs': ['abs', 'abdominal'],
      'obliques': ['oblique'],
      'quads': ['quad'],
      'hamstrings': ['hamstring'],
      'glutes': ['glute'],
      'calves': ['calf', 'calves'],
      'adductors': ['adductor'],
      'abductors': ['abductor'],
      'neck': ['neck'],
    };
    for (final entry in priorities.entries) {
      final terms = aliases[entry.key] ?? [entry.key.replaceAll('_', ' ')];
      if (terms.any(haystack.contains)) return entry.value;
    }
    return 'medium';
  }

  /// Decides *how* a movement should be loaded, independently of its movement
  /// pattern. A bodyweight pull-up can therefore remain calisthenics for a
  /// novice, become weighted for progressive strength work, or give way to a
  /// free-weight main lift when that is the sensible available option.
  static _LoadingPreference _loadingPreference({
    required List<ExerciseCatalogData> candidates,
    required SlotRole role,
    required SlotTrainingMethod method,
    required TrainingGoal goal,
    required ExperienceLevel experience,
  }) {
    final hasFreeWeight = candidates.any(_isFreeWeight);
    final hasCalisthenics = candidates.any(_isCalisthenics);
    final hasWeightedCalisthenics = candidates.any(_isWeightedCalisthenics);
    final wantsProgressiveExternalLoad =
        goal == TrainingGoal.strength || goal == TrainingGoal.powerbuilding;
    final isExperienced = experience != ExperienceLevel.novice;

    // Max Effort and Dynamic Effort need precise, repeatable loading. Prefer
    // barbells/dumbbells, then a valid weighted bodyweight movement only when
    // it is actually supported by the catalog.
    if (method == SlotTrainingMethod.maxEffort ||
        method == SlotTrainingMethod.dynamicEffort) {
      if (hasFreeWeight) return _LoadingPreference.freeWeight;
      if (isExperienced && hasWeightedCalisthenics) {
        return _LoadingPreference.weightedCalisthenics;
      }
      if (hasCalisthenics) return _LoadingPreference.calisthenics;
      return _LoadingPreference.flexible;
    }

    // Athletic/technique work and novice movement practice are most useful as
    // unweighted calisthenics when that option exists. Extra load is not
    // prescribed merely because a pull-up or dip happens to support it.
    if ((goal == TrainingGoal.athletic ||
            method == SlotTrainingMethod.technique ||
            experience == ExperienceLevel.novice) &&
        hasCalisthenics &&
        role != SlotRole.isolation) {
      return _LoadingPreference.calisthenics;
    }

    // For an experienced strength/powerbuilding lifter, use added weight on
    // bodyweight movements only when free-weight loading is unavailable for
    // this exact slot. This avoids turning every dip/pull-up into "weighted"
    // just because the movement permits it.
    if (role.isHeavy &&
        wantsProgressiveExternalLoad &&
        isExperienced &&
        !hasFreeWeight &&
        hasWeightedCalisthenics) {
      return _LoadingPreference.weightedCalisthenics;
    }
    if (role.isHeavy && hasFreeWeight) return _LoadingPreference.freeWeight;
    if (!hasFreeWeight && hasCalisthenics) {
      return _LoadingPreference.calisthenics;
    }
    return _LoadingPreference.flexible;
  }

  static bool _isFreeWeight(ExerciseCatalogData exercise) =>
      const {'barbell', 'dumbbell', 'kettlebell'}.contains(exercise.modality);

  static bool _isCalisthenics(ExerciseCatalogData exercise) =>
      exercise.modality == 'bodyweight';

  static bool _isWeightedCalisthenics(ExerciseCatalogData exercise) =>
      _isCalisthenics(exercise) && exercise.supportsWeightedBodyweight;

  static double _loadingBonus(
    int exerciseId,
    List<ExerciseCatalogData> candidates,
    _LoadingPreference preference,
  ) {
    final exercise = candidates.firstWhere(
      (candidate) => candidate.id == exerciseId,
    );
    return switch (preference) {
      _LoadingPreference.freeWeight when _isFreeWeight(exercise) => 2.4,
      _LoadingPreference.calisthenics when _isCalisthenics(exercise) => 2.4,
      _LoadingPreference.weightedCalisthenics
          when _isWeightedCalisthenics(exercise) =>
        2.4,
      _ => 0,
    };
  }

  static String _loadingReason(_LoadingPreference preference) =>
      switch (preference) {
        _LoadingPreference.freeWeight =>
          'Free-weight loading is preferred for this slot.',
        _LoadingPreference.calisthenics =>
          'Unweighted calisthenics is preferred for this slot.',
        _LoadingPreference.weightedCalisthenics =>
          'Weighted calisthenics is appropriate for this slot.',
        _LoadingPreference.flexible =>
          'The best available loading style was selected for this slot.',
      };

  static String? _equipmentVariantFor(
    ExerciseCatalogData? exercise,
    _LoadingPreference preference,
  ) {
    if (exercise?.modality != 'bodyweight') return null;
    if (preference == _LoadingPreference.weightedCalisthenics &&
        exercise!.supportsWeightedBodyweight) {
      return 'weighted';
    }
    if (preference == _LoadingPreference.calisthenics) return 'bodyweight';
    return null;
  }

  /// D-06 hard rule helper: an exercise counts as "advanced/just-unlocked"
  /// for the metcon stacking guard when it is explicitly tagged advanced,
  /// or when it carries a non-empty prerequisite gate (i.e. it was only
  /// just unlocked once its prerequisite was cleared). Mirrors
  /// [ExerciseScalingResolver._hasRequiredEquipment]'s decode-failure
  /// convention: a malformed `prerequisiteSlugs` JSON payload is treated
  /// as "not advanced" rather than thrown.
  static bool _isCrossfitAdvancedOrJustUnlocked(ExerciseCatalogData exercise) {
    if (exercise.programmingDifficulty == 'advanced') return true;
    final raw = exercise.prerequisiteSlugs;
    if (raw == null || raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List && decoded.isNotEmpty;
    } on FormatException {
      return false;
    }
  }

  static int _affinityScore(String value) => switch (value) {
    'never' => -1,
    'liked' => 1,
    'core' => 2,
    _ => 0,
  };

  static bool _isEligibleForAutomaticProgramming(
    ExerciseCatalogData exercise,
    SmartProgramConfiguration configuration,
  ) => ExerciseProgrammingEligibility.allows(
    experience: configuration.experience,
    style: configuration.trainingStyle,
    difficulty: exercise.programmingDifficulty,
    commonness: exercise.programmingCommonness,
    allowedTrainingStylesJson: exercise.allowedTrainingStyles,
    technicalEligibility: exercise.technicalEligibility,
    primaryMuscle: exercise.primaryMuscle,
    excludedMuscles: configuration.excludedMuscles,
  );

  Future<_EquipmentProfile> _equipment(int? requestedGymId) async {
    GymData? gym;
    if (requestedGymId != null) {
      gym = await (_db.select(
        _db.gyms,
      )..where((t) => t.id.equals(requestedGymId))).getSingleOrNull();
    } else {
      gym =
          await (_db.select(_db.gyms)
                ..where((t) => t.isDefault.equals(true))
                ..limit(1))
              .getSingleOrNull();
    }
    if (gym == null || gym.allEquipment) {
      return const _EquipmentProfile(allEquipment: true, keys: {});
    }
    final rows = await (_db.select(
      _db.gymEquipment,
    )..where((t) => t.gymId.equals(gym!.id) & t.available.equals(true))).get();
    return _EquipmentProfile(
      allEquipment: false,
      keys: rows.map((row) => row.equipmentKey).toSet(),
    );
  }

  static DayStressRole _stressRole({
    required String splitType,
    required String label,
    required int orderIndex,
    required int daysPerWeek,
    required PeriodizationModel model,
  }) {
    if (splitType == 'full_body' ||
        splitType == 'full_body_linear' ||
        splitType == 'full_body_ab' ||
        splitType == 'full_body_ab_gpp' ||
        splitType == 'abc') {
      return switch (orderIndex % 3) {
        0 => DayStressRole.intensity,
        1 => DayStressRole.volume,
        // Dynamic work is a Westside-specific method, not the default third
        // day of a linear/concurrent full-body split. Keeping this mixed
        // prevents a normal beginner program from silently becoming 8x3.
        _ => DayStressRole.mixed,
      };
    }
    if (model == PeriodizationModel.maxEffort) {
      if (splitType == 'upper_lower' && daysPerWeek >= 4) {
        return orderIndex < 2
            ? DayStressRole.intensity
            : DayStressRole.dynamicTechnique;
      }
      if (splitType == 'upper_lower_full_body') {
        return label.toLowerCase().contains('full')
            ? DayStressRole.dynamicTechnique
            : DayStressRole.intensity;
      }
    }
    if (splitType == 'upper_lower' && daysPerWeek >= 4) {
      return orderIndex < 2 ? DayStressRole.intensity : DayStressRole.volume;
    }
    if (splitType == 'ppl' && daysPerWeek >= 6) {
      return orderIndex < 3 ? DayStressRole.mixed : DayStressRole.volume;
    }
    if (splitType == 'upper_lower_full_body') {
      return label.toLowerCase().contains('full')
          ? DayStressRole.mixed
          : DayStressRole.intensity;
    }
    return DayStressRole.mixed;
  }

  static SlotTrainingMethod _methodFor({
    required SlotRole role,
    required DayStressRole stressRole,
    required TrainingGoal goal,
    required ExperienceLevel experience,
    required PeriodizationModel model,
  }) {
    if (experience == ExperienceLevel.novice ||
        model == PeriodizationModel.linear) {
      if (stressRole == DayStressRole.dynamicTechnique) {
        return SlotTrainingMethod.straightSets;
      }
    }
    if (role == SlotRole.main &&
        model == PeriodizationModel.maxEffort &&
        experience != ExperienceLevel.novice &&
        stressRole != DayStressRole.volume &&
        stressRole != DayStressRole.dynamicTechnique) {
      return SlotTrainingMethod.maxEffort;
    }
    if (model == PeriodizationModel.maxEffort &&
        experience != ExperienceLevel.novice &&
        stressRole == DayStressRole.dynamicTechnique &&
        role.isHeavy) {
      return SlotTrainingMethod.dynamicEffort;
    }
    if (role == SlotRole.main) {
      return switch (goal) {
        TrainingGoal.hypertrophy => SlotTrainingMethod.doubleProgression,
        TrainingGoal.strength =>
          experience == ExperienceLevel.novice
              ? SlotTrainingMethod.straightSets
              : SlotTrainingMethod.topSetBackoff,
        TrainingGoal.powerbuilding => SlotTrainingMethod.topSetBackoff,
        TrainingGoal.athletic => SlotTrainingMethod.technique,
      };
    }
    if (role == SlotRole.supplemental) {
      return SlotTrainingMethod.doubleProgression;
    }
    if (role == SlotRole.conditioning) return SlotTrainingMethod.technique;
    return goal == TrainingGoal.strength
        ? SlotTrainingMethod.repetition
        : SlotTrainingMethod.doubleProgression;
  }

  static List<_SlotNeed> _needsFor(
    String label, {
    PrimaryLiftSpecialization? primaryLiftSpecialization,
    required TrainingStyle trainingStyle,
    required bool includeGppConditioning,
    required ExperienceLevel experience,
    required int weekIndex,
  }) {
    final value = label.toLowerCase();
    if (primaryLiftSpecialization != null &&
        primaryLiftSpecialization.lift.appliesToDayLabel(label)) {
      final base = _needsForPrimaryLift(primaryLiftSpecialization);
      return includeGppConditioning && value.contains('full')
          ? [...base, const _SlotNeed(null, null, SlotRole.conditioning)]
          : base;
    }
    // A standalone GPP day is intentionally narrow: one conventional cardio
    // / carry slot, not an opaque high-fatigue WOD. It remains easy to edit or
    // remove through the normal program editor. Routes through
    // GppProgramPlanner (CF-03) instead of a bare literal so the day gets a
    // real, segment-tagged, categorically-Dynamic-Effort-safe need.
    if (value.trim() == 'gpp') {
      return GppProgramPlanner.segmentNeedsFor()
          .map(_fromCrossfitNeed)
          .toList(growable: false);
    }
    // CrossFit starts conditioning-first. The catalogue policy below still
    // blocks uncurated, technical-review novice, and manual-only movements.
    // Routes through CrossfitProgramPlanner (CF-01/CF-02) instead of the bare
    // 2-slot stub, so the day gets a full warmup/skill/strength/metcon/
    // cooldown blueprint with a week-driven metcon format rotation.
    if (trainingStyle.isConditioningFirst) {
      return CrossfitProgramPlanner.segmentNeedsFor(
        experience: experience,
        variationSeed: weekIndex,
      ).map(_fromCrossfitNeed).toList(growable: false);
    }
    if (value.contains('push') || value.contains('chest')) {
      return const [
        _SlotNeed('horizontal_push', null, SlotRole.main),
        _SlotNeed('vertical_push', null, SlotRole.supplemental),
        _SlotNeed('horizontal_push', null, SlotRole.accessory),
        _SlotNeed(null, 'tricep', SlotRole.isolation),
        _SlotNeed(null, 'shoulder', SlotRole.isolation),
      ];
    }
    if (value.contains('pull') || value.contains('back')) {
      return const [
        _SlotNeed('horizontal_pull', null, SlotRole.main),
        _SlotNeed('vertical_pull', null, SlotRole.supplemental),
        _SlotNeed('horizontal_pull', null, SlotRole.accessory),
        _SlotNeed(null, 'bicep', SlotRole.isolation),
        _SlotNeed(null, 'rear', SlotRole.isolation),
      ];
    }
    if (value.contains('leg') || value.contains('lower')) {
      return const [
        _SlotNeed('squat', null, SlotRole.main),
        _SlotNeed('hinge', null, SlotRole.supplemental),
        _SlotNeed('lunge', null, SlotRole.accessory),
        _SlotNeed(null, 'quad', SlotRole.isolation),
        _SlotNeed(null, 'hamstring', SlotRole.isolation),
        _SlotNeed(null, 'cal', SlotRole.isolation),
      ];
    }
    if (value.contains('upper')) {
      return const [
        _SlotNeed('horizontal_push', null, SlotRole.main),
        _SlotNeed('horizontal_pull', null, SlotRole.supplemental),
        _SlotNeed('vertical_push', null, SlotRole.accessory),
        _SlotNeed('vertical_pull', null, SlotRole.accessory),
        _SlotNeed(null, 'bicep', SlotRole.isolation),
        _SlotNeed(null, 'tricep', SlotRole.isolation),
      ];
    }
    if (value.contains('arm')) {
      return const [
        _SlotNeed(null, 'bicep', SlotRole.accessory),
        _SlotNeed(null, 'tricep', SlotRole.accessory),
        _SlotNeed(null, 'shoulder', SlotRole.isolation),
      ];
    }
    if (value.contains('shoulder')) {
      return const [
        _SlotNeed('vertical_push', null, SlotRole.main),
        _SlotNeed(null, 'shoulder', SlotRole.isolation),
        _SlotNeed(null, 'rear', SlotRole.isolation),
      ];
    }
    const base = [
      _SlotNeed('squat', null, SlotRole.main),
      _SlotNeed('horizontal_push', null, SlotRole.supplemental),
      _SlotNeed('horizontal_pull', null, SlotRole.accessory),
      _SlotNeed('hinge', null, SlotRole.accessory),
      _SlotNeed(null, 'shoulder', SlotRole.isolation),
    ];
    // Only Full Body A/B + GPP (or an explicit config opt-in) receives this
    // optional finish. Regular full-body, upper/lower, and PPL plans keep
    // exactly their existing exercise count.
    return includeGppConditioning && value.contains('full body')
        ? [...base, const _SlotNeed(null, null, SlotRole.conditioning)]
        : base;
  }

  /// Maps the shared public [CrossfitSlotNeed] descriptor (returned by
  /// `CrossfitProgramPlanner`/`GppProgramPlanner`) onto this file's private
  /// [_SlotNeed], 1:1 field-for-field.
  static _SlotNeed _fromCrossfitNeed(CrossfitSlotNeed need) => _SlotNeed(
    need.pattern,
    need.muscle,
    need.role,
    preferredSlugs: need.preferredSlugs,
    segment: need.segment,
    metconGroupKey: need.metconGroupKey,
    metconFormat: need.metconFormat,
    metconCapSeconds: need.metconCapSeconds,
    metconMinutes: need.metconMinutes,
  );

  static List<_SlotNeed> _needsForPrimaryLift(
    PrimaryLiftSpecialization specialization,
  ) {
    final lift = specialization.lift;
    final main = _SlotNeed(
      lift.movementPattern,
      null,
      SlotRole.main,
      preferredSlugs: lift.preferredSlugs,
    );
    final assistance = switch (lift) {
      PrimaryLift.squat => switch (specialization.stickingPoint) {
        PrimaryLiftStickingPoint.bottom => const _SlotNeed(
          'squat',
          'quad',
          SlotRole.supplemental,
        ),
        PrimaryLiftStickingPoint.lockout => const _SlotNeed(
          'hinge',
          'glute',
          SlotRole.supplemental,
        ),
        _ => const _SlotNeed('lunge', 'quad', SlotRole.supplemental),
      },
      PrimaryLift.deadlift => switch (specialization.stickingPoint) {
        PrimaryLiftStickingPoint.offFloor => const _SlotNeed(
          'lunge',
          'quad',
          SlotRole.supplemental,
        ),
        _ => const _SlotNeed('hinge', 'hamstring', SlotRole.supplemental),
      },
      PrimaryLift.benchPress => switch (specialization.stickingPoint) {
        PrimaryLiftStickingPoint.chest => const _SlotNeed(
          'horizontal_push',
          'chest',
          SlotRole.supplemental,
        ),
        _ => const _SlotNeed(null, 'back', SlotRole.supplemental),
      },
      PrimaryLift.overheadPress => switch (specialization.stickingPoint) {
        PrimaryLiftStickingPoint.bottom => const _SlotNeed(
          'vertical_push',
          'shoulder',
          SlotRole.supplemental,
        ),
        _ => const _SlotNeed(null, 'back', SlotRole.supplemental),
      },
      PrimaryLift.pullUp => switch (specialization.stickingPoint) {
        PrimaryLiftStickingPoint.deadHang => const _SlotNeed(
          'vertical_pull',
          null,
          SlotRole.supplemental,
        ),
        _ => const _SlotNeed(null, 'back', SlotRole.supplemental),
      },
    };
    final isolation = switch (lift) {
      PrimaryLift.squat ||
      PrimaryLift.deadlift => const _SlotNeed(null, 'abs', SlotRole.isolation),
      PrimaryLift.benchPress || PrimaryLift.overheadPress => const _SlotNeed(
        null,
        'tricep',
        SlotRole.isolation,
      ),
      PrimaryLift.pullUp => const _SlotNeed(null, 'bicep', SlotRole.isolation),
    };
    return [
      main,
      assistance,
      const _SlotNeed('horizontal_push', null, SlotRole.accessory),
      const _SlotNeed('horizontal_pull', null, SlotRole.accessory),
      isolation,
    ];
  }

  /// Projects the day's total duration from its current (possibly
  /// mid-trim) plan list, itemizing each slot's real warmup ramp (via
  /// [WarmupResolver]) and real unilateral doubling (from the catalog's
  /// `movementPatternRaw`) so the trim decision matches what the
  /// materialized session will actually incur (D-06/D-08/D-09, T-18-11).
  static Duration _estimateDayDuration(
    List<_DaySlotPlan> plans,
    Map<int, ExerciseCatalogData> catalogById,
  ) {
    final durations = [
      for (final plan in plans) _estimateSlotDuration(plan, catalogById),
    ];
    return WorkoutDurationEstimator.estimateSession(durations);
  }

  static Duration _estimateSlotDuration(
    _DaySlotPlan plan,
    Map<int, ExerciseCatalogData> catalogById,
  ) {
    // A metcon's duration is a fixed cap, not a per-rep estimate — an EMOM
    // need expresses its length via `metconMinutes` (no `metconCapSeconds`),
    // so derive capSeconds inline for that one case rather than adding a 6th
    // field to _TimePlan (21-06).
    if (plan.timePlan.segment == SessionSegment.metcon) {
      final capSeconds =
          plan.timePlan.metconCapSeconds ??
          ((plan.slot.metconMinutes ?? 0) * 60);
      return WorkoutDurationEstimator.estimateCappedSegment(
        capSeconds: capSeconds,
      );
    }
    final exercise = catalogById[plan.exerciseId]!;
    final warmupSteps = WarmupResolver.resolve(
      role: plan.slot.role,
      mechanics: exercise.mechanics,
      modality: exercise.modality,
      targetPercentOf1Rm: plan.slot.method == SlotTrainingMethod.maxEffort
          ? 0.90
          : null,
      isFirstHeavyLiftInSession: plan.isFirstHeavy,
    );
    final isUnilateral = (exercise.movementPatternRaw ?? '')
        .toLowerCase()
        .contains('unilateral');
    return WorkoutDurationEstimator.estimateExercise(
      workingSets: plan.timePlan.target.sets,
      repsMin: plan.timePlan.target.repsMin,
      repsMax: plan.timePlan.target.repsMax,
      restSeconds: plan.timePlan.target.restSeconds,
      setType: plan.timePlan.setType,
      warmupSteps: warmupSteps,
      isUnilateral: isUnilateral,
    );
  }

  static _Target _targetFor(
    SlotRole role,
    SlotTrainingMethod method,
    String priorityLevel,
    double? focusWeight,
  ) {
    if (method == SlotTrainingMethod.maxEffort) {
      return const _Target(1, 1, 3, 1, 300);
    }
    final base = switch (role) {
      SlotRole.main => const _Target(3, 4, 6, 2, 240),
      SlotRole.supplemental => const _Target(4, 6, 10, 2, 180),
      SlotRole.accessory => const _Target(3, 8, 12, 2, 120),
      SlotRole.isolation => const _Target(3, 12, 15, 1, 75),
      SlotRole.conditioning => const _Target(1, 1, 1, 3, 60),
    };
    final sets = switch (priorityLevel) {
      'high' => base.sets + 1,
      'maintenance' when !role.isHeavy => (base.sets - 1).clamp(1, base.sets),
      _ => base.sets,
    };
    var weightedSets = sets;
    if (focusWeight != null && focusWeight >= 0.40) {
      weightedSets++;
    } else if (focusWeight != null && focusWeight < 0.20 && !role.isHeavy) {
      weightedSets = (weightedSets - 1).clamp(1, weightedSets).toInt();
    }
    return _Target(
      weightedSets,
      base.repsMin,
      base.repsMax,
      base.rir,
      base.restSeconds,
    );
  }

  /// Keep time-saving work out of main lifts. One Myo activation set plus its
  /// mini-sets is an explicit, legible alternative for short sessions—not a
  /// hidden reduction in training quality.
  static _TimePlan _timePlanFor({
    required SlotRole role,
    required _Target target,
    required SmartProgramConfiguration configuration,
  }) {
    final canCompress =
        configuration.allowTimeSavingSetTechniques &&
        configuration.workoutDurationMinutes <= 45 &&
        role == SlotRole.isolation;
    if (!canCompress) return _TimePlan.standard(target);
    const compressed = _Target(1, 12, 20, 0, 45);
    const prescription = SlotPrescription(
      name: 'Time-saving myo-reps',
      segments: [
        WorkSegment(
          sets: 1,
          repsMin: 12,
          repsMax: 20,
          intent: Intent.rir2,
          setType: SetType.myoReps,
          meta: {'activationReps': 15, 'miniSets': 3},
        ),
      ],
    );
    return _TimePlan(
      target: compressed,
      setType: SetType.myoReps,
      why:
          ' Myo-reps are used here because you chose a ${configuration.workoutDurationMinutes}-minute session.',
      prescriptionCodecJson: SlotPrescriptionCodec.encode(prescription),
    );
  }

  static String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  static String _canonicalMuscleId(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('chest') || value.contains('pec')) return 'chest';
    if (value.contains('lat')) return 'lats';
    if (value.contains('trap')) return 'traps';
    if (value.contains('back') || value.contains('erector')) return 'back';
    if (value.contains('front') && value.contains('delt')) return 'front_delts';
    if (value.contains('rear') || value.contains('posterior')) {
      return 'rear_delts';
    }
    if (value.contains('delt') || value.contains('shoulder')) {
      return 'side_delts';
    }
    if (value.contains('bicep')) return 'biceps';
    if (value.contains('tricep')) return 'triceps';
    if (value.contains('forearm')) return 'forearms';
    if (value.contains('quad') || value.contains('adductor')) return 'quads';
    if (value.contains('hamstring')) return 'hamstrings';
    if (value.contains('glute') || value.contains('abductor')) return 'glutes';
    if (value.contains('calf')) return 'calves';
    if (value.contains('oblique')) return 'obliques';
    if (value.contains('ab') || value.contains('core')) return 'abs';
    return value.replaceAll(' ', '_');
  }

  static _FocusNote _focusNoteForWeek({
    required SmartProgramConfiguration configuration,
    required String muscleId,
    required int weekIndex,
  }) {
    if (configuration.muscleFocusWave != MuscleFocusWave.alternating ||
        configuration.muscleVolumeWeights.length < 2 ||
        !configuration.muscleVolumeWeights.containsKey(muscleId)) {
      return const _FocusNote();
    }
    final ids = configuration.muscleVolumeWeights.keys.toList(growable: false);
    final highFocusId = ids[weekIndex % ids.length];
    if (muscleId == highFocusId) {
      return const _FocusNote(
        isHighFocus: true,
        message: ' This is this muscle’s high-focus week.',
      );
    }
    return const _FocusNote(
      isLightFocus: true,
      message: ' This muscle is in a lighter-focus week.',
    );
  }

  static int _stableSeed(String value) {
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }
}

class _EquipmentProfile {
  const _EquipmentProfile({required this.allEquipment, required this.keys});

  final bool allEquipment;
  final Set<String> keys;

  bool allows(ExerciseCatalogData exercise) {
    if (allEquipment) return true;
    final raw = exercise.requiredEquipmentKeys;
    final required = raw == null
        ? <String>[exercise.modality]
        : (jsonDecode(raw) as List).cast<String>();
    return required.every(keys.contains);
  }
}

class _SlotNeed {
  const _SlotNeed(
    this.pattern,
    this.muscle,
    this.role, {
    this.preferredSlugs = const {},
    this.segment,
    this.metconGroupKey,
    this.metconFormat,
    this.metconCapSeconds,
    this.metconMinutes,
  });
  final String? pattern;
  final String? muscle;
  final SlotRole role;
  final Set<String> preferredSlugs;

  /// CrossFit/GPP session-segment tag (21-01/21-04/21-05). Null for every
  /// non-CrossFit/GPP need — this is the overwhelming majority of call sites.
  final SessionSegment? segment;
  final String? metconGroupKey;
  final SetType? metconFormat;
  final int? metconCapSeconds;
  final int? metconMinutes;
}

class _Target {
  const _Target(
    this.sets,
    this.repsMin,
    this.repsMax,
    this.rir,
    this.restSeconds,
  );
  final int sets;
  final int repsMin;
  final int repsMax;
  final int rir;
  final int restSeconds;

  _Target copyWith({int? sets}) =>
      _Target(sets ?? this.sets, repsMin, repsMax, rir, restSeconds);
}

class _TimePlan {
  const _TimePlan({
    required this.target,
    required this.setType,
    required this.why,
    this.prescriptionCodecJson,
    this.segment,
    this.supersetGroup,
    this.metconCapSeconds,
  });

  const _TimePlan.standard(_Target target)
    : this(target: target, setType: SetType.standard, why: '');

  final _Target target;
  final SetType setType;
  final String why;
  final String? prescriptionCodecJson;

  /// Set only for metcon-segment slots (bypassing [_timePlanFor] entirely) —
  /// lets [_estimateSlotDuration] and the time-budget trim loop treat a
  /// metcon's duration as fixed rather than per-rep-estimated (21-06).
  final SessionSegment? segment;
  final int? supersetGroup;
  final int? metconCapSeconds;

  _TimePlan copyWith({_Target? target}) => _TimePlan(
    target: target ?? this.target,
    setType: setType,
    why: why,
    prescriptionCodecJson: prescriptionCodecJson,
    segment: segment,
    supersetGroup: supersetGroup,
    metconCapSeconds: metconCapSeconds,
  );
}

/// A slot's fully-computed pass-1 plan for one day: the target/timePlan the
/// existing single-pass code would have inserted immediately, plus the
/// movement-order flag needed to feed [WarmupResolver] the same
/// first-heavy-lift-in-session input the materialize-time resolver uses.
/// [timePlan] is mutated in place by the time-budget trim loop between pass 1
/// and pass 2 (D-05/D-07); [target] stays fixed since weekly-set-cap
/// accounting and `restSeconds` are read from the pre-trim target, matching
/// the previous single-pass behavior unchanged by this plan.
class _DaySlotPlan {
  _DaySlotPlan({
    required this.slot,
    required this.exerciseId,
    required this.target,
    required this.timePlan,
    required this.isFirstHeavy,
    required this.focusNote,
  });

  final _ResolvedSmartSlot slot;
  final int exerciseId;
  final _Target target;
  _TimePlan timePlan;
  final bool isFirstHeavy;
  final _FocusNote focusNote;
}

class _FocusNote {
  const _FocusNote({
    this.isHighFocus = false,
    this.isLightFocus = false,
    this.message = '',
  });

  final bool isHighFocus;
  final bool isLightFocus;
  final String message;
}

class _ResolvedSmartSlot {
  const _ResolvedSmartSlot({
    required this.id,
    required this.orderIndex,
    required this.anchorExerciseId,
    required this.role,
    required this.method,
    required this.poolSize,
    required this.priorityLevel,
    required this.muscleId,
    required this.why,
    required this.loadingPreference,
    required this.assignments,
    this.segment,
    this.metconGroupKey,
    this.metconFormat,
    this.metconCapSeconds,
    this.metconMinutes,
  }) : explanation = null;

  /// A hard-filter-exhausted slot for which no safe candidate — including
  /// via the D-03 scaling-ladder regression — was found (D-01). A stable
  /// `ProgramExerciseSlots` row (and a `ProgramSlotExplanations` row per
  /// week, `status: 'empty'`) is written for it at the call site in
  /// `_createStableSlots`, but [id] here remains a placeholder never read:
  /// `populate()`'s per-slot loop always `continue`s before consulting it,
  /// since [anchorExerciseId] is null.
  _ResolvedSmartSlot.empty({
    required this.orderIndex,
    required this.role,
    required this.method,
    required this.explanation,
  }) : id = -1,
       anchorExerciseId = null,
       poolSize = 0,
       priorityLevel = 'medium',
       muscleId = '',
       why = explanation!.rationale,
       loadingPreference = _LoadingPreference.flexible,
       assignments = const {},
       segment = null,
       metconGroupKey = null,
       metconFormat = null,
       metconCapSeconds = null,
       metconMinutes = null;

  final int id;
  final int orderIndex;
  final int? anchorExerciseId;
  final SlotRole role;
  final SlotTrainingMethod method;
  final int poolSize;
  final String priorityLevel;
  final String muscleId;
  final String why;
  final _LoadingPreference loadingPreference;
  final Map<int, RotationAssignmentData> assignments;

  /// CrossFit/GPP session-segment tag and metcon descriptors, carried
  /// verbatim from the `_SlotNeed` this slot was resolved from (21-06). Null
  /// for every non-CrossFit/GPP slot.
  final SessionSegment? segment;
  final String? metconGroupKey;
  final SetType? metconFormat;
  final int? metconCapSeconds;
  final int? metconMinutes;

  /// Set only by [_ResolvedSmartSlot.empty] — its `rationale` is persisted
  /// to `ProgramSlotExplanations` at the empty-slot call site above,
  /// ignored otherwise.
  final SelectionExplanation? explanation;
}

enum _LoadingPreference {
  freeWeight,
  calisthenics,
  weightedCalisthenics,
  flexible,
}
