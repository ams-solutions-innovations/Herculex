import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../data/local/database.dart';
import '../../../../theme/colors.dart';
import '../../../../theme/tokens/tokens.dart';
import '../../../../widgets/premium_button.dart';
import '../../domain/fasting_plan.dart';
import '../end_fast_dialog.dart';
import '../fasting_providers.dart';

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
                  _durationString(isOverTarget || isQuickFast ? elapsed : remaining),
                  style: theme.textTheme.displayLarge?.copyWith(fontSize: 32),
                ),
                const SizedBox(height: 4),
                Text(
                  isOverTarget || isQuickFast ? "ELAPSED" : "REMAINING",
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: hx.secondary, letterSpacing: 1.0),
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
    final pickedTime =
        await showTimePicker(context: context, initialTime: initialTime);
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
      final targetTime =
          newStartTime.add(Duration(seconds: active.targetSeconds));
      await ref
          .read(fastingNotificationSchedulerProvider)
          .scheduleFastingGoal(targetTime, planName: 'Fasting');
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Adjust Target Fast Duration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$tempHours hours',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
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
                child: const Text('CANCEL')),
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
    await ref
        .read(fastingNotificationSchedulerProvider)
        .scheduleFastingGoal(targetTime, planName: '${selected}h');
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
                  Text(title,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontSize: 9, color: hx.secondary)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.edit,
                  size: 12, color: hx.domainFasting.withValues(alpha: 0.7)),
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
