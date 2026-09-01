import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';
import 'package:herculex/features/fasting/presentation/end_fast_dialog.dart';
import 'package:herculex/features/fasting/presentation/fasting_providers.dart';
import 'package:herculex/features/notifications/presentation/notification_settings_provider.dart';
import 'package:herculex/theme/colors.dart';
import 'package:herculex/theme/tokens/tokens.dart';
import 'package:herculex/widgets/premium_button.dart';
import 'package:intl/intl.dart';

/// The running-session view: ring + timer for a targeted fast, an
/// elapsed-only clock for a Quick Fast (no ring, no "remaining", no editable
/// target — there isn't one).
class ActiveFastPanel extends ConsumerWidget {
  const ActiveFastPanel({super.key, required this.active});

  final FastingSessionData active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final isQuickFast = isQuickFastTarget(active.targetSeconds);

    final tickerAsync = ref.watch(fastingTimerTickerProvider);
    final elapsed = tickerAsync.valueOrNull ?? Duration.zero;
    final target = Duration(seconds: active.targetSeconds);
    final remaining = target - elapsed;
    final isOverTarget = !isQuickFast && remaining.isNegative;

    final progress = isQuickFast || target.inSeconds == 0
        ? null
        : (elapsed.inSeconds / target.inSeconds).clamp(0.0, 1.0);

    final format = DateFormat('HH:mm (MMM d)');
    final startedStr = format.format(active.startedAt);
    final targetEndStr = format.format(active.startedAt.add(target));

