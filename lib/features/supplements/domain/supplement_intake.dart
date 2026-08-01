import 'supplement.dart';

/// Sums what the supplements ticked off on a given day add to the diary's
/// micronutrient totals (§4).
class SupplementIntake {
  /// Nutrient ID → amount, in that nutrient's own unit. Keys match the food
  /// diary's tracked-nutrient IDs so the two can simply be added.
  final Map<String, double> nutrients;

  /// Supplements that were ticked but declare no nutrient contribution —
  /// surfaced so the UI can explain a blank breakdown rather than hiding it.
  final List<String> untrackedNames;

  const SupplementIntake({
    required this.nutrients,
    required this.untrackedNames,
  });

  static const empty =
      SupplementIntake(nutrients: {}, untrackedNames: []);

  bool get isEmpty => nutrients.isEmpty && untrackedNames.isEmpty;

  /// One dose per supplement per day: the tracker is a checklist, not a
  /// counter, so a ticked item counts exactly once.
  static SupplementIntake forDay({
    required List<Supplement> supplements,
    required Set<String> takenIds,
  }) {
    final totals = <String, double>{};
    final untracked = <String>[];

    for (final s in supplements) {
      if (!takenIds.contains(s.id)) continue;
      if (!s.contributesNutrients) {
        untracked.add(s.name);
        continue;
      }
      s.nutrients.forEach((id, amount) {
        if (amount <= 0) return;
        totals[id] = (totals[id] ?? 0) + amount;
      });
    }

    return SupplementIntake(
      nutrients: Map.unmodifiable(totals),
      untrackedNames: List.unmodifiable(untracked),
    );
  }
}
