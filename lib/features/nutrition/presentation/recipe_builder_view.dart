import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../widgets/premium_button.dart';
import '../domain/daily_totals.dart';
import '../domain/food_insights.dart';
import '../domain/macro_targets.dart';
import 'custom_food_form_sheet.dart';
import 'nutrition_providers.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing
              ? (widget.isMeal ? 'Edit Meal' : 'Edit Recipe')
              : (widget.isMeal ? 'Create a Meal' : 'Create a Recipe'),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addIngredient,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
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
                    child: Icon(Icons.camera_alt, size: 28, color: AppColors.primary),
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
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
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
          Divider(height: 1, color: AppColors.outlineVariant.withValues(alpha: 0.3)),
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
                    widget.isMeal ? 'No items added yet.' : 'No ingredients added yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
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
              hintStyle: theme.textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
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

          PremiumButton(
            text: _saving ? 'Saving…' : (widget.isMeal ? 'Save Meal' : 'Save Recipe'),
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
                        trackColor: AppColors.outlineVariant.withValues(alpha: 0.25),
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
                    _macroColumn(theme, share: split.carbsShare, grams: per.carbsG, label: 'Net Carbs', color: AppColors.macroCarbs),
                    _macroColumn(theme, share: split.fatShare, grams: per.fatG, label: 'Fat', color: AppColors.macroFat),
                    _macroColumn(theme, share: split.proteinShare, grams: per.proteinG, label: 'Protein', color: AppColors.macroProtein),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Percent of Your Daily Goals',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _goalBarCell(theme, label: 'Calories', value: per.kcal, target: targets?.kcal.toDouble(), color: AppColors.macroKcal, isKcal: true)),
              const SizedBox(width: 8),
              Expanded(child: _goalBarCell(theme, label: 'Net Carbs', value: per.carbsG, target: targets?.carbsG.toDouble(), color: AppColors.macroCarbs)),
              const SizedBox(width: 8),
              Expanded(child: _goalBarCell(theme, label: 'Fat', value: per.fatG, target: targets?.fatG.toDouble(), color: AppColors.macroFat)),
              const SizedBox(width: 8),
              Expanded(child: _goalBarCell(theme, label: 'Protein', value: per.proteinG, target: targets?.proteinG.toDouble(), color: AppColors.macroProtein)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macroColumn(ThemeData theme, {required double share, required double grams, required String label, required Color color}) {
    final pct = grams <= 0 ? 0 : (share * 100).round();
    return Column(
      children: [
        Text('$pct%', style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text('${grams.round()}g', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, fontSize: 10)),
      ],
    );
  }

  Widget _goalBarCell(ThemeData theme, {required String label, required double value, required double? target, required Color color, bool isKcal = false}) {
    final pct = (target != null && target > 0) ? (value / target).clamp(0.0, 1.0) : 0.0;
    final pctInt = (pct * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, fontSize: 10)),
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
            Text('$pctInt%', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 10)),
            Text(
              target != null && target > 0
                  ? isKcal
                      ? '${target.round()}'
                      : '${target.round()}g'
                  : '--',
              style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, fontSize: 9),
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
      canvas.drawArc(rect, startAngle + 0.04, math.max(0, sweepAngle - 0.08), false, paint);
      startAngle += sweepAngle;
    }

    if (fShare > 0) {
      final sweepAngle = 2 * math.pi * fShare;
      final paint = Paint()
        ..color = fatColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle + 0.04, math.max(0, sweepAngle - 0.08), false, paint);
      startAngle += sweepAngle;
    }

    if (pShare > 0) {
      final sweepAngle = 2 * math.pi * pShare;
      final paint = Paint()
        ..color = proteinColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle + 0.04, math.max(0, sweepAngle - 0.08), false, paint);
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
  const _IngredientTile({required this.ingredient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final food =
        ref.watch(watchFoodByIdProvider(ingredient.foodId)).asData?.value ??
        _placeholder(ingredient.foodId);
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
        title: Text(food.name),
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
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: AppColors.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: AppColors.outlineVariant),
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
