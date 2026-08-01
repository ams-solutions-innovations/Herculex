import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../theme/colors.dart';
import '../../../widgets/glass_container.dart';
import '../../nutrition/domain/daily_totals.dart';
import '../../nutrition/presentation/nutrition_providers.dart';
import '../../fasting/presentation/fasting_providers.dart';
import '../../fasting/presentation/fasting_bottom_sheet.dart';
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 0,
                      child: _ProfileAvatarButton(name: name),
                    ),
                    Center(
                      child: Text(
                        "Herculex",
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      child: IconButton(
                        icon: const Icon(Icons.tune, size: 20),
                        tooltip: 'Customize dashboard',
                        onPressed: () => _showCustomizeSheet(context, ref),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Config-driven widget list (§18). Each visible slot maps to a
              // renderer; the cycle widget is additionally gated on sex.
              for (final w in config.visibleWidgets)
                if (w.type != DashboardWidgetType.cycle || isFemale) ...[
                  _renderWidget(w.type, theme, ref, context),
                  const SizedBox(height: 24),
                ],
              const SizedBox(height: 76),
            ],
          ),
        ),
      ),
    );
  }

  /// Maps a dashboard widget type to its renderer. Keeps the existing
  /// hand-built sections; the new recovery/CNS/volume/PR/bodyweight cards live
  /// in dashboard_widgets.dart.
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

  /// First name only, for profile avatar initials.
  String _firstName(String? name) {
    final raw = name?.trim() ?? '';
    if (raw.isEmpty) return '';
    return raw.split(RegExp(r'\s+')).first;
  }


  Widget _buildFastingWidget(ThemeData theme, WidgetRef ref, BuildContext context) {
    final activeAsync = ref.watch(activeFastingSessionProvider);

    return activeAsync.when(
      data: (active) {
        if (active != null) {
          final tickerAsync = ref.watch(fastingTimerTickerProvider);
          final elapsed = tickerAsync.valueOrNull ?? Duration.zero;
          final target = Duration(seconds: active.targetSeconds);
          final remaining = target - elapsed;
          final isOverTarget = remaining.isNegative;

          final progress = target.inSeconds > 0 ? (elapsed.inSeconds / target.inSeconds).clamp(0.0, 1.0) : 0.0;

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
            onTap: () => FastingBottomSheet.show(context),
            borderRadius: BorderRadius.circular(28),
            child: GlassContainer(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timelapse, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        isOverTarget ? "FASTING COMPLETE" : "INTERMITTENT FASTING",
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.primary,
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
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                      Column(
                        children: [
                          Text(
                            durationString(isOverTarget ? elapsed : remaining),
                            style: theme.textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            isOverTarget ? "ELAPSED" : "REMAINING",
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
                          Text("TARGET END", style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, fontSize: 10)),
                          Text(targetEndStr, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  )
                ],
              ),
            ),
          );
        } else {
          return InkWell(
            onTap: () => FastingBottomSheet.show(context),
            borderRadius: BorderRadius.circular(28),
            child: GlassContainer(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timelapse, color: AppColors.secondary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        "INTERMITTENT FASTING",
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.secondary,
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "START FASTING",
                      style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
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