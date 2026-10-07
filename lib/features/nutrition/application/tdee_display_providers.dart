import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/domain/target_resolver.dart';

// Lives apart from tdee_providers.dart on purpose: it needs
// nutrition_providers.dart, which imports tdee_providers.dart (a cycle
// otherwise).

/// The manual target the user has saved that applies today, or null.
///
/// Deliberately returns the saved RULE and not `effectiveTargetsProvider`,
/// whose baseline fallback would otherwise masquerade as a saved target in the
/// estimate-vs-target comparison (D-07).
final savedTargetForTodayProvider = FutureProvider.autoDispose<TargetRule?>((
  ref,
) async {
  final rows = await ref.watch(nutritionTargetsProvider.future);
  final at = ref.watch(clockProvider).now();
  final today = DateTime(at.year, at.month, at.day);
  final isTrainingDay = await ref
      .watch(nutritionRepositoryProvider)
      .trainedOn(today);
  return TargetResolver.resolveRule(
    rules: [
      for (final r in rows)
        TargetRule(
          kcal: r.kcal,
          proteinG: r.proteinG,
          carbsG: r.carbsG,
          fatG: r.fatG,
          fiberG: r.fiberG,
          appliesTo: r.appliesTo,
        ),
    ],
    date: today,
    isTrainingDay: isTrainingDay,
  );
});
