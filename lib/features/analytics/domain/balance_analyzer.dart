import 'training_snapshot.dart';

class BalanceResult {
  final double pushPercentage;
  final double pullPercentage;
  final bool hasAsymmetry;

  const BalanceResult({
    required this.pushPercentage,
    required this.pullPercentage,
    required this.hasAsymmetry,
  });

  static const balanced = BalanceResult(
    pushPercentage: 50.0,
    pullPercentage: 50.0,
    hasAsymmetry: false,
  );
}

class BalanceAnalyzer {
  static BalanceResult summary({
    required List<ResolvedSet> sets,
  }) {
    double pushTonnage = 0;
    double pullTonnage = 0;

    for (final resolvedSet in sets) {
      final force = resolvedSet.exercise.force.toLowerCase();
      final muscle = resolvedSet.exercise.primaryMuscle.toLowerCase();

      if (force == 'push' || muscle == 'chest' || muscle == 'shoulders' || muscle == 'triceps') {
        pushTonnage += resolvedSet.tonnageKg;
      } else if (force == 'pull' || muscle == 'back' || muscle == 'biceps') {
        pullTonnage += resolvedSet.tonnageKg;
      }
    }

    final total = pushTonnage + pullTonnage;
    if (total == 0) {
      return BalanceResult.balanced;
    }

    final pushPct = (pushTonnage / total) * 100.0;
    final pullPct = (pullTonnage / total) * 100.0;

    final diff = (pushPct - pullPct).abs();
    final hasAsymmetry = diff > 25.0;

    return BalanceResult(
      pushPercentage: pushPct,
      pullPercentage: pullPct,
      hasAsymmetry: hasAsymmetry,
    );
  }
}
