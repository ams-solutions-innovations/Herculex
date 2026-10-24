// lib/features/sleep/presentation/views/sleep_tracking_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/health/application/health_providers.dart';
import 'package:herculex/features/sleep/application/sleep_providers.dart';
import 'package:herculex/features/sleep/domain/sleep_score_engine.dart';
import 'package:herculex/features/sleep/domain/sleep_weightlifting_impact.dart';
import 'package:herculex/features/sleep/presentation/sheets/manual_sleep_entry_sheet.dart';
import 'package:herculex/features/sleep/presentation/widgets/sleep_gradient_trend_chart.dart';
import 'package:herculex/features/sleep/presentation/widgets/sleep_hero_gauge.dart';
import 'package:herculex/features/sleep/presentation/widgets/sleep_lifting_correlation_chart.dart';
import 'package:herculex/features/sleep/presentation/widgets/sleep_stages_breakdown_card.dart';
import 'package:herculex/features/sleep/presentation/widgets/sleep_weightlifting_impact_card.dart';
import 'package:intl/intl.dart';

/// Main hub for sleep monitoring, recovery analytics, and resistance training adaptation.
class SleepTrackingView extends ConsumerStatefulWidget {
  const SleepTrackingView({super.key});

  @override
  ConsumerState<SleepTrackingView> createState() => _SleepTrackingViewState();
}

class _SleepTrackingViewState extends ConsumerState<SleepTrackingView> {
  bool _isSyncing = false;
  double _horizontalDragDistance = 0;

  String _formatDateIso(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _goToPreviousDay() {
    final selectedDate = ref.read(selectedSleepDateProvider);
    ref.read(selectedSleepDateProvider.notifier).state = selectedDate.subtract(
      const Duration(days: 1),
    );
  }

  void _goToNextDay() {
    final selectedDate = ref.read(selectedSleepDateProvider);
    final now = ref.read(clockProvider).now();
    if (!_isSameDay(selectedDate, now)) {
      ref.read(selectedSleepDateProvider.notifier).state = selectedDate.add(
        const Duration(days: 1),
      );
    }
  }

  Future<void> _syncHealthData() async {
    setState(() => _isSyncing = true);
    await ref.read(healthServiceProvider).runDailySync();
    ref.invalidate(todaySleepProvider);
    ref.invalidate(selectedSleepRecordProvider);
    ref.invalidate(sleepHistoryProvider);
    ref.invalidate(sleepLiftingCorrelationProvider);
    if (!mounted) return;
    setState(() => _isSyncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = ref.watch(clockProvider);
    final now = clock.now();

    final selectedDate = ref.watch(selectedSleepDateProvider);
    final isToday = _isSameDay(selectedDate, now);

    final selectedRecordAsync = ref.watch(selectedSleepRecordProvider);
    final targetHours = ref.watch(sleepTargetHoursProvider);
    final historyAsync = ref.watch(sleepHistoryProvider(30));
    final correlationAsync = ref.watch(sleepLiftingCorrelationProvider);

    final record = selectedRecordAsync.valueOrNull;

    // Evaluate score and impact for the selected date's record if available
    final score = record != null
        ? SleepScoreEngine.calculate(
            record.targetHours == targetHours
                ? record
                : record.copyWith(targetHours: targetHours),
          )
        : (isToday ? ref.watch(todaySleepScoreProvider) : null);

    final impact = record != null
        ? SleepWeightliftingEngine.evaluate(
            sleepHours: record.totalHours,
            deepSleepHours: record.stages != null
                ? record.stages!.deepMinutes / 60.0
                : null,
            remSleepHours: record.stages != null
                ? record.stages!.remMinutes / 60.0
                : null,
            sleepDebt: record.sleepDebtHours,
            restingHr: record.restingHr,
          )
        : ref.watch(todayWeightliftingImpactProvider);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) {
        _horizontalDragDistance += details.primaryDelta ?? 0;
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (_horizontalDragDistance > 50 || velocity > 200) {
          _goToPreviousDay();
        } else if (_horizontalDragDistance < -50 || velocity < -200) {
          _goToNextDay();
        }
        _horizontalDragDistance = 0;
      },
      onHorizontalDragCancel: () {
        _horizontalDragDistance = 0;
      },
      child: HxScreenShell(
        title: 'Sleep & Recovery',
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: 'Sync wearable data',
            onPressed: _isSyncing ? null : _syncHealthData,
          ),
          IconButton(
            icon: const Icon(Icons.edit_calendar_rounded),
            tooltip: 'Log or edit sleep',
            onPressed: () {
              ManualSleepEntrySheet.show(
                context,
                initialRecord: record,
                dateIso: _formatDateIso(selectedDate),
              );
            },
          ),
        ],
        children: [
          // ── Date navigation bar ──────────────────────────────────────────────
          _buildDateNavigator(theme, selectedDate, isToday, now),
          const SizedBox(height: 16),

          // ── Sleep Recovery Score Gauge ───────────────────────────────────────
          SleepHeroGauge(
            record: record,
            score: score,
            targetHours: targetHours,
          ),
          const SizedBox(height: 24),

          // ── Weightlifting & CNS Impact Card ──────────────────────────────────
          SleepWeightliftingImpactCard(impact: impact),
          const SizedBox(height: 24),

          // ── Sleep Stages & Physiological Cycles ──────────────────────────────
          SleepStagesBreakdownCard(record: record),
          const SizedBox(height: 24),

          // ── Animated Gradient Sleep Trend Chart ──────────────────────────────
          historyAsync.when(
            data: (history) => SleepGradientTrendChart(
              history: history,
              targetHours: targetHours,
            ),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(child: Text('Error loading trend: $e')),
          ),
          const SizedBox(height: 24),

          // ── Empirical Sleep vs. Workout RPE Correlation Chart ────────────────
          correlationAsync.when(
            data: (correlation) =>
                SleepLiftingCorrelationChart(correlation: correlation),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDateNavigator(
    ThemeData theme,
    DateTime selectedDate,
    bool isToday,
    DateTime now,
  ) {
    final dateLabel = isToday
        ? 'Today, ${DateFormat('MMM d').format(selectedDate)}'
        : DateFormat('EEEE, MMM d').format(selectedDate);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            visualDensity: VisualDensity.compact,
            onPressed: _goToPreviousDay,
          ),
          Text(
            dateLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            visualDensity: VisualDensity.compact,
            onPressed: isToday ? null : _goToNextDay,
          ),
        ],
      ),
    );
  }
}
