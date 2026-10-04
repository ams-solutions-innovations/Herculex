import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/components/hx_screen_shell.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/analytics/domain/variant_performance.dart';
import 'package:herculex/features/profile/domain/anthropometry.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/exercise_ergonomics.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/progression_engine.dart';
import 'package:herculex/features/workouts/presentation/sheets/progression_override_sheet.dart';
import 'package:herculex/features/workouts/presentation/widgets/exercise_analytics_cards.dart';
import 'package:herculex/features/workouts/presentation/widgets/exercise_artwork.dart';

class ExerciseDetailsView extends ConsumerWidget {
  final int exerciseId;

  const ExerciseDetailsView({super.key, required this.exerciseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(
      exerciseCatalogProvider(const ExerciseCatalogFilter()),
    );

    return catalog.when(
      loading: () => const _DetailsLoading(),
      error: (error, _) =>
          _DetailsMessage(message: 'Failed to load exercise: $error'),
      data: (exercises) {
        ExerciseCatalogData? exercise;
        for (final candidate in exercises) {
          if (candidate.id == exerciseId) {
            exercise = candidate;
            break;
          }
        }
        if (exercise == null) {
          return const _DetailsMessage(message: 'Exercise not found');
        }
        return _ExerciseDetailsBody(exercise: exercise);
      },
    );
  }
}

class _ExerciseDetailsBody extends ConsumerWidget {
  final ExerciseCatalogData exercise;

  const _ExerciseDetailsBody({required this.exercise});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byEquipment = ref.watch(equipmentPerformanceProvider(exercise.id));
    final byAccessory = ref.watch(accessoryPerformanceProvider(exercise.id));
    final weightFormat = ref.watch(weightFormatProvider);
    final metric = LoggingMetric.fromId(exercise.loggingMetric);

    return HxScreenShell(
      title: exercise.name,
      children: [
        Center(
          child: ExerciseArtwork(exercise: exercise, size: 190, radius: 24),
        ),
        const SizedBox(height: 18),
        HxCard(
          accent: AppColors.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                exercise.name,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(label: exercise.primaryMuscle),
                  _InfoChip(label: exercise.equipment),
                  _InfoChip(label: exercise.mechanics),
                  _InfoChip(label: exercise.force),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ProgrammingPreferenceCard(exercise: exercise),
        const SizedBox(height: 14),
        ErgonomicsCard(exercise: exercise),
        const SizedBox(height: 14),
        // An estimated 1RM is a weight for a rep. A plank, a sled push and a
        // row erg have no such number, so the trend card is simply absent
        // rather than plotting a flat line through their placeholder zeros
        // (EXR-05).
        if (metric.isRepBased && metric.isLoaded) ...[
          AdvancedTrendCard(exerciseId: exercise.id, metric: metric),
          const SizedBox(height: 14),
          ResistanceProfileCard(exerciseId: exercise.id, metric: metric),
          const SizedBox(height: 14),
        ],
        CalisthenicsStatsCard(exercise: exercise, metric: metric),
        const SizedBox(height: 14),
        _PerformanceCard(
          title: 'By equipment',
          async: byEquipment,
          weightFormat: weightFormat,
          metric: metric,
          labelOf: (record) => equipmentVariantLabel(record.label),
        ),
        const SizedBox(height: 14),
        _PerformanceCard(
          title: 'By accessories',
          async: byAccessory,
          weightFormat: weightFormat,
          metric: metric,
          labelOf: (record) => record.label,
        ),
        const SizedBox(height: 14),
        _ProgressionGoalCard(exercise: exercise),
        const SizedBox(height: 14),
        ExerciseTimelineCard(exerciseId: exercise.id),
        const SizedBox(height: 14),
        HxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exercise setup',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _DetailRow(label: 'Equipment', value: exercise.equipment),
              _DetailRow(label: 'Movement', value: exercise.mechanics),
              _DetailRow(label: 'Force', value: exercise.force),
              _DetailRow(label: 'Plane', value: exercise.plane),
              _DetailRow(
                label: 'Rest target',
                value: '${exercise.defaultRestSeconds ~/ 60} min',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgrammingPreferenceCard extends ConsumerWidget {
  const _ProgrammingPreferenceCard({required this.exercise});

  final ExerciseCatalogData exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected =
        ref.watch(exerciseAffinityProvider(exercise.id)).asData?.value ??
        ExerciseAffinity.okay;
    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Programming preference',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Used by Smart exercise selection. “Never” is a hard filter.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.secondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final affinity in ExerciseAffinity.values)
                ChoiceChip(
                  label: Text(affinity.label),
                  selected: selected == affinity,
                  onSelected: (_) => ref
                      .read(exercisePreferencesRepositoryProvider)
                      .setAffinity(exerciseId: exercise.id, affinity: affinity),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            exercise.maxEffortEligibility == MaxEffortEligibility.eligible.id
                ? 'Eligible for Smart Max Effort selection.'
                : exercise.maxEffortEligibility ==
                      MaxEffortEligibility.advancedOnly.id
                ? 'Max Effort is available only as an advanced manual choice.'
                : 'Not suitable for Max Effort.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.secondary),
          ),
        ],
      ),
    );
  }
}

class ErgonomicsCard extends ConsumerWidget {
  const ErgonomicsCard({super.key, required this.exercise});

  final ExerciseCatalogData exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slug = exercise.movementSlug;
    if (slug == null) return const SizedBox.shrink();

