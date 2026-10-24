import 'dart:convert';

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
import 'package:herculex/features/workouts/presentation/sheets/exercise_affinity_sheet.dart';
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
        _AnimatedEntrance(
          child: _ExerciseHeroCard(exercise: exercise, metric: metric),
        ),
        const SizedBox(height: 24),
        const _DetailSectionHeading(
          icon: Icons.insights_rounded,
          title: 'Your progress',
          subtitle: 'Trends and personal performance for this movement',
        ),
        // An estimated 1RM is a weight for a rep. A plank, a sled push and a
        // row erg have no such number, so the trend card is simply absent
        // rather than plotting a flat line through their placeholder zeros
        // (EXR-05).
        if (metric.isRepBased && metric.isLoaded) ...[
          _AnimatedEntrance(
            child: AdvancedTrendCard(exerciseId: exercise.id, metric: metric),
          ),
          const SizedBox(height: 14),
          _AnimatedEntrance(
            child: ResistanceProfileCard(
              exerciseId: exercise.id,
              metric: metric,
            ),
          ),
          const SizedBox(height: 14),
        ],
        _AnimatedEntrance(
          child: CalisthenicsStatsCard(exercise: exercise, metric: metric),
        ),
        const SizedBox(height: 14),
        _AnimatedEntrance(
          child: _PerformanceCard(
            title: 'By equipment',
            async: byEquipment,
            weightFormat: weightFormat,
            metric: metric,
            labelOf: (record) => equipmentVariantLabel(record.label),
          ),
        ),
        const SizedBox(height: 14),
        _AnimatedEntrance(
          child: _PerformanceCard(
            title: 'By accessories',
            async: byAccessory,
            weightFormat: weightFormat,
            metric: metric,
            labelOf: (record) => record.label,
          ),
        ),
        const SizedBox(height: 24),
        const _DetailSectionHeading(
          icon: Icons.tune_rounded,
          title: 'Your setup',
          subtitle: 'Personal preferences, programming and movement details',
        ),
        _AnimatedEntrance(
          child: _ProgrammingPreferenceCard(exercise: exercise),
        ),
        const SizedBox(height: 14),
        _AnimatedEntrance(child: ErgonomicsCard(exercise: exercise)),
        const SizedBox(height: 14),
        _AnimatedEntrance(child: _ProgressionGoalCard(exercise: exercise)),
        const SizedBox(height: 14),
        _AnimatedEntrance(
          child: _ExerciseSetupCard(exercise: exercise, metric: metric),
        ),
        const SizedBox(height: 24),
        const _DetailSectionHeading(
          icon: Icons.history_rounded,
          title: 'Training history',
          subtitle: 'Your latest completed sessions',
        ),
        _AnimatedEntrance(
          child: ExerciseTimelineCard(
            exerciseId: exercise.id,
            metric: metric,
            weightFormat: weightFormat,
          ),
        ),
      ],
    );
  }
}

class _ExerciseHeroCard extends StatelessWidget {
  const _ExerciseHeroCard({required this.exercise, required this.metric});

