import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/units.dart';
import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/tokens/tokens.dart';
import '../../../ui/hx_card.dart';
import '../../../ui/hx_screen_shell.dart';
import '../../analytics/domain/training_snapshot.dart';
import '../../analytics/domain/variant_performance.dart';
import '../../analytics/presentation/analytics_providers.dart';
import '../domain/equipment_variants.dart';
import '../domain/one_rep_max.dart';
import 'workouts_providers.dart';
import 'exercise_artwork.dart';

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
        _TrendCard(exerciseId: exercise.id),
        const SizedBox(height: 14),
        _PerformanceCard(
          title: 'By equipment',
          async: byEquipment,
          weightFormat: weightFormat,
          labelOf: (record) => equipmentVariantLabel(record.label),
        ),
        const SizedBox(height: 14),
        _PerformanceCard(
          title: 'By accessories',
          async: byAccessory,
          weightFormat: weightFormat,
          labelOf: (record) => record.label,
        ),
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

class _TrendCard extends ConsumerWidget {
  final int exerciseId;

  const _TrendCard({required this.exerciseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(trainingSnapshotProvider);
    return HxCard(
      child: snapshot.when(
        loading: () => const _CardLoading(),
        error: (error, _) => Text('Could not load trend: $error'),
        data: (value) {
          final points = _trendPoints(value, exerciseId);
          if (points.isEmpty) {
            return const _EmptyCardContent(
              title: 'Estimated 1RM trend',
              message: 'Complete a working set to start this trend.',
            );
          }
          return _TrendChart(points: points);
        },
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<_TrendPoint> points;

  const _TrendChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final values = points.map((point) => point.value).toList();
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final spread = (maxValue - minValue).abs();
    final padding = spread < 1 ? 8 : spread * 0.18;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Estimated 1RM trend',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Best estimated 1RM per completed session',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.secondary),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (points.length - 1).toDouble(),
              minY: (minValue - padding).clamp(0, double.infinity).toDouble(),
              maxY: maxValue + padding,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: _interval(minValue, maxValue),
                getDrawingHorizontalLine: (_) => FlLine(
                  color: hx.outlineVariant.withValues(alpha: 0.35),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    interval: _interval(minValue, maxValue),
                    getTitlesWidget: (value, _) => Text(
                      value.round().toString(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: points.length > 5 ? 2 : 1,
                    getTitlesWidget: (value, _) {
                      final index = value.round();
                      if (index < 0 || index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          DateFormat('d.M.').format(points[index].date),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.secondary),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots
                      .map(
                        (spot) => LineTooltipItem(
                          '${spot.y.toStringAsFixed(1)} kg e1RM',
                          TextStyle(
                            color: hx.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < points.length; i++)
                      FlSpot(i.toDouble(), points[i].value),
                  ],
                  isCurved: true,
                  color: hx.primary,
                  barWidth: 3,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                      radius: 4,
                      color: hx.primary,
                      strokeWidth: 2,
                      strokeColor: hx.onPrimary,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: hx.primary.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static double _interval(double min, double max) {
    final spread = (max - min).abs();
    if (spread < 10) return 5;
    if (spread < 40) return 10;
    return 20;
  }
}

class _PerformanceCard extends StatelessWidget {
  final String title;
  final AsyncValue<List<PerformanceRecord>> async;
  final WeightFormat weightFormat;
  final String Function(PerformanceRecord) labelOf;

  const _PerformanceCard({
    required this.title,
    required this.async,
    required this.weightFormat,
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
                                      '${weightFormat.format(record.bestWeightKg)} × ${record.bestWeightReps} reps · ${record.setCount} sets',
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
                              if (record.bestE1RmKg != null)
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

class _EmptyCardContent extends StatelessWidget {
  final String title;
  final String message;

  const _EmptyCardContent({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(message, style: TextStyle(color: AppColors.secondary)),
      ],
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

class _TrendPoint {
  final DateTime date;
  final double value;

  const _TrendPoint({required this.date, required this.value});
}

List<_TrendPoint> _trendPoints(TrainingSnapshot snapshot, int exerciseId) {
  final bestByDay = <DateTime, double>{};
  for (final resolved in snapshot.sets) {
    if (resolved.exercise.id != exerciseId) continue;
    final e1rm =
        OneRepMax.estimate(
          weightKg: resolved.effectiveKg,
          reps: resolved.set.reps,
        ) ??
        resolved.effectiveKg;
    final date = resolved.session.endedAt ?? resolved.session.startedAt;
    final day = DateTime(date.year, date.month, date.day);
    final current = bestByDay[day];
    if (current == null || e1rm > current) bestByDay[day] = e1rm;
  }

  final points = [
    for (final entry in bestByDay.entries)
      _TrendPoint(date: entry.key, value: entry.value),
  ]..sort((a, b) => a.date.compareTo(b.date));

  if (points.length <= 8) return points;
  return points.sublist(points.length - 8);
}
