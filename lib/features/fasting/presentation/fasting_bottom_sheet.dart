import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/colors.dart';
import '../../../widgets/glass_container.dart';
import '../../../widgets/premium_button.dart';
import '../domain/fasting_plan.dart';
import 'fasting_providers.dart';

class FastingBottomSheet extends ConsumerStatefulWidget {
  const FastingBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FastingBottomSheet(),
    );
  }

  @override
  ConsumerState<FastingBottomSheet> createState() => _FastingBottomSheetState();
}

class _FastingBottomSheetState extends ConsumerState<FastingBottomSheet> {
  FastingPlan _selectedPlan = FastingPlan.h16;
  int _customTargetHours = 15;
  DateTime? _customStartTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeAsync = ref.watch(activeFastingSessionProvider);
    final historyAsync = ref.watch(fastingHistoryProvider);
    final streakAsync = ref.watch(fastingStreakProvider);
    final avgEatingAsync = ref.watch(fastingAverageEatingWindowProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Grabber/Handle
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    activeAsync.when(
                      data: (active) {
                        if (active != null) {
                          return _buildActiveFastView(theme, active);
                        } else {
                          return _buildStartFastView(theme);
                        }
                      },
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (err, stack) => Center(child: Text('Error: $err')),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 24),
                    _buildInsightsSection(theme, streakAsync, avgEatingAsync),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 24),
                    _buildHistorySection(theme, historyAsync),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveFastView(ThemeData theme, dynamic active) {
    final tickerAsync = ref.watch(fastingTimerTickerProvider);
    final elapsed = tickerAsync.valueOrNull ?? Duration.zero;
    final target = Duration(seconds: active.targetSeconds);
    final remaining = target - elapsed;
    final isOverTarget = remaining.isNegative;

    final progress = target.inSeconds > 0
        ? (elapsed.inSeconds / target.inSeconds).clamp(0.0, 1.0)
        : 0.0;

    final format = DateFormat('HH:mm (MMM d)');
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

    return Column(
      children: [
        Text(
          isOverTarget ? "FASTING COMPLETE" : "YOU ARE FASTING",
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.primary,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isOverTarget
              ? "Target reached! Break your fast when ready."
              : "Keep up the great work!",
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.secondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 10,
                backgroundColor: AppColors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            ),
            Column(
              children: [
                Text(
                  durationString(isOverTarget ? elapsed : remaining),
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isOverTarget ? "ELAPSED" : "REMAINING",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildTimeDetailCard(
              theme,
              "STARTED",
              startedStr,
              Icons.play_arrow,
              onTap: () => _editActiveStartTime(context, active),
            ),
            _buildTimeDetailCard(
              theme,
              "TARGET END",
              targetEndStr,
              Icons.outlined_flag,
              onTap: () => _editActiveTargetHours(context, active),
            ),
          ],
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: PremiumButton(
            text: "END FAST",
            isPrimary: true,
            icon: Icons.stop_circle_outlined,
            onTap: () => _confirmEndFast(context),
          ),
        ),
      ],
    );
  }

  Widget _buildStartFastView(ThemeData theme) {
    final format = DateFormat('HH:mm (MMM d)');
    final startTimeDisplay = _customStartTime != null
        ? format.format(_customStartTime!)
        : "Now";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              Text(
                "READY TO START FASTING?",
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.primary,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Select a plan aligned with your daily flow.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        InkWell(
          onTap: () => _pickCustomStartTime(context),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 12),
                Text(
                  "Start time:",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
                const Spacer(),
                Text(
                  startTimeDisplay,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 14, color: AppColors.primary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            "INTERMITTENT",
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final plan in FastingPlan.values.where(
          (p) => !p.isProlonged && p != FastingPlan.custom,
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _planTile(theme, plan),
          ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "PROLONGED",
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "1–3 DAYS",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                  fontSize: 9,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final plan in FastingPlan.values.where((p) => p.isProlonged))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _planTile(theme, plan),
          ),
        const SizedBox(height: 12),
        _customPlanTile(theme),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: PremiumButton(
            text: "START FAST NOW",
            isPrimary: true,
            icon: Icons.play_arrow_outlined,
            onTap: _startFast,
          ),
        ),
      ],
    );
  }

