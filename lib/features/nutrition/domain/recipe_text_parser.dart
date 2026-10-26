import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';

class RamblerRecipeResult {
  final int? recipeId;
  final String recipeName;
  final int servings;
  final String? instructions;
  final List<RamblerFoodItem> items;

  const RamblerRecipeResult({
    this.recipeId,
    required this.recipeName,
    required this.servings,
    this.instructions,
    required this.items,
  });
}

/// Parses servings, title, instructions, and ingredients from user speech/text
/// for recipe creation and editing.
class RecipeTextParser {
  const RecipeTextParser._();

  static int parseServings(String text, {int fallback = 1}) {
    final m1 = RegExp(
      r'(?:makes?|serves?|servings?|porcij[aei]?|portions?|for)\s*[:=-]?\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (m1 != null) return int.tryParse(m1.group(1)!) ?? fallback;

    final m2 = RegExp(
      r'(\d+)\s*(?:servings?|serv\b|porcij[aei]?|portions?|people|oseb[aei]?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (m2 != null) return int.tryParse(m2.group(1)!) ?? fallback;

    return fallback;
  }

  static String parseTitle(String text, String? aiSummary) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isNotEmpty) {
      final first = lines.first;
      if (first.contains(':')) {
        final cand = first.split(':').first.trim();
        if (cand.isNotEmpty &&
            cand.length < 50 &&
            !RegExp(r'\d+\s*(?:g|ml|oz|kcal)').hasMatch(cand)) {
          return cand;
        }
      } else if (!RegExp(r'\d+\s*(?:g|ml|oz|kcal)').hasMatch(first) &&
          first.length < 50) {
        return first;
      }
    }
    if (aiSummary != null && aiSummary.trim().isNotEmpty) {
      final clean = aiSummary.trim();
      if (clean.length < 50) return clean;
    }
    return 'Custom Recipe';
  }

  static String? parseInstructions(String text) {
    final match = RegExp(
      r'(?:directions?|instructions?|steps?|navodila?)\s*[:=-]\s*(.*)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    return match?.group(1)?.trim();
  }

  /// Extracts ingredient quantities and names locally when AI is unavailable.
  ///
  /// Macros default to `0` (not fabricated constants) so the caller can match
  /// against the local 45k food catalogue or ask the user to fill in unknown
  /// macros honestly.
  static List<RamblerFoodItem> fallbackParseItems(String text) {
    final items = <RamblerFoodItem>[];
    final lines = text
        .split(RegExp(r'[\n,;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    for (final line in lines) {
      // Strip optional leading recipe title prefix ("Chicken Bowl: 200g chicken")
      final cleaned = line.contains(':') &&
              !line.toLowerCase().startsWith('direction') &&
              !line.toLowerCase().startsWith('instruction') &&
              !line.toLowerCase().startsWith('step') &&
              !line.toLowerCase().startsWith('navodil')
          ? line.split(':').sublist(1).join(':').trim()
          : line;
      if (cleaned.isEmpty) continue;

      final m = RegExp(
        r'^(?:(\d+(?:\.\d+)?)\s*(g|ml|oz|piece|pieces|scoop|scoops|cup|cups|tbsp|tsp)?\s+([a-zA-Z][a-zA-Z\s-]*)|([a-zA-Z][a-zA-Z\s-]*?)\s+(\d+(?:\.\d+)?)\s*(g|ml|oz|piece|pieces|scoop|scoops|cup|cups|tbsp|tsp)?)$',
        caseSensitive: false,
      ).firstMatch(cleaned);
      if (m != null) {
        final rawAmount =
            double.tryParse(m.group(1) ?? m.group(5) ?? '') ?? 100.0;
        final rawUnit = (m.group(2) ?? m.group(6) ?? 'g').toLowerCase();
        final name = (m.group(3) ?? m.group(4) ?? cleaned).trim();
        final lower = name.toLowerCase();
        if (name.isNotEmpty &&
            !lower.startsWith('serv') &&
            !lower.startsWith('make') &&
            !lower.startsWith('direct') &&
            !lower.startsWith('instruct') &&
            !lower.startsWith('people') &&
            !lower.startsWith('portion') &&
            !lower.startsWith('porcij')) {
          final (grams, normalizedUnit) = _toGramsAndUnit(rawAmount, rawUnit);
          items.add(
            RamblerFoodItem(
              name: name,
              servingGrams: grams,
              portionAmount: rawAmount,
              portionUnit: normalizedUnit,
              kcalPer100g: 0,
              proteinPer100g: 0,
              carbsPer100g: 0,
              fatPer100g: 0,
            ),
          );
        }
      }
    }
    return items;
  }

  static (double, String) _toGramsAndUnit(double amount, String unit) {
    switch (unit) {
      case 'oz':
        return (double.parse((amount * 28.35).toStringAsFixed(1)), 'oz');
      case 'tbsp':
        return (amount * 15.0, 'tbsp');
      case 'tsp':
        return (amount * 5.0, 'tsp');
      case 'cup':
      case 'cups':
        return (amount * 240.0, 'cup');
      case 'scoop':
      case 'scoops':
        return (amount * 30.0, 'scoop');
      case 'piece':
      case 'pieces':
        return (amount * 50.0, 'piece');
      case 'ml':
        return (amount, 'ml');
      default:
        return (amount, 'g');
    }
  }
}
