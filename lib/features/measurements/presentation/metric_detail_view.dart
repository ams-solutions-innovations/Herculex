import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/measurements/presentation/body_fat_ai_dialog.dart';
import 'package:herculex/features/physique/application/goal_target_provider.dart';
import 'package:herculex/features/physique/presentation/save_goal_target.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:intl/intl.dart';

final _metricHistoryProvider =
    StreamProvider.family<List<BodyMeasurementData>, String>((ref, metric) {
      return ref.watch(measurementsRepositoryProvider).watchMetric(metric);
    });

class MetricDetailView extends ConsumerStatefulWidget {
  final String metric;

  const MetricDetailView({super.key, required this.metric});

  static const labels = <String, String>{
    'bodyweight': 'Bodyweight',
    'body_fat': 'Body Fat',
    'neck': 'Neck',
    'chest': 'Chest',
    'arms_l': 'Arm (L)',
    'arms_r': 'Arm (R)',
    'waist': 'Waist',
    'hips': 'Hips',
    'thigh_l': 'Thigh (L)',
    'thigh_r': 'Thigh (R)',
    'calf_l': 'Calf (L)',
    'calf_r': 'Calf (R)',
    'back': 'Back',
  };

  static String getLabel(String key) => labels[key] ?? key;

  @override
  ConsumerState<MetricDetailView> createState() => _MetricDetailViewState();
}

class _MetricDetailViewState extends ConsumerState<MetricDetailView> {
  String get _label => MetricDetailView.getLabel(widget.metric);
  String get _unit => widget.metric == 'bodyweight'
      ? 'kg'
      : (widget.metric == 'body_fat' ? '%' : 'cm');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final historyAsync = ref.watch(_metricHistoryProvider(widget.metric));

