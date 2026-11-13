import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/recipe_text_parser.dart';

void main() {
  group('RecipeTextParser', () {
    test('parses servings from explicit keywords', () {
      expect(
        RecipeTextParser.parseServings(
          'Chicken rice bowl: 200g chicken, 100g rice. Makes 2 servings.',
        ),
        equals(2),
      );
      expect(
        RecipeTextParser.parseServings('Pasta for 4 people with 400g pasta'),
        equals(4),
      );
      expect(RecipeTextParser.parseServings('Pancakes - serves: 3'), equals(3));
      expect(RecipeTextParser.parseServings('Oatmeal, 1 serving'), equals(1));
      expect(
        RecipeTextParser.parseServings('Beef stew za 4 porcije'),
        equals(4),
      );
      expect(
        RecipeTextParser.parseServings('Just foods with no servings specified'),
        equals(1),
      );
    });

    test('parses title from recipe text or AI summary', () {
      expect(
        RecipeTextParser.parseTitle(
          'Mediterranean Salad: 150g lettuce, 50g feta cheese',
          'Salad',
        ),
        equals('Mediterranean Salad'),
      );

      expect(
        RecipeTextParser.parseTitle(
          'High Protein Shake\n30g whey\n250ml milk',
          'Protein Shake',
        ),
        equals('High Protein Shake'),
      );

      expect(
        RecipeTextParser.parseTitle(
          '100g oats, 200ml milk, 1 scoop protein',
          'Oatmeal bowl',
        ),
        equals('Oatmeal bowl'),
      );

      expect(
        RecipeTextParser.parseTitle('100g oats, 200ml milk', null),
        equals('Custom Recipe'),
      );
    });

    test('parses directions/instructions from text', () {
      final text =
          'Chicken Bowl: 200g chicken, 100g rice.\nDirections: Cook chicken in olive oil and serve over rice.';
      expect(
        RecipeTextParser.parseInstructions(text),
        equals('Cook chicken in olive oil and serve over rice.'),
      );

      final textSlo =
          'Losos z rižem: 200g lososa, 150g riža.\nNavodila: Lososa popeci na ponvi, riž skuhaj v slani vodi.';
      expect(
        RecipeTextParser.parseInstructions(textSlo),
        equals('Lososa popeci na ponvi, riž skuhaj v slani vodi.'),
      );

      expect(
        RecipeTextParser.parseInstructions('No instructions here'),
        isNull,
      );
    });

    test(
      'fallbackParseItems extracts individual food components and quantities',
      () {
        final text =
            '250g chicken breast\n150g white rice\n2 tbsp olive oil\n1 piece banana';
        final items = RecipeTextParser.fallbackParseItems(text);

        expect(items.length, equals(4));
        expect(items[0].name.toLowerCase(), contains('chicken breast'));
        expect(items[0].servingGrams, equals(250.0));
        expect(items[0].portionUnit, equals('g'));
        // Unknown macros default to 0 rather than fabricated constants.
        expect(items[0].kcalPer100g, equals(0.0));

        expect(items[1].name.toLowerCase(), contains('white rice'));
        expect(items[1].servingGrams, equals(150.0));

        expect(items[2].name.toLowerCase(), contains('olive oil'));
        expect(items[2].portionAmount, equals(2.0));
        expect(items[2].portionUnit, equals('tbsp'));
        expect(items[2].servingGrams, equals(30.0));

        expect(items[3].name.toLowerCase(), contains('banana'));
        expect(items[3].portionAmount, equals(1.0));
        expect(items[3].portionUnit, equals('piece'));
        expect(items[3].servingGrams, equals(50.0));
      },
    );
  });
}
