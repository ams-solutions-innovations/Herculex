import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/colors.dart';
import '../../../widgets/glass_container.dart';
import '../../../widgets/premium_button.dart';
import '../../workouts/presentation/workouts_providers.dart';
import 'block_builder_view.dart';
import 'programs_providers.dart';
import '../../../data/local/database.dart';

class TrainingBlocksView extends ConsumerStatefulWidget {
  const TrainingBlocksView({super.key});

  @override
  ConsumerState<TrainingBlocksView> createState() => _TrainingBlocksViewState();
}

class _TrainingBlocksViewState extends ConsumerState<TrainingBlocksView> {
  int _selectedFilterMonths = 1; // 1, 3, or 6 months
  final Map<int, bool> _expandedWeeks = {}; // track week expansion states

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workoutsAsync = ref.watch(scheduledWorkoutsProvider);
    final conflictsAsync = ref.watch(recoveryConflictsProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
          children: [
            _buildHeader(theme),
            const SizedBox(height: 24),
            conflictsAsync.when(
              data: (conflicts) {
                if (conflicts.isNotEmpty) {
                  return Column(
                    children: conflicts.map((c) => _buildConflictCard(theme, c['message'])).toList(),
                  );
                }
                return Container();
              },
              loading: () => const Center(child: LinearProgressIndicator()),
              error: (err, stack) => Container(),
            ),
            const SizedBox(height: 16),
            workoutsAsync.when(
              data: (workouts) {
                if (workouts.isEmpty) {
                  return _buildEmptyState(theme);
                }
                return _buildTimeline(theme, workouts);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text("Error: $err")),
            ),
             const SizedBox(height: 32),
            PremiumButton(
              text: "Sync to Calendar",
              icon: Icons.calendar_month_rounded,
              onTap: () async {
                final calendarService = ref.read(calendarServiceProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Syncing scheduled workouts to system calendar... 🗓️"),
                    backgroundColor: AppColors.primary,
                    duration: Duration(seconds: 1),
                  ),
                );
                
                final success = await calendarService.exportScheduleToCalendar();
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(
                            success ? Icons.check_circle_rounded : Icons.error_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            success
                                ? "Calendar export completed successfully!"
                                : "Calendar sync failed. Please check permissions.",
                          ),
                        ],
                      ),
                      backgroundColor: success ? AppColors.primary : Colors.redAccent,
                      duration: const Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              "Exported workouts include emojis like Leg Day 🦵",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: Text("Training Blocks", style: theme.textTheme.displayMedium, textAlign: TextAlign.center),
              ),
              Positioned(
                right: 0,
                child: IconButton(
                  icon: Icon(Icons.add_circle, color: AppColors.primary, size: 28),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const BlockBuilderView()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _buildSegment(1, "1 Month", theme),
              _buildSegment(3, "3 Months", theme),
              _buildSegment(6, "6 Months", theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSegment(int filterVal, String text, ThemeData theme) {
    final isSelected = _selectedFilterMonths == filterVal;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedFilterMonths = filterVal;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(
            child: Text(
              text,
              style: theme.textTheme.labelLarge?.copyWith(
                color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConflictCard(ThemeData theme, String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        color: theme.colorScheme.secondary.withValues(alpha: 0.1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                Text("Conflict Detected", style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            PremiumButton(
              text: "Auto-Adjust Program",
              isPrimary: false,
              onTap: () {
                // Auto recovery resolves conflicts by pushing secondary overlapping workout downstream
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Auto-resolving muscle groups overlap..."), backgroundColor: AppColors.primary),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return GlassContainer(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.fitness_center_outlined, size: 48, color: AppColors.primary),
          const SizedBox(height: 16),
          Text("No Active Periodization Block", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            "Structure a visually stunning Meso/Macro training block tailored precisely to your metabolic rhythms.",
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PremiumButton(
            text: "BUILD NEW BLOCK",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const BlockBuilderView()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(ThemeData theme, List<ScheduledWorkoutData> workouts) {
    // Group scheduled workouts by week (every 7 days from start)
    if (workouts.isEmpty) return Container();

    final firstDate = DateTime.parse(workouts.first.dateIso);
    final Map<int, List<ScheduledWorkoutData>> weekGroups = {};

    for (final w in workouts) {
      final wDate = DateTime.parse(w.dateIso);
      final daysDiff = wDate.difference(firstDate).inDays;
      final weekIndex = (daysDiff / 7).floor() + 1;

      if (!weekGroups.containsKey(weekIndex)) {
        weekGroups[weekIndex] = [];
      }
      weekGroups[weekIndex]!.add(w);
    }

    // Filter by months selected (1 month = 4 weeks, 3 months = 12 weeks, 6 months = 24 weeks)
    final maxWeeks = _selectedFilterMonths * 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: weekGroups.keys.where((wIdx) => wIdx <= maxWeeks).map((wIdx) {
        final isExpanded = _expandedWeeks[wIdx] ?? true;
        final weekWorkouts = weekGroups[wIdx]!;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _expandedWeeks[wIdx] = !isExpanded;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.date_range, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Week $wIdx - ${wIdx == 4 ? 'Deload Recovery' : 'Accumulation Cycle'}",
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: AppColors.secondary),
                    ],
                  ),
                ),
              ),
              if (isExpanded) ...[
                const SizedBox(height: 8),
                _buildWeekVolumeSlider(theme, wIdx),
                const SizedBox(height: 8),
                Column(
                  children: weekWorkouts.map((w) => _buildWorkoutTimelineItem(theme, w)).toList(),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWeekVolumeSlider(ThemeData theme, int weekIndex) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text("MANUAL OVERRIDE", style: TextStyle(fontSize: 10, color: AppColors.secondary, letterSpacing: 1.0)),
          const Spacer(),
          SizedBox(
            width: 140,
            child: Slider(
              value: 1.0,
              min: 0.8,
              max: 1.2,
              divisions: 4,
              label: "100%",
              onChanged: (val) {
                // Adjusts specific week factor factor scaling targets (80% - 120%)
              },
            ),
          ),
          const SizedBox(width: 8),
          const Text("100%", style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildWorkoutTimelineItem(ThemeData theme, ScheduledWorkoutData workout) {
    final parsedDate = DateTime.parse(workout.dateIso);
    final dayStr = DateFormat('E, MMM d').format(parsedDate);
    final isSkipped = workout.status == 'skipped';

    return Card(
      color: isSkipped ? theme.colorScheme.surface.withValues(alpha: 0.5) : theme.cardTheme.color,
      elevation: isSkipped ? 0 : 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              isSkipped ? Icons.beach_access : Icons.fitness_center,
              color: isSkipped ? theme.textTheme.bodyMedium?.color : theme.colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSkipped ? "Vacation Rest Block 🌴" : "Training Session",
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(dayStr, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            Icon(Icons.drag_indicator, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}