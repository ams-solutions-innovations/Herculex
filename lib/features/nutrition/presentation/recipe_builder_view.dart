import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../widgets/premium_button.dart';
import '../domain/daily_totals.dart';
import 'custom_food_form_sheet.dart';
import 'nutrition_providers.dart';

class RecipeBuilderView extends ConsumerStatefulWidget {
  final RecipeData? existingRecipe;
  const RecipeBuilderView({super.key, this.existingRecipe});

  @override
  ConsumerState<RecipeBuilderView> createState() => _RecipeBuilderViewState();
}

class _RecipeBuilderViewState extends ConsumerState<RecipeBuilderView> {
  late final TextEditingController _name;
  late final TextEditingController _servings;
  late final TextEditingController _notes;
  int? _recipeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existingRecipe;
    _recipeId = r?.id;
    _name = TextEditingController(text: r?.name ?? '');
    _servings = TextEditingController(text: (r?.servings ?? 1).toString());
    _notes = TextEditingController(text: r?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _servings.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _ensureRecipe() async {
    if (_recipeId != null) return;
    final name = _name.text.trim().isEmpty
        ? 'Untitled recipe'
        : _name.text.trim();
    final servings = int.tryParse(_servings.text.trim()) ?? 1;
    _recipeId = await ref
        .read(nutritionRepositoryProvider)
        .createRecipe(
          name: name,
          servings: servings,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );
    setState(() {});
  }

  Future<void> _addIngredient() async {
    await _ensureRecipe();
    if (!mounted) return;
    final food = await _showFoodPicker();
    if (food == null) return;
    final grams = await _askGrams(initial: food.servingGrams ?? 100);
    if (grams == null) return;
    await ref
        .read(nutritionRepositoryProvider)
        .addIngredient(recipeId: _recipeId!, foodId: food.id, grams: grams);
  }

  Future<FoodData?> _showFoodPicker() async {
    return showModalBottomSheet<FoodData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _IngredientPickerSheet(),
    );
  }

  Future<double?> _askGrams({required double initial}) async {
    final ctrl = TextEditingController(text: initial.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Grams'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(suffixText: 'g'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(ctrl.text.trim())),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _save() async {
    await _ensureRecipe();
    if (_recipeId == null) return;
    setState(() => _saving = true);
    final repo = ref.read(nutritionRepositoryProvider);
    final name = _name.text.trim().isEmpty
        ? 'Untitled recipe'
        : _name.text.trim();
    final servings = int.tryParse(_servings.text.trim()) ?? 1;
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();

    await repo.updateRecipe(
      id: _recipeId!,
      name: name,
      servings: servings,
      notes: notes,
    );

    final list = await ref.read(recipesProvider.future);
    final created = list.firstWhere(
      (r) => r.id == _recipeId!,
      orElse: () => RecipeData(
        id: _recipeId!,
        name: name,
        servings: servings,
        notes: notes,
        createdAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop<RecipeData>(created);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existingRecipe != null;
    final ingredients = _recipeId == null
        ? const AsyncValue<List<RecipeIngredientData>>.data([])
        : ref.watch(recipeIngredientsProvider(_recipeId!));
    final macros = _recipeId == null
        ? null
        : ref.watch(_recipeMacrosProvider(_recipeId!));

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit recipe' : 'New recipe'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
        children: [
          _Field(label: 'Name', controller: _name),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Field(
                  label: 'Servings',
                  controller: _servings,
                  numeric: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Field(label: 'Notes', controller: _notes, maxLines: 3),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ingredients',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add ingredient'),
                onPressed: _addIngredient,
              ),
            ],
          ),
          ingredients.when(
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No ingredients yet.',
                    style: theme.textTheme.bodyMedium,
                  ),
                );
              }
              return Column(
                children: list
                    .map((ing) => _IngredientTile(ingredient: ing))
                    .toList(),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text('Error: $e'),
          ),
          const SizedBox(height: 24),
          if (macros != null)
            macros.when(
              data: (per) => _MacrosPreview(per: per),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          const SizedBox(height: 32),
          PremiumButton(
            text: _saving ? 'Saving…' : 'Save recipe',
            onTap: _saving ? () {} : _save,
          ),
        ],
      ),
    );
  }
}

final _recipeMacrosProvider = FutureProvider.family<DailyTotals, int>((
  ref,
  recipeId,
) async {
  // Re-evaluate whenever ingredients change.
  ref.watch(recipeIngredientsProvider(recipeId));
  return ref.read(nutritionRepositoryProvider).recipeMacrosPerServing(recipeId);
});

class _IngredientTile extends ConsumerWidget {
  final RecipeIngredientData ingredient;
  const _IngredientTile({required this.ingredient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final food = ref
        .watch(foodSearchProvider(null))
        .asData
        ?.value
        .firstWhere(
          (f) => f.id == ingredient.foodId,
          orElse: () => _placeholder(ingredient.foodId),
        );
    return Dismissible(
      key: ValueKey('ing_${ingredient.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Colors.redAccent.withValues(alpha: 0.85),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) =>
          ref.read(nutritionRepositoryProvider).removeIngredient(ingredient.id),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(food?.name ?? 'Loading…'),
        trailing: Text('${ingredient.grams.toStringAsFixed(0)} g'),
      ),
    );
  }

  FoodData _placeholder(int id) => FoodData(
    id: id,
    name: 'Loading…',
    kcalPer100g: 0,
    proteinPer100g: 0,
    carbsPer100g: 0,
    fatPer100g: 0,
    referenceBasis: '100 g',
    source: 'local',
    isCustom: false,
    createdAt: DateTime.now(),
  );
}

class _MacrosPreview extends StatelessWidget {
  final DailyTotals per;
  const _MacrosPreview({required this.per});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Per serving',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat(per.kcal.toStringAsFixed(0), 'kcal', theme),
              _stat('${per.proteinG.toStringAsFixed(1)}g', 'protein', theme),
              _stat('${per.carbsG.toStringAsFixed(1)}g', 'carbs', theme),
              _stat('${per.fatG.toStringAsFixed(1)}g', 'fat', theme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, ThemeData theme) => Column(
    children: [
      Text(
        value,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary),
      ),
    ],
  );
}

class _IngredientPickerSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_IngredientPickerSheet> createState() =>
      _IngredientPickerSheetState();
}

class _IngredientPickerSheetState
    extends ConsumerState<_IngredientPickerSheet> {
  String? _query;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foods = ref.watch(foodSearchProvider(_query));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _ctrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search foods…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surfaceContainer,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('New custom food'),
                onPressed: () async {
                  final food = await CustomFoodFormSheet.show(context);
                  if (food != null && context.mounted) {
                    Navigator.of(context).pop(food);
                  }
                },
              ),
            ),
          ),
          Expanded(
            child: foods.when(
              data: (list) => ListView.separated(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(list[i].name, style: theme.textTheme.titleSmall),
                  subtitle: Text(
                    '${list[i].kcalPer100g.toStringAsFixed(0)} kcal/100g',
                  ),
                  onTap: () => Navigator.of(context).pop(list[i]),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool numeric;
  final int maxLines;
  const _Field({
    required this.label,
    required this.controller,
    this.numeric = false,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: numeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
              : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceContainer,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
