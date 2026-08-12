import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../nutrition/domain/daily_totals.dart';
import '../../nutrition/presentation/nutrition_providers.dart';
import '../../nutrition/presentation/recipe_builder_view.dart';

class CustomRecipesView extends ConsumerWidget {
  const CustomRecipesView({super.key});

  Future<void> _deleteRecipe(BuildContext context, WidgetRef ref, RecipeData recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "${recipe.name}"?'),
        content: const Text('This hides it from your recipe list. Any logged history keeps its recorded nutrition and stays unchanged.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: const StadiumBorder(),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(nutritionRepositoryProvider).deleteRecipe(recipe.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted ${recipe.name}'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }
  }

  void _openRecipeBuilder(BuildContext context, {RecipeData? recipe}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeBuilderView(existingRecipe: recipe),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recipesAsync = ref.watch(recipesProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Custom Recipes'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openRecipeBuilder(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Recipe'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: recipesAsync.when(
        data: (recipes) {
          if (recipes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.menu_book_rounded,
                      size: 64,
                      color: AppColors.secondary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No custom recipes yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the button below to build your first recipe with custom ingredients.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            itemCount: recipes.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final recipe = recipes[index];
              return _RecipeTile(
                recipe: recipe,
                onTap: () => _openRecipeBuilder(context, recipe: recipe),
                onDelete: () => _deleteRecipe(context, ref, recipe),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, stack) => Center(child: Text('Error loading recipes: $e')),
      ),
    );
  }
}

final _recipeMacrosViewProvider =
    FutureProvider.family<DailyTotals, int>((ref, recipeId) async {
  ref.watch(recipeIngredientsProvider(recipeId));
  return ref.read(nutritionRepositoryProvider).recipeMacrosPerServing(recipeId);
});

class _RecipeTile extends ConsumerWidget {
  final RecipeData recipe;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RecipeTile({
    required this.recipe,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ingredientsAsync = ref.watch(recipeIngredientsProvider(recipe.id));
    final macrosAsync = ref.watch(_recipeMacrosViewProvider(recipe.id));

    final count = ingredientsAsync.asData?.value.length ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onTap: onTap,
        title: Row(
          children: [
            Expanded(
              child: Text(
                recipe.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            macrosAsync.when(
              data: (per) {
                final kcal = per.kcal.round();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$kcal kcal / serving',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (err, stack) => const SizedBox.shrink(),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.room_service_outlined, size: 14, color: AppColors.secondary),
                const SizedBox(width: 4),
                Text(
                  '${recipe.servings} ${recipe.servings == 1 ? 'serving' : 'servings'} • $count ${count == 1 ? 'ingredient' : 'ingredients'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                ),
              ],
            ),
            if (recipe.notes != null && recipe.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                recipe.notes!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 8),
            macrosAsync.when(
              data: (per) {
                final p = per.proteinG.toStringAsFixed(1);
                final c = per.carbsG.toStringAsFixed(1);
                final f = per.fatG.toStringAsFixed(1);
                return Row(
                  children: [
                    _MacroBadge(label: 'P', value: '${p}g', color: Colors.blue.shade600),
                    const SizedBox(width: 8),
                    _MacroBadge(label: 'C', value: '${c}g', color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    _MacroBadge(label: 'F', value: '${f}g', color: Colors.pink.shade600),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (err, stack) => const SizedBox.shrink(),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: AppColors.onSurfaceVariant,
              onPressed: onTap,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.red.shade400,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MacroBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
