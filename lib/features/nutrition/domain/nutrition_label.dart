enum LabelExtractionSource { ocr, gemini }

class NutritionLabelDraft {
  final String name;
  final String? brand;
  final double? servingGrams;
  final String servingUnit;
  final double? kcalPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final double? fiberPer100g;
  final double? sodiumMgPer100g;
  final Map<String, double> microsPer100g;
  final double confidence;
  final LabelExtractionSource source;
  final String evidence;
  final String? warning;

  const NutritionLabelDraft({
    required this.name,
    this.brand,
    this.servingGrams,
    this.servingUnit = 'g',
    this.kcalPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.fiberPer100g,
    this.sodiumMgPer100g,
    this.microsPer100g = const {},
    required this.confidence,
    required this.source,
    required this.evidence,
    this.warning,
  });

  bool get hasCoreNutrition =>
      kcalPer100g != null &&
      proteinPer100g != null &&
      carbsPer100g != null &&
      fatPer100g != null;

  NutritionLabelDraft withWarning(String message) => NutritionLabelDraft(
    name: name,
    brand: brand,
    servingGrams: servingGrams,
    servingUnit: servingUnit,
    kcalPer100g: kcalPer100g,
    proteinPer100g: proteinPer100g,
    carbsPer100g: carbsPer100g,
    fatPer100g: fatPer100g,
    fiberPer100g: fiberPer100g,
    sodiumMgPer100g: sodiumMgPer100g,
    microsPer100g: microsPer100g,
    confidence: confidence,
    source: source,
    evidence: evidence,
    warning: message,
  );

  static double? per100(double? value, double? servingGrams) {
    if (value == null) return null;
    if (servingGrams == null || servingGrams <= 0) return value;
    return value * 100 / servingGrams;
  }
}