    final profile = ref.watch(profileProvider).asData?.value;
    if (profile == null) return const SizedBox.shrink();

    final ratios = AnthropometryRatios(profile);
    if (!ratios.hasRequiredMeasurements) return const SizedBox.shrink();

    final ergoRepo = ref
        .watch(exerciseErgonomicsRepositoryProvider)
        .asData
        ?.value;
    if (ergoRepo == null) return const SizedBox.shrink();

    final ergonomics = ergoRepo.getForMovement(slug);
    if (ergonomics == null) return const SizedBox.shrink();

    final activeGuidance = <ErgonomicGuidance>[];

    // Legs / Femur
    if (ratios.legProportion == LegProportion.long) {
      final g =
          ergonomics.guidanceByRatio['long_femur'] ??
          ergonomics.guidanceByRatio['long_legs'];
      if (g != null) activeGuidance.add(g);
    } else if (ratios.legProportion == LegProportion.short) {
      final g =
          ergonomics.guidanceByRatio['short_femur'] ??
          ergonomics.guidanceByRatio['short_legs'];
      if (g != null) activeGuidance.add(g);
    }

    // Torso
    if (ratios.torsoProportion == TorsoProportion.short) {
      final g = ergonomics.guidanceByRatio['short_torso'];
      if (g != null) activeGuidance.add(g);
    } else if (ratios.torsoProportion == TorsoProportion.long) {
      final g = ergonomics.guidanceByRatio['long_torso'];
      if (g != null) activeGuidance.add(g);
    }

    // Arms
    if (ratios.armProportion == ArmProportion.long) {
      final g = ergonomics.guidanceByRatio['long_arms'];
      if (g != null) activeGuidance.add(g);
    } else if (ratios.armProportion == ArmProportion.short) {
      final g = ergonomics.guidanceByRatio['short_arms'];
      if (g != null) activeGuidance.add(g);
    }

    if (activeGuidance.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.accessibility_new, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Anthropometric Ergonomics',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Guidance tailored to your body proportions',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in activeGuidance) ...[
            Text(item.guidance, style: theme.textTheme.bodyMedium),
            if (item.sources.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Sources: ${item.sources.join(", ")}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PerformanceCard extends StatelessWidget {
  final String title;
  final AsyncValue<List<PerformanceRecord>> async;
  final WeightFormat weightFormat;

  /// What the exercise is measured in. Decides whether the per-variant line
  /// can honestly quote a best weight and reps at all (EXR-05).
  final LoggingMetric metric;
  final String Function(PerformanceRecord) labelOf;

  const _PerformanceCard({
    required this.title,
    required this.async,
    required this.weightFormat,
    required this.metric,
    required this.labelOf,
  });

  @override
  Widget build(BuildContext context) {
    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          async.when(
            loading: () => const _CardLoading(),
            error: (error, _) => Text('Could not load data: $error'),
            data: (records) => records.isEmpty
                ? const Text('No completed sets yet')
                : Column(
                    children: [
                      for (final record in records)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      labelOf(record),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    Text(
                                      metric.isRepBased && metric.isLoaded
                                          ? '${weightFormat.format(record.bestWeightKg)} × ${record.bestWeightReps} reps · ${record.setCount} sets'
                                          // A best set of a timed or measured
                                          // movement is not a weight for a rep;
                                          // the honest number here is how much
                                          // of it was done.
                                          : '${record.setCount} sets',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.secondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              if (record.bestE1RmKg != null &&
                                  metric.isRepBased &&
                                  metric.isLoaded)
                                Text(
                                  weightFormat.format(record.bestE1RmKg!),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.secondary),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _CardLoading extends StatelessWidget {
  const _CardLoading();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 44,
    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
  );
}

class _DetailsLoading extends StatelessWidget {
  const _DetailsLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.transparent,
    body: Center(child: CircularProgressIndicator()),
  );
}

class _DetailsMessage extends StatelessWidget {
  final String message;

  const _DetailsMessage({required this.message});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: Center(child: Text(message)),
  );
}

class _ProgressionGoalCard extends ConsumerWidget {
  final ExerciseCatalogData exercise;

  const _ProgressionGoalCard({required this.exercise});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressionAsync = ref.watch(
      exerciseProgressionProvider(exercise.id),
    );
    final theme = Theme.of(context);
    final hx = context.hx;

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progression Strategy',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.edit_outlined, size: 20, color: hx.primary),
                tooltip: 'Configure Progression',
                onPressed: () => ProgressionOverrideSheet.show(
                  context,
                  exerciseId: exercise.id,
                  exerciseName: exercise.name,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          progressionAsync.when(
            loading: () => const _CardLoading(),
            error: (e, _) => Text('Could not load progression: $e'),
            data: (progression) {
              if (progression == null || !progression.enabled) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Double Progression (Default: Muscle Gain)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rep target: 8–12 reps · Weekly increase: +2.5%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => ProgressionOverrideSheet.show(
                        context,
                        exerciseId: exercise.id,
                        exerciseName: exercise.name,
                      ),
                      child: Text(
                        'Customize progression goal…',
                        style: TextStyle(
                          color: hx.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                );
              }

              final goal = ProgressionGoal.values.firstWhere(
                (g) => g.name == progression.goal,
                orElse: () => ProgressionGoal.muscleGain,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: hx.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          goal.label,
                          style: TextStyle(
                            color: hx.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${goal.repsMin}–${goal.repsMax} reps',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Weekly increase: +${progression.weeklyIncreasePct.toStringAsFixed(1)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
