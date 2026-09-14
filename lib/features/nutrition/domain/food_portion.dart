import 'package:herculex/data/local/database.dart';

/// A food's nutrition is always stored per 100 g/ml (except legacy catalogue
/// records, which are stored per named serving).  Its serving fields describe
/// the human-friendly measure a person actually uses: scoop, nugget, slice,
/// bottle … This helper keeps the display and the nutrition maths in sync.
class FoodPortion {
  static const _massUnits = {'g', 'gram', 'grams'};
  static const _volumeUnits = {'ml', 'millilitre', 'millilitres'};

  static bool isLegacy(FoodData food) =>
      food.referenceBasis.toLowerCase().contains('legacy serving');

  static bool isVolumeBased(FoodData food) =>
      food.referenceBasis.toLowerCase().contains('100 ml');

  static String defaultUnit(FoodData food) {
    final unit = food.servingUnit?.trim();
    if (unit != null && unit.isNotEmpty && unit != 'undetermined') {
      return unit;
    }
    return isVolumeBased(food) ? 'ml' : 'g';
  }

  static double defaultAmount(FoodData food) {
    final amount = food.servingAmount;
    if (amount != null && amount > 0) return amount;
    final weight = food.servingGrams;
    if (weight != null && weight > 0) return weight;
    return 100;
  }

  /// Only expose sensible alternatives. A minced meat can be weighed in
  /// grams, while a product that defines a scoop/piece can be logged as that
  /// measure or weighed in grams. We never offer millilitres for solids.
  static List<String> availableUnits(FoodData food) {
    final native = defaultUnit(food);
    final units = <String>[native];
    if (isLegacy(food)) {
      // Some legacy records (notably imported protein powders) are per
      // serving but still have a verified serving weight parsed from the
      // product name. Let those users weigh the same serving in grams.
      if (!_massUnits.contains(native.toLowerCase()) &&
          !_volumeUnits.contains(native.toLowerCase()) &&
          (food.servingGrams ?? 0) > 0) {
        units.add('g');
      }
      return units;
    }

    if (isVolumeBased(food)) {
      if (!_volumeUnits.contains(native.toLowerCase())) units.add('ml');
    } else if (!_massUnits.contains(native.toLowerCase())) {
      units.add('g');
    }
    return units;
  }

  static bool isNativeUnit(FoodData food, String unit) =>
      unit.trim().toLowerCase() == defaultUnit(food).toLowerCase();

  /// Physical mass/volume represented by [amount]. Null means that a legacy
  /// entry is a named serving whose underlying mass was not verified.
  static double? massForAmount(FoodData food, double amount, String unit) {
    final normalized = unit.trim().toLowerCase();
    if (_massUnits.contains(normalized) || _volumeUnits.contains(normalized)) {
      return amount;
    }
    final servingMass = food.servingGrams;
    final servingAmount = food.servingAmount;
    if (servingMass == null ||
        servingMass <= 0 ||
        servingAmount == null ||
        servingAmount <= 0) {
      return null;
    }
    if (isNativeUnit(food, unit)) return amount * servingMass / servingAmount;
    return null;
  }

  /// Factor by which the stored nutrient values are scaled for a logged
  /// amount.  Named measures use their labelled physical weight; legacy rows
  /// deliberately scale by portions because their nutrients are per serving.
  static double nutritionFactor(FoodData food, double amount, String unit) {
    if (isLegacy(food)) {
      if (isNativeUnit(food, unit)) return amount / defaultAmount(food);
      final mass = massForAmount(food, amount, unit);
      final servingMass = food.servingGrams;
      if (mass != null && servingMass != null && servingMass > 0) {
        return mass / servingMass;
      }
      return amount / defaultAmount(food);
    }
    return (massForAmount(food, amount, unit) ?? amount) / 100;
  }

  static String label(FoodData food, {bool includeMass = true}) => labelFor(
    amount: defaultAmount(food),
    unit: defaultUnit(food),
    mass: food.servingGrams,
    includeMass: includeMass,
  );

  static String labelFor({
    required double amount,
    required String unit,
    double? mass,
    bool includeMass = true,
  }) {
    final quantity = formatAmount(amount);
    final measure = '$quantity ${unit.trim()}'.trim();
    final normalUnit = unit.trim().toLowerCase();
    final isMassMeasure =
        _massUnits.contains(normalUnit) || _volumeUnits.contains(normalUnit);
    if (!includeMass || isMassMeasure || mass == null || mass <= 0) {
      return measure;
    }
    return '$measure (${formatAmount(mass)} g)';
  }

  static String formatAmount(double amount) => amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(1);
}
