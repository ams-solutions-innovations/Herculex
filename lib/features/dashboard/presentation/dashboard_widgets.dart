import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/units.dart';
import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../analytics/domain/weekly_muscle_volume.dart';
import '../../analytics/presentation/analytics_providers.dart';
import '../../gyms/presentation/gym_picker_sheet.dart';
import '../../nutrition/domain/daily_totals.dart';
import '../../nutrition/domain/macro_targets.dart';
import '../../workouts/presentation/exercise_picker_sheet.dart';
import '../../workouts/presentation/workouts_providers.dart';
import '../../nutrition/presentation/nutrition_providers.dart';
import '../../nutrition/presentation/barcode_scanner_view.dart';
import '../../nutrition/presentation/custom_food_form_sheet.dart';
import '../../nutrition/presentation/food_picker_sheet.dart';
import '../../nutrition/presentation/log_entry_sheet.dart';
import '../../nutrition/domain/barcode_utils.dart';
import '../../shell/main_scaffold.dart';
import '../domain/streaks.dart';
import 'dashboard_providers.dart';

Widget _card({required Widget child}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        // Pill-family radius shared with GlassContainer, so dashboard cards
        // read as capsules rather than squircles.
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: child,
    );

/// Fully-rounded "pill" surface used by the compact single-line dashboard
/// widgets (CNS Load, Total Volume …). [radius] animates so a pill can open
/// into a card without the shape jumping.
class _Pill extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsets padding;

  const _Pill({
    required this.child,
    this.onTap,
    this.radius = 999,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(radius),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

Widget _title(BuildContext context, String text) => Text(text,
    style: Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.bold));

/// Smart workout launcher (§18): reads the day's scheduled workout and offers
/// to start it pre-populated. "Start Leg Day?" → Yes starts a real session.
class SmartWorkoutLauncherCard extends ConsumerWidget {
  const SmartWorkoutLauncherCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todaysScheduledWorkoutProvider);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(context, "Today's Plan"),
          const SizedBox(height: 12),
          today.when(
            data: (workout) {
              if (workout == null) {
                return Text('No workout scheduled today.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.secondary));
              }
              if (workout.isDone) {
                return Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text('${workout.programDay.name} complete',
                        style: theme.textTheme.titleSmall),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(workout.programDay.name,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text('${workout.exerciseCount} exercises planned',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.secondary)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: Text('Start ${workout.programDay.name}?'),
                      onPressed: () async {
                        final gym =
                            await GymPickerSheet.resolve(context, ref);
                        if (gym.cancelled) return;
                        await ref
                            .read(scheduledWorkoutServiceProvider)
                            .startScheduledWorkout(workout, gymId: gym.gymId);
                        ref.invalidate(todaysScheduledWorkoutProvider);
                      },
                    ),
                  ),
                ],
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}

/// Compact recovery overview (§18) reusing the Phase-3 19-group engine: shows
/// the most-fatigued groups.
class RecoverySummaryCard extends ConsumerWidget {
  const RecoverySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recovery = ref.watch(recoveryV3Provider);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(context, 'Recovery'),
          const SizedBox(height: 12),
          recovery.when(
            data: (groups) {
              final sorted = [...groups]
                ..sort((a, b) => a.recoveryScore.compareTo(b.recoveryScore));
              final worst = sorted.take(4).toList();
              return Column(
                children: [
                  for (final g in worst)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                              width: 92,
                              child: Text(g.muscle,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                              )),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: g.recoveryScore / 100,
                                minHeight: 8,
                                backgroundColor: AppColors.outlineVariant
                                    .withValues(alpha: 0.2),
                                valueColor: AlwaysStoppedAnimation(
                                  g.recoveryScore >= 70
                                      ? Colors.green
                                      : g.recoveryScore >= 30
                                          ? Colors.amber
                                          : Colors.red,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                              width: 36,
                              child: Text('${g.recoveryScore}',
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.secondary))),
                        ],
                      ),
                    ),
                ],
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}

/// CNS readiness mini-card (§18).
class CnsLoadMiniCard extends ConsumerWidget {
  const CnsLoadMiniCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cns = ref.watch(cnsTrendsProvider);
    return _Pill(
      child: Row(
        children: [
          Expanded(child: _title(context, 'CNS Load')),
          cns.when(
            data: (t) {
              final color = switch (t.status) {
                'FRESH' => Colors.green,
                'MODERATE' => Colors.amber,
                _ => Colors.red,
              };
              return Row(
                children: [
                  Text('${(t.readiness * 100).round()}%',
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(t.status,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ),
                ],
              );
            },
            loading: () => const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => const Icon(Icons.error_outline, size: 18),
          ),
        ],
      ),
    );
  }
}

