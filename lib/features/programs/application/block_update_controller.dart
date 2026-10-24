import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/data/smart_program_planner.dart';
import 'package:herculex/features/programs/domain/block_adjustment_advisor.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/domain/time_saving_policy.dart';
import 'package:herculex/features/recovery/application/recovery_providers.dart';
import 'package:herculex/features/recovery/domain/deload_urgency.dart';
import 'package:herculex/features/recovery/domain/joint_model.dart';

/// What the user asked the rest of the block to become.
class BlockUpdateRequest {
  const BlockUpdateRequest({
    required this.daysPerWeek,
    required this.sessionMinutes,
    required this.lighter,
    this.allowTimeSavingSetTechniques = true,
    this.timeSavingTechnique = TimeSavingTechnique.automatic,
  });

  final int daysPerWeek;
  final int sessionMinutes;
  final bool allowTimeSavingSetTechniques;
  final TimeSavingTechnique timeSavingTechnique;

  /// Scale every regenerated week's working volume down.
  final bool lighter;
}

/// Working-volume factor of a "lighter" block (the week volume slider's
/// scale, where 1.0 is as planned).
const lighterBlockVolume = 0.85;

/// Rebuilds the remaining weeks of a block as a new, unconfirmed draft.
///
/// Nothing the user sees changes here: the draft is archived and inactive,
/// exactly like a freshly built block, until [ProgramReviewView] confirms it
/// and retires the old block. Logged sessions stay attached to the old block.
class BlockUpdateController {
  BlockUpdateController(this._ref);

  final Ref _ref;

  ProgramsRepository get _repo => _ref.read(programsRepositoryProvider);

  /// Weeks still ahead in [program], counting the current one.
  Future<int> remainingWeeks(ProgramData program) async {
    final tracking = await _repo.watchProgramTracking(program.id).first;
    return (program.weeks - tracking.currentWeekIndex).clamp(1, program.weeks);
  }

  /// Returns the draft program's id.
  Future<int> buildDraft(
    ProgramData program,
    BlockUpdateRequest request,
  ) async {
    final db = _ref.read(appDatabaseProvider);
    final now = _ref.read(clockProvider).now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final weeks = await remainingWeeks(program);
    final buildMode = ProgramBuildMode.fromId(program.buildMode);
    final mode = ScheduleMode.values.firstWhere(
      (m) => m.id == program.scheduleMode,
      orElse: () => ScheduleMode.weekly,
    );
    var split = SplitType.fromId(program.splitType);
    // Two days cannot cover a body-part split; fall back to full body.
    if (request.daysPerWeek <= 2 && split.slots.length > 2) {
      split = SplitType.fullBodyAb;
    }
    final plan = SplitTemplates.generate(
      type: split,
      daysPerWeek: request.daysPerWeek,
      mode: mode,
      cycleLength: mode == ScheduleMode.cycle ? request.daysPerWeek + 1 : null,
    );

    // A manual block keeps its own templates, matched by slot name.
    final templates = buildMode == ProgramBuildMode.manual
        ? await _repo.templatesBySlotLabel(program.id)
        : const <String, int>{};
    final templateIdsBySlot = <int, int?>{
      for (final slot in plan.slotSummary)
        slot.slotIndex: templates[slot.label],
    };

    final draftId = await _repo.createProgramFromSplit(
      name: program.name,
      description: program.description,
      weeks: weeks,
      plan: plan,
      startDate: tomorrow,
      periodizationModel: program.periodizationModel,
      templateIdsBySlot: templateIdsBySlot,
      buildMode: buildMode,
      trainingGoal: TrainingGoal.fromId(program.trainingGoal),
      experienceLevel: ExperienceLevel.fromId(program.experienceLevel),
      activate: false,
      archived: true,
      materialize: false,
    );
    try {
      if (buildMode != ProgramBuildMode.manual) {
        final joints = await _ref
            .read(jointPainRepositoryProvider)
            .currentStatuses();
        await SmartProgramPlanner(db).populate(
          draftId,
          SmartProgramConfiguration(
            goal: TrainingGoal.fromId(program.trainingGoal),
            experience: ExperienceLevel.fromId(program.experienceLevel),
            buildMode: buildMode,
            workoutDurationMinutes: request.sessionMinutes,
            allowTimeSavingSetTechniques:
                !request.lighter && request.allowTimeSavingSetTechniques,
            timeSavingTechnique: request.timeSavingTechnique,
            excludedMuscles: JointModel.excludedMusclesFor({
              for (final status in joints.values)
                if (status.isFlagged) status.joint,
            }),
          ),
        );
        await _repo.carryUserExerciseChoices(
          fromProgramId: program.id,
          toProgramId: draftId,
        );
      }
      await _repo.snapshotLinkedTemplates(draftId);
      if (request.lighter) {
        final draftWeeks = await _repo.watchProgramWeeks(draftId).first;
        for (final week in draftWeeks) {
          await _repo.setWeekAdjustment(
            week.id,
            adjustmentFactor: week.adjustmentFactor * lighterBlockVolume,
          );
        }
      }
      return draftId;
    } catch (_) {
      await _repo.deleteProgram(draftId);
      rethrow;
    }
  }

