/// A short, plain-language claim about a food's composition — the "This food
/// is high in protein" badges shown while logging (§3).
class FoodInsight {
  final String label;

  /// `positive` badges are worth highlighting, `caution` ones warn, `neutral`
  /// is descriptive. Drives the badge colour only.
  final InsightTone tone;

  const FoodInsight(this.label, this.tone);
}

enum InsightTone { positive, neutral, caution }

/// Derives composition badges from per-100 g macros.
///
/// Thresholds follow EU Regulation 1924/2006 nutrition claims where one
/// exists (high protein = ≥20 % of energy from protein; low fat = ≤3 g/100 g;
/// high fibre = ≥6 g/100 g; low sugar-free proxies are omitted because the
/// catalogue has no sugar column). The remaining badges use widely-used
/// commercial thresholds and are deliberately conservative.
class FoodInsights {
  /// EU: "source of protein" needs 12 % of energy from protein; "high" 20 %.
  static const _proteinHighEnergyShare = 0.20;
  static const _proteinSourceEnergyShare = 0.12;

  static const _lowFatPer100g = 3.0;
  static const _highFatPer100g = 17.5;
  static const _highFibrePer100g = 6.0;
  static const _sourceFibrePer100g = 3.0;
  static const _lowCaloriePer100g = 40.0;
  static const _highSodiumMgPer100g = 600.0;

  /// Badges for a food described per 100 g. Returns at most [limit] badges,
  /// most informative first, and none at all for foods with no energy (an
  /// empty or malformed catalogue row shouldn't sprout claims).
  static List<FoodInsight> forPer100g({
    required double kcal,
    required double proteinG,
    required double carbsG,
    required double fatG,
    double? fiberG,
    double? sodiumMg,
    int limit = 3,
  }) {
    if (kcal <= 0) return const [];

    final out = <FoodInsight>[];

    final proteinShare = proteinG * 4 / kcal;
    if (proteinShare >= _proteinHighEnergyShare) {
      out.add(const FoodInsight('High in protein', InsightTone.positive));
    } else if (proteinShare >= _proteinSourceEnergyShare) {
      out.add(const FoodInsight('Source of protein', InsightTone.positive));
    }

    if (fiberG != null) {
      if (fiberG >= _highFibrePer100g) {
        out.add(const FoodInsight('High in fibre', InsightTone.positive));
      } else if (fiberG >= _sourceFibrePer100g) {
        out.add(const FoodInsight('Source of fibre', InsightTone.positive));
      }
    }

    if (fatG <= _lowFatPer100g) {
      out.add(const FoodInsight('Low fat', InsightTone.positive));
    } else if (fatG >= _highFatPer100g) {
      out.add(const FoodInsight('High in fat', InsightTone.caution));
    }

    if (kcal <= _lowCaloriePer100g) {
      out.add(const FoodInsight('Low calorie', InsightTone.positive));
    }

    if (sodiumMg != null && sodiumMg >= _highSodiumMgPer100g) {
      out.add(const FoodInsight('High in sodium', InsightTone.caution));
    }

    // Carb-dominant foods get a descriptive badge only when nothing more
    // useful applies, so a balanced food doesn't collect three labels.
    if (out.isEmpty && carbsG * 4 / kcal >= 0.55) {
      out.add(const FoodInsight('Carb-dense', InsightTone.neutral));
    }

    return out.take(limit).toList();
  }
}

/// Energy split of a portion, for the ring/bar in the logging preview.
class MacroSplit {
  final double proteinKcal;
  final double carbsKcal;
  final double fatKcal;

  const MacroSplit({
    required this.proteinKcal,
    required this.carbsKcal,
    required this.fatKcal,
  });

  factory MacroSplit.fromGrams({
    required double proteinG,
    required double carbsG,
    required double fatG,
  }) =>
      MacroSplit(
        proteinKcal: proteinG * 4,
        carbsKcal: carbsG * 4,
        fatKcal: fatG * 9,
      );

  double get totalKcal => proteinKcal + carbsKcal + fatKcal;

  double get proteinShare => totalKcal <= 0 ? 0 : proteinKcal / totalKcal;
  double get carbsShare => totalKcal <= 0 ? 0 : carbsKcal / totalKcal;
  double get fatShare => totalKcal <= 0 ? 0 : fatKcal / totalKcal;
}
