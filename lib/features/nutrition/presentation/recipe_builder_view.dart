import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/features/nutrition/domain/daily_totals.dart';
import 'package:herculex/features/nutrition/domain/food_insights.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/presentation/custom_food_form_sheet.dart';
import 'package:herculex/features/nutrition/presentation/log_entry_sheet.dart';
import 'package:herculex/features/nutrition/presentation/nutrition_providers.dart';

class RecipeBuilderView extends ConsumerStatefulWidget {
  final RecipeData? existingRecipe;
  final bool isMeal;

  const RecipeBuilderView({
    super.key,
    this.existingRecipe,
    this.isMeal = false,
  });

  @override
  ConsumerState<RecipeBuilderView> createState() => _RecipeBuilderViewState();
}

class _RecipeBuilderViewState extends ConsumerState<RecipeBuilderView> {
  late final TextEditingController _name;
  late final TextEditingController _servings;
  late final TextEditingController _notes;
  int? _recipeId;
  bool _saving = false;
  String _shareSetting = 'Public';

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
        ? (widget.isMeal ? 'Untitled meal' : 'Untitled recipe')
        : _name.text.trim();
    final servings = int.tryParse(_servings.text.trim()) ?? 1;
    _recipeId = await ref
        .read(nutritionRepositoryProvider)
        .createRecipe(
          name: name,
          servings: servings,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );
    // Dismissing the sheet while the insert is in flight otherwise throws
    // "setState() called after dispose()" — `_addIngredient` right below
    // already guards the same await.
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _addIngredient() async {
    await _ensureRecipe();
    if (!mounted) return;
    final food = await _showFoodPicker();
    if (food == null || !mounted) return;
    await LogEntrySheet.forIngredient(context, food: food, recipeId: _recipeId);
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

  Future<void> _save() async {
    await _ensureRecipe();
    if (_recipeId == null) return;
    setState(() => _saving = true);
    final repo = ref.read(nutritionRepositoryProvider);
    final name = _name.text.trim().isEmpty
        ? (widget.isMeal ? 'Untitled meal' : 'Untitled recipe')
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
    final targets = ref.watch(baselineTargetsProvider);

    return HxScreenShell(
      title: isEditing
          ? (widget.isMeal ? 'Edit Meal' : 'Edit Recipe')
          : (widget.isMeal ? 'Create a Meal' : 'Create a Recipe'),
      actions: [
        IconButton(
          tooltip: 'Add Ingredient',
          icon: const Icon(Icons.add_rounded),
          onPressed: _addIngredient,
        ),
      ],
      pinnedBottom: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: PremiumButton(
          text: _saving
              ? 'Saving…'
              : (widget.isMeal ? 'Save Meal' : 'Save Recipe'),
          onTap: _saving ? () {} : _save,
        ),
      ),
      children: [
        // ── Hero Photo Header Box (Matching Screenshot 1) ─────────────────
        Container(
          height: 140,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.15),
                AppColors.surfaceContainer,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: InkWell(
            onTap: () {
              Haptics.selection();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Add photo feature coming soon')),
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.camera_alt,
                    size: 28,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add Photo',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Meal Name Input Field ──────────────────────────────────────────
        TextField(
          controller: _name,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            labelText: widget.isMeal ? 'Meal Name' : 'Recipe Name',
            hintText: 'Enter name…',
            border: const UnderlineInputBorder(),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Share Setting Row ──────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Share with',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.onSurface,
              ),
            ),
            DropdownButton<String>(
              value: _shareSetting,
              underline: const SizedBox.shrink(),
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              items: const [
                DropdownMenuItem(value: 'Public', child: Text('Public')),
                DropdownMenuItem(value: 'Private', child: Text('Private')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _shareSetting = val);
              },
            ),
          ],
        ),
        Divider(
          height: 1,
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
        const SizedBox(height: 20),

        // ── Live Macro Donut Chart & Daily Goal Breakdown ──────────────────
        if (macros != null)
          macros.when(
            data: (per) => _MacroBreakdownCard(per: per, targets: targets),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          )
        else
          _MacroBreakdownCard(per: DailyTotals.empty, targets: targets),

        const SizedBox(height: 24),

        // ── Ingredients Section ────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.isMeal ? 'Meal Items' : 'Ingredients',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              onPressed: _addIngredient,
            ),
          ],
        ),
        ingredients.when(
          data: (list) {
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  widget.isMeal
                      ? 'No items added yet.'
                      : 'No ingredients added yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              );
            }
            return Column(
              children: list
                  .map(
                    (ing) =>
                        _IngredientTile(ingredient: ing, recipeId: _recipeId!),
                  )
                  .toList(),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Text('Error: $e'),
        ),
        const SizedBox(height: 20),

        // ── Directions / Instructions Section ─────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Directions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notes,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Add instructions for making this meal…',
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.secondary,
            ),
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.outlineVariant),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