    return HxScreenShell(
      title: _label,
      actions: [
        if (widget.metric == 'body_fat')
          IconButton(
            icon: Icon(Icons.auto_awesome, color: AppColors.primary),
            tooltip: 'Herculex AI Estimate',
            onPressed: () {
              Haptics.selection();
              BodyFatAiDialog.show(context);
            },
          ),
      ],
      pinnedBottom: _bottomLogButton(context),
      children: [
        historyAsync.when(
          data: (rows) {
            if (rows.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 48,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.show_chart,
                        size: 64,
                        color: AppColors.secondary.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No $_label entries yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Log your first measurement to track trends over time',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary.withValues(alpha: 0.8),
                        ),
                      ),
                      if (widget.metric == 'bodyweight') ...[
                        const SizedBox(height: 24),
                        _TargetWeightSection(latestKg: null, unit: _unit),
                      ],
                    ],
                  ),
                ),
              );
            }

            final latest = rows.last;
            final first = rows.first;
            final diffTotal = rows.length >= 2
                ? latest.value - first.value
                : 0.0;
            final values = rows.map((r) => r.value).toList();
            final minVal = values.reduce((a, b) => a < b ? a : b);
            final maxVal = values.reduce((a, b) => a > b ? a : b);
            final avgVal = values.reduce((a, b) => a + b) / values.length;

            return Column(
              children: [
                // ── Summary Cards Grid ──
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'Latest',
                        value: '${latest.value.toStringAsFixed(1)} $_unit',
                        subtitle: _formatShortDate(latest.dateIso),
                        icon: Icons.speed,
                        accentColor: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        title: 'Net Change',
                        value: rows.length < 2
                            ? '—'
                            : '${diffTotal >= 0 ? "+" : ""}${diffTotal.toStringAsFixed(1)} $_unit',
                        subtitle: rows.length < 2
                            ? 'Need 2+ logs'
                            : 'Since start',
                        icon: diffTotal >= 0
                            ? Icons.trending_up
                            : Icons.trending_down,
                        accentColor: diffTotal == 0
                            ? AppColors.secondary
                            : ((widget.metric == 'bodyweight' ||
                                      widget.metric == 'body_fat')
                                  ? (diffTotal < 0
                                        ? Colors.green
                                        : Colors.orange)
                                  : (diffTotal > 0
                                        ? Colors.green
                                        : Colors.blue)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStatTile(
                        label: 'Min',
                        value: '${minVal.toStringAsFixed(1)} $_unit',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniStatTile(
                        label: 'Avg',
                        value: '${avgVal.toStringAsFixed(1)} $_unit',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniStatTile(
                        label: 'Max',
                        value: '${maxVal.toStringAsFixed(1)} $_unit',
                      ),
                    ),
                  ],
                ),
                if (widget.metric == 'bodyweight') ...[
                  const SizedBox(height: 14),
                  _TargetWeightSection(latestKg: latest.value, unit: _unit),
                ],
                const SizedBox(height: 20),

                // ── Chart Section ──
                Text(
                  'Progress Trend',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 20, 20, 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildChart(
                        rows,
                        widget.metric == 'bodyweight'
                            ? ref.watch(goalTargetProvider).targetKg
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── History Section ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'History (${rows.length})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final r in rows.reversed)
                  _HistoryTile(
                    row: r,
                    unit: _unit,
                    onDelete: () async {
                      Haptics.medium();
                      await ref
                          .read(measurementsRepositoryProvider)
                          .deleteMeasurement(r.id);
                    },
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }

  Widget _buildChart(List<BodyMeasurementData> rows, [double? targetValue]) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    for (var i = 0; i < rows.length; i++) {
      spots.add(FlSpot(i.toDouble(), rows[i].value));
    }

    var minY = rows.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    var maxY = rows.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    final hasTarget =
        targetValue != null &&
        targetValue > 0 &&
        !targetValue.isNaN &&
        !targetValue.isInfinite;

    if (hasTarget) {
      if (targetValue < minY) minY = targetValue;
      if (targetValue > maxY) maxY = targetValue;
    }

    final padding = (maxY - minY) * 0.15;
    final effectivePadding = padding == 0 ? 1.0 : padding;
    final chartMinY = (minY - effectivePadding).floorToDouble();
    final chartMaxY = (maxY + effectivePadding).ceilToDouble();

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 0,
          // With one measurement the inferred x-range collapses to a point and
          // fl_chart's `(x - minX) / (maxX - minX)` goes NaN — a RenderBox
          // assertion on the user's very first body measurement.
          maxX: spots.length > 1 ? (spots.length - 1).toDouble() : 1.0,
          minY: chartMinY,
          maxY: chartMaxY,
          extraLinesData: !hasTarget
              ? null
              : ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: targetValue,
                      color: AppColors.primary.withValues(alpha: 0.6),
                      strokeWidth: 1.5,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(right: 8, bottom: 2),
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        labelResolver: (_) =>
                            'Target: ${targetValue.toStringAsFixed(1)} $_unit',
                      ),
                    ),
                  ],
                ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (chartMaxY - chartMinY) / 4 > 0
                ? (chartMaxY - chartMinY) / 4
                : 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.outlineVariant.withValues(alpha: 0.2),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (val, meta) {
                  return Text(
                    val.toStringAsFixed(0),
                    style: TextStyle(color: AppColors.secondary, fontSize: 10),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: (rows.length / 4).ceilToDouble().clamp(1.0, 10.0),
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx >= 0 && idx < rows.length) {
                    final date = DateTime.tryParse(rows[idx].dateIso);
                    if (date != null) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text(
                          DateFormat('d MMM').format(date),
                          style: TextStyle(
                            color: AppColors.secondary,
                            fontSize: 10,
                          ),
                        ),
                      );
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final idx = spot.spotIndex;
                  final dateStr = idx < rows.length ? rows[idx].dateIso : '';
                  final date = DateTime.tryParse(dateStr);
                  final formattedDate = date != null
                      ? DateFormat('d MMM yyyy').format(date)
                      : dateStr;
                  return LineTooltipItem(
                    '${spot.y.toStringAsFixed(1)} $_unit\n',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    children: [
                      TextSpan(
                        text: formattedDate,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.normal,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: rows.length > 1,
              color: AppColors.primary,
              barWidth: 3.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: rows.length < 15,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                      radius: 4,
                      color: AppColors.primary,
                      strokeWidth: 2,
                      strokeColor: Theme.of(context).scaffoldBackgroundColor,
                    ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.3),
                    AppColors.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomLogButton(BuildContext context) {
    final isBodyFat = widget.metric == 'body_fat';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: isBodyFat
            ? Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Haptics.selection();
                          BodyFatAiDialog.show(context);
                        },
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('AI Estimate'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: () => _logEntry(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Manual Entry'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () => _logEntry(context),
                  icon: const Icon(Icons.add),
                  label: Text('Log $_label'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _logEntry(BuildContext context) async {
    Haptics.selection();
    final rows = ref.read(_metricHistoryProvider(widget.metric)).asData?.value;
    final lastVal = (rows != null && rows.isNotEmpty) ? rows.last.value : null;

    String initialText = '';
    if (widget.metric == 'bodyweight') {
      final latestKg = await ref.read(latestBodyweightProvider.future);
      final profile = ref.read(profileProvider).valueOrNull;
      final kg = latestKg ?? profile?.weightKg;
      if (kg != null) {
        final fmt = ref.read(weightFormatProvider);
        initialText = fmt.formatValue(kg);
      }
    } else if (lastVal != null) {
      initialText = lastVal.truncateToDouble() == lastVal
          ? lastVal.toStringAsFixed(0)
          : lastVal.toStringAsFixed(1);
    }

    final ctrl = TextEditingController(text: initialText);
    if (initialText.isNotEmpty) {
      ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialText.length,
      );
    }
    if (!context.mounted) return;
    final value = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Log $_label'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'Enter value',
            suffixText: _unit,
          ),
          onSubmitted: (v) => Navigator.pop(dialogCtx, double.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogCtx, double.tryParse(ctrl.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (value != null) {
      Haptics.medium();
      await ref
          .read(measurementsRepositoryProvider)
          .logMeasurement(
            dateIso: DateFormat('yyyy-MM-dd').format(DateTime.now()),
            metric: widget.metric,
            value: value,
          );
    }
  }

  String _formatShortDate(String dateIso) {
    final parsed = DateTime.tryParse(dateIso);
    if (parsed == null) return dateIso;
    return DateFormat('d MMM yyyy').format(parsed);
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              Icon(icon, size: 18, color: accentColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatTile extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final BodyMeasurementData row;
  final String unit;
  final VoidCallback onDelete;

  const _HistoryTile({
    required this.row,
    required this.unit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime.tryParse(row.dateIso);
    final formattedDate = date != null
        ? DateFormat('EEEE, d MMM yyyy').format(date)
        : row.dateIso;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          '${row.value.toStringAsFixed(1)} $unit',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          formattedDate,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          color: AppColors.secondary,
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _TargetWeightSection extends ConsumerWidget {
  final double? latestKg;
  final String unit;

  const _TargetWeightSection({required this.latestKg, required this.unit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final target = ref.watch(goalTargetProvider);
    final targetKg = target.targetKg;

    final hasTarget = targetKg != null;
    final diff = (hasTarget && latestKg != null) ? latestKg! - targetKg : null;

    String subtitle;
    if (diff == null) {
      subtitle = hasTarget ? 'Target set' : 'Tap to set your target weight';
    } else if (diff.abs() < 0.05) {
      subtitle = 'Goal reached! 🎉';
    } else if (diff > 0) {
      subtitle = '${diff.toStringAsFixed(1)} $unit to lose';
    } else {
      subtitle = '${(-diff).toStringAsFixed(1)} $unit to gain';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.track_changes_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  target.fromRoadmap
                      ? 'Target Bodyweight · end of ${target.phase!.label.toLowerCase()}'
                      : 'Target Bodyweight',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasTarget
                      ? '${targetKg.toStringAsFixed(1)} $unit'
                      : 'Not set',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: hasTarget
                        ? AppColors.onSurface
                        : AppColors.secondary,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: (diff != null && diff.abs() < 0.05)
                        ? Colors.green
                        : AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
              shape: const StadiumBorder(),
            ),
            onPressed: () => _editTargetWeight(context, ref, targetKg),
            child: Text(hasTarget ? 'Edit' : 'Set'),
          ),
        ],
      ),
    );
  }

  Future<void> _editTargetWeight(
    BuildContext context,
    WidgetRef ref,
    double? currentKg,
  ) async {
    final ctrl = TextEditingController(
      text: currentKg != null ? currentKg.toStringAsFixed(1) : '',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomPad = MediaQuery.of(ctx).viewInsets.bottom + 20;
        return Container(
          padding: EdgeInsets.fromLTRB(24, 20, 24, bottomPad),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Set Target Bodyweight',
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Target Weight ($unit)',
                  hintText: 'e.g. 75.0',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final val = double.tryParse(ctrl.text.trim());
                    if (val != null && val > 0) {
                      await saveGoalTarget(ctx, ref, val);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save Target Weight'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
