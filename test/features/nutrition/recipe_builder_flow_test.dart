import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/recipe_text_parser.dart';
import 'package:herculex/features/nutrition/presentation/dialogs/rambler_recipe_dialog.dart';
import 'package:herculex/features/nutrition/presentation/sheets/food_picker_sheet.dart';
import 'package:herculex/features/nutrition/presentation/views/recipe_builder_view.dart';

void main() {
  group('Recipe Builder Flow', () {
    test('RecipeBuilderView instantiates correctly', () {
      const view = RecipeBuilderView();
      expect(view.isMeal, isFalse);
      expect(view.existingRecipe, isNull);
    });

    test('FoodPickerSheet.showForRecipe can be configured', () {
      const sheet = FoodPickerSheet(
        recipeId: 42,
        mealKey: 'recipe',
      );
      expect(sheet.recipeId, equals(42));
      expect(sheet.mealKey, equals('recipe'));
    });

    test('RamblerRecipeDialog can be configured with recipe parameters', () {
      const dialog = RamblerRecipeDialog(
        existingRecipeId: 10,
        initialRecipeName: 'Protein Shake',
        initialServings: 2,
      );
      expect(dialog.existingRecipeId, equals(10));
      expect(dialog.initialRecipeName, equals('Protein Shake'));
      expect(dialog.initialServings, equals(2));
    });
  });
}
