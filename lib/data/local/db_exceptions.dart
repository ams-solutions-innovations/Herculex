/// Thrown by `NutritionRepository.deleteFood`'s pre-flight when a food is
/// still referenced by logged entries or a recipe — the one live RESTRICT
/// edge hardened ahead of FK enforcement (RB-04 Phase 1). RB-05 replaces this
/// with soft-delete so the UI never has to surface it.
class FoodInUseException implements Exception {
  const FoodInUseException({
    required this.entryCount,
    required this.recipeCount,
  });

  /// Number of `food_entries` rows still pointing at this food.
  final int entryCount;

  /// Number of `recipe_ingredients` rows still pointing at this food.
  final int recipeCount;

  @override
  String toString() =>
      'FoodInUseException(entryCount: $entryCount, recipeCount: $recipeCount)';
}
