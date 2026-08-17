import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';

/// Quick exercise info shown from an active workout.
///
/// The bottom sheet stays intentionally light: it confirms which exercise the
/// user opened and provides one clear route to the full analytics page. The
/// detailed equipment, accessory and trend data belongs on that page, not in a
/// cramped workout popup.
class ExercisePerformanceSheet extends StatelessWidget {
  final ExerciseCatalogData exercise;
  const ExercisePerformanceSheet({super.key, required this.exercise});

  static Future<void> show(BuildContext context, ExerciseCatalogData exercise) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExercisePerformanceSheet(exercise: exercise),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.30,
      minChildSize: 0.24,
      maxChildSize: 0.42,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color:
              theme.bottomSheetTheme.backgroundColor ??
              AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
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
              exercise.name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('View full exercise details'),
                onPressed: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  router.push('/exercise/${exercise.id}');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
