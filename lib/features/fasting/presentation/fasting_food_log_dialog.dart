import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/in_app_notification_controller.dart';
import 'package:herculex/features/fasting/presentation/fasting_providers.dart';
import 'package:herculex/features/gamification/presentation/gamification_providers.dart';
import 'package:herculex/theme/colors.dart';
import 'package:herculex/theme/tokens/tokens.dart';

/// Checks if an active fasting session is currently ongoing.
/// If active, prompts the user whether they want to end their fast or continue fasting.
///
/// Returns:
/// - `true` if food logging should proceed (user chose either "End Fast & Save" or "Keep Fasting").
/// - `false` if the user cancelled the dialog / food logging.
Future<bool> confirmEndFastOnFoodLog(
  BuildContext context,
  WidgetRef ref,
) async {
  final repo = ref.read(fastingRepositoryProvider);
  final active = await repo.activeSession();
  if (active == null) return true;
  if (!context.mounted) return false;

  final hx = context.hx;
  final theme = Theme.of(context);

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: hx.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.timer_outlined, color: hx.domainFasting, size: 24),
            const SizedBox(width: 8),
            const Text("Active Fast"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "You are currently fasting. Logging food will break your fast. Would you like to end your fast now?",
              style: theme.textTheme.bodyMedium?.copyWith(color: hx.secondary),
            ),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: AppColors.primary.withValues(alpha: 0.12),
              leading: Icon(
                Icons.check_circle_outline,
                color: AppColors.primary,
              ),
              title: Text(
                "End Fast & Save",
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                "End fast and save session to history",
                style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
              ),
              onTap: () async {
                Navigator.pop(dialogContext, true);
                final scheduler =
                    ref.read(fastingNotificationSchedulerProvider);
                await scheduler.cancelFastingGoal();
                final currentActive = await repo.activeSession();
                final pastSessions = await repo.history();
                await repo.endSession(completed: true);
                if (currentActive != null) {
                  final duration =
                      DateTime.now().difference(currentActive.startedAt);
                  final evaluator = ref.read(achievementEvaluatorProvider);
                  final items = evaluator.evaluateFinishedFast(
                    fastDuration: duration,
                    pastSessions: pastSessions,
                    planName: 'Fasting Protocol',
                    targetSeconds: currentActive.targetSeconds,
                  );
                  final notifier = ref.read(
                    inAppNotificationControllerProvider.notifier,
                  );
                  for (final item in items) {
                    notifier.show(item);
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: hx.surfaceContainer,
              leading: Icon(Icons.play_arrow_outlined, color: hx.onSurface),
              title: const Text(
                "Keep Fasting",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                "Log food without stopping the active fast",
                style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
              ),
              onTap: () => Navigator.pop(dialogContext, true),
            ),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: Colors.red.withValues(alpha: 0.1),
              leading: const Icon(
                Icons.close_rounded,
                color: Colors.redAccent,
              ),
              title: const Text(
                "Cancel",
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                "Do not log food",
                style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
              ),
              onTap: () => Navigator.pop(dialogContext, false),
            ),
          ],
        ),
      );
    },
  );

  return result ?? false;
}