  final ExerciseCatalogData exercise;
  final LoggingMetric metric;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            hx.primary.withValues(alpha: hx.isDark ? 0.25 : 0.14),
            hx.surfaceContainerLowest,
            hx.tertiary.withValues(alpha: hx.isDark ? 0.12 : 0.07),
          ],
        ),
        border: Border.all(color: hx.primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: hx.primary.withValues(alpha: hx.isDark ? 0.12 : 0.08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Stack(
          children: [
            Positioned(
              top: -54,
              right: -42,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hx.primary.withValues(alpha: hx.isDark ? 0.13 : 0.08),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.fitness_center_rounded,
                                  size: 14,
                                  color: hx.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  exercise.category.toUpperCase(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: hx.primary,
                                    letterSpacing: 1.1,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              exercise.name,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.08,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              exercise.primaryMuscle,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: hx.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 112,
                        height: 112,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: hx.surfaceContainerLowest.withValues(
                            alpha: hx.isDark ? 0.65 : 0.75,
                          ),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: hx.onSurface.withValues(alpha: 0.08),
                          ),
                        ),
                        child: ExerciseArtwork(
                          exercise: exercise,
                          size: 104,
                          radius: 21,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        label: exercise.equipment,
                        icon: Icons.sports_gymnastics_rounded,
                      ),
                      _InfoChip(
                        label: metric.label,
                        icon: Icons.straighten_rounded,
                      ),
                      if (exercise.isCustom)
                        const _InfoChip(
                          label: 'Custom',
                          icon: Icons.edit_rounded,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSectionHeading extends StatelessWidget {
  const _DetailSectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: hx.primary.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: hx.primary, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: hx.secondary,
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

class _AnimatedEntrance extends StatelessWidget {
  const _AnimatedEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: HxMotion.slower,
      curve: HxMotion.emphasized,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

class _ProgrammingPreferenceCard extends ConsumerWidget {
  const _ProgrammingPreferenceCard({required this.exercise});

  final ExerciseCatalogData exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final selected =
        ref.watch(exerciseAffinityProvider(exercise.id)).asData?.value ??
        ExerciseAffinity.okay;
    final (affinityColor, affinityIcon) = ExerciseAffinitySheet.visualFor(
      selected,
    );
    final affinityDesc = ExerciseAffinitySheet.descriptionFor(selected);

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Programming preference',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Used by Smart exercise selection. “Never” is a hard filter.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: affinityColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: affinityColor.withValues(alpha: 0.35)),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => ExerciseAffinitySheet.show(
                  context,
                  exercise: exercise,
                  currentAffinity: selected,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: affinityColor.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          affinityIcon,
                          size: 20,
                          color: affinityColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selected.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: affinityColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              affinityDesc,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: hx.secondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: hx.secondary,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            exercise.maxEffortEligibility == MaxEffortEligibility.eligible.id
                ? 'Eligible for Smart Max Effort selection.'
                : exercise.maxEffortEligibility ==
                      MaxEffortEligibility.advancedOnly.id
                ? 'Max Effort is available only as an advanced manual choice.'
                : 'Not suitable for Max Effort.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
            ),
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
    final hx = context.hx;
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
                ? _PerformanceEmptyState(metric: metric)
                : Builder(
                    builder: (context) {
                      final peak = records
                          .map(
                            (record) =>
                                record.bestE1RmKg ?? record.bestWeightKg,
                          )
                          .fold<double>(
                            0,
                            (current, value) =>
                                value > current ? value : current,
                          );
                      return Column(
                        children: [
                          for (final record in records)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          labelOf(record),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      if (record.bestE1RmKg != null &&
                                          metric.isRepBased &&
                                          metric.isLoaded)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: hx.primary.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            weightFormat.format(
                                              record.bestE1RmKg!,
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                  color: hx.primary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    metric.isRepBased && metric.isLoaded
                                        ? '${weightFormat.format(record.bestWeightKg)} × ${record.bestWeightReps} reps · ${record.setCount} sets'
                                        : '${record.setCount} sets',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: hx.secondary),
                                  ),
                                  const SizedBox(height: 9),
                                  _PerformanceTrack(
                                    value: peak == 0
                                        ? 0
                                        : ((record.bestE1RmKg ??
                                                      record.bestWeightKg) /
                                                  peak)
                                              .clamp(0.0, 1.0)
                                              .toDouble(),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceTrack extends StatelessWidget {
  const _PerformanceTrack({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 7,
        color: hx.surfaceVariant,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value),
          duration: HxMotion.slower,
          curve: HxMotion.emphasized,
          builder: (context, progress, _) => FractionallySizedBox(
            widthFactor: progress,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [hx.primary, hx.tertiary]),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PerformanceEmptyState extends StatelessWidget {
  const _PerformanceEmptyState({required this.metric});

  final LoggingMetric metric;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hx.surfaceVariant.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_outlined, color: hx.secondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              metric.isRepBased
                  ? 'Complete a session to compare your best sets here.'
                  : 'Performance comparisons are available after you log this movement.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: hx.secondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _InfoChip({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseSetupCard extends ConsumerWidget {
  const _ExerciseSetupCard({required this.exercise, required this.metric});

  final ExerciseCatalogData exercise;
  final LoggingMetric metric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final snapshot = ref.watch(trainingSnapshotProvider).asData?.value;
    final muscleRows =
        snapshot?.exerciseMuscles
            .where((row) => row.exerciseId == exercise.id)
            .toList() ??
        const <ExerciseMuscleData>[];

    final muscleSummary = _muscleSummary(muscleRows, exercise.primaryMuscle);
    final attachments = _attachmentLabels(exercise.attachments);
    final details = <(String, String)>[
      ('Equipment', exercise.equipment),
      ('Load type', _humanize(exercise.modality)),
      ('Exercise type', _humanize(exercise.mechanics)),
      ('Force', _humanize(exercise.force)),
      ('Movement plane', _humanize(exercise.plane)),
      (
        'Movement pattern',
        _humanize(
          exercise.movementPatternRaw ??
              exercise.movementPattern ??
              exercise.mechanics,
        ),
      ),
      ('Logged as', metric.label),
      ('Rest target', _restTarget(exercise.defaultRestSeconds)),
      ('CNS demand', '${exercise.cnsScore} / 10'),
      ('Recovery impact', '${exercise.recoveryImpact} / 5'),
      ('Muscles involved', muscleSummary),
      if (attachments.isNotEmpty) ('Attachments', attachments.join(' · ')),
      if (exercise.aka?.trim().isNotEmpty ?? false)
        ('Also known as', exercise.aka!.trim()),
      if (exercise.supportsWeightedBodyweight)
        ('Bodyweight loading', 'Added weight supported'),
      if (!exercise.isCustom)
        ('Catalog review', exercise.isReviewed ? 'Reviewed' : 'Needs review'),
    ];

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, color: hx.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Movement details',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (label, value) in details)
                    SizedBox(
                      width: width,
                      child: _SetupValueTile(label: label, value: value),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _muscleSummary(List<ExerciseMuscleData> rows, String fallback) {
    String names(String role) => rows
        .where((row) => row.role == role)
        .map((row) => row.muscle)
        .toSet()
        .join(', ');

    final primary = names('primary');
    final secondary = names('secondary');
    final stabilizers = names('stabilizer');
    final lines = <String>[];
    if (primary.isNotEmpty) lines.add('Primary: $primary');
    if (secondary.isNotEmpty) lines.add('Assist: $secondary');
    if (stabilizers.isNotEmpty) lines.add('Stabilizers: $stabilizers');
    return lines.isEmpty ? fallback : lines.join('\n');
  }

  List<String> _attachmentLabels(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final values = jsonDecode(raw);
      if (values is List) return values.whereType<String>().toList();
    } on FormatException {
      return [raw];
    }
    return const [];
  }

  String _humanize(String value) => value
      .split(RegExp(r'[_\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  String _restTarget(int seconds) {
    if (seconds < 60) return '$seconds sec';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return remainder == 0 ? '$minutes min' : '$minutes min $remainder sec';
  }
}

class _SetupValueTile extends StatelessWidget {
  const _SetupValueTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hx.surfaceVariant.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: hx.secondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.45,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
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
