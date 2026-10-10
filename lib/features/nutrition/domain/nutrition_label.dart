/// One set of nutrition values read from a package.
///
/// Most products have exactly one. Some print several tables for different
/// states of the same product — "drained" and "not drained", "as sold" and
/// "prepared" — and each of those is a variant with its own [label].
class NutritionVariant {
  final String? label;
  final double? servingGrams;
  final double? portionAmount;
  final String servingUnit;
  final double? kcalPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final double? fiberPer100g;
  final double? sodiumMgPer100g;
  final Map<String, double> microsPer100g;

  const NutritionVariant({
    this.label,
    this.servingGrams,
    this.portionAmount,
    this.servingUnit = 'g',
    this.kcalPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.fiberPer100g,
    this.sodiumMgPer100g,
    this.microsPer100g = const {},
  });

  bool get hasCoreNutrition =>
      kcalPer100g != null &&
      proteinPer100g != null &&
      carbsPer100g != null &&
      fatPer100g != null;

  static double? per100(double? value, double? servingGrams) {
    if (value == null) return null;
    if (servingGrams == null || servingGrams <= 0) return value;
    return value * 100 / servingGrams;
  }
}

/// A product read from its nutrition label photo(s). It is only a draft: the
/// user reviews and edits it before anything is saved.
class NutritionLabelDraft {
  final String name;
  final String? brand;
  final List<NutritionVariant> variants;
  final double confidence;
  final String evidence;
  final String? warning;

  const NutritionLabelDraft({
    required this.name,
    this.brand,
    required this.variants,
    required this.confidence,
    required this.evidence,
    this.warning,
  });

  bool get hasMultipleVariants => variants.length > 1;
}

/// The name a variant is saved under: the product name, plus the variant label
/// when the product has more than one variant to tell apart.
String variantFoodName(String name, String? label, {required bool multiple}) {
  final suffix = label?.trim();
  if (!multiple || suffix == null || suffix.isEmpty) return name;
  return '$name ($suffix)';
}