/// This week's total tonnage (§18), as a pill that opens into a per-muscle
/// breakdown of where the volume actually went.
class WeeklyVolumeMiniCard extends ConsumerStatefulWidget {
  const WeeklyVolumeMiniCard({super.key});

  @override
  ConsumerState<WeeklyVolumeMiniCard> createState() =>
      _WeeklyVolumeMiniCardState();
}

class _WeeklyVolumeMiniCardState extends ConsumerState<WeeklyVolumeMiniCard> {
  bool _expanded = false;
  late bool _showSets;

  @override
  void initState() {
    super.initState();
    _showSets =
        ref.read(sharedPreferencesProvider).getBool('show_volume_in_sets') ??
            false;
  }

  void _toggleShowSets() {
    final prefs = ref.read(sharedPreferencesProvider);
    setState(() => _showSets = !_showSets);
    prefs.setBool('show_volume_in_sets', _showSets);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final volume = ref.watch(weeklyMuscleVolumeProvider);
    final data = volume.asData?.value;
    final showSets = _showSets;

    return _Pill(
      radius: _expanded ? 24 : 999,
      padding: EdgeInsets.fromLTRB(24, 16, 16, _expanded ? 20 : 16),
      onTap: data == null ? null : () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _title(context, 'Total Volume'),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        Haptics.selection();
                        _toggleShowSets();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              showSets ? 'Sets' : 'Tonnage',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.swap_horiz, size: 14, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  Haptics.selection();
                  _toggleShowSets();
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: volume.when(
                    data: (v) => Text(
                        showSets ? '${v.totalSets} sets' : _formatTonnage(v.totalTonnageKg),
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                    loading: () => const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    error: (e, _) => const Icon(Icons.error_outline, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(Icons.expand_more,
                    size: 22, color: AppColors.secondary),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_expanded || data == null
                ? const SizedBox(width: double.infinity)
                : _breakdown(theme, data, showSets),
          ),
        ],
      ),
    );
  }

  Widget _breakdown(ThemeData theme, WeeklyMuscleVolume v, bool showSets) {
    if (v.byMuscle.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('No sets logged yet this week.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
      );
    }
    final sortedList = List<MuscleVolume>.from(v.byMuscle);
    if (showSets) {
      sortedList.sort((a, b) => b.sets.compareTo(a.sets));
    } else {
      sortedList.sort((a, b) => b.tonnageKg.compareTo(a.tonnageKg));
    }
    final max = sortedList.isNotEmpty
        ? (showSets ? sortedList.first.sets : sortedList.first.tonnageKg)
        : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text('${v.totalSets} working sets since Monday',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
        const SizedBox(height: 12),
        for (final m in sortedList)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(m.muscle,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis)),
                    if (showSets) ...[
                      Text(_formatTonnage(m.tonnageKg),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.secondary)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 62,
                        child: Text('${m.sets.toStringAsFixed(m.sets < 10 ? 1 : 0)} sets',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                    ] else ...[
                      Text('${m.sets.toStringAsFixed(m.sets < 10 ? 1 : 0)} sets',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.secondary)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 62,
                        child: Text(_formatTonnage(m.tonnageKg),
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: max <= 0
                        ? 0
                        : ((showSets ? m.sets : m.tonnageKg) / max).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Delegates to the active measurement system, so imperial users read
  /// pounds rather than tonnes.
  String _formatTonnage(double kg) =>
      ref.read(weightFormatProvider).formatTonnage(kg);
}

/// Calories left today (§18): `Goal - Food + Exercise`. Tapping opens the
/// nutrition tab.
class RemainingCaloriesCard extends ConsumerWidget {
  const RemainingCaloriesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final r = ref.watch(remainingCaloriesProvider);

    if (r == null) {
      return _Pill(
        child: Row(
          children: [
            Expanded(child: _title(context, 'Remaining')),
            Text('Set a goal',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.secondary)),
          ],
        ),
      );
    }

    final color = r.isOver ? Colors.redAccent : AppColors.macroKcal;
    return _Pill(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
      onTap: () => ref.read(mainTabIndexProvider.notifier).state = 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                  child: _title(
                      context, r.isOver ? 'Over budget' : 'Calories Remaining')),
              Text('${r.remaining.abs()}',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold, color: color)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('kcal',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: r.consumedFraction,
              minHeight: 6,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _term(theme, 'Goal', r.goal, AppColors.secondary),
              _op(theme, '−'),
              _term(theme, 'Food', r.food, AppColors.macroProtein),
              _op(theme, '+'),
              _term(theme, 'Exercise', r.exercise, AppColors.brightness == Brightness.dark ? const Color(0xFF30D158) : const Color(0xFF34C759)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _term(ThemeData theme, String label, int value, Color color) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    fontSize: 9,
                    letterSpacing: 0.8)),
            Text('$value',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      );

  Widget _op(ThemeData theme, String symbol) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            ' ',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              letterSpacing: 0.8,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              symbol,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
}

/// Consecutive days of food logging (§18).
class NutritionStreakCard extends ConsumerWidget {
  const NutritionStreakCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(nutritionStreakProvider);
    return _StreakPill(
      label: 'Nutrition Streak',
      icon: Icons.restaurant,
      unit: s.current == 1 ? 'day' : 'days',
      streak: s,
      color: AppColors.macroProtein,
      onTap: () => ref.read(mainTabIndexProvider.notifier).state = 1,
    );
  }
}

/// Consecutive training weeks (§18). Weeks, not days, so rest days don't
/// break the run.
class WorkoutStreakCard extends ConsumerWidget {
  const WorkoutStreakCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(workoutStreakProvider);
    return _StreakPill(
      label: 'Workout Streak',
      icon: Icons.fitness_center,
      unit: s.current == 1 ? 'week' : 'weeks',
      streak: s,
      color: AppColors.primary,
      onTap: () => ref.read(mainTabIndexProvider.notifier).state = 2,
    );
  }
}

class _StreakPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final String unit;
  final Streak streak;
  final Color color;
  final VoidCallback? onTap;

