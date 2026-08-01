class DailyTotals {
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final double sodiumMg;
  final double potassiumMg;
  final double cholesterolMg;

  /// Nutrient values keyed by the stable IDs from the food catalogue.
  /// Missing keys mean unavailable; a present zero is a measured zero.
  final Map<String, double> micros;

  const DailyTotals({
    this.kcal = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.fiberG = 0,
    this.sodiumMg = 0,
    this.potassiumMg = 0,
    this.cholesterolMg = 0,
    this.micros = const {},
  });

  static const empty = DailyTotals();

  bool get hasMicros =>
      micros.isNotEmpty || sodiumMg > 0 || potassiumMg > 0 || cholesterolMg > 0;

  bool hasNutrient(String id) => micros.containsKey(id);

  double? nutrient(String id) => micros[id];

  DailyTotals plus({
    double kcal = 0,
    double proteinG = 0,
    double carbsG = 0,
    double fatG = 0,
    double fiberG = 0,
    double sodiumMg = 0,
    double potassiumMg = 0,
    double cholesterolMg = 0,
    Map<String, double> micros = const {},
  }) => DailyTotals(
    kcal: this.kcal + kcal,
    proteinG: this.proteinG + proteinG,
    carbsG: this.carbsG + carbsG,
    fatG: this.fatG + fatG,
    fiberG: this.fiberG + fiberG,
    sodiumMg: this.sodiumMg + sodiumMg,
    potassiumMg: this.potassiumMg + potassiumMg,
    cholesterolMg: this.cholesterolMg + cholesterolMg,
    micros: _mergeMicros(this.micros, micros),
  );

  static Map<String, double> _mergeMicros(
    Map<String, double> left,
    Map<String, double> right,
  ) {
    if (left.isEmpty) return right.isEmpty ? const {} : Map.unmodifiable(right);
    if (right.isEmpty) return Map.unmodifiable(left);
    final merged = {...left};
    for (final entry in right.entries) {
      merged[entry.key] = (merged[entry.key] ?? 0) + entry.value;
    }
    return Map.unmodifiable(merged);
  }
}
