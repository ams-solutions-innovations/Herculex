import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../../../theme/haptics.dart';
import '../../../theme/tokens/tokens.dart';
import '../../../ui/hx_card.dart';
import '../../../ui/hx_screen_shell.dart';
import '../../../ui/hx_top_tabs.dart';
import '../data/micro_workouts_repository.dart';
import 'exercise_artwork.dart';
import 'exercise_picker_sheet.dart';
import 'widgets/mini_workout_sparkles.dart';
import 'workouts_providers.dart';

/// Full-featured Mini (Micro) Workouts tracking and management page.
class MicroWorkoutsView extends ConsumerStatefulWidget {
  const MicroWorkoutsView({super.key});

  @override
  ConsumerState<MicroWorkoutsView> createState() => _MicroWorkoutsViewState();
}

class _MicroWorkoutsViewState extends ConsumerState<MicroWorkoutsView> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final todayAsync = ref.watch(microWorkoutsTodayProvider);
    final allAsync = ref.watch(microWorkoutsAllProvider);
    final weeklyStatsAsync = ref.watch(microWorkoutsWeeklyStatsProvider);
    final todayLogsAsync = ref.watch(microWorkoutsTodayLogsProvider);
    final repo = ref.watch(microWorkoutsRepositoryProvider);

    return HxScreenShell(
      title: 'Mini Workouts',
      actions: [
        IconButton(
          icon: const Icon(Icons.add_rounded),
          tooltip: 'Add Mini Workout',
          onPressed: () => _openEditor(context, null),
        ),
      ],
      pinnedBottom: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: () => _openEditor(context, null),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                'New Mini Workout',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: hx.domainTraining,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
      ),
      children: [
        const SizedBox(height: 12),

        // ── 1. Hero Summary & 7-Day Consistency ──
        _buildHeroCard(context, todayAsync, weeklyStatsAsync),

        const SizedBox(height: 16),

        // ── 2. Top Segmented Navigation Tabs ──
        HxTopTabs(
          labels: const ['Today', 'All Habits', "Today's Log"],
          index: _currentTab,
          accent: hx.domainTraining,
          onChanged: (idx) => setState(() => _currentTab = idx),
        ),

        const SizedBox(height: 14),

        // ── 3. Tab Contents ──
        if (_currentTab == 0)
          _buildTodayTab(context, todayAsync, repo)
        else if (_currentTab == 1)
          _buildAllTab(context, allAsync, repo)
        else
          _buildLogsTab(context, todayLogsAsync, repo),

        const SizedBox(height: 90),
      ],
    );
  }

  // ── Hero Summary Card ──
  Widget _buildHeroCard(
    BuildContext context,
    AsyncValue<List<MicroWorkoutStatus>> todayAsync,
    AsyncValue<MicroWorkoutWeeklyStats> weeklyAsync,
  ) {
    final hx = context.hx;
    final trainingColor = hx.domainTraining;

    final todayList = todayAsync.value ?? [];
    final weekly = weeklyAsync.value;

    int totalDoneSets = 0;
    int totalTargetSets = 0;
    int totalRepsDone = 0;

    for (final item in todayList) {
      totalDoneSets += item.completedToday;
      totalTargetSets += item.microWorkout.timesPerDay;
      totalRepsDone += item.repsCompletedToday;
    }

    final double overallProgress = totalTargetSets > 0
        ? (totalDoneSets / totalTargetSets).clamp(0.0, 1.0)
        : 0.0;
    final isAllDone = totalTargetSets > 0 && totalDoneSets >= totalTargetSets;

    return HxCard(
      accent: trainingColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              // Progress Ring
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: overallProgress,
                      strokeWidth: 6,
                      backgroundColor: hx.outlineVariant.withValues(alpha: 0.25),
                      valueColor: AlwaysStoppedAnimation(
                        isAllDone ? const Color(0xFF10B981) : trainingColor,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(overallProgress * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: isAllDone
                                ? const Color(0xFF10B981)
                                : hx.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAllDone
                          ? 'Daily Goal Achieved! 🎉'
                          : '$totalDoneSets of $totalTargetSets sets done',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: hx.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalRepsDone total micro reps logged today',
                      style: TextStyle(
                        fontSize: 13,
                        color: hx.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 12),

          // Weekly Streak & 7-Day Consistency Dots
          _buildWeeklyConsistencyRow(context, weekly),
        ],
      ),
    );
  }

  Widget _buildWeeklyConsistencyRow(
    BuildContext context,
    MicroWorkoutWeeklyStats? weekly,
  ) {
    final hx = context.hx;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    final dailySets = weekly?.dailySets ?? {};
    final streak = weekly?.streakDays ?? 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 7-day dots
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 6; i >= 0; i--) ...[
              () {
                final day = today.subtract(Duration(days: i));
                final dayKey = DateTime(day.year, day.month, day.day);
                final setsCount = dailySets[dayKey] ?? 0;
                final isCurrentDay = i == 0;
                final weekdayLabel = weekdays[(day.weekday - 1) % 7];

                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Column(
                    children: [
                      Text(
                        weekdayLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isCurrentDay
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isCurrentDay
                              ? hx.domainTraining
                              : hx.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: setsCount > 0
                              ? const Color(0xFF10B981)
                              : (isCurrentDay
                                  ? hx.domainTraining.withValues(alpha: 0.15)
                                  : hx.surfaceVariant),
                          border: isCurrentDay
                              ? Border.all(
                                  color: hx.domainTraining,
                                  width: 1.5,
                                )
                              : null,
                        ),
                        child: Center(
                          child: setsCount > 0
                              ? const Icon(
                                  Icons.check,
                                  size: 13,
                                  color: Colors.white,
                                )
                              : (isCurrentDay
                                  ? Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: hx.domainTraining,
                                      ),
                                    )
                                  : null),
                        ),
                      ),
                    ],
                  ),
                );
              }(),
            ],
          ],
        ),

        // Streak badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: Color(0xFFF59E0B),
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '$streak day streak',
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tab 1: Today's Checklist ──
  Widget _buildTodayTab(
    BuildContext context,
    AsyncValue<List<MicroWorkoutStatus>> todayAsync,
    MicroWorkoutsRepository repo,
  ) {
    return todayAsync.when(
      data: (list) {
        if (list.isEmpty) {
          return _buildEmptyState(
            context,
            'No mini workouts configured for today.',
            'Build consistency throughout the day with short micro routines like push-ups, squats, or pull-ups.',
          );
        }

        final allDone = list.every((item) => item.doneForToday);
        final totalDoneReps = list.fold<int>(
          0,
          (sum, item) => sum + item.repsCompletedToday,
        );
        final totalDoneSets = list.fold<int>(
          0,
          (sum, item) => sum + item.completedToday,
        );

        return Column(
          children: [
            if (allDone) ...[
              MiniWorkoutAllDoneBanner(
                totalReps: totalDoneReps,
                totalSets: totalDoneSets,
              ),
              const SizedBox(height: 12),
            ],
            for (final item in list)
              _buildWorkoutItemCard(context, item, repo, isTodayTab: true),
          ],
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // ── Tab 2: All Routines (Active & Paused) ──
  Widget _buildAllTab(
    BuildContext context,
    AsyncValue<List<MicroWorkoutStatus>> allAsync,
    MicroWorkoutsRepository repo,
  ) {
    return allAsync.when(
      data: (list) {
        if (list.isEmpty) {
          return _buildEmptyState(
            context,
            'No habits yet.',
            'Create your first mini habit to start tracking.',
          );
        }

        final activeList =
            list.where((item) => item.microWorkout.active).toList();
        final pausedList =
            list.where((item) => !item.microWorkout.active).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (activeList.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'ACTIVE HABITS (${activeList.length})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: context.hx.onSurfaceVariant,
                  ),
                ),
              ),
              for (final item in activeList)
                _buildWorkoutItemCard(context, item, repo, isTodayTab: false),
            ],
            if (pausedList.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'PAUSED HABITS (${pausedList.length})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: context.hx.onSurfaceVariant,
                  ),
                ),
              ),
              for (final item in pausedList)
                _buildWorkoutItemCard(context, item, repo, isTodayTab: false),
            ],
          ],
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // ── Tab 3: Activity Log / Completed Sets ──
  Widget _buildLogsTab(
    BuildContext context,
    AsyncValue<List<MicroWorkoutLogEntry>> logsAsync,
    MicroWorkoutsRepository repo,
  ) {
    final hx = context.hx;
    final timeFormat = DateFormat('HH:mm');

    return logsAsync.when(
      data: (logs) {
        if (logs.isEmpty) {
          return _buildEmptyState(
            context,
            'No mini sessions logged yet today.',
            'When you tap "+1" or complete a round, each set will appear here in your daily timeline.',
          );
        }

        return Column(
          children: [
            for (final log in logs)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: hx.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hx.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.check_circle_outline_rounded,
                          color: Color(0xFF10B981),
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.exerciseName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: hx.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${log.reps} reps ${log.weightKg > 0 ? "(+${log.weightKg.toStringAsFixed(1)} kg)" : ""} • ${timeFormat.format(log.completedAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: hx.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                      ),
                      color: hx.onSurfaceVariant,
                      tooltip: 'Remove log entry',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete this logged set?'),
                            content: const Text(
                              'This will remove this 1-set session from your workout history and volume tracking.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          Haptics.light();
                          await repo.deleteSession(log.sessionId);
                        }
                      },
                    ),
                  ],
                ),
              ),
          ],
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // ── Workout Item Card ──
  Widget _buildWorkoutItemCard(
    BuildContext context,
    MicroWorkoutStatus item,
    MicroWorkoutsRepository repo, {
    required bool isTodayTab,
  }) {
    final hx = context.hx;
    final isPaused = !item.microWorkout.active;
    final isDone = item.doneForToday;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDone
            ? const Color(0xFF10B981).withValues(alpha: 0.12)
            : (isPaused
                ? hx.surfaceContainerLowest.withValues(alpha: 0.5)
                : hx.surfaceContainerLowest),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDone
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : hx.outlineVariant.withValues(alpha: 0.35),
          width: isDone ? 1.4 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: () => _openEditor(context, item.microWorkout),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Exercise artwork or icon
              if (item.exercise != null)
                ExerciseArtwork(
                  exercise: item.exercise!,
                  size: 44,
                  radius: 12,
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: hx.domainTraining.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.fitness_center_rounded,
                      color: hx.domainTraining,
                      size: 22,
                    ),
                  ),
                ),

              const SizedBox(width: 12),

              // Title and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.microWorkout.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isPaused
                                  ? hx.onSurfaceVariant
                                  : hx.onSurface,
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        if (isPaused)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: hx.outlineVariant.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'PAUSED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: hx.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.microWorkout.targetReps} reps/set • ${item.completedToday}/${item.microWorkout.timesPerDay} today (${item.repsCompletedToday} total reps)',
                      style: TextStyle(
                        fontSize: 12,
                        color: hx.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Segmented Dots
                    MiniWorkoutSegmentedProgress(
                      completed: item.completedToday,
                      total: item.microWorkout.timesPerDay,
                      dotSize: 10,
                      spacing: 6,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Action buttons
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MiniWorkoutCheckButton(
                    isDone: isDone,
                    completedCount: item.completedToday,
                    targetCount: item.microWorkout.timesPerDay,
                    onPressed: () {
                      repo.logCompletion(item.microWorkout);
                    },
                  ),
                  if (item.completedToday > 0) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        Haptics.light();
                        repo.undoLastCompletion(item.microWorkout.id);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          'Undo',
                          style: TextStyle(
                            fontSize: 11,
                            color: hx.onSurfaceVariant,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty State ──
  Widget _buildEmptyState(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    final hx = context.hx;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hx.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hx.domainTraining.withValues(alpha: 0.12),
            ),
            child: Icon(
              Icons.checklist_rounded,
              color: hx.domainTraining,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: hx.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: hx.onSurfaceVariant,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => _openEditor(context, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Mini Habit'),
            style: FilledButton.styleFrom(
              backgroundColor: hx.domainTraining,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── Create / Edit Sheet ──
  Future<void> _openEditor(
    BuildContext context,
    MicroWorkoutData? existing,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MicroWorkoutEditorSheet(
        existing: existing,
      ),
    );
  }
}

/// Modal Bottom Sheet for Creating and Editing Mini Workouts
class _MicroWorkoutEditorSheet extends ConsumerStatefulWidget {
  const _MicroWorkoutEditorSheet({
    this.existing,
  });

  final MicroWorkoutData? existing;

  @override
  ConsumerState<_MicroWorkoutEditorSheet> createState() =>
      _MicroWorkoutEditorSheetState();
}

class _MicroWorkoutEditorSheetState
    extends ConsumerState<_MicroWorkoutEditorSheet> {
  late final TextEditingController _nameCtrl;
  int? _selectedExerciseId;
  String _selectedExerciseName = 'Select Exercise';
  int _targetReps = 20;
  int _timesPerDay = 3;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _nameCtrl = TextEditingController(text: e.name);
      _selectedExerciseId = e.exerciseId;
      _targetReps = e.targetReps;
      _timesPerDay = e.timesPerDay;
      _active = e.active;
    } else {
      _nameCtrl = TextEditingController(text: '');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExercise() async {
    final results = await ExercisePickerSheet.show(context);
    if (results == null || results.isEmpty || !mounted) return;

    final picked = results.first.exercise;
    setState(() {
      _selectedExerciseId = picked.id;
      _selectedExerciseName = picked.name;
      if (_nameCtrl.text.trim().isEmpty || widget.existing == null) {
        _nameCtrl.text = '$_targetReps ${picked.name}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final isEditing = widget.existing != null;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: hx.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEditing ? 'Edit Mini Workout' : 'New Mini Workout',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: hx.onSurface,
                  ),
                ),
                if (isEditing)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                    ),
                    onPressed: _confirmDelete,
                  ),
              ],
            ),
            const SizedBox(height: 18),

            // 1. Exercise Picker
            Text(
              'EXERCISE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: hx.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickExercise,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: hx.surfaceContainer,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hx.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.fitness_center_rounded,
                      color: hx.domainTraining,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedExerciseName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _selectedExerciseId != null
                              ? hx.onSurface
                              : hx.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: hx.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Custom Routine Name
            Text(
              'ROUTINE NAME',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: hx.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. 20 Pushups throughout the day',
                filled: true,
                fillColor: hx.surfaceContainer,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: hx.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 3. Target Reps per round
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TARGET REPS PER ROUND',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: hx.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '$_targetReps reps',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: hx.domainTraining,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildStepperBtn(
                      icon: Icons.remove,
                      onTap: () {
                        if (_targetReps > 5) {
                          setState(() => _targetReps -= 5);
                          _updateDefaultName();
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildStepperBtn(
                      icon: Icons.add,
                      onTap: () {
                        if (_targetReps < 200) {
                          setState(() => _targetReps += 5);
                          _updateDefaultName();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 4. Times per day (Frequency)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ROUNDS PER DAY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: hx.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '$_timesPerDay × daily (${_targetReps * _timesPerDay} reps total)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: hx.onSurface,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildStepperBtn(
                      icon: Icons.remove,
                      onTap: () {
                        if (_timesPerDay > 1) {
                          setState(() => _timesPerDay--);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildStepperBtn(
                      icon: Icons.add,
                      onTap: () {
                        if (_timesPerDay < 12) {
                          setState(() => _timesPerDay++);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),

            if (isEditing) ...[
              const SizedBox(height: 18),
              // 5. Active Toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Active Habit',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Pause without deleting to temporarily hide from today\'s checklist',
                  style: TextStyle(fontSize: 12),
                ),
                value: _active,
                activeThumbColor: hx.domainTraining,
                onChanged: (val) => setState(() => _active = val),
              ),
            ],

            const SizedBox(height: 24),

            // Save / Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: hx.domainTraining,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  isEditing ? 'Save Changes' : 'Create Mini Workout',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final hx = context.hx;
    return InkWell(
      onTap: () {
        Haptics.light();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: hx.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hx.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Center(
          child: Icon(icon, size: 18, color: hx.onSurface),
        ),
      ),
    );
  }

  void _updateDefaultName() {
    if (widget.existing == null && _selectedExerciseId != null) {
      _nameCtrl.text = '$_targetReps $_selectedExerciseName';
    }
  }

  Future<void> _save() async {
    if (_selectedExerciseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an exercise first')),
      );
      return;
    }

    final name = _nameCtrl.text.trim().isEmpty
        ? '$_targetReps $_selectedExerciseName'
        : _nameCtrl.text.trim();

    final repo = ref.read(microWorkoutsRepositoryProvider);

    if (widget.existing != null) {
      await repo.update(
        id: widget.existing!.id,
        name: name,
        exerciseId: _selectedExerciseId,
        targetReps: _targetReps,
        timesPerDay: _timesPerDay,
        active: _active,
      );
    } else {
      await repo.create(
        name: name,
        exerciseId: _selectedExerciseId!,
        targetReps: _targetReps,
        timesPerDay: _timesPerDay,
      );
    }

    Haptics.success();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Mini Workout?'),
        content: const Text(
          'This will remove this mini workout habit. Your past completed sessions will remain preserved in your workout history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && widget.existing != null) {
      Haptics.light();
      await ref
          .read(microWorkoutsRepositoryProvider)
          .delete(widget.existing!.id);
      if (mounted) Navigator.pop(context);
    }
  }
}