    return Column(
      children: [
        Text(
          isQuickFast
              ? "QUICK FAST"
              : isOverTarget
              ? "FASTING COMPLETE"
              : "YOU ARE FASTING",
          style: theme.textTheme.labelLarge?.copyWith(
            color: hx.domainFasting,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isQuickFast
              ? "No target — end whenever you're ready."
              : isOverTarget
              ? "Target reached! Break your fast when ready."
              : "Keep up the great work!",
          style: theme.textTheme.bodyMedium?.copyWith(color: hx.secondary),
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
                backgroundColor: hx.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(hx.domainFasting),
              ),
            ),
            Column(
              children: [
                Text(
                  _durationString(
                    isOverTarget || isQuickFast ? elapsed : remaining,
                  ),
                  style: theme.textTheme.displayLarge?.copyWith(fontSize: 32),
                ),
                const SizedBox(height: 4),
                Text(
                  isOverTarget || isQuickFast ? "ELAPSED" : "REMAINING",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hx.secondary,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: PremiumButton(
            text: "END FAST",
            isPrimary: true,
            icon: Icons.stop_circle_outlined,
            onTap: () => confirmEndFast(context, ref),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _TimeDetailCard(
              title: "STARTED",
              value: startedStr,
              icon: Icons.play_arrow,
              onTap: () => _editStartTime(context, ref),
            ),
            if (isQuickFast)
              const _TimeDetailCard(
                title: "TARGET",
                value: "None",
                icon: Icons.all_inclusive,
              )
            else
              _TimeDetailCard(
                title: "TARGET END",
                value: targetEndStr,
                icon: Icons.outlined_flag,
                onTap: () => _editTargetHours(context, ref),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _FastingStageCard(elapsed: elapsed),
      ],
    );
  }

  String _durationString(Duration duration) {
    final hours = duration.inHours.abs().toString().padLeft(2, '0');
    final minutes = (duration.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds.abs() % 60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }

  Future<void> _editStartTime(BuildContext context, WidgetRef ref) async {
    final initialTime = TimeOfDay.fromDateTime(active.startedAt);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (pickedTime == null) return;

    var newStartTime = DateTime(
      active.startedAt.year,
      active.startedAt.month,
      active.startedAt.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (newStartTime.isAfter(DateTime.now())) {
      newStartTime = newStartTime.subtract(const Duration(days: 1));
    }

    final repo = ref.read(fastingRepositoryProvider);
    await repo.updateSessionStartTime(active.id, newStartTime);

    if (!isQuickFastTarget(active.targetSeconds)) {
      final targetTime = newStartTime.add(
        Duration(seconds: active.targetSeconds),
      );
      final notifEnabled = ref
          .read(notificationSettingsProvider)
          .fastingGoalReachedEnabled;
      await ref
          .read(fastingNotificationSchedulerProvider)
          .scheduleFastingGoal(
            targetTime,
            planName: 'Fasting',
            enabled: notifEnabled,
          );
    }
  }

  Future<void> _editTargetHours(BuildContext context, WidgetRef ref) async {
    final currentHours = active.targetSeconds ~/ 3600;
    int tempHours = currentHours > 0 ? currentHours : 16;
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Adjust Target Fast Duration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$tempHours hours',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
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

    if (selected == null) return;
    final newTargetSec = selected * 3600;
    final repo = ref.read(fastingRepositoryProvider);
    await repo.updateSessionTarget(active.id, newTargetSec);

    final targetTime = active.startedAt.add(Duration(seconds: newTargetSec));
    final notifEnabled = ref
        .read(notificationSettingsProvider)
        .fastingGoalReachedEnabled;
    await ref
        .read(fastingNotificationSchedulerProvider)
        .scheduleFastingGoal(
          targetTime,
          planName: '${selected}h',
          enabled: notifEnabled,
        );
  }
}

class _TimeDetailCard extends StatelessWidget {
  const _TimeDetailCard({
    required this.title,
    required this.value,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final card = Card(
      color: hx.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: hx.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: hx.domainFasting),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: hx.secondary,
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
              Icon(
                Icons.edit,
                size: 12,
                color: hx.domainFasting.withValues(alpha: 0.7),
              ),
          ],
        ),
      ),
    );

    return Expanded(
      child: onTap == null
          ? card
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: card,
            ),
    );
  }
}

class _FastingStageCard extends ConsumerWidget {
  const _FastingStageCard({required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final stage = ref.watch(currentFastingStageProvider);

    if (stage == null) {
      return const SizedBox.shrink();
    }

    final accent = hx.domainFasting;
    final currentHour = elapsed.inHours.clamp(1, 72);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: hx.isDark ? 0.12 : 0.08),
            hx.surfaceContainerLowest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(_getStageIcon(stage.icon), color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          "FAZA TELESA · ${stage.hour}. URA",
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            fontSize: 10,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            stage.stageCategory,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stage.stageName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            stage.shortMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (stage.detail != null && stage.detail!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              stage.detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: hx.secondary,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _showAllStagesSheet(context, ref, currentHour),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Prikaži vse faze posta (6h–72h)",
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 16, color: accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAllStagesSheet(
    BuildContext context,
    WidgetRef ref,
    int currentHour,
  ) {
    final hx = context.hx;
    final stagesAsync = ref.read(fastingStagesProvider);
    final stages = stagesAsync.valueOrNull ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: hx.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: hx.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Faze in spremembe v telesu",
                            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "Kaj se dogaja v telesu od 1h do 72h posta",
                            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: hx.secondary,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: stages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = stages[index];
                      final isCurrent = item.hour == currentHour;
                      final isPast = item.hour < currentHour;
                      final accent = hx.domainFasting;

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? accent.withValues(alpha: 0.12)
                              : isPast
                              ? hx.surfaceContainer
                              : hx.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isCurrent
                                ? accent
                                : isPast
                                ? accent.withValues(alpha: 0.3)
                                : hx.outlineVariant.withValues(alpha: 0.2),
                            width: isCurrent ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? accent
                                    : isPast
                                    ? accent.withValues(alpha: 0.2)
                                    : hx.surfaceVariant,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: isPast
                                    ? Icon(
                                        Icons.check,
                                        size: 18,
                                        color: isCurrent
                                            ? Colors.white
                                            : accent,
                                      )
                                    : Text(
                                        "${item.hour}h",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isCurrent
                                              ? Colors.white
                                              : hx.onSurface,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.stageName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: isCurrent
                                                ? accent
                                                : hx.onSurface,
                                          ),
                                        ),
                                      ),
                                      if (isCurrent)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: accent,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Text(
                                            "ZDAJ",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.shortMessage,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: hx.onSurface.withValues(
                                        alpha: 0.9,
                                      ),
                                    ),
                                  ),
                                  if (item.detail != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      item.detail!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: hx.secondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

IconData _getStageIcon(String? icon) {
  switch (icon) {
    case 'restaurant':
      return Icons.restaurant_rounded;
    case 'battery_charging_full':
      return Icons.battery_charging_full_rounded;
    case 'trending_flat':
      return Icons.trending_flat_rounded;
    case 'hourglass_empty':
      return Icons.hourglass_empty_rounded;
    case 'spa':
      return Icons.spa_rounded;
    case 'balance':
      return Icons.balance_rounded;
    case 'bedtime':
      return Icons.bedtime_rounded;
    case 'bolt':
      return Icons.bolt_rounded;
    case 'autorenew':
      return Icons.autorenew_rounded;
    case 'local_fire_department':
      return Icons.local_fire_department_rounded;
    case 'favorite':
      return Icons.favorite_rounded;
    case 'swap_horiz':
      return Icons.swap_horiz_rounded;
    case 'whatshot':
      return Icons.whatshot_rounded;
    case 'health_and_safety':
      return Icons.health_and_safety_rounded;
    case 'fitness_center':
      return Icons.fitness_center_rounded;
    case 'stars':
      return Icons.stars_rounded;
    case 'build':
      return Icons.build_rounded;
    case 'recycling':
      return Icons.recycling_rounded;
    case 'insights':
      return Icons.insights_rounded;
    case 'psychology':
      return Icons.psychology_rounded;
    case 'cleaning_services':
      return Icons.cleaning_services_rounded;
    case 'workspace_premium':
      return Icons.workspace_premium_rounded;
    case 'electric_bolt':
      return Icons.electric_bolt_rounded;
    case 'shield':
      return Icons.shield_rounded;
    case 'military_tech':
      return Icons.military_tech_rounded;
    case 'dna':
      return Icons.fingerprint_rounded;
    case 'emoji_events':
      return Icons.emoji_events_rounded;
    default:
      return Icons.timelapse_rounded;
  }
}