final _recipeMacrosProvider = FutureProvider.family<DailyTotals, int>((
  ref,
  recipeId,
) async {
  ref.watch(recipeIngredientsProvider(recipeId));
  return ref.read(nutritionRepositoryProvider).recipeMacrosPerServing(recipeId);
});

// ─── Macro Breakdown Card matching Reference Screenshot 1 ───────────────────
class _MacroBreakdownCard extends StatelessWidget {
  final DailyTotals per;
  final MacroTargets? targets;

  const _MacroBreakdownCard({required this.per, required this.targets});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final split = MacroSplit.fromGrams(
      proteinG: per.proteinG,
      carbsG: per.carbsG,
      fatG: per.fatG,
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(80, 80),
                      painter: _MacroDonutPainter(
                        proteinG: per.proteinG,
                        carbsG: per.carbsG,
                        fatG: per.fatG,
                        proteinColor: AppColors.macroProtein,
                        carbsColor: AppColors.macroCarbs,
                        fatColor: AppColors.macroFat,
                        trackColor: AppColors.outlineVariant.withValues(
                          alpha: 0.25,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          per.kcal <= 0 ? '-' : '${per.kcal.round()}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          'Cal',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.secondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _macroColumn(
                      theme,
                      share: split.carbsShare,
                      grams: per.carbsG,
                      label: 'Net Carbs',
                      color: AppColors.macroCarbs,
                    ),
                    _macroColumn(
                      theme,
                      share: split.fatShare,
                      grams: per.fatG,
                      label: 'Fat',
                      color: AppColors.macroFat,
                    ),
                    _macroColumn(
                      theme,
                      share: split.proteinShare,
                      grams: per.proteinG,
                      label: 'Protein',
                      color: AppColors.macroProtein,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Percent of Your Daily Goals',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _goalBarCell(
                  theme,
                  label: 'Calories',
                  value: per.kcal,
                  target: targets?.kcal.toDouble(),
                  color: AppColors.macroKcal,
                  isKcal: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _goalBarCell(
                  theme,
                  label: 'Net Carbs',
                  value: per.carbsG,
                  target: targets?.carbsG.toDouble(),
                  color: AppColors.macroCarbs,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _goalBarCell(
                  theme,
                  label: 'Fat',
                  value: per.fatG,
                  target: targets?.fatG.toDouble(),
                  color: AppColors.macroFat,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _goalBarCell(
                  theme,
                  label: 'Protein',
                  value: per.proteinG,
                  target: targets?.proteinG.toDouble(),
                  color: AppColors.macroProtein,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macroColumn(
    ThemeData theme, {
    required double share,
    required double grams,
    required String label,
    required Color color,
  }) {
    final pct = grams <= 0 ? 0 : (share * 100).round();
    return Column(
      children: [
        Text(
          '$pct%',
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${grams.round()}g',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.secondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _goalBarCell(
    ThemeData theme, {
    required String label,
    required double value,
    required double? target,
    required Color color,
    bool isKcal = false,
  }) {
    final pct = (target != null && target > 0)
        ? (value / target).clamp(0.0, 1.0)
        : 0.0;
    final pctInt = (pct * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.secondary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 5,
            color: AppColors.outlineVariant.withValues(alpha: 0.3),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: pct > 0 ? pct : 0.01,
                child: Container(color: color),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$pctInt%',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
            Text(
              target != null && target > 0
                  ? isKcal
                        ? '${target.round()}'
                        : '${target.round()}g'
                  : '--',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MacroDonutPainter extends CustomPainter {
  final double proteinG;
  final double carbsG;
  final double fatG;
  final Color proteinColor;
  final Color carbsColor;
  final Color fatColor;
  final Color trackColor;

  _MacroDonutPainter({
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.proteinColor,
    required this.carbsColor,
    required this.fatColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = 7.0;
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    final totalGrams = proteinG + carbsG + fatG;
    if (totalGrams <= 0) return;

    final pShare = proteinG / totalGrams;
    final cShare = carbsG / totalGrams;
    final fShare = fatG / totalGrams;

    final rect = Rect.fromCircle(center: center, radius: radius);
    double startAngle = -math.pi / 2;

    if (cShare > 0) {
      final sweepAngle = 2 * math.pi * cShare;
      final paint = Paint()
        ..color = carbsColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        rect,
        startAngle + 0.04,
        math.max(0, sweepAngle - 0.08),
        false,
        paint,
      );
      startAngle += sweepAngle;
    }

    if (fShare > 0) {
      final sweepAngle = 2 * math.pi * fShare;
      final paint = Paint()
        ..color = fatColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        rect,
        startAngle + 0.04,
        math.max(0, sweepAngle - 0.08),
        false,
        paint,
      );
      startAngle += sweepAngle;
    }

    if (pShare > 0) {
      final sweepAngle = 2 * math.pi * pShare;
      final paint = Paint()
        ..color = proteinColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        rect,
        startAngle + 0.04,
        math.max(0, sweepAngle - 0.08),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MacroDonutPainter oldDelegate) =>
      oldDelegate.proteinG != proteinG ||
      oldDelegate.carbsG != carbsG ||
      oldDelegate.fatG != fatG;
}

class _IngredientTile extends ConsumerWidget {
  final RecipeIngredientData ingredient;
  final int recipeId;

  const _IngredientTile({required this.ingredient, required this.recipeId});

  Future<void> _editIngredient(
    BuildContext context,
    WidgetRef ref,
    FoodData food,
  ) async {
    await LogEntrySheet.forIngredient(
      context,
      food: food,
      existingIngredient: ingredient,
      recipeId: recipeId,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final food =
        ref.watch(watchFoodByIdProvider(ingredient.foodId)).asData?.value ??
        _placeholder(ingredient.foodId);

    final factor = ingredient.grams / 100.0;
    final kcal = (food.kcalPer100g * factor).round();
    final protein = (food.proteinPer100g * factor).toStringAsFixed(1);
    final carbs = (food.carbsPer100g * factor).toStringAsFixed(1);
    final fat = (food.fatPer100g * factor).toStringAsFixed(1);

    return HxStickyDismissible(
      key: ValueKey('ing_${ingredient.id}'),
      borderRadius: BorderRadius.circular(16),
      margin: const EdgeInsets.only(bottom: 8),
      onDismissed: () =>
          ref.read(nutritionRepositoryProvider).removeIngredient(ingredient.id),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: InkWell(
          onTap: () => _editIngredient(context, ref, food),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              food.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${ingredient.grams.toStringAsFixed(0)} g',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.macroKcal.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$kcal kcal',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.macroKcal,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _MacroPill(
                            label: 'P',
                            value: '${protein}g',
                            color: AppColors.macroProtein,
                          ),
                          const SizedBox(width: 6),
                          _MacroPill(
                            label: 'C',
                            value: '${carbs}g',
                            color: AppColors.macroCarbs,
                          ),
                          const SizedBox(width: 6),
                          _MacroPill(
                            label: 'F',
                            value: '${fat}g',
                            color: AppColors.macroFat,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: AppColors.secondary,
                  onPressed: () => _editIngredient(context, ref, food),
                  tooltip: 'Edit ingredient',
                ),
              ],
            ),
          ),
        ),
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

class _MacroPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MacroPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _IngredientPickerSheet extends ConsumerStatefulWidget {
  const _IngredientPickerSheet();

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
    final queryText = (_query ?? '').trim();
    final hasQuery = queryText.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Stack(
        children: [
          Column(
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Add Ingredient',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Custom Food'),
                      onPressed: () async {
                        final food = await CustomFoodFormSheet.show(context);
                        if (food != null && context.mounted) {
                          Navigator.of(context).pop(food);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: hasQuery
                    ? _buildSearchResults(controller, theme, queryText)
                    : _buildDefaultList(controller, theme),
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: math.max(24.0, MediaQuery.paddingOf(context).bottom + 14.0),
            child: _buildFloatingSearchBar(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(
    ScrollController controller,
    ThemeData theme,
    String query,
  ) {
    final searchAsync = ref.watch(foodSearchProvider(query));
    return searchAsync.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No foods found matching "$query".',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondary),
              ),
            ),
          );
        }
        return ListView.separated(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) => _buildFoodTile(list[i], theme),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildDefaultList(ScrollController controller, ThemeData theme) {
    final recentsAsync = ref.watch(recentlyLoggedFoodsProvider);
    final allFoodsAsync = ref.watch(foodSearchProvider(null));

    final recents = recentsAsync.asData?.value ?? [];
    final allFoods = allFoodsAsync.asData?.value ?? [];

    if (recentsAsync.isLoading && allFoodsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (recents.isEmpty && allFoods.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No foods found. Use the search bar below or create a custom food.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.secondary),
          ),
        ),
      );
    }

    final recentIds = recents.map((f) => f.id).toSet();
    final remainingFoods = allFoods
        .where((f) => !recentIds.contains(f.id))
        .toList();

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
      children: [
        // ── Most Frequent / Recent Foods ──
        if (recents.isNotEmpty) ...[
          _buildSectionHeader(
            icon: Icons.history_rounded,
            title: 'Frequently Used',
            subtitle: 'Most common & recent',
            iconColor: AppColors.primary,
            theme: theme,
          ),
          for (final f in recents) ...[
            _buildFoodTile(f, theme),
            const Divider(height: 1),
          ],
          const SizedBox(height: 8),
        ],

        // ── All Foods ──
        if (remainingFoods.isNotEmpty) ...[
          _buildSectionHeader(
            icon: Icons.restaurant_menu,
            title: 'All Foods',
            subtitle: 'Catalogue',
            iconColor: AppColors.secondary,
            theme: theme,
          ),
          for (final f in remainingFoods) ...[
            _buildFoodTile(f, theme),
            const Divider(height: 1),
          ],
        ],
      ],
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
    required ThemeData theme,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor ?? AppColors.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFoodTile(FoodData food, ThemeData theme) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        food.name,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${food.kcalPer100g.toStringAsFixed(0)} kcal/100g · P: ${food.proteinPer100g.toStringAsFixed(1)}g · C: ${food.carbsPer100g.toStringAsFixed(1)}g · F: ${food.fatPer100g.toStringAsFixed(1)}g',
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
      ),
      trailing: Icon(Icons.add_circle_outline, color: AppColors.primary),
      onTap: () => Navigator.of(context).pop(food),
    );
  }

  Widget _buildFloatingSearchBar(ThemeData theme) {
    final hx = context.hx;
    final isDark = hx.isDark;
    final hasQuery = _ctrl.text.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              hx.primary.withValues(alpha: isDark ? 0.16 : 0.08),
              hx.surfaceContainer,
            ),
            Color.alphaBlend(
              hx.primary.withValues(alpha: isDark ? 0.06 : 0.03),
              isDark ? hx.surfaceContainerLowest : hx.surfaceVariant,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: hx.primary.withValues(alpha: isDark ? 0.35 : 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: hx.primary.withValues(alpha: isDark ? 0.18 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: 0.5,
          ),
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.40)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: isDark ? 14 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _ctrl,
        onChanged: (v) => setState(() => _query = v),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: hx.onSurface,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search for a food or ingredient',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: hx.secondary.withValues(alpha: 0.85),
          ),
          prefixIcon: Icon(Icons.search_rounded, size: 22, color: hx.primary),
          suffixIcon: hasQuery
              ? IconButton(
                  icon: Icon(Icons.close, size: 20, color: hx.secondary),
                  onPressed: () {
                    _ctrl.clear();
                    setState(() => _query = null);
                  },
                  tooltip: 'Clear',
                )
              : null,
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}
