import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../theme/tokens/tokens.dart';
import '../../../widgets/glass_container.dart';
import '../../nutrition/domain/daily_totals.dart';
import '../../nutrition/presentation/nutrition_providers.dart';
import '../../fasting/domain/fasting_plan.dart';
import '../../fasting/presentation/end_fast_dialog.dart';
import '../../fasting/presentation/fasting_providers.dart';
import '../../profile/domain/profile.dart';
import '../domain/dashboard_config.dart';
import 'dashboard_providers.dart';
import 'dashboard_widgets.dart';
import '../../supplements/presentation/supplement_tracker_widget.dart';



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
        if (e.value.visible) e,
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
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
                  if (editMode)
                    _DoneEditingButton(
                      onTap: () {
                        Haptics.selection();
                        ref.read(dashboardEditModeProvider.notifier).state =
                            false;
                      },
                    )
                  else ...[
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
                                      (t) => t != DashboardWidgetType.cycle)
                                  .toList();
                          if (validTypes.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          void enterEditMode() {
                            if (editMode) return;
                            Haptics.heavy();
                            ref
                                .read(dashboardEditModeProvider.notifier)
                                .state = true;
                          }

                          final Widget rendered = validTypes.length > 1
                              ? _StackedDashboardWidget(
                                  types: validTypes,
                                  theme: theme,
                                  renderWidget: (type) =>
                                      _renderWidget(type, theme, ref, context),
                                  onLongPress: enterEditMode,
                                )
                              : GestureDetector(
                                  onLongPress: editMode ? null : enterEditMode,
                                  child: _renderWidget(
                                    validTypes.first,
                                    theme,
                                    ref,
                                    context,
                                  ),
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
                          final tileWidth = _tileWidth(context, w.effectiveSize);
                          return LongPressDraggable<int>(
                            data: index,
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
                                          color: Colors.black
                                              .withValues(alpha: 0.35),
                                          blurRadius: 24,
                                          spreadRadius: 4,
                                          offset: const Offset(0, 10),
                                        ),
                                        BoxShadow(
                                          color: context.hx.primary
                                              .withValues(alpha: 0.35),
                                          blurRadius: 16,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: Opacity(
                                      opacity: 0.95,
                                      child: tile,
                                    ),
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
                                Haptics.selection();
                                ref
                                    .read(dashboardConfigProvider.notifier)
                                    .reorder(details.data, index);
                              },
                              builder: (context, candidate, rejected) {
                                final isTarget = candidate.isNotEmpty;
                                return AnimatedScale(
                                  scale: isTarget ? 0.94 : 1.0,
                                  duration: HxMotion.fast,
                                  curve: HxMotion.emphasized,
                                  child: AnimatedContainer(
                                    duration: HxMotion.fast,
                                    curve: HxMotion.emphasized,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(28),
                                      boxShadow: isTarget
                                          ? [
                                              BoxShadow(
                                                color: context.hx.primary
                                                    .withValues(alpha: 0.45),
                                                blurRadius: 16,
                                                spreadRadius: 2,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: tile,
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
    return size == DashboardWidgetSize.half
        ? (available - 16) / 2
        : available;
  }

  /// Maps a dashboard widget type to its renderer.
  Widget _renderWidget(DashboardWidgetType type, ThemeData theme, WidgetRef ref,
      BuildContext context) {
    switch (type) {
      case DashboardWidgetType.fastingTimer:
        return _buildFastingWidget(theme, ref, context);
      case DashboardWidgetType.macros:
        return LiveMacrosGrid(
          totals: ref.watch(dailyTotalsProvider(_today())).asData?.value ??
              DailyTotals.empty,
          targets: ref.watch(effectiveTargetsProvider(_today())).asData?.value ??
              ref.watch(baselineTargetsProvider),
        );
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
      case DashboardWidgetType.bodyweight:
        return const BodyweightMiniCard();
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


  Widget _buildFastingWidget(ThemeData theme, WidgetRef ref, BuildContext context) {
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

          final progress = isQuickFast || target.inSeconds == 0
              ? null
              : (elapsed.inSeconds / target.inSeconds).clamp(0.0, 1.0);

          final format = DateFormat('HH:mm');
          final startedStr = format.format(active.startedAt);
          final targetEndStr = format.format(active.startedAt.add(target));

          String durationString(Duration duration) {
            final hours = duration.inHours.abs().toString().padLeft(2, '0');
            final minutes = (duration.inMinutes.abs() % 60).toString().padLeft(2, '0');
            final seconds = (duration.inSeconds.abs() % 60).toString().padLeft(2, '0');
            return "$hours:$minutes:$seconds";
          }

          return InkWell(
            onTap: () => context.push('/fasting'),
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
                border: Border.all(
                  color: accent.withValues(alpha: 0.3),
                ),
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
                                isOverTarget || isQuickFast ? elapsed : remaining),
                            style: theme.textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            isOverTarget || isQuickFast ? "ELAPSED" : "REMAINING",
                            style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, letterSpacing: 1.0),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("STARTED", style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, fontSize: 10)),
                          Text(startedStr, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(isQuickFast ? "TARGET" : "TARGET END", style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, fontSize: 10)),
                          Text(isQuickFast ? "None" : targetEndStr, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.stop_circle_outlined, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            "END FAST",
                            style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
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
          return InkWell(
            onTap: () => context.push('/fasting'),
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
                border: Border.all(
                  color: accent.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timelapse, color: accent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        "INTERMITTENT FASTING",
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: accent,
                          letterSpacing: 1.2,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "No Active Fast",
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Track your fasting windows to align nutrition, metabolic health, and muscle recovery.",
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  InkWell(
                    onTap: () => context.push('/fasting'),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "START FASTING",
                        style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
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
        child: SizedBox(
          height: 160,
          child: Center(child: Text("Error: $err")),
        ),
      ),
    );
  }

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
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
      onTap: () => context.push('/profile'),
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

/// Samsung One UI-style swipeable stacked widget with pill pagination dots.
class _StackedDashboardWidget extends StatefulWidget {
  const _StackedDashboardWidget({
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
  State<_StackedDashboardWidget> createState() => _StackedDashboardWidgetState();
}

class _StackedDashboardWidgetState extends State<_StackedDashboardWidget> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _heightForKind(DashboardWidgetKind kind) {
    return switch (kind) {
      DashboardWidgetKind.card => 146.0,
      DashboardWidgetKind.large => 280.0,
      DashboardWidgetKind.pill => 105.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final primaryKind = widget.types.first.kind;
    final height = _heightForKind(primaryKind);

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: height,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.types.length,
              onPageChanged: (i) {
                Haptics.selection();
                setState(() => _page = i);
              },
              itemBuilder: (context, index) {
                return widget.renderWidget(widget.types[index]);
              },
            ),
          ),
          const SizedBox(height: HxSpace.x2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.types.length; i++)
                AnimatedContainer(
                  duration: HxMotion.base,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? hx.primary
                        : hx.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Filled "Done" pill shown in the header while the dashboard is in edit
/// mode — the exit gesture, mirroring iOS Home Screen edit mode.
class _DoneEditingButton extends StatelessWidget {
  const _DoneEditingButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: hx.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'Done',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
    );
  }
}

/// Wraps a dashboard tile with One UI / iOS-style in-place edit controls: a
/// remove button (top-left) and, for widgets that support it, a resize
/// handle (bottom-right) that snaps the tile between half and full width.
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
    final notifier = ref.read(dashboardConfigProvider.notifier);
    final canResize = !slot.isStack && slot.type.resizable;

    return AnimatedContainer(
      duration: HxMotion.base,
      curve: HxMotion.emphasized,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: editMode
            ? Border.all(
                color: hx.primary.withValues(alpha: 0.5),
                width: 1.5,
              )
            : null,
      ),
      child: AnimatedSize(
        duration: HxMotion.slow,
        curve: HxMotion.emphasized,
        alignment: Alignment.topCenter,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            editMode ? IgnorePointer(child: child) : child,
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
                  child: _ResizeHandle(
                    size: slot.effectiveSize,
                    onFlip: (next) {
                      Haptics.selection();
                      notifier.resize(slotIndex, next);
                    },
                  ),
                ),
            ],
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

/// Drag-to-resize handle. Supports both tapping to toggle size and horizontal dragging.
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.size, required this.onFlip});

  final DashboardWidgetSize size;
  final ValueChanged<DashboardWidgetSize> onFlip;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  double _dragAccum = 0;

  void _flip() {
    widget.onFlip(
      widget.size == DashboardWidgetSize.half
          ? DashboardWidgetSize.full
          : DashboardWidgetSize.half,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return GestureDetector(
      onTap: _flip,
      onPanUpdate: (details) {
        _dragAccum += details.delta.dx;
        if (_dragAccum.abs() > 36) {
          _flip();
          _dragAccum = 0;
        }
      },
      onPanEnd: (_) => _dragAccum = 0,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: hx.primary,
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
        child: Transform.rotate(
          angle: 1.5708, // 90°: horizontal drag maps to a horizontal glyph
          child: Icon(
            widget.size == DashboardWidgetSize.half
                ? Icons.unfold_more
                : Icons.unfold_less,
            size: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}