  Widget _planTile(ThemeData theme, FastingPlan plan) {
    final isSelected = _selectedPlan == plan;
    return InkWell(
      onTap: () => setState(() => _selectedPlan = plan),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                plan.isProlonged
                    ? Icons.bedtime_outlined
                    : Icons.hourglass_empty,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.nameString,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    plan.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _customPlanTile(ThemeData theme) {
    final isSelected = _selectedPlan == FastingPlan.custom;
    return InkWell(
      onTap: () {
        setState(() => _selectedPlan = FastingPlan.custom);
        _pickCustomTargetHours(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.tune_rounded,
                color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Custom (${_customTargetHours}h)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Set your own target hours (tap to change)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomTargetHours(BuildContext context) async {
    int tempHours = _customTargetHours;
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Custom Fast Duration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$tempHours hours',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Slider(
                value: tempHours.toDouble(),
                min: 1,
                max: 168,
                divisions: 167,
                activeColor: AppColors.primary,
                onChanged: (val) => setDlgState(() => tempHours = val.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, tempHours),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('SET DURATION'),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      setState(() => _customTargetHours = selected);
    }
  }

  Future<void> _pickCustomStartTime(BuildContext context) async {
    final now = DateTime.now();
    final initialTime = TimeOfDay.fromDateTime(_customStartTime ?? now);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (pickedTime == null) return;

    var dt = DateTime(now.year, now.month, now.day, pickedTime.hour, pickedTime.minute);
    if (dt.isAfter(now)) {
      // If the selected time is later today, assume the fast began yesterday at that time
      dt = dt.subtract(const Duration(days: 1));
    }

    setState(() => _customStartTime = dt);
  }

  Future<void> _startFast() async {
    final targetSec = _selectedPlan == FastingPlan.custom
        ? _customTargetHours * 3600
        : _selectedPlan.targetSeconds;

    final repo = ref.read(fastingRepositoryProvider);
    await repo.startSession(targetSec, customStartTime: _customStartTime);

    final started = _customStartTime ?? DateTime.now();
    final targetTime = started.add(Duration(seconds: targetSec));
    final planName = _selectedPlan == FastingPlan.custom
        ? '$_customTargetHours-Hour'
        : _selectedPlan.nameString;

    await ref
        .read(fastingNotificationSchedulerProvider)
        .scheduleFastingGoal(targetTime, planName: planName);
  }

  Future<void> _editActiveStartTime(BuildContext context, dynamic active) async {
    final initialTime = TimeOfDay.fromDateTime(active.startedAt as DateTime);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (pickedTime == null) return;

    final orig = active.startedAt as DateTime;
    var newStartTime = DateTime(
      orig.year,
      orig.month,
      orig.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (newStartTime.isAfter(DateTime.now())) {
      newStartTime = newStartTime.subtract(const Duration(days: 1));
    }

    final repo = ref.read(fastingRepositoryProvider);
    await repo.updateSessionStartTime(active.id as int, newStartTime);

    final targetTime = newStartTime.add(Duration(seconds: active.targetSeconds as int));
    await ref
        .read(fastingNotificationSchedulerProvider)
        .scheduleFastingGoal(targetTime, planName: 'Fasting');
  }

  Future<void> _editActiveTargetHours(BuildContext context, dynamic active) async {
    int currentHours = (active.targetSeconds as int) ~/ 3600;
    int tempHours = currentHours > 0 ? currentHours : 16;
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Adjust Target Fast Duration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$tempHours hours',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Slider(
                value: tempHours.toDouble(),
                min: 1,
                max: 168,
                divisions: 167,
                activeColor: AppColors.primary,
                onChanged: (val) => setDlgState(() => tempHours = val.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, tempHours),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('UPDATE'),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      final newTargetSec = selected * 3600;
      final repo = ref.read(fastingRepositoryProvider);
      await repo.updateSessionTarget(active.id as int, newTargetSec);

      final started = active.startedAt as DateTime;
      final targetTime = started.add(Duration(seconds: newTargetSec));
      await ref
          .read(fastingNotificationSchedulerProvider)
          .scheduleFastingGoal(targetTime, planName: '${selected}h');
    }
  }

  Widget _buildTimeDetailCard(
    ThemeData theme,
    String title,
    String value,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    final card = Card(
      color: AppColors.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.edit, size: 12, color: AppColors.primary.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );

    return Expanded(
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: card,
            )
          : card,
    );
  }

  Widget _buildInsightsSection(
    ThemeData theme,
    AsyncValue<int> streakAsync,
    AsyncValue<double> avgEatingAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            "FASTING INSIGHTS",
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildInsightMetricCard(
                theme,
                "Current Streak",
                streakAsync.when(
                  data: (s) => "$s ${s == 1 ? 'day' : 'days'}",
                  loading: () => "...",
                  error: (e, s) => "0",
                ),
                Icons.local_fire_department,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildInsightMetricCard(
                theme,
                "Avg. Window",
                avgEatingAsync.when(
                  data: (hrs) => "${hrs.toStringAsFixed(1)} hrs",
                  loading: () => "...",
                  error: (e, s) => "8.0 hrs",
                ),
                Icons.restaurant,
                AppColors.earthBrown,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInsightMetricCard(
    ThemeData theme,
    String title,
    String value,
    IconData icon,
    Color accentColor,
  ) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              Icon(icon, size: 18, color: accentColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(
    ThemeData theme,
    AsyncValue<dynamic> historyAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            "RECENT SESSIONS",
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        historyAsync.when(
          data: (history) {
            if (history.isEmpty) {
              return GlassContainer(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.history_toggle_off_rounded,
                      size: 36,
                      color: AppColors.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "No Fasting History",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Your completed fasting sessions will appear here.",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: history.length > 5 ? 5 : history.length,
              separatorBuilder: (context, index) => const Divider(height: 24),
              itemBuilder: (context, index) {
                final session = history[index];
                final duration = session.endedAt!.difference(session.startedAt);
                final hours = duration.inHours;
                final minutes = duration.inMinutes % 60;
                final dateStr = DateFormat(
                  'E, MMM d',
                ).format(session.startedAt);
                final targetHours = session.targetSeconds ~/ 3600;

                return Dismissible(
                  key: ValueKey('session_${session.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    color: Colors.redAccent.withValues(alpha: 0.85),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    return await showDialog<bool>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          backgroundColor: AppColors.surfaceContainerLowest,
                          title: const Text("Delete Session"),
                          content: const Text(
                            "Are you sure you want to delete this fasting session?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("CANCEL"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(
                                "DELETE",
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ) ?? false;
                  },
                  onDismissed: (_) {
                    ref.read(fastingRepositoryProvider).deleteSession(session.id);
                  },
                  child: InkWell(
                    onTap: () => _showHistoryDetails(context, session),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: session.completed
                                  ? AppColors.primary.withValues(alpha: 0.1)
                                  : AppColors.surfaceVariant,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              session.completed
                                  ? Icons.check_circle_outline
                                  : Icons.close,
                              color: session.completed
                                  ? AppColors.primary
                                  : AppColors.secondary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "$hours hrs $minutes min fast",
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "Target: ${targetHours}h • $dateStr",
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (session.completed)
                            Text(
                              "SUCCESS",
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          else
                            Text(
                              "INCOMPLETE",
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.secondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }

  Future<void> _showHistoryDetails(BuildContext context, dynamic session) async {
    final format = DateFormat('yyyy-MM-dd HH:mm');
    final startedStr = format.format(session.startedAt as DateTime);
    final endedStr = session.endedAt != null
        ? format.format(session.endedAt as DateTime)
        : 'Ongoing';
    final duration = session.endedAt != null
        ? (session.endedAt as DateTime).difference(session.startedAt as DateTime)
        : Duration.zero;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Fasting Session Details',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.play_arrow_outlined),
              title: const Text('Started'),
              subtitle: Text(startedStr),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.stop_outlined),
              title: const Text('Ended'),
              subtitle: Text(endedStr),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Total Duration'),
              subtitle: Text('${duration.inHours}h ${duration.inMinutes % 60}m'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await ref
                          .read(fastingRepositoryProvider)
                          .updateSessionCompletion(session.id as int, !(session.completed as bool));
                    },
                    icon: Icon(session.completed as bool ? Icons.close : Icons.check),
                    label: Text(session.completed as bool ? 'Mark Incomplete' : 'Mark Completed'),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ref.read(fastingRepositoryProvider).deleteSession(session.id as int);
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmEndFast(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          title: const Text("End Fast"),
          content: const Text(
            "Are you sure you want to end your current fasting session?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL"),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await ref.read(fastingNotificationSchedulerProvider).cancelFastingGoal();
                await ref.read(fastingRepositoryProvider).endSession(completed: true);
              },
              child: Text(
                "END FAST",
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}