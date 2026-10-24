import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/health/application/health_providers.dart';
import 'package:herculex/features/steps/application/steps_providers.dart';
import 'package:herculex/features/steps/domain/step_score_engine.dart';
import 'package:herculex/features/steps/domain/step_weightlifting_impact.dart';
import 'package:herculex/features/steps/presentation/sheets/manual_step_entry_sheet.dart';
import 'package:herculex/features/steps/presentation/widgets/step_gradient_trend_chart.dart';
import 'package:herculex/features/steps/presentation/widgets/step_hero_progress_ring.dart';
import 'package:herculex/features/steps/presentation/widgets/step_hourly_bar_chart.dart';
import 'package:herculex/features/steps/presentation/widgets/step_lifting_correlation_chart.dart';
import 'package:herculex/features/steps/presentation/widgets/step_weightlifting_impact_card.dart';
import 'package:intl/intl.dart';

/// Main hub for step tracking, NEAT energy expenditure, and strength training adaptations.
class StepsTrackingView extends ConsumerStatefulWidget {
  const StepsTrackingView({super.key});

  @override
  ConsumerState<StepsTrackingView> createState() => _StepsTrackingViewState();
}

class _StepsTrackingViewState extends ConsumerState<StepsTrackingView> {
  bool _isSyncing = false;
  double _horizontalDragDistance = 0;

  String _formatDateIso(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _goToPreviousDay() {
    final selectedDate = ref.read(selectedStepDateProvider);
    ref.read(selectedStepDateProvider.notifier).state = selectedDate.subtract(
      const Duration(days: 1),
    );
  }

  void _goToNextDay() {
    final selectedDate = ref.read(selectedStepDateProvider);
    final now = ref.read(clockProvider).now();
    if (!_isSameDay(selectedDate, now)) {
      ref.read(selectedStepDateProvider.notifier).state = selectedDate.add(
        const Duration(days: 1),
      );
    }
  }

  Future<void> _syncHealthData() async {
    setState(() => _isSyncing = true);
    await ref.read(healthServiceProvider).runDailySync();
    ref.invalidate(todayStepsProvider);
    ref.invalidate(selectedStepRecordProvider);
    ref.invalidate(stepHistoryProvider);
    ref.invalidate(stepLiftingCorrelationProvider);
    if (!mounted) return;
    setState(() => _isSyncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = ref.watch(clockProvider);
    final now = clock.now();

    final selectedDate = ref.watch(selectedStepDateProvider);
    final isToday = _isSameDay(selectedDate, now);

    final selectedRecordAsync = ref.watch(selectedStepRecordProvider);
    final goal = ref.watch(stepGoalProvider);
    final historyAsync = ref.watch(stepHistoryProvider(30));
    final correlationAsync = ref.watch(stepLiftingCorrelationProvider);

    final record = selectedRecordAsync.valueOrNull;

    final score = record != null
        ? StepScoreEngine.calculate(steps: record.stepCount, goal: goal)
        : (isToday ? ref.watch(todayStepScoreProvider) : null);

    final impact = record != null
        ? StepWeightliftingEngine.calculate(steps: record.stepCount)
        : ref.watch(todayStepWeightliftingImpactProvider);

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
        title: 'Daily Steps & NEAT',
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: 'Sync wearable steps',
            onPressed: _isSyncing ? null : _syncHealthData,
          ),
          IconButton(
            icon: const Icon(Icons.edit_calendar_rounded),
            tooltip: 'Log or edit steps',
            onPressed: () {
              ManualStepEntrySheet.show(
                context,
                initialRecord: record,
                dateIso: _formatDateIso(selectedDate),
              );
            },
          ),
        ],
        children: [
          // Date navigator
          _buildDateNavigator(theme, selectedDate, isToday, now),
          const SizedBox(height: 16),

          // Hero Progress Ring
          StepHeroProgressRing(record: record, score: score),
          const SizedBox(height: 24),

          // Hourly Distribution Bar Chart
          StepHourlyBarChart(record: record),
          const SizedBox(height: 24),

          // Weightlifting Impact Card
          StepWeightliftingImpactCard(impact: impact),
          const SizedBox(height: 24),

          // Animated Gradient Step Trend Chart
          historyAsync.when(
            data: (history) =>
                StepGradientTrendChart(history: history, targetSteps: goal),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(child: Text('Error loading trend: $e')),
          ),
          const SizedBox(height: 24),

          // Empirical Steps vs. Workout RPE Correlation Chart
          correlationAsync.when(
            data: (correlation) =>
                StepLiftingCorrelationChart(correlation: correlation),
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
