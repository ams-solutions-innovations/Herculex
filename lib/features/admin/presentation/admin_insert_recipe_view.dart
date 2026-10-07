import 'package:flutter/material.dart';

import 'package:herculex/features/nutrition/presentation/views/recipe_builder_view.dart';

/// The admin "insert recipe" surface now defers to the real recipe builder.
class AdminInsertRecipeView extends StatelessWidget {
  const AdminInsertRecipeView({super.key});

  @override
  Widget build(BuildContext context) => const RecipeBuilderView();
}
