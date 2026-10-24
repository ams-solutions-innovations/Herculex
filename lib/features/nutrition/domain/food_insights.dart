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

/// Overall nutrition grade determining background gradient highlights:
/// - [gold]: High protein efficiency (≥ 10g protein / 100 kcal)
/// - [green]: Low calories (≤ 50 kcal / 100g or low calorie portion ≤ 60 kcal)
/// - [red]: Bad macros (unfavourable ratio dominated by fat/carbs with negligible protein)
/// - [normal]: Balanced / normal macros (no special highlight)
enum FoodNutritionGrade { gold, green, red, normal }

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

  /// Evaluates food macros to determine its nutrition highlight grade:
  /// - [FoodNutritionGrade.gold]: High protein efficiency (≥ 10g protein per 100 kcal)
  /// - [FoodNutritionGrade.green]: Low calorie density or low calorie portion
  /// - [FoodNutritionGrade.red]: Bad macros (unfavourable ratio dominated by fat/carbs with negligible protein)
  /// - [FoodNutritionGrade.normal]: Balanced macros / neutral
  static FoodNutritionGrade gradeFor({
    String? name,
    required double kcal,
    required double proteinG,
    required double carbsG,
    required double fatG,
    double? kcalPer100g,
  }) {
    if (name == '—' ||
        (kcal <= 0 && proteinG <= 0 && carbsG <= 0 && fatG <= 0)) {
      return FoodNutritionGrade.normal;
    }

    // 1. Gold gradient: ≥ 10g protein per 100 kcal
    // "ce ima hrana 10g beljakovin na 100kcal je to zlat gradient"
    if (kcal > 0 &&
        ((proteinG / kcal) * 100 >= 10.0 || proteinG * 10 >= kcal)) {
      return FoodNutritionGrade.gold;
    }

    final totalMacroKcal = proteinG * 4 + carbsG * 4 + fatG * 9;
    final totalEnergyKcal = kcal > 0 ? kcal : totalMacroKcal;
    final proteinShare = totalEnergyKcal > 0
        ? (proteinG * 4) / totalEnergyKcal
        : 0.0;
    final carbsShare = totalEnergyKcal > 0
        ? (carbsG * 4) / totalEnergyKcal
        : 0.0;
    final fatShare = totalEnergyKcal > 0 ? (fatG * 9) / totalEnergyKcal : 0.0;

    // Bad macros detection:
    // "ce so slabi makroti je rdec dragient"
    // Unfavourable macronutrient balance: fat-dominant with very low protein,
    // combined high fat + high carbs with negligible protein (junk food), or pure sugar.
    final isBadMacros =
        totalEnergyKcal > 0 &&
        ((fatShare >= 0.55 && proteinShare < 0.08) ||
            (fatShare >= 0.38 && carbsShare >= 0.40 && proteinShare < 0.08) ||
            (carbsShare >= 0.85 && proteinShare < 0.04 && kcal >= 80));

    // 2. Green gradient: Low calories
    // "ce so nizke kalorije je zelen"
    final isLowCalorie =
        !isBadMacros &&
        ((kcalPer100g != null && kcalPer100g > 0 && kcalPer100g <= 50) ||
            (kcal <= 60 && fatShare < 0.45));

    if (isLowCalorie) {
      return FoodNutritionGrade.green;
    }

    // 3. Red gradient: Bad macros
    if (isBadMacros) {
      return FoodNutritionGrade.red;
    }

    // 4. Normal: No gradient
    // "pa ce je normalno pa ga ni"
    return FoodNutritionGrade.normal;
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
  }) => MacroSplit(
    proteinKcal: proteinG * 4,
    carbsKcal: carbsG * 4,
    fatKcal: fatG * 9,
  );

  double get totalKcal => proteinKcal + carbsKcal + fatKcal;

  double get proteinShare => totalKcal <= 0 ? 0 : proteinKcal / totalKcal;
  double get carbsShare => totalKcal <= 0 ? 0 : carbsKcal / totalKcal;
  double get fatShare => totalKcal <= 0 ? 0 : fatKcal / totalKcal;
}