  const _StreakPill({
    required this.label,
    required this.icon,
    required this.unit,
    required this.streak,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = streak.current == 0;
    return _Pill(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: dim ? 0.08 : 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 18, color: dim ? AppColors.secondary : color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (streak.best > 0)
                  Text('Best ${streak.best} $unit',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.secondary, fontSize: 10)),
              ],
            ),
          ),
          if (streak.activeToday && streak.current > 0) ...[
            Icon(Icons.local_fire_department, size: 18, color: color),
            const SizedBox(width: 4),
          ],
          Text('${streak.current}',
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: dim ? AppColors.secondary : color)),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(unit,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.secondary)),
          ),
        ],
      ),
    );
  }
}

/// Latest estimated 1RM PRs (§18).
class LatestPrsCard extends ConsumerWidget {
  const LatestPrsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prs = ref.watch(topOneRmsProvider);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(context, 'Latest PRs'),
          const SizedBox(height: 12),
          prs.when(
            data: (list) => list.isEmpty
                ? Text('No PRs yet',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondary))
                : Column(
                    children: [
                      for (final p in list.take(3))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                  child: Text(p.exerciseName,
                                      style: theme.textTheme.bodyMedium,
                                      overflow: TextOverflow.ellipsis)),
                              Text(ref.watch(weightFormatProvider).format(p.estimatedOneRmKg, decimals: 0),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary)),
                            ],
                          ),
                        ),
                    ],
                  ),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}

/// Latest bodyweight reading (§18) with quick add and graph dropdown view.
class BodyweightMiniCard extends ConsumerStatefulWidget {
  const BodyweightMiniCard({super.key});

  @override
  ConsumerState<BodyweightMiniCard> createState() => _BodyweightMiniCardState();
}

