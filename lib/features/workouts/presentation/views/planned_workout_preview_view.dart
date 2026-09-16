import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart'
    as slot_prescription;
import 'package:herculex/features/shell/main_scaffold.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/presentation/widgets/exercise_artwork.dart';

/// A standalone pushed route (FLOW-02, D-09) rendering a scheduled workout's
/// full plan from a `scheduleId` alone, via [plannedWorkoutPreviewProvider].
/// Replaces the sheet-on-sheet `_WorkoutPlanPreviewSheet` that used to live
/// inside `DayDetailSheet`, so the preview has a real back-stack entry.
///
/// Viewing this screen never creates a `WorkoutSessions` row — the Start
/// workout CTA is the only action that does, mirroring
/// `DayDetailSheet._start`'s pop-then-navigate pattern.
class PlannedWorkoutPreviewView extends ConsumerWidget {
  const PlannedWorkoutPreviewView({super.key, required this.scheduleId});

  final int scheduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(plannedWorkoutPreviewProvider(scheduleId));

    return Scaffold(
      appBar: AppBar(title: const Text('Planned workout')),
      body: dataAsync.when(
        data: (data) {
          if (data == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('This scheduled workout no longer exists.'),
              ),
            );
          }
          return _PlanBody(data: data, scheduleId: scheduleId);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('This scheduled workout no longer exists.'),
          ),
        ),
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.data, required this.scheduleId});

  final PlannedWorkoutPreviewData data;
  final int scheduleId;

  bool get _showStartCta =>
      data.plan.exercises.isNotEmpty &&
      (data.status == ScheduleStatus.planned ||
          data.status == ScheduleStatus.moved);

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(scheduledWorkoutServiceProvider)
          .startScheduledWorkoutById(scheduleId);
      ref.read(mainTabIndexProvider.notifier).state = 2;
      if (context.mounted) Navigator.of(context).pop();
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = data.plan;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${plan.name} · ${plan.exercises.length} exercises',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 16),
        for (final (index, plannedExercise) in plan.exercises.indexed) ...[
          Builder(
            builder: (context) {
              final exercise = data.exercises[plannedExercise.exerciseId];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (exercise != null)
                      ExerciseArtwork(
                        exercise: exercise,
                        size: 44,
                        radius: 10,
                        equipmentVariant: plannedExercise.equipmentVariant,
                      )
                    else
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.fitness_center_rounded,
                          size: 20,
                          color: AppColors.primary,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exercise?.name ?? 'Exercise',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            formatPlannedExerciseSets(plannedExercise),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (index != plan.exercises.length - 1) const SizedBox(height: 8),
        ],
        if (plan.exercises.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'No exercises are planned yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ),
        if (_showStartCta) ...[
          const SizedBox(height: 24),
          Center(
            child: Consumer(
              builder: (context, ref, _) => PremiumButton(
                text: 'Start workout',
                icon: Icons.play_arrow_rounded,
                onTap: () => _start(context, ref),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Formats [exercise]'s sets into the same segment-string convention as
/// `SlotPrescription.format()` — consecutive sets sharing identical reps,
/// set type, intent, %1RM and warmup status are grouped into one run (e.g.
/// `"2x8 @40% + 3x8 @70%"`), so the preview shows real set-by-set detail
/// rather than a single compact summary line.
///
/// Public (not `_`-prefixed) so it can be unit-tested directly; used only by
/// [_PlanBody] in this file otherwise.
@visibleForTesting
String formatPlannedExerciseSets(PlannedExerciseSnapshot exercise) {
  if (exercise.sets.isEmpty) return 'No sets prescribed';
  final runs = <List<PlannedSetSnapshot>>[];
  for (final set in exercise.sets) {
    final currentRun = runs.isEmpty ? null : runs.last;
    if (currentRun != null && _sameSetRun(currentRun.last, set)) {
      currentRun.add(set);
    } else {
      runs.add([set]);
    }
  }
  final segments = runs.map(_formatSetRun).join(' + ');
  return '$segments · Rest ${exercise.restSeconds}s';
}

bool _sameSetRun(PlannedSetSnapshot a, PlannedSetSnapshot b) {
  return a.repsMin == b.repsMin &&
      a.repsMax == b.repsMax &&
      a.setType == b.setType &&
      a.intent == b.intent &&
      a.percentOf1Rm == b.percentOf1Rm &&
      a.isWarmup == b.isWarmup;
}

String _formatSetRun(List<PlannedSetSnapshot> run) {
  final first = run.first;
  final count = run.length;
  final reps = first.repsMin == first.repsMax
      ? '${first.repsMin ?? '—'}'
      : '${first.repsMin ?? '—'}-${first.repsMax ?? '—'}';
  final buffer = StringBuffer('${count}x$reps');

  if (first.percentOf1Rm != null) {
    buffer.write(' @${(first.percentOf1Rm! * 100).round()}%');
  } else {
    final intent = slot_prescription.Intent.fromId(first.intent);
    if (intent != slot_prescription.Intent.amrap &&
        intent != slot_prescription.Intent.toFailure) {
      buffer.write(' @RIR${intent.rir}');
    }
  }

  final setType = SetType.fromId(first.setType);
  if (setType != SetType.standard) {
    buffer.write(' ${setType.label}');
  }

  final formatted = buffer.toString();
  return first.isWarmup ? 'Warmup: $formatted' : formatted;
}
