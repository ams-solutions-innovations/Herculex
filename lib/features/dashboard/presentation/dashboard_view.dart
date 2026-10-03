import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/dashboard/domain/dashboard_config.dart';
import 'package:herculex/features/dashboard/presentation/dashboard_widgets.dart';
import 'package:herculex/features/dashboard/presentation/widgets/hercul_insights_card.dart';
import 'package:herculex/features/fasting/application/fasting_providers.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';
import 'package:herculex/features/fasting/presentation/end_fast_dialog.dart';
import 'package:herculex/features/fasting/presentation/widgets/fasting_stage_icon.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/domain/daily_totals.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/supplements/presentation/supplement_tracker_widget.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/weekly_report_ready_card.dart';
import 'package:intl/intl.dart';

class DashboardView extends ConsumerWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final name = _firstName(profile?.name);
    final isFemale = profile?.sex == BiologicalSex.female;
    final config = ref.watch(dashboardConfigProvider);
    final editMode = ref.watch(dashboardEditModeProvider);

    final visibleEntries = [
      for (final e in config.widgets.asMap().entries)
        if (e.value.visible &&
            (isFemale ||
                e.value.types.any((t) => t != DashboardWidgetType.cycle)))
          e,
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: editMode
          ? Padding(
              padding: const EdgeInsets.only(bottom: 76.0),
              child: _DoneEditingButton(
                onTap: () {
                  Haptics.selection();
                  ref.read(dashboardEditModeProvider.notifier).state = false;
                },
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Personal, left-aligned header in the display face — the
              // identity prototype for the UI rework (P1).
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.secondary,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name.isEmpty ? "Herculex" : name,
                          style: theme.textTheme.headlineMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!editMode) ...[
                    IconButton(
                      icon: const Icon(Icons.tune, size: 20),
                      tooltip: 'Customize dashboard',
                      onPressed: () => _showCustomizeSheet(context, ref),
                    ),
                    const SizedBox(width: 4),
                    _ProfileAvatarButton(name: name),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              const WeeklyReportReadyCard(),
              // Config-driven widget grid (§18). Each visible slot maps to a
              // standalone renderer or a Samsung-style widget stack, laid out
              // in a 2-column staggered grid so widgets can go half- or
              // full-width (One UI / iOS-style in-place resize).
              StaggeredGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 24,
                crossAxisSpacing: 16,
                children: [
                  for (final entry in visibleEntries)
                    StaggeredGridTile.fit(
                      crossAxisCellCount:
                          entry.value.effectiveSize == DashboardWidgetSize.half
                          ? 1
                          : 2,
                      child: Builder(
                        key: ValueKey(entry.value.id),
                        builder: (context) {
                          final w = entry.value;
                          final index = entry.key;
                          final validTypes = isFemale
                              ? w.types
                              : w.types
                                    .where(
                                      (t) => t != DashboardWidgetType.cycle,
                                    )
                                    .toList();
                          if (validTypes.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          void enterEditMode() {
                            if (editMode) return;
                            Haptics.heavy();
                            ref.read(dashboardEditModeProvider.notifier).state =
                                true;
                          }

                          final Widget rendered = validTypes.length > 1
                              ? StackedDashboardWidget(
                                  types: validTypes,
                                  theme: theme,
                                  renderWidget: (type) =>
                                      _renderWidget(type, theme),
                                  onLongPress: enterEditMode,
                                )
                              : GestureDetector(
                                  onLongPress: editMode ? null : enterEditMode,
                                  child: _renderWidget(validTypes.first, theme),
                                );

                          final tile = _EditableDashboardTile(
                            slotIndex: index,
                            slot: w,
                            editMode: editMode,
                            child: rendered,
                          );

                          if (!editMode) return tile;

                          // Edit mode: press-and-hold again to drag the tile
                          // to a new position (reorder), like a home-screen
                          // widget grid. Dropping onto another tile swaps
                          // their slot order.
                          final tileWidth = _tileWidth(
                            context,
                            w.effectiveSize,
                          );
                          return LongPressDraggable<int>(
                            data: index,
                            delay: const Duration(milliseconds: 120),
                            onDragStarted: Haptics.medium,
                            feedback: Material(
                              color: Colors.transparent,
                              child: SizedBox(
                                width: tileWidth,
                                child: Transform.scale(
                                  scale: 1.04,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(28),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.35,
                                          ),
                                          blurRadius: 24,
                                          spreadRadius: 4,
                                          offset: const Offset(0, 10),
                                        ),
                                        BoxShadow(
                                          color: context.hx.primary.withValues(
                                            alpha: 0.35,
                                          ),
                                          blurRadius: 16,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: Opacity(opacity: 0.95, child: tile),
                                  ),
                                ),
                              ),
                            ),
                            childWhenDragging: AnimatedOpacity(
                              duration: HxMotion.fast,
                              opacity: 0.25,
                              child: tile,
                            ),
                            child: DragTarget<int>(
                              onWillAcceptWithDetails: (details) =>
                                  details.data != index,
                              onAcceptWithDetails: (details) {
                                final sourceIndex = details.data;
                                final sourceSlot = (sourceIndex >= 0 &&
                                        sourceIndex < config.widgets.length)
                                    ? config.widgets[sourceIndex]
                                    : null;
                                if (sourceSlot != null &&
                                    w.canStackWith(sourceSlot)) {
                                  Haptics.heavy();
                                  ref
                                      .read(dashboardConfigProvider.notifier)
                                      .stackSlots(sourceIndex, index);
                                } else {
                                  Haptics.selection();
                                  ref
                                      .read(dashboardConfigProvider.notifier)
                                      .reorder(sourceIndex, index);
                                }
                              },
                              builder: (context, candidate, rejected) {
                                final isTarget = candidate.isNotEmpty;
                                final draggedIdx = candidate.firstOrNull;
                                final draggedSlot = (draggedIdx != null &&
                                        draggedIdx >= 0 &&
                                        draggedIdx < config.widgets.length)
                                    ? config.widgets[draggedIdx]
                                    : null;
                                final isStackCandidate = isTarget &&
                                    draggedSlot != null &&
                                    w.canStackWith(draggedSlot);

                                return AnimatedScale(
                                  scale: isTarget
                                      ? (isStackCandidate ? 0.96 : 0.94)
                                      : 1.0,
                                  duration: HxMotion.fast,
                                  curve: HxMotion.emphasized,
                                  child: AnimatedContainer(
                                    duration: HxMotion.fast,
                                    curve: HxMotion.emphasized,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(28),
                                      border: isStackCandidate
                                          ? Border.all(
                                              color: context.hx.primary,
                                              width: 2.5,
                                            )
                                          : null,
                                      boxShadow: isTarget
                                          ? [
                                              BoxShadow(
                                                color: (isStackCandidate
                                                        ? context.hx.primary
                                                        : context.hx.secondary)
                                                    .withValues(alpha: 0.5),
                                                blurRadius: 18,
                                                spreadRadius: 2,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        tile,
                                        if (isStackCandidate)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: context.hx.primary,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.layers_outlined,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Drop to Stack',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 76),
            ],
          ),
        ),
      ),
    );
  }

  /// Approximate on-screen tile width for the drag feedback, matching the
  /// grid's 24px page padding and 16px column gap.
  double _tileWidth(BuildContext context, DashboardWidgetSize size) {
    final available = MediaQuery.sizeOf(context).width - 48;
    return size == DashboardWidgetSize.half ? (available - 16) / 2 : available;
  }

  /// Maps a dashboard widget type to its renderer.
  Widget _renderWidget(DashboardWidgetType type, ThemeData theme) {
    switch (type) {
      case DashboardWidgetType.fastingTimer:
        return const FastingTimerWidget();
      case DashboardWidgetType.macros:
        return const _LiveMacrosGridWrapper();
      case DashboardWidgetType.calorieTrends:
        return const CalorieTrendPreviewCard();
      case DashboardWidgetType.bodyweightTrends:
        return const BodyweightTrendPreviewCard();
      case DashboardWidgetType.todaysPlan:
        return const SmartWorkoutLauncherCard();
      case DashboardWidgetType.miniWorkouts:
        return const MiniWorkoutsCard();
      case DashboardWidgetType.workoutCalendar:
        return const WorkoutCalendarCard();
      case DashboardWidgetType.recoverySummary:
        return const RecoverySummaryCard();
      case DashboardWidgetType.cnsLoad:
        return const CnsLoadMiniCard();
      case DashboardWidgetType.weeklyVolume:
        return const WeeklyVolumeMiniCard();
      case DashboardWidgetType.latestPrs:
        return const LatestPrsCard();
      case DashboardWidgetType.cycle:
        return const CycleFocusCard();
      case DashboardWidgetType.quickScan:
        return const QuickScanWidget();
      case DashboardWidgetType.supplements:
        return const SupplementTrackerWidget();
      case DashboardWidgetType.remainingCalories:
        return const RemainingCaloriesCard();
      case DashboardWidgetType.nutritionStreak:
        return const NutritionStreakCard();
      case DashboardWidgetType.workoutStreak:
        return const WorkoutStreakCard();
      case DashboardWidgetType.herculInsights:
        return const HerculInsightsCard();
    }
  }

  void _showCustomizeSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DashboardCustomizeSheet(),
    );
  }

  /// Time-of-day greeting above the name in the dashboard header.
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 18) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  /// First name only, for profile avatar initials.
  String _firstName(String? name) {
    final raw = name?.trim() ?? '';
    if (raw.isEmpty) return '';
    return raw.split(RegExp(r'\s+')).first;
  }
}

class _LiveMacrosGridWrapper extends ConsumerWidget {
  const _LiveMacrosGridWrapper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);

    return LiveMacrosGrid(
      totals:
          ref.watch(dailyTotalsProvider(today)).asData?.value ??
          DailyTotals.empty,
      targets:
          ref.watch(effectiveTargetsProvider(today)).asData?.value ??
          ref.watch(baselineTargetsProvider),
    );
  }
}

class FastingTimerWidget extends ConsumerWidget {
  const FastingTimerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeAsync = ref.watch(activeFastingSessionProvider);
    // Domain color-coding (UI-rework P1): fasting reads teal everywhere so the
    // section is recognisable at a glance.
    final accent = context.hx.domainFasting;

    return activeAsync.when(
      data: (active) {
        if (active != null) {
          final isQuickFast = isQuickFastTarget(active.targetSeconds);
          final tickerAsync = ref.watch(fastingTimerTickerProvider);
          final elapsed = tickerAsync.valueOrNull ?? Duration.zero;
          final target = Duration(seconds: active.targetSeconds);
          final remaining = target - elapsed;
          final isOverTarget = !isQuickFast && remaining.isNegative;
          final currentStage = ref.watch(currentFastingStageProvider);

          final progress = isQuickFast || target.inSeconds == 0
              ? null
              : (elapsed.inSeconds / target.inSeconds).clamp(0.0, 1.0);

          final format = DateFormat('HH:mm');
          final startedStr = format.format(active.startedAt);
          final targetEndStr = format.format(active.startedAt.add(target));

          String durationString(Duration duration) {
            final hours = duration.inHours.abs().toString().padLeft(2, '0');
            final minutes = (duration.inMinutes.abs() % 60).toString().padLeft(
              2,
              '0',
            );
            final seconds = (duration.inSeconds.abs() % 60).toString().padLeft(
              2,
              '0',
            );
            return "$hours:$minutes:$seconds";
          }

          return InkWell(
            onTap: () => context.push(AppRoutes.fasting),
            borderRadius: BorderRadius.circular(28),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: context.hx.isDark ? 0.16 : 0.12),
                    context.hx.surfaceContainerLowest,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: accent.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timelapse, color: accent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        isQuickFast
                            ? "QUICK FAST"
                            : isOverTarget
                            ? "FASTING COMPLETE"
                            : "INTERMITTENT FASTING",
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: accent,
                          letterSpacing: 1.2,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 8,
                          backgroundColor: AppColors.surfaceVariant,
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                        ),
                      ),
                      Column(
                        children: [
                          Text(
                            durationString(
                              isOverTarget || isQuickFast ? elapsed : remaining,
                            ),
                            style: theme.textTheme.displayLarge?.copyWith(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            isOverTarget || isQuickFast
                                ? "ELAPSED"
                                : "REMAINING",
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.secondary,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (currentStage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(
                          alpha: context.hx.isDark ? 0.18 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            getFastingStageIcon(currentStage.icon),
                            size: 14,
                            color: accent,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              "${currentStage.hour}. ura: ${currentStage.stageName}",
                              style: TextStyle(
                                color: accent,
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
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "STARTED",
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.secondary,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            startedStr,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            isQuickFast ? "TARGET" : "TARGET END",
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.secondary,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            isQuickFast ? "None" : targetEndStr,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // End Fast reachable from the home screen (UI-rework P0).
                  InkWell(
                    onTap: () => confirmEndFast(context, ref),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.stop_circle_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "END FAST",
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          final nextFast = ref.watch(nextScheduledFastProvider);

          return InkWell(
            onTap: () => context.push(AppRoutes.fasting),
            borderRadius: BorderRadius.circular(28),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: context.hx.isDark ? 0.16 : 0.12),
                    context.hx.surfaceContainerLowest,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: accent.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timelapse, color: accent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        nextFast != null
                            ? "SCHEDULED FASTING"
                            : "INTERMITTENT FASTING",
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: accent,
                          letterSpacing: 1.2,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (nextFast != null) ...[
                    Builder(
                      builder: (context) {
                        final now = DateTime.now();
                        final isToday =
                            nextFast.nextOccurrence.year == now.year &&
                            nextFast.nextOccurrence.month == now.month &&
                            nextFast.nextOccurrence.day == now.day;
                        final isTomorrow =
                            nextFast.nextOccurrence.year == now.year &&
                            nextFast.nextOccurrence.month == now.month &&
                            nextFast.nextOccurrence.day == now.day + 1;
                        final timeStr = DateFormat(
                          'HH:mm',
                        ).format(nextFast.nextOccurrence);
                        final dayLabel = isToday
                            ? 'Danes ob'
                            : (isTomorrow
                                  ? 'Jutri ob'
                                  : DateFormat(
                                      'EEEE ob',
                                    ).format(nextFast.nextOccurrence));
                        final hrsUntil = nextFast.timeUntil.inHours;
                        final minsUntil = nextFast.timeUntil.inMinutes % 60;
                        final untilStr = hrsUntil > 0
                            ? '${hrsUntil}h ${minsUntil}m'
                            : '${minsUntil}m';

                        return Column(
                          children: [
                            Text(
                              "Naslednji post: $dayLabel $timeStr",
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 19,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "${nextFast.planLabel} · Začetek čez $untilStr",
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "Urnik je aktiven in vas bo pravočasno opomnil na začetek posta.",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.secondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        );
                      },
                    ),
                  ] else ...[
                    Text(
                      "No Active Fast",
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Track your fasting windows to align nutrition, metabolic health, and muscle recovery.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  InkWell(
                    onTap: () => context.push(AppRoutes.fasting),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        nextFast != null ? "START FAST NOW" : "START FASTING",
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
      loading: () => const GlassContainer(
        padding: EdgeInsets.all(32),
        child: SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (err, stack) => GlassContainer(
        padding: const EdgeInsets.all(32),
        child: SizedBox(height: 160, child: Center(child: Text("Error: $err"))),
      ),
    );
  }
}

/// Circular gradient avatar in the dashboard header. Replaces the Profile nav
/// tab as the entry point into `/profile`.
class _ProfileAvatarButton extends StatelessWidget {
  final String name;
  const _ProfileAvatarButton({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'A' : name.trim()[0].toUpperCase();
    return GestureDetector(
      onTap: () => context.push(AppRoutes.profile),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, Color(0xFF30D158)],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Samsung One UI-style swipeable stacked widget with layered depth and pagination dots.
class StackedDashboardWidget extends ConsumerStatefulWidget {
  const StackedDashboardWidget({
    super.key,
    required this.types,
    required this.theme,
    required this.renderWidget,
    required this.onLongPress,
  });

  final List<DashboardWidgetType> types;
  final ThemeData theme;
  final Widget Function(DashboardWidgetType type) renderWidget;
  final VoidCallback onLongPress;

  @override
  ConsumerState<StackedDashboardWidget> createState() =>
      _StackedDashboardWidgetState();
}

class _StackedDashboardWidgetState
    extends ConsumerState<StackedDashboardWidget> {
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _heightForTypes(List<DashboardWidgetType> types) {
    if (types.any((t) => t.kind == DashboardWidgetKind.large)) {
      return 330.0;
    }
    if (types.any((t) => t.kind == DashboardWidgetKind.card)) {
      return 184.0;
    }
    return 76.0;
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final shape = ref.watch(dashboardCardShapeProvider);
    final height = _heightForTypes(widget.types);
    final count = widget.types.length;
    final isPillOnly =
        widget.types.every((t) => t.kind == DashboardWidgetKind.pill);
    final layerRadius = isPillOnly ? shape.pillRadius : shape.cardRadius;

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Bottom-most stack layer background (for 3+ items)
              if (count > 2)
                Positioned(
                  top: -8,
                  left: 16,
                  right: 16,
                  height: height,
                  child: Container(
                    decoration: BoxDecoration(
                      color: hx.surfaceContainerLowest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(
                        layerRadius > 30 ? layerRadius - 4 : layerRadius,
                      ),
                      border: Border.all(
                        color: hx.outlineVariant.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                ),

              // Middle stack layer background (for 2+ items)
              if (count > 1)
                Positioned(
                  top: -4,
                  left: 8,
                  right: 8,
                  height: height,
                  child: Container(
                    decoration: BoxDecoration(
                      color: hx.surfaceContainerLowest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(layerRadius),
                      border: Border.all(
                        color: hx.outlineVariant.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ),

              // Main swipeable PageView
              SizedBox(
                height: height,
                child: PageView.builder(
                  controller: _controller,
                  physics: const BouncingScrollPhysics(),
                  itemCount: count,
                  onPageChanged: (i) {
                    Haptics.selection();
                    setState(() => _page = i);
                  },
                  itemBuilder: (context, index) {
                    final type = widget.types[index];
                    final child = widget.renderWidget(type);
                    if (height > 100 &&
                        type.kind == DashboardWidgetKind.pill) {
                      return Center(child: child);
                    }
                    return child;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Pagination indicator dots / pills
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                GestureDetector(
                  onTap: () {
                    Haptics.selection();
                    _controller.animateToPage(
                      i,
                      duration: HxMotion.base,
                      curve: HxMotion.emphasized,
                    );
                  },
                  child: AnimatedContainer(
                    duration: HxMotion.base,
                    curve: HxMotion.emphasized,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? hx.primary
                          : hx.outlineVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3),
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

/// Floating "Done" pill shown in the bottom right corner while the dashboard is
/// in edit mode — the exit gesture, mirroring iOS Home Screen edit mode.
class _DoneEditingButton extends StatelessWidget {
  const _DoneEditingButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: hx.primary,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: hx.primary.withValues(alpha: 0.4),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, color: hx.onPrimary, size: 18),
            const SizedBox(width: 6),
            Text(
              'Done',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: hx.onPrimary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a dashboard tile with One UI / iOS-style in-place edit controls: a
/// remove button (top-left) and, for widgets that support it, an intuitive
/// size toggle pill (bottom-right) that flips the tile between half and full width.
class _EditableDashboardTile extends ConsumerWidget {
  const _EditableDashboardTile({
    required this.slotIndex,
    required this.slot,
    required this.editMode,
    required this.child,
  });

  final int slotIndex;
  final DashboardWidgetConfig slot;
  final bool editMode;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final shape = ref.watch(dashboardCardShapeProvider);
    final notifier = ref.read(dashboardConfigProvider.notifier);
    final canResize = !slot.isStack && slot.type.resizable;

    return AnimatedContainer(
      duration: HxMotion.base,
      curve: HxMotion.emphasized,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(shape.cardRadius),
        border: editMode
            ? Border.all(color: hx.primary.withValues(alpha: 0.6), width: 1.5)
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedSwitcher(
            duration: HxMotion.base,
            switchInCurve: HxMotion.emphasized,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(
              key: ValueKey('${slot.id}_${slot.effectiveSize}'),
              child: editMode ? IgnorePointer(child: child) : child,
            ),
          ),
          if (editMode) ...[
            Positioned(
              top: -8,
              left: -8,
              child: _RemoveButton(
                onTap: () {
                  Haptics.selection();
                  notifier.toggleSlot(slotIndex, false);
                },
              ),
            ),
            if (canResize)
              Positioned(
                bottom: -8,
                right: -8,
                child: _ResizeButton(
                  size: slot.effectiveSize,
                  onFlip: (next) {
                    Haptics.selection();
                    notifier.resize(slotIndex, next);
                  },
                ),
              ),
            if (slot.isStack)
              Positioned(
                bottom: -8,
                right: -8,
                child: _UnstackButton(
                  onTap: () {
                    Haptics.selection();
                    notifier.unstackWidget(slot.types.last);
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Small circular unstack control in dashboard edit mode for stacked slots.
class _UnstackButton extends StatelessWidget {
  const _UnstackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: hx.surfaceContainer,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Theme.of(context).scaffoldBackgroundColor,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_clear_outlined, size: 13, color: hx.secondary),
            const SizedBox(width: 4),
            Text(
              'Unstack',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: hx.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small circular remove control, iOS Control Center-style.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).scaffoldBackgroundColor,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
            ),
          ],
        ),
        child: const Icon(Icons.remove, size: 16, color: Colors.white),
      ),
    );
  }
}

/// Intuitive size-toggle button in dashboard edit mode: clearly communicates
/// current footprint and provides a comfortable tap target with tactile feedback.
class _ResizeButton extends StatelessWidget {
  const _ResizeButton({required this.size, required this.onFlip});

  final DashboardWidgetSize size;
  final ValueChanged<DashboardWidgetSize> onFlip;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final isHalf = size == DashboardWidgetSize.half;

    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onFlip(isHalf ? DashboardWidgetSize.full : DashboardWidgetSize.half);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: hx.primary,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Theme.of(context).scaffoldBackgroundColor,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isHalf
                  ? Icons.open_in_full_rounded
                  : Icons.close_fullscreen_rounded,
              size: 12,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              isHalf ? 'Full' : '1/2',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
