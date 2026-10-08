import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';
import 'package:herculex/features/physique/domain/roadmap_draft_editor.dart';

/// Where [GoalTarget.targetKg] comes from.
enum GoalTargetSource {
  /// The active physique goal's roadmap.
  roadmap,

  /// The weight typed on the Profile or Goals screen.
  manual,

  /// Neither exists.
  none,
}

/// The weight the member is heading to right now.
class GoalTarget {
  const GoalTarget({
    required this.source,
    this.targetKg,
    this.dreamKg,
    this.phase,
    this.goalId,
  });

  static const none = GoalTarget(source: GoalTargetSource.none);

  final GoalTargetSource source;

  /// Where the current phase ends; the number every screen shows.
  final double? targetKg;

  /// Where the whole roadmap ends. Null without a roadmap.
  final double? dreamKg;

  /// The phase [targetKg] belongs to. Null without a roadmap.
  final DietPhase? phase;
  final int? goalId;

  bool get fromRoadmap => source == GoalTargetSource.roadmap;
}

DietPhase _phaseOf(String name) {
  for (final p in DietPhase.values) {
    if (p.name == name) return p;
  }
  return DietPhase.maintain;
}

/// The single answer to "what is my target weight?".
///
/// With an active physique goal it is the weight the current phase ends at
/// (the next phase's, once that one starts), so the Profile, dashboard, charts
/// and widget can never disagree with the roadmap. Without one it is the
/// weight the member typed. The profile's own copy of that weight is left
/// alone while a roadmap runs, so it is still there if the goal is archived.
final goalTargetProvider = Provider<GoalTarget>((ref) {
  final profile = ref.watch(profileProvider).asData?.value;
  final manual = profile?.targetWeightKg ?? ref.watch(goalWeightProvider);
  GoalTarget fallback() => manual == null
      ? GoalTarget.none
      : GoalTarget(source: GoalTargetSource.manual, targetKg: manual);

  final goal = ref.watch(activePhysiqueGoalProvider).asData?.value;
  if (goal == null) return fallback();
  final phases = ref
      .watch(physiqueRoadmapPhasesProvider(goal.id))
      .asData
      ?.value;
  if (phases == null || phases.isEmpty) return fallback();

  final pick =
      phases.where((p) => p.status == 'current').firstOrNull ??
      phases.where((p) => p.status == 'upcoming').firstOrNull ??
      phases.last;
  final at = phases.indexOf(pick);
  double? target = pick.targetWeightKg;
  // A phase without a weight (a hand-added one) holds whatever surrounds it.
  for (var i = at + 1; target == null && i < phases.length; i++) {
    target = phases[i].targetWeightKg;
  }
  for (var i = at - 1; target == null && i >= 0; i--) {
    target = phases[i].targetWeightKg;
  }
  if (target == null) return fallback();

  double? dream;
  for (final p in phases.reversed) {
    dream = p.targetWeightKg;
    if (dream != null) break;
  }
  return GoalTarget(
    source: GoalTargetSource.roadmap,
    targetKg: target,
    dreamKg: dream,
    phase: _phaseOf(pick.phaseType),
    goalId: goal.id,
  );
});

sealed class GoalTargetResult {
  const GoalTargetResult();
}

class GoalTargetApplied extends GoalTargetResult {
  const GoalTargetApplied({required this.viaRoadmap});

  /// True when the roadmap was re-planned, false when only the typed weight
  /// was stored.
  final bool viaRoadmap;
}

/// The typed weight cannot be reached by changing the running phase alone: the
/// member has to edit the roadmap (change the phase, or plan it in steps).
class GoalTargetNeedsRoadmapChange extends GoalTargetResult {
  const GoalTargetNeedsRoadmapChange({
    required this.goalId,
    required this.message,
  });

  final int goalId;
  final String message;
}

/// Every place that lets the member type a target weight goes through here.
///
/// With a roadmap the weight moves the running phase's end and re-chains the
/// phases after it, so the roadmap stays the only truth. Without one it is
/// stored as before, in the profile and in the goals preference.
class GoalTargetController {
  GoalTargetController(this._ref);

  final Ref _ref;

