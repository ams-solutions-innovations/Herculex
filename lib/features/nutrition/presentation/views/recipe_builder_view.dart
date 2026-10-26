import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/domain/barcode_utils.dart';
import 'package:herculex/features/nutrition/domain/daily_totals.dart';
import 'package:herculex/features/nutrition/domain/food_insights.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/presentation/dialogs/rambler_recipe_dialog.dart';
import 'package:herculex/features/nutrition/presentation/sheets/food_picker_sheet.dart';
import 'package:herculex/features/nutrition/presentation/sheets/log_entry_sheet.dart';
import 'package:herculex/features/nutrition/presentation/views/barcode_scanner_view.dart';
import 'package:herculex/features/nutrition/presentation/widgets/barcode_resolution_flow.dart';

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

  Future<void> _updateRecipeMetadata() async {
    if (_recipeId == null) return;
    final name = _name.text.trim().isEmpty
        ? (widget.isMeal ? 'Untitled meal' : 'Untitled recipe')
        : _name.text.trim();
    final servings = int.tryParse(_servings.text.trim()) ?? 1;
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    await ref.read(nutritionRepositoryProvider).updateRecipe(
      id: _recipeId!,
      name: name,
      servings: servings > 0 ? servings : 1,
      notes: notes,
    );
    ref.invalidate(_recipeMacrosProvider(_recipeId!));
  }

  Future<void> _openRamblerRecipe() async {
    await _ensureRecipe();
    if (!mounted) return;

    final result = await RamblerRecipeDialog.show(
      context,
      existingRecipeId: _recipeId,
      initialRecipeName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      initialServings: int.tryParse(_servings.text.trim()) ?? 1,
      initialNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );

    if (result == null || !mounted) return;

    if ((_name.text.trim().isEmpty ||
            _name.text.trim() == 'Untitled recipe' ||
            _name.text.trim() == 'Untitled meal') &&
        result.recipeName.isNotEmpty) {
      _name.text = result.recipeName;
    }
    if (result.servings > 0) {
      _servings.text = result.servings.toString();
    }
    if (_notes.text.trim().isEmpty &&
        (result.instructions?.isNotEmpty ?? false)) {
      _notes.text = result.instructions!;
    }

    ref.invalidate(recipeIngredientsProvider(_recipeId!));
    ref.invalidate(_recipeMacrosProvider(_recipeId!));

    setState(() {});
    AppNotice.show(
      context,
      'Added ${result.items.length} ${result.items.length == 1 ? 'ingredient' : 'ingredients'} to recipe',
    );
  }

  Future<void> _addIngredient() async {
    await _ensureRecipe();
    if (!mounted || _recipeId == null) return;
    await FoodPickerSheet.showForRecipe(context, recipeId: _recipeId!);
    if (mounted) {
      ref.invalidate(recipeIngredientsProvider(_recipeId!));
      ref.invalidate(_recipeMacrosProvider(_recipeId!));
      setState(() {});
    }
  }

  Future<void> _scanBarcode() async {
    await _ensureRecipe();
    if (!mounted || _recipeId == null) return;
    final scanned = await BarcodeScannerView.show(context);
    if (scanned == null || !mounted) return;
    var normalized = normalizeBarcode(scanned);
    if (normalized == null) {
      final corrected = await _manualBarcodeDialog(initial: scanned);
      if (corrected == null || !mounted) return;
      normalized = normalizeBarcode(corrected);
      if (normalized == null) return;
    }
    final code = normalized.value;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final food = await ref
        .read(nutritionRepositoryProvider)
        .lookupBarcode(code);
    if (!mounted) return;
    Navigator.of(context).pop();
    final FoodData targetFood;
    if (food == null) {
      final created = await resolveUnknownBarcode(context, ref, code);
      if (created == null || !mounted) return;
      targetFood = created;
    } else {
      targetFood = food;
    }
    await LogEntrySheet.forIngredient(
      context,
      food: targetFood,
      recipeId: _recipeId,
    );
    if (mounted) {
      ref.invalidate(recipeIngredientsProvider(_recipeId!));
      ref.invalidate(_recipeMacrosProvider(_recipeId!));
      setState(() {});
    }
  }

  Future<String?> _manualBarcodeDialog({String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    String? error;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Correct barcode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This code is not a valid retail barcode.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'EAN-13, UPC-A, EAN-8 or GTIN-14',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final normalized = normalizeBarcode(controller.text);
                if (normalized == null) {
                  setState(() => error = 'Invalid length or check digit');
                  return;
                }
                Navigator.of(dialogContext).pop(normalized.value);
              },
              child: const Text('Use code'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return value;
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
          tooltip: 'Rambler AI',
          icon: const Icon(Icons.mic_rounded),
          onPressed: _openRamblerRecipe,
        ),
        IconButton(
          tooltip: 'Scan Barcode',
          icon: const Icon(Icons.qr_code_scanner_rounded),
          onPressed: _scanBarcode,
        ),
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
              AppNotice.show(
                context,
                'Add photo feature coming soon',
                kind: AppNoticeKind.info,
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
          onChanged: (_) => _updateRecipeMetadata(),
        ),
        const SizedBox(height: 16),

        // ── Servings & Serving Size ─────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Servings',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 16),
                          visualDensity: VisualDensity.compact,
                          color: AppColors.onSurface,
                          onPressed: () {
                            final current =
                                int.tryParse(_servings.text.trim()) ?? 1;
                            if (current > 1) {
                              Haptics.selection();
                              setState(() {
                                _servings.text = (current - 1).toString();
                              });
                              _updateRecipeMetadata();
                            }
                          },
                        ),
                        Expanded(
                          child: TextField(
                            controller: _servings,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                            onChanged: (_) {
                              _updateRecipeMetadata();
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 16),
                          visualDensity: VisualDensity.compact,
                          color: AppColors.onSurface,
                          onPressed: () {
                            final current =
                                int.tryParse(_servings.text.trim()) ?? 1;
                            Haptics.selection();
                            setState(() {
                              _servings.text = (current + 1).toString();
                            });
                            _updateRecipeMetadata();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: ingredients.when(
                data: (list) {
                  final totalGrams =
                      list.fold<double>(0, (sum, ing) => sum + ing.grams);
                  final servings = int.tryParse(_servings.text.trim()) ?? 1;
                  final perServingGrams = (servings > 0 && totalGrams > 0)
                      ? (totalGrams / servings).round()
                      : 0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Serving Size',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                AppColors.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          perServingGrams > 0
                              ? '~$perServingGrams g / serving'
                              : '1 serving',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
            ),
          ],
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.mic_rounded, size: 15),
                  label: const Text('Rambler'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _openRamblerRecipe,
                ),
                const SizedBox(width: 6),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 15),
                  label: const Text('Scan'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _scanBarcode,
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _addIngredient,
                ),
              ],
            ),
          ],
        ),
        ingredients.when(
          data: (list) {
            if (list.isEmpty) {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.restaurant_menu_rounded,
                      size: 32,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isMeal
                          ? 'No Items in Meal Yet'
                          : 'No Ingredients Yet',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add ingredients by speaking with Rambler AI, scanning a barcode, or searching the catalogue.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.mic_rounded, size: 16),
                          label: const Text('Rambler AI'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF64B5F6),
                            foregroundColor: Colors.black87,
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: _openRamblerRecipe,
                        ),
                        FilledButton.tonalIcon(
                          icon: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 16,
                          ),
                          label: const Text('Scan Code'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: _scanBarcode,
                        ),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Food'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: _addIngredient,
                        ),
                      ],
                    ),
                  ],
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
          onChanged: (_) => _updateRecipeMetadata(),
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