class _BodyweightMiniCardState extends ConsumerState<BodyweightMiniCard> {
  String _graphRange = '7D';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bw = ref.watch(latestBodyweightProvider);
    final history = ref.watch(bodyweightHistoryProvider);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _title(context, 'Bodyweight'),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _graphRange,
                  icon: Icon(Icons.show_chart, size: 18, color: AppColors.primary),
                  isDense: true,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Off', child: Text('No Graph')),
                    DropdownMenuItem(value: '7D', child: Text('7 Days')),
                    DropdownMenuItem(value: '30D', child: Text('30 Days')),
                    DropdownMenuItem(value: '90D', child: Text('90 Days')),
                    DropdownMenuItem(value: 'All', child: Text('All Time')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      Haptics.selection();
                      setState(() => _graphRange = val);
                    }
                  },
                ),
              ),
              const Spacer(),
              bw.when(
                data: (kg) => Text(
                  kg == null
                      ? '—'
                      : ref.watch(weightFormatProvider).format(kg),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                loading: () => const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (e, _) => const Icon(Icons.error_outline, size: 18),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.add_circle_outline, color: AppColors.primary, size: 22),
                tooltip: 'Quick add bodyweight',
                visualDensity: VisualDensity.compact,
                onPressed: () => _showAddBodyweightDialog(context),
              ),
            ],
          ),
          if (_graphRange != 'Off') ...[
            const SizedBox(height: 12),
            history.when(
              data: (rows) {
                final filtered = _filterHistory(rows, _graphRange);
                if (filtered.length < 2) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Log at least 2 entries to display graph',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                    ),
                  );
                }

                final spots = [
                  for (final (i, r) in filtered.indexed)
                    FlSpot(i.toDouble(), r.value),
                ];

                return SizedBox(
                  height: 120,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: AppColors.primary,
                          barWidth: 3,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.primary.withValues(alpha: 0.15),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const SizedBox(
                height: 40,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Text('Error loading graph: $e'),
            ),
          ],
        ],
      ),
    );
  }

  List<BodyMeasurementData> _filterHistory(List<BodyMeasurementData> rows, String range) {
    if (rows.isEmpty || range == 'All') return rows;
    final now = DateTime.now();
    final days = switch (range) {
      '7D' => 7,
      '30D' => 30,
      '90D' => 90,
      _ => 0,
    };
    if (days == 0) return rows;
    final cutoff = now.subtract(Duration(days: days));
    final filtered = rows.where((r) {
      final parsed = DateTime.tryParse(r.dateIso);
      return parsed != null && parsed.isAfter(cutoff);
    }).toList();
    if (filtered.length < 2 && rows.length >= 2) {
      return rows.sublist((rows.length - 7).clamp(0, rows.length));
    }
    return filtered;
  }

  Future<void> _showAddBodyweightDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final fmt = ref.read(weightFormatProvider);
    final value = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Quick Log Bodyweight'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Weight',
            suffixText: fmt.suffix,
            hintText: fmt.isMetric ? 'e.g. 75.5' : 'e.g. 166',
          ),
          onSubmitted: (v) => Navigator.pop(dialogCtx, double.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, double.tryParse(ctrl.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (value != null && value > 0) {
      Haptics.medium();
      final dateIso = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await ref.read(measurementsRepositoryProvider).logMeasurement(
        dateIso: dateIso,
        metric: 'bodyweight',
        // Measurements are stored in kilograms regardless of display unit.
        value: fmt.toKg(value),
      );
      ref.invalidate(latestBodyweightProvider);
    }
  }
}

/// Live calorie/macro grid (§18) with Average Weekly Calories and interactive trend graph.
class LiveMacrosGrid extends ConsumerStatefulWidget {
  final DailyTotals totals;
  final MacroTargets? targets;
  const LiveMacrosGrid({super.key, required this.totals, required this.targets});

  @override
  ConsumerState<LiveMacrosGrid> createState() => _LiveMacrosGridState();
}

class _LiveMacrosGridState extends ConsumerState<LiveMacrosGrid> {
  String _selectedMacro = 'kcal'; // 'kcal', 'protein', 'carbs', 'fat'
  String _timelineRange = '7D'; // '3D', '7D', '14D', '30D', '90D'

  int _daysForRange(String range) {
    return switch (range) {
      '3D' => 3,
      '7D' => 7,
      '14D' => 14,
      '30D' => 30,
      '90D' => 90,
      _ => 7,
    };
  }

  Color _colorForMacro(String macro) {
    return switch (macro) {
      'kcal' => AppColors.macroKcal,
      'protein' => AppColors.macroProtein,
      'carbs' => AppColors.macroCarbs,
      'fat' => AppColors.macroFat,
      _ => AppColors.macroKcal,
    };
  }

  String _unitForMacro(String macro) {
    return macro == 'kcal' ? 'kcal' : 'g';
  }

  double? _targetForMacro(MacroTargets? t, String macro) {
    if (t == null) return null;
    return switch (macro) {
      'kcal' => t.kcal.toDouble(),
      'protein' => t.proteinG.toDouble(),
      'carbs' => t.carbsG.toDouble(),
      'fat' => t.fatG.toDouble(),
      _ => null,
    };
  }