  /// Called when the user confirms the draft: the old block stops tomorrow.
  Future<void> retire(int programId) async {
    final now = _ref.read(clockProvider).now();
    await _repo.retireForReplacement(
      programId,
      DateTime(now.year, now.month, now.day + 1),
    );
  }
}

final blockUpdateControllerProvider = Provider<BlockUpdateController>(
  BlockUpdateController.new,
);

/// The active block plus a reason to rebuild it, when there is one.
typedef BlockAdjustment = ({
  ProgramData program,
  BlockAdjustmentRecommendation recommendation,
});

const blockAdjustmentDismissedKey = 'block_adjustment_dismissed';

/// `programId-suggestedDays-reason` of the last dismissed suggestion,
/// so a dismissed suggestion stays gone until something about it changes.
final blockAdjustmentDismissedProvider = StateProvider<String?>(
  (ref) => ref
      .read(sharedPreferencesProvider)
      .getString(blockAdjustmentDismissedKey),
);

String blockAdjustmentKey(BlockAdjustment adjustment) =>
    '${adjustment.program.id}-'
    '${adjustment.recommendation.suggestedDaysPerWeek}-'
    '${adjustment.recommendation.reason.name}';

/// The current recommendation for the active block, ignoring dismissals.
final blockAdjustmentProvider = FutureProvider<BlockAdjustment?>((ref) async {
  final program = await ref.watch(activeProgramProvider.future);
  final days = program?.daysPerWeek;
  if (program == null || days == null) return null;
  final adherence = await ref
      .watch(programsRepositoryProvider)
      .recentAdherence(program.id, now: ref.watch(clockProvider).now());
  final deload = await ref.watch(muscleDeloadSignalsProvider.future);
  final cns = await ref.watch(cnsTrendsProvider.future);
  final recovery = await ref.watch(recoveryV3Provider.future);
  final trained = recovery.where((r) => r.weeklySets > 0).toList();
  final recommendation = BlockAdjustmentAdvisor.evaluate(
    daysPerWeek: days,
    recentWeeks: adherence,
    deloadRecommended: deload.any(
      (s) => s.urgency == DeloadUrgency.recommended,
    ),
    cnsDeloadSuggested: cns.deloadSuggested,
    averageRecoveryScore: trained.isEmpty
        ? null
        : trained.fold<int>(0, (sum, r) => sum + r.recoveryScore) /
              trained.length,
  );
  if (recommendation == null) return null;
  return (program: program, recommendation: recommendation);
});

/// [blockAdjustmentProvider] minus a suggestion the user dismissed.
final visibleBlockAdjustmentProvider = Provider<BlockAdjustment?>((ref) {
  final adjustment = ref.watch(blockAdjustmentProvider).valueOrNull;
  if (adjustment == null) return null;
  if (ref.watch(blockAdjustmentDismissedProvider) ==
      blockAdjustmentKey(adjustment)) {
    return null;
  }
  return adjustment;
});
