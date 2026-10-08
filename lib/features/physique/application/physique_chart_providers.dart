import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/application/physique_schedule_provider.dart';
import 'package:herculex/features/physique/domain/physique_series.dart';
import 'package:herculex/features/physique/domain/physique_strength_series.dart';
import 'package:herculex/features/physique/domain/roadmap_schedule.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';

// Series maths lives in the domain builders; this file only selects inputs.

/// The user's range choice; null means "use the default for this goal".
final physiqueChartRangeProvider = StateProvider<ChartRange?>((ref) => null);

/// Selection, else All for a goal under 30 days old and 3M after that.
final physiqueEffectiveRangeProvider = Provider.family<ChartRange, int>((
  ref,
  goalId,
) {
  final selected = ref.watch(physiqueChartRangeProvider);
  if (selected != null) return selected;
  final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
  if (goal == null) return ChartRange.all;
  return ChartRange.defaultFor(
    goalStartedAt: goal.startedAt,
    now: ref.watch(clockProvider).now(),
  );
});

final physiqueStrengthSamplesProvider = StreamProvider<List<StrengthSample>>((
  ref,
) {
  return ref.watch(physiqueSeriesRepositoryProvider).watchStrengthSamples();
});

final physiqueSessionDatesProvider = StreamProvider<List<DateTime>>((ref) {
  return ref.watch(physiqueSeriesRepositoryProvider).watchSessionDates();
});

DietPhase _dietPhaseOf(String name) {
  for (final p in DietPhase.values) {
    if (p.name == name) return p;
  }
  return DietPhase.maintain;
}

final physiqueWeightChartProvider = Provider.family<WeightChartData, int>((
  ref,
  goalId,
) {
  final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
  if (goal == null) return WeightChartData.empty;
  final logs = ref.watch(physiqueWeightLogsProvider).asData?.value ?? const [];
  final phases =
      ref.watch(physiqueRoadmapPhasesProvider(goalId)).asData?.value ??
      const [];

  // Where the roadmap says each unfinished phase ends, for the plan line.
  final schedule = ref.watch(physiqueRoadmapScheduleProvider(goalId));
  final planStops = [
    for (final p in schedule?.phases ?? const <ScheduledPhase>[])
      if (p.status != 'done' && p.endKg != null)
        ChartPoint(p.endDate, p.endKg!),
  ];

  // Chain each phase's start weight from the previous phase's target.
  double? startKg = goal.startWeightKg ?? (logs.isEmpty ? null : logs.first.kg);
  final inputs = <PhaseBandInput>[];
  for (final p in phases) {
    inputs.add(
      PhaseBandInput(
        phase: _dietPhaseOf(p.phaseType),
        plannedWeeks: p.plannedWeeks,
        startedAt: p.status == 'upcoming' ? null : p.startedAt,
        startWeightKg: startKg,
        targetWeightKg: p.targetWeightKg,
      ),
    );
    startKg = p.targetWeightKg ?? startKg;
  }

  return PhysiqueSeriesBuilder.weight(
    logs: logs,
    now: ref.watch(clockProvider).now(),
    range: ref.watch(physiqueEffectiveRangeProvider(goalId)),
    goalStartedAt: goal.startedAt,
    phases: inputs,
    planStops: planStops,
  );
});

final physiqueSelectedLiftProvider = StateProvider<PrimaryLift?>((ref) => null);

class StrengthChartData {
  const StrengthChartData({
    required this.lift,
    required this.points,
    required this.liftsWithData,
  });

  static const empty = StrengthChartData(
    lift: null,
    points: [],
    liftsWithData: {},
  );

  final PrimaryLift? lift;
  final List<ChartPoint> points;
  final Set<PrimaryLift> liftsWithData;
}

final physiqueStrengthChartProvider = Provider.family<StrengthChartData, int>((
  ref,
  goalId,
) {
  final samples =
      ref.watch(physiqueStrengthSamplesProvider).asData?.value ?? const [];
  final now = ref.watch(clockProvider).now();
  final range = ref.watch(physiqueEffectiveRangeProvider(goalId));
  final withData = <PrimaryLift>{
    for (final l in PrimaryLift.values)
      if (E1rmSeriesBuilder.hasDataIn(
        samples: samples,
        lift: l,
        now: now,
        range: range,
      ))
        l,
  };
  if (withData.isEmpty) return StrengthChartData.empty;

  final selected = ref.watch(physiqueSelectedLiftProvider);
  final lift = (selected != null && withData.contains(selected))
      ? selected
      : E1rmSeriesBuilder.defaultLift(samples: samples, now: now, range: range);
  if (lift == null) return StrengthChartData.empty;
  return StrengthChartData(
    lift: lift,
    points: E1rmSeriesBuilder.build(
      samples: samples,
      lift: lift,
      now: now,
      range: range,
    ),
    liftsWithData: withData,
  );
});

final physiqueTrainingLevelChartProvider =
    Provider.family<List<TrainingLevelPoint>, int>((ref, goalId) {
      final dates =
          ref.watch(physiqueSessionDatesProvider).asData?.value ?? const [];
      return TrainingLevelSeriesBuilder.build(
        sessionDates: dates,
        now: ref.watch(clockProvider).now(),
        range: ref.watch(physiqueEffectiveRangeProvider(goalId)),
      );
    });