  double _valueForTotals(DailyTotals totals, String macro) {
    return switch (macro) {
      'kcal' => totals.kcal,
      'protein' => totals.proteinG,
      'carbs' => totals.carbsG,
      'fat' => totals.fatG,
      _ => totals.kcal,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.targets;
    final avgWeeklyKcal = ref.watch(averageWeeklyCaloriesProvider);
    final historyAsync = ref.watch(nutritionHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Average Weekly Calories Banner ──
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.local_fire_department,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "AVERAGE WEEKLY CALORIES",
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          avgWeeklyKcal == null
                              ? "—"
                              : "${avgWeeklyKcal.round()} kcal/day",
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── 2x2 Daily Live Macros Grid ──
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.5,
          children: [
            _macroCard(theme, 'CALORIES', Icons.local_fire_department,
                current: widget.totals.kcal.round().toString(),
                total: t == null ? '' : '/ ${t.kcal}',
                progress: t == null
                    ? null
                    : (widget.totals.kcal / t.kcal).clamp(0.0, 1.0),
                color: AppColors.macroKcal),
            _macroCard(theme, 'PROTEIN', Icons.egg_alt,
                current: '${widget.totals.proteinG.round()}g',
                total: t == null ? '' : '/ ${t.proteinG}g',
                progress: t == null
                    ? null
                    : (widget.totals.proteinG / t.proteinG).clamp(0.0, 1.0),
                color: AppColors.macroProtein),
            _macroCard(theme, 'CARBS', Icons.bakery_dining,
                current: '${widget.totals.carbsG.round()}g',
                total: t == null ? '' : '/ ${t.carbsG}g',
                progress: t == null
                    ? null
                    : (widget.totals.carbsG / t.carbsG).clamp(0.0, 1.0),
                color: AppColors.macroCarbs),
            _macroCard(theme, 'FATS', Icons.water_drop,
                current: '${widget.totals.fatG.round()}g',
                total: t == null ? '' : '/ ${t.fatG}g',
                progress: t == null
                    ? null
                    : (widget.totals.fatG / t.fatG).clamp(0.0, 1.0),
                color: AppColors.macroFat),
          ],
        ),

        const SizedBox(height: 16),

        // ── Nutrition Trend Graph Card ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Macro Metric Selector Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _macroChip('kcal', 'Calories'),
                    const SizedBox(width: 6),
                    _macroChip('protein', 'Protein'),
                    const SizedBox(width: 6),
                    _macroChip('carbs', 'Carbs'),
                    const SizedBox(width: 6),
                    _macroChip('fat', 'Fats'),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Timeline Range & Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Trend (${_selectedMacro.toUpperCase()})",
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary,
                    ),
                  ),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _timelineRange,
                      icon: Icon(Icons.calendar_today,
                          size: 16, color: AppColors.primary),
                      isDense: true,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: '3D', child: Text('3 Days')),
                        DropdownMenuItem(
                            value: '7D', child: Text('1 Week')),
                        DropdownMenuItem(
                            value: '14D', child: Text('2 Weeks')),
                        DropdownMenuItem(
                            value: '30D', child: Text('1 Month')),
                        DropdownMenuItem(
                            value: '90D', child: Text('3 Months')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          Haptics.selection();
                          setState(() => _timelineRange = val);
                        }
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Graph Render
              historyAsync.when(
                data: (historyMap) => _buildChart(
                  context,
                  historyMap,
                  _selectedMacro,
                  _timelineRange,
                  _targetForMacro(t, _selectedMacro),
                ),
                loading: () => const SizedBox(
                  height: 140,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (e, _) => SizedBox(
                  height: 140,
                  child: Center(
                    child: Text("Error loading trend graph: $e",
                        style: theme.textTheme.bodySmall),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _macroChip(String macroKey, String label) {
    final isSelected = _selectedMacro == macroKey;
    final color = _colorForMacro(macroKey);
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        Haptics.selection();
        setState(() => _selectedMacro = macroKey);
      },
      selectedColor: color.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? color : AppColors.secondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? color : AppColors.outlineVariant.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildChart(
    BuildContext context,
    Map<String, DailyTotals> historyMap,
    String macro,
    String range,
    double? targetValue,
  ) {
    final theme = Theme.of(context);
    final days = _daysForRange(range);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final color = _colorForMacro(macro);
    final unit = _unitForMacro(macro);

    final spots = <FlSpot>[];
    final dates = <DateTime>[];

    for (int i = days - 1; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      dates.add(date);
      final iso = DateFormat('yyyy-MM-dd').format(date);
      final totals = historyMap[iso] ?? DailyTotals.empty;
      final val = _valueForTotals(totals, macro);
      spots.add(FlSpot((days - 1 - i).toDouble(), val));
    }

    final hasAnyData = spots.any((s) => s.y > 0);

    if (!hasAnyData) {
      return SizedBox(
        height: 140,
        child: Center(
          child: Text(
            'No logged nutrition entries in the selected timeframe.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.secondary),
          ),
        ),
      );
    }

    final maxYValue = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final topBound = (targetValue != null && targetValue > maxYValue)
        ? targetValue * 1.15
        : maxYValue > 0
            ? maxYValue * 1.2
            : 100.0;

    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (days - 1).toDouble(),
          minY: 0,
          maxY: topBound,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: topBound / 4 > 0 ? topBound / 4 : 1,
            getDrawingHorizontalLine: (val) => FlLine(
              color: AppColors.outlineVariant.withValues(alpha: 0.15),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (days / 4).clamp(1.0, 30.0),
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= dates.length) return const SizedBox.shrink();
                  final d = dates[idx];
                  final label = days <= 7
                      ? DateFormat('E').format(d)
                      : DateFormat('M/d').format(d);
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: targetValue == null || targetValue <= 0
              ? null
              : ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: targetValue,
                      color: color.withValues(alpha: 0.5),
                      strokeWidth: 1.5,
                      dashArray: [4, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(right: 8, bottom: 2),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: color,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        labelResolver: (_) =>
                            'Target: ${targetValue.round()} $unit',
                      ),
                    ),
                  ],
                ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final idx = spot.x.toInt();
                  final dateStr = idx >= 0 && idx < dates.length
                      ? DateFormat('MMM d').format(dates[idx])
                      : '';
                  return LineTooltipItem(
                    '$dateStr\n${spot.y.round()} $unit',
                    TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: days <= 14,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: color,
                  strokeWidth: 1,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _macroCard(
    ThemeData theme,
    String title,
    IconData icon, {
    required String current,
    required String total,
    required double? progress,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary, letterSpacing: 1.0)),
              Icon(icon, size: 16, color: AppColors.primary),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(current,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  Text(total,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.secondary)),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress ?? 0.0,
                backgroundColor: AppColors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                borderRadius: BorderRadius.circular(4),
                minHeight: 4,
              ),
            ],
          ),
        ],
      ),
    );
  }
}