  Future<GoalTargetResult> setTarget(double kg) async {
    final goal = await _ref.read(activePhysiqueGoalProvider.future);
    if (goal == null) return _storeManual(kg);
    final rows = await _ref.read(physiqueRoadmapPhasesProvider(goal.id).future);
    final open = [
      for (final r in rows)
        if (r.status != 'done') r,
    ];
    if (open.isEmpty) return _storeManual(kg);

    final first = open.first;
    final current = first.targetWeightKg;
    if (current != null && (current - kg).abs() < 0.05) {
      return const GoalTargetApplied(viaRoadmap: true);
    }

    final fromKg = _ref
        .read(localProfileRepositoryProvider)
        .currentProfile
        ?.weightKg;
    if (fromKg == null || fromKg <= 0) {
      return GoalTargetNeedsRoadmapChange(
        goalId: goal.id,
        message: 'Add your current weight first, then set a target.',
      );
    }

    final drafts = [
      for (final r in open)
        RoadmapPhaseDraft(
          phase: _phaseOf(r.phaseType),
          plannedWeeks: r.plannedWeeks,
          targetWeightKg: r.targetWeightKg,
          targetBfPercent: r.targetBfPercent,
          weeklyRateKg: r.weeklyRateKg,
          tempoCapped: r.tempoCapped,
        ),
    ];
    final startedAt = first.status == 'current' ? first.startedAt : null;
    final elapsed = startedAt == null
        ? 0
        : _ref.read(clockProvider).now().difference(startedAt).inDays ~/ 7;

    final pinned = RoadmapDraftEditor.pinPhaseEnd(
      drafts,
      0,
      fromWeightKg: fromKg,
      endWeightKg: kg,
      goalTargetBfPercent: goal.targetBfPercent,
      maintenanceKcal:
          _ref.read(maintenanceKcalProvider) ??
          PhysiqueTuning.defaultMaintenanceKcal,
      eligibility: _ref.read(physiqueRoadmapEligibilityProvider(goal.id)),
      elapsedWeeks: elapsed,
    );
    if (pinned == null) {
      return GoalTargetNeedsRoadmapChange(
        goalId: goal.id,
        message: _whyNot(drafts.first.phase, kg, fromKg),
      );
    }
    await _ref
        .read(physiqueRoadmapRepositoryProvider)
        .replaceRoadmap(goal.id, pinned);
    return const GoalTargetApplied(viaRoadmap: true);
  }

  /// Removes the typed target. A running roadmap keeps its own weights.
  Future<void> clearManual() => _writeManual(null);

  Future<GoalTargetResult> _storeManual(double kg) async {
    await _writeManual(kg);
    return const GoalTargetApplied(viaRoadmap: false);
  }

  Future<void> _writeManual(double? kg) async {
    final repo = _ref.read(localProfileRepositoryProvider);
    final profile = repo.currentProfile;
    if (profile != null) {
      await repo.save(
        kg == null
            ? profile.copyWith(clearTargetWeight: true)
            : profile.copyWith(targetWeightKg: kg),
        syncToLog: false,
      );
    }
    final goalWeight = _ref.read(goalWeightProvider.notifier);
    if (kg == null) {
      await goalWeight.clear();
    } else {
      await goalWeight.set(kg);
    }
  }

  static String _whyNot(DietPhase phase, double kg, double fromKg) {
    final name = phase.label.toLowerCase();
    switch (phase) {
      case DietPhase.maintain:
      case DietPhase.recomp:
        return 'Your current phase ($name) keeps your weight steady. Edit '
            'your roadmap to change the phase, then set a new target.';
      case DietPhase.cut:
        if (kg >= fromKg) {
          return 'A cut ends lower than where you are now. Edit your '
              'roadmap to change the phase.';
        }
      case DietPhase.bulk:
      case DietPhase.maingain:
        if (kg <= fromKg) {
          return 'A $name phase ends higher than where you are now. Edit '
              'your roadmap to change the phase.';
        }
    }
    return 'That is more than a year away at a safe pace. Edit your roadmap '
        'to plan it in steps.';
  }
}

final goalTargetControllerProvider = Provider<GoalTargetController>(
  GoalTargetController.new,
);
