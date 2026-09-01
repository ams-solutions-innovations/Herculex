import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/core/units.dart';
import 'package:herculex/features/analytics/domain/muscle_volume_details.dart';
import 'package:herculex/features/analytics/presentation/muscle_volume_providers.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/theme/haptics.dart';
import 'package:herculex/theme/tokens/tokens.dart';
import 'package:herculex/ui/ui.dart';
import 'package:intl/intl.dart';

/// Detailed view showing exercise history, workouts, and dates for a specific muscle.
class MuscleVolumeDetailView extends ConsumerWidget {
  const MuscleVolumeDetailView({super.key, required this.muscle});

  final String muscle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(muscleVolumeDetailProvider(muscle));
    final selectedTimeframe = ref.watch(selectedVolumeTimeframeProvider);

    return HxScreenShell(
      title: '$muscle Volume',
      children: [
        detailAsync.when(
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MuscleDetailHeaderCard(data: data),
              const SizedBox(height: HxSpace.x4),
              _DetailTimeframeSelector(currentTimeframe: selectedTimeframe),
              const SizedBox(height: HxSpace.x4),
              if (data.workouts.isEmpty)
                _EmptyWorkoutsCard(
                  muscle: muscle,
                  timeframe: data.timeframe,
                  onSelectAllTime: () {
                    Haptics.selection();
                    ref.read(selectedVolumeTimeframeProvider.notifier).state =
                        VolumeTimeframe.allTime;
                  },
                )
              else
                _WorkoutSessionsList(data: data),
            ],
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: HxSpace.x8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(HxSpace.x6),
              child: Text(
                'Failed to load muscle details: $e',
                style: TextStyle(color: context.hx.danger),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 1. Muscle Header Card ───────────────────────────────────────────────────

class _MuscleDetailHeaderCard extends ConsumerWidget {
  const _MuscleDetailHeaderCard({required this.data});

  final MuscleGroupDetailData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final weight = ref.watch(weightFormatProvider);

    return HxCard(
      accent: hx.domainTraining,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    data.muscle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: hx.outlineVariant.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      data.region.label,
                      style: TextStyle(
                        fontSize: 10,
                        color: hx.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hx.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  data.timeframe.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hx.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x3),
          Text(
            weight.formatTonnage(data.totalTonnageKg),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: hx.primary,
            ),
          ),
          const SizedBox(height: HxSpace.x4),
          Row(
            children: [
              Expanded(
                child: _DetailStatTile(
                  label: 'Working Sets',
                  value: data.totalSets.toStringAsFixed(
                    data.totalSets < 10 ? 1 : 0,
                  ),
                  icon: Icons.fitness_center,
                ),
              ),
              const SizedBox(width: HxSpace.x2),
              Expanded(
                child: _DetailStatTile(
                  label: 'Total Reps',
                  value: '${data.totalReps}',
                  icon: Icons.repeat,
                ),
              ),
              const SizedBox(width: HxSpace.x2),
              Expanded(
                child: _DetailStatTile(
                  label: 'Workouts',
                  value: '${data.workoutsCount}',
                  icon: Icons.calendar_today,
                ),
              ),
            ],
          ),
          if (data.topExercise != null) ...[
            const SizedBox(height: HxSpace.x3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: hx.surfaceContainer,
                borderRadius: BorderRadius.circular(HxRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.star_rounded, size: 16, color: hx.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Most Frequent: ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hx.secondary,
                      fontSize: 11,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      data.topExercise!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailStatTile extends StatelessWidget {
  const _DetailStatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hx.surfaceContainer,
        borderRadius: BorderRadius.circular(HxRadius.md),
        border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: hx.secondary),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: hx.secondary,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── 2. Timeframe Selector ────────────────────────────────────────────────────

class _DetailTimeframeSelector extends ConsumerWidget {
  const _DetailTimeframeSelector({required this.currentTimeframe});

  final VolumeTimeframe currentTimeframe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tf in VolumeTimeframe.values) ...[
            GestureDetector(
              onTap: () {
                Haptics.selection();
                ref.read(selectedVolumeTimeframeProvider.notifier).state = tf;
              },
              child: AnimatedContainer(
                duration: HxMotion.base,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: tf == currentTimeframe
                      ? hx.primary
                      : hx.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(HxRadius.pill),
                  border: Border.all(
                    color: tf == currentTimeframe
                        ? hx.primary
                        : hx.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  tf.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: tf == currentTimeframe
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: tf == currentTimeframe ? Colors.white : hx.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(width: HxSpace.x2),
          ],
        ],
      ),
    );
  }
}

// ── 3. Empty State ───────────────────────────────────────────────────────────

class _EmptyWorkoutsCard extends StatelessWidget {
  const _EmptyWorkoutsCard({
    required this.muscle,
    required this.timeframe,
    required this.onSelectAllTime,
  });

  final String muscle;
  final VolumeTimeframe timeframe;
  final VoidCallback onSelectAllTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return HxCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HxSpace.x6),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.fitness_center_outlined,
                size: 40,
                color: hx.secondary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: HxSpace.x3),
              Text(
                'No sets logged for $muscle',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'No recorded exercises in ${timeframe.label.toLowerCase()}.',
                style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
                textAlign: TextAlign.center,
              ),
              if (timeframe != VolumeTimeframe.allTime) ...[
                const SizedBox(height: HxSpace.x4),
                ElevatedButton.icon(
                  onPressed: onSelectAllTime,
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('View All Time History'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hx.surfaceContainer,
                    foregroundColor: hx.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(HxRadius.pill),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── 4. Workout Sessions List ─────────────────────────────────────────────────

class _WorkoutSessionsList extends ConsumerWidget {
  const _WorkoutSessionsList({required this.data});

  final MuscleGroupDetailData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final weight = ref.watch(weightFormatProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            'TRAINING SESSIONS (${data.workouts.length})',
            style: theme.textTheme.labelSmall?.copyWith(
              color: hx.secondary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        for (final session in data.workouts) ...[
          _WorkoutSessionCard(session: session, weight: weight),
          const SizedBox(height: HxSpace.x4),
        ],
      ],
    );
  }
}

class _WorkoutSessionCard extends StatelessWidget {
  const _WorkoutSessionCard({required this.session, required this.weight});

  final MuscleWorkoutSessionItem session;
  final WeightFormat weight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    final dateStr = DateFormat('EEEE, MMM d, yyyy').format(session.date);
    final timeStr = DateFormat('HH:mm').format(session.date);
    final relDate = _relativeDate(session.date);

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          dateStr,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: hx.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            relDate,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: hx.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${session.sessionName} • $timeStr',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hx.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  Haptics.selection();
                  context.push('/workout-history/${session.sessionId}');
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: hx.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hx.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: hx.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_forward, size: 12, color: hx.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Volume Summary for this session
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: hx.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${session.exercises.length} exercise${session.exercises.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: hx.secondary,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '${session.muscleSets.toStringAsFixed(session.muscleSets < 10 ? 1 : 0)} sets • ${weight.formatTonnage(session.muscleTonnageKg)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: hx.onSurface,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Exercises List
          for (var i = 0; i < session.exercises.length; i++) ...[
            if (i > 0) const Divider(height: 20),
            _ExerciseSection(exercise: session.exercises[i], weight: weight),
          ],
        ],
      ),
    );
  }

  String _relativeDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${diff}d ago';
    return DateFormat('MMM d').format(date);
  }
}

class _ExerciseSection extends StatelessWidget {
  const _ExerciseSection({required this.exercise, required this.weight});

  final MuscleWorkoutExerciseItem exercise;
  final WeightFormat weight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    final roleColor = switch (exercise.role.toLowerCase()) {
      'primary' => hx.success,
      'secondary' => hx.warning,
      _ => hx.secondary,
    };

    final roleLabel = switch (exercise.role.toLowerCase()) {
      'primary' => 'Primary (100%)',
      'secondary' => 'Secondary (50%)',
      'stabilizer' => 'Stabilizer (20%)',
      _ => exercise.role,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  Haptics.selection();
                  context.push('/exercise/${exercise.exerciseId}');
                },
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        exercise.exerciseName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: hx.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: hx.secondary.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                roleLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: roleColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Sets list
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: hx.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hx.outlineVariant.withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < exercise.sets.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 8,
                    color: hx.outlineVariant.withValues(alpha: 0.1),
                  ),
                _SetRow(
                  setNumber: i + 1,
                  set: exercise.sets[i],
                  weight: weight,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.setNumber,
    required this.set,
    required this.weight,
  });

  final int setNumber;
  final MuscleSetItem set;
  final WeightFormat weight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '$setNumber',
            style: theme.textTheme.bodySmall?.copyWith(
              color: hx.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Text(
                '${weight.format(set.weightKg)} × ${set.reps}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (set.rpeX10 != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: hx.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '@${(set.rpeX10! / 10).toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: hx.primary,
                    ),
                  ),
                ),
              ],
              if (set.setType != SetType.standard) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: hx.outlineVariant.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    set.setType.label,
                    style: TextStyle(
                      fontSize: 9,
                      color: hx.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          weight.format(set.tonnageKg),
          style: theme.textTheme.bodySmall?.copyWith(
            color: hx.secondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