/// Cycle-phase focus card (§18). Content is still the Phase-7 placeholder
/// (luteal focus); shown only for female profiles.
class CycleFocusCard extends StatelessWidget {
  const CycleFocusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primaryContainer),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.monitor_heart, color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Luteal Phase Focus",
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  "Your energy naturally dips this week. Prioritize steady-state cardio and complex carbs over high-intensity intervals.",
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Edit-mode sheet (§18): toggle widget visibility and drag to reorder.
class DashboardCustomizeSheet extends ConsumerWidget {
  const DashboardCustomizeSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final config = ref.watch(dashboardConfigProvider);
    final notifier = ref.read(dashboardConfigProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor ??
              AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Customize Dashboard',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Drag to reorder · toggle to show/hide',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.secondary)),
            const SizedBox(height: 12),
            Expanded(
              child: ReorderableListView(
                scrollController: controller,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                onReorder: notifier.reorder,
                children: [
                  for (final w in config.widgets)
                    Padding(
                      key: ValueKey(w.type.id),
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.drag_handle),
                          title: Text(w.type.label),
                          // Use the themed Switch (white thumb on a blue
                          // track) — the previous adaptive switch forced a blue
                          // thumb, which vanished against the blue track.
                          trailing: Switch(
                            value: w.visible,
                            onChanged: (v) => notifier.toggle(w.type, v),
                          ),
                        ),
                      ),
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

/// Mini Workouts checklist widget (§20). Renders an interactive task list of
/// micro-workouts for today. Each checkbox logs completions towards volume/recovery.
class MiniWorkoutsCard extends ConsumerWidget {
  const MiniWorkoutsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final todayAsync = ref.watch(microWorkoutsTodayProvider);
    final repo = ref.watch(microWorkoutsRepositoryProvider);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.check_box_outlined, color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  _title(context, "Mini Workouts"),
                ],
              ),
              TextButton.icon(
                onPressed: () => _createMiniWorkout(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Add"),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          todayAsync.when(
            data: (list) {
              if (list.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'No mini workouts set up for today.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _createMiniWorkout(context, ref),
                        icon: const Icon(Icons.fitness_center, size: 18),
                        label: const Text('Set Up Mini Workout'),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  for (final item in list)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: item.doneForToday
                            ? AppColors.primaryContainer.withValues(alpha: 0.25)
                            : AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        leading: IconButton(
                          icon: Icon(
                            item.doneForToday
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            color: item.doneForToday ? AppColors.primary : AppColors.outline,
                            size: 24,
                          ),
                          onPressed: () {
                            Haptics.light();
                            repo.logCompletion(item.microWorkout);
                          },
                        ),
                        title: Text(
                          item.microWorkout.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            decoration: item.doneForToday ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Text(
                          '${item.completedToday}/${item.microWorkout.timesPerDay} completed (${item.microWorkout.targetReps} reps/round)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                        trailing: item.doneForToday
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.2),
                                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                                ),
                                child: const Text('Done', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                              )
                            : FilledButton.tonal(
                                onPressed: () {
                                  Haptics.light();
                                  repo.logCompletion(item.microWorkout);
                                },
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('+1 Done'),
                              ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            error: (e, _) => Text('Error: $e', style: TextStyle(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _createMiniWorkout(BuildContext context, WidgetRef ref) async {
    final results = await ExercisePickerSheet.show(context);
    if (results == null || results.isEmpty || !context.mounted) return;
    final exercise = results.first;

    final repsCtrl = TextEditingController(text: '20');
    final timesCtrl = TextEditingController(text: '3');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Add Mini Workout: ${exercise.exercise.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: repsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Target reps per round'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: timesCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Times per day'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final reps = int.tryParse(repsCtrl.text) ?? 20;
    final times = (int.tryParse(timesCtrl.text) ?? 1).clamp(1, 24);
    await ref.read(microWorkoutsRepositoryProvider).create(
          name: '$reps ${exercise.exercise.name}',
          exerciseId: exercise.exercise.id,
          targetReps: reps,
          timesPerDay: times,
        );
  }
}

/// Interactive Workout Calendar widget on the dashboard (§18).
/// Offers Day and Week view toggle modes for viewing scheduled workouts and completed sessions.
class WorkoutCalendarCard extends ConsumerWidget {
  const WorkoutCalendarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(calendarViewModeProvider);
    final selectedDate = ref.watch(calendarSelectedDateProvider);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month_rounded, color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  _title(context, "Workout Calendar"),
                ],
              ),
              // Segmented view switcher (Day vs Week)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildModeButton(
                      ref: ref,
                      label: "Week",
                      mode: CalendarViewMode.week,
                      activeMode: viewMode,
                    ),
                    _buildModeButton(
                      ref: ref,
                      label: "Day",
                      mode: CalendarViewMode.day,
                      activeMode: viewMode,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (viewMode == CalendarViewMode.week)
            _buildWeekView(context, ref, selectedDate)
          else
            _buildDayView(context, ref, selectedDate),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required WidgetRef ref,
    required String label,
    required CalendarViewMode mode,
    required CalendarViewMode activeMode,
  }) {
    final isActive = mode == activeMode;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        ref.read(calendarViewModeProvider.notifier).state = mode;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : AppColors.secondary,
          ),
        ),
      ),
    );
  }

  Widget _buildWeekView(BuildContext context, WidgetRef ref, DateTime selectedDate) {
    final weekSummaryAsync = ref.watch(weekCalendarSummaryProvider(selectedDate));

    return weekSummaryAsync.when(
      data: (summaries) {
        final selectedSummary = summaries.firstWhere(
          (s) => s.date.year == selectedDate.year &&
              s.date.month == selectedDate.month &&
              s.date.day == selectedDate.day,
          orElse: () => summaries.firstWhere((s) => s.isToday, orElse: () => summaries.first),
        );

        return Column(
          children: [
            // 7-day pill strip
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final day in summaries) ...[
                  _buildDayPill(context, ref, day, selectedDate),
                ],
              ],
            ),
            const SizedBox(height: 16),
            // Details card for selected day
            _buildDayDetailsCard(context, ref, selectedSummary),
          ],
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
      error: (e, _) => Text('Error loading calendar: $e'),
    );
  }

  Widget _buildDayPill(BuildContext context, WidgetRef ref, CalendarDaySummary summary, DateTime selectedDate) {
    final isSelected = summary.date.year == selectedDate.year &&
        summary.date.month == selectedDate.month &&
        summary.date.day == selectedDate.day;

    final dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final dayLabel = dayLetters[summary.date.weekday - 1];

    Color pillBg = AppColors.surfaceContainer;
    Color borderCol = Colors.transparent;
    if (isSelected) {
      pillBg = AppColors.primaryContainer.withValues(alpha: 0.4);
      borderCol = AppColors.primary;
    } else if (summary.isToday) {
      borderCol = AppColors.primary.withValues(alpha: 0.5);
    }

    return Expanded(
      child: GestureDetector(
        onTap: () {
          Haptics.light();
          ref.read(calendarSelectedDateProvider.notifier).state = summary.date;
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderCol, width: isSelected ? 1.5 : 1.0),
          ),
          child: Column(
            children: [
              Text(
                dayLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppColors.primary : AppColors.secondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${summary.date.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: summary.isToday || isSelected ? FontWeight.bold : FontWeight.w500,
                  color: summary.isToday ? AppColors.primary : null,
                ),
              ),
              const SizedBox(height: 6),
              // Status Indicator Dot
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (summary.hasCompleted)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    )
                  else if (summary.hasScheduled)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.outlineVariant.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayDetailsCard(BuildContext context, WidgetRef ref, CalendarDaySummary summary) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('EEEE, MMM d').format(summary.date);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                summary.isToday ? 'Today ($dateStr)' : dateStr,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (summary.hasCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Workout Completed',
                    style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!summary.hasScheduled && !summary.hasCompleted)
            Text(
              'Rest Day — No workouts scheduled.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
            ),
          if (summary.hasScheduled) ...[
            for (final sched in summary.scheduledWorkouts) ...[
              Row(
                children: [
                  Icon(
                    sched.status == 'done' ? Icons.check_circle : Icons.schedule,
                    color: sched.status == 'done' ? Colors.green : AppColors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Scheduled Workout (${sched.status.toUpperCase()})',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (summary.hasCompleted) ...[
            const SizedBox(height: 6),
            for (final sess in summary.completedSessions) ...[
              InkWell(
                onTap: () => context.push('/workout-history/${sess.id}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.fitness_center, color: AppColors.primary, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          sess.notes != null && sess.notes!.isNotEmpty
                              ? sess.notes!
                              : 'Workout Session #${sess.id}',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        DateFormat('HH:mm').format(sess.startedAt),
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: AppColors.secondary),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDayView(BuildContext context, WidgetRef ref, DateTime selectedDate) {
    final theme = Theme.of(context);
    final weekSummaryAsync = ref.watch(weekCalendarSummaryProvider(selectedDate));

    return weekSummaryAsync.when(
      data: (summaries) {
        final summary = summaries.firstWhere(
          (s) => s.date.year == selectedDate.year &&
              s.date.month == selectedDate.month &&
              s.date.day == selectedDate.day,
          orElse: () => summaries.firstWhere((s) => s.isToday, orElse: () => summaries.first),
        );

        return Column(
          children: [
            // Date Navigation Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    Haptics.light();
                    ref.read(calendarSelectedDateProvider.notifier).state =
                        selectedDate.subtract(const Duration(days: 1));
                  },
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        summary.isToday ? 'Today' : DateFormat('EEEE').format(selectedDate),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        DateFormat('MMM d, yyyy').format(selectedDate),
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    Haptics.light();
                    ref.read(calendarSelectedDateProvider.notifier).state =
                        selectedDate.add(const Duration(days: 1));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDayDetailsCard(context, ref, summary),
          ],
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
      error: (e, _) => Text('Error: $e'),
    );
  }
}

class QuickScanWidget extends ConsumerWidget {
  const QuickScanWidget({super.key});

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    Haptics.selection();
    final scanned = await BarcodeScannerView.show(context);
    if (scanned == null || !context.mounted) return;
    var normalized = normalizeBarcode(scanned);
    if (normalized == null) return;
    final code = normalized.value;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final food = await ref
        .read(nutritionRepositoryProvider)
        .lookupBarcode(code);

    if (!context.mounted) return;
    Navigator.of(context).pop();

    final today = DateUtils.dateOnly(DateTime.now());
    if (food == null) {
      final created = await CustomFoodFormSheet.show(
        context,
        initialBarcode: code,
      );
      if (created != null && context.mounted) {
        await LogEntrySheet.forFood(
          context,
          food: created,
          date: today,
          initialMealKey: 'snack',
        );
      }
    } else {
      await LogEntrySheet.forFood(
        context,
        food: food,
        date: today,
        initialMealKey: 'snack',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.qr_code_scanner,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'QUICK FOOD SCAN',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    'Scan product barcode to log food',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _scan(context, ref),
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Scan Barcode'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () {
                  final today = DateUtils.dateOnly(DateTime.now());
                  FoodPickerSheet.show(context, date: today, mealKey: 'snack');
                },
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Search'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
