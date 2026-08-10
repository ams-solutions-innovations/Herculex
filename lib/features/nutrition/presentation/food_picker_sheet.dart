import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../domain/barcode_utils.dart';
import '../domain/meal.dart';
import '../domain/meal_slots.dart';
import 'barcode_scanner_view.dart';
import 'custom_food_form_sheet.dart';
import 'gemini_photo_analysis_dialog.dart';
import 'label_capture_dialog.dart';
import 'log_entry_sheet.dart';
import 'meal_slots_provider.dart';
import 'nutrition_providers.dart';
import 'recipe_builder_view.dart';

/// Tabbed bottom sheet: All · My Meals · My Recipes · My Foods.
class FoodPickerSheet extends ConsumerStatefulWidget {
  final DateTime date;
  final String mealKey;

  const FoodPickerSheet({super.key, required this.date, required this.mealKey});

  static Future<bool?> show(
    BuildContext context, {
    required DateTime date,
    required String mealKey,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FoodPickerSheet(date: date, mealKey: mealKey),
    );
  }

  @override
  ConsumerState<FoodPickerSheet> createState() => _FoodPickerSheetState();
}

class _FoodPickerSheetState extends ConsumerState<FoodPickerSheet>
    with TickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this);
  final _queryCtrl = TextEditingController();
  String? _query;
  late String _activeMealKey = widget.mealKey;

  @override
  void dispose() {
    _tabs.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _logFood(FoodData f) async {
    final logged = await LogEntrySheet.forFood(
      context,
      food: f,
      date: widget.date,
      initialMealKey: _activeMealKey,
    );
    if (logged == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _quickLogFood(FoodData f) async {
    Haptics.success();
    final repo = ref.read(nutritionRepositoryProvider);
    final amount = f.servingAmount ?? f.servingGrams ?? 100;
    final unit = f.referenceBasis.toLowerCase().contains('100 ml') ? 'ml' : 'g';
    await repo.logFood(
      date: widget.date,
      mealKey: _activeMealKey,
      foodId: f.id,
      grams: unit == 'g' ? amount : null,
      portionAmount: amount,
      portionUnit: unit,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _logRecipe(RecipeData r) async {
    final logged = await LogEntrySheet.forRecipe(
      context,
      recipe: r,
      date: widget.date,
      initialMealKey: _activeMealKey,
    );
    if (logged == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _quickLogRecipe(RecipeData r) async {
    Haptics.success();
    final repo = ref.read(nutritionRepositoryProvider);
    await repo.logRecipe(
      date: widget.date,
      mealKey: _activeMealKey,
      recipeId: r.id,
      servings: 1.0,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _scan() async {
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
    if (food == null) {
      final created = await CustomFoodFormSheet.show(
        context,
        initialBarcode: code,
      );
      if (created != null) _logFood(created);
    } else {
      _logFood(food);
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

  Future<void> _takePhotoAndAnalyze() async {
    final picker = ImagePicker();
    final choice = await showModalBottomSheet<_PhotoChoice>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Poslikaj hrano s kamero'),
              subtitle: const Text(
                'Gemini AI bo ocenil sestavo in hranilne vrednosti',
              ),
              onTap: () => Navigator.pop(
                ctx,
                const _PhotoChoice(_PhotoMode.food, ImageSource.camera),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Izberi sliko iz galerije'),
              onTap: () => Navigator.pop(
                ctx,
                const _PhotoChoice(_PhotoMode.food, ImageSource.gallery),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.document_scanner_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Poslikaj prehransko deklaracijo'),
              subtitle: const Text(
                'OCR prebere deklaracijo; Gemini popravi slab rezultat',
              ),
              onTap: () => Navigator.pop(
                ctx,
                const _PhotoChoice(_PhotoMode.label, ImageSource.camera),
              ),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    final picked = await picker.pickImage(source: choice.source);
    if (picked == null || !mounted) return;
    final bool? logged;
    if (choice.mode == _PhotoMode.label) {
      if (!mounted) return;
      logged = await LabelCaptureDialog.show(
        context,
        imageFile: File(picked.path),
        meal: Meal.fromName(_activeMealKey),
        mealKey: _activeMealKey,
        date: widget.date,
      );
    } else {
      if (!mounted) return;
      logged = await GeminiPhotoAnalysisDialog.show(
        context,
        imageFile: File(picked.path),
        meal: Meal.fromName(_activeMealKey),
        mealKey: _activeMealKey,
        date: widget.date,
      );
    }

    if (logged == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _showMealSelector(BuildContext context, List<MealSlot> slots) {
    Haptics.selection();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Meal Slot',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in slots)
                    GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        setState(() => _activeMealKey = m.key);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: _activeMealKey == m.key ? AppColors.primary : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          m.label,
                          style: TextStyle(
                            color: _activeMealKey == m.key ? Colors.white : AppColors.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slots = ref.watch(mealSlotsProvider);
    final matchingSlots = slots.where((s) => s.key == _activeMealKey).toList();
    final slot = matchingSlots.isEmpty ? null : matchingSlots.first;
    final activeMealLabel = slot?.label ?? _activeMealKey;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),

            // ── Header with Meal Dropdown Selector ───────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                InkWell(
                  onTap: () => _showMealSelector(context, slots),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          activeMealLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 48), // Balance spacing
              ],
            ),
            const SizedBox(height: 8),

            // ── Search Input Bar ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _queryCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search for a food, recipe, or meal',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                  prefixIcon: const Icon(Icons.search, size: 22),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.camera_alt_outlined,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        onPressed: _takePhotoAndAnalyze,
                        tooltip: 'Poslikaj hrano z AI',
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner, size: 20),
                        onPressed: _scan,
                        tooltip: 'Skeniraj črtno kodo',
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(
                      color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(
                      color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Category Tabs (All, My Meals, My Recipes, My Foods) ─────────
            TabBar(
              controller: _tabs,
              isScrollable: false,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.secondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(text: 'All'),
                Tab(text: 'My Meals'),
                Tab(text: 'My Recipes'),
                Tab(text: 'My Foods'),
              ],
            ),
            Divider(height: 1, color: AppColors.outlineVariant.withValues(alpha: 0.3)),

            // ── Tab Views ────────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildAllTab(controller),
                  _buildMyMealsTab(controller),
                  _buildMyRecipesTab(controller),
                  _buildMyFoodsTab(controller),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── ALL TAB ───────────────────────────────────────────────────────────────
  Widget _buildAllTab(ScrollController controller) {
    final asyncFoods = ref.watch(foodSearchProvider(_query));
    return asyncFoods.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No matching foods found.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                  ),
                  const SizedBox(height: 16),
                  if ((_query ?? '').trim().isNotEmpty)
                    FilledButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Create custom food'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () async {
                        final food = await CustomFoodFormSheet.show(
                          context,
                          initialName: _query!.trim(),
                        );
                        if (food != null && mounted) _logFood(food);
                      },
                    ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: list.length,
          itemBuilder: (_, i) => _FoodTile(
            food: list[i],
            onTap: () => _logFood(list[i]),
            onQuickAdd: () => _quickLogFood(list[i]),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // ─── MY MEALS TAB ──────────────────────────────────────────────────────────
  Widget _buildMyMealsTab(ScrollController controller) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        // Top Action Cards
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.restaurant_outlined,
                title: 'Create a Meal',
                onTap: () async {
                  final created = await Navigator.push<RecipeData>(
                    context,
                    MaterialPageRoute(builder: (_) => const RecipeBuilderView(isMeal: true)),
                  );
                  if (created != null && mounted) _logRecipe(created);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                icon: Icons.calendar_today_outlined,
                title: 'Copy Previous Meal',
                onTap: () {
                  Haptics.selection();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copying previous meal functionality')),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),

        // Empty state banner matching screenshot
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.rice_bowl_outlined, size: 44, color: AppColors.primary),
              ),
              const SizedBox(height: 20),
              Text(
                'Log Your Go-To Meals Faster.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Create and save your favorite meals to log quickly again and again.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondary,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── MY RECIPES TAB ────────────────────────────────────────────────────────
  Widget _buildMyRecipesTab(ScrollController controller) {
    final async = ref.watch(recipesProvider);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        // Top Action Cards
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.soup_kitchen_outlined,
                title: 'Create a Recipe',
                onTap: () async {
                  final created = await Navigator.push<RecipeData>(
                    context,
                    MaterialPageRoute(builder: (_) => const RecipeBuilderView()),
                  );
                  if (created != null && mounted) _logRecipe(created);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                icon: Icons.menu_book_outlined,
                title: 'Discover Recipes',
                onTap: () {
                  Haptics.selection();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Discover recipes coming soon')),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Section header + Sort filter
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Recipes',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.sort, size: 16),
              label: const Text('Date Created'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.secondary,
                side: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        async.when(
          data: (list) {
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No recipes created yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final r in list)
                  _RecipeTile(
                    recipe: r,
                    onTap: () => _logRecipe(r),
                    onQuickAdd: () => _quickLogRecipe(r),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }

  // ─── MY FOODS TAB ──────────────────────────────────────────────────────────
  Widget _buildMyFoodsTab(ScrollController controller) {
    final asyncFoods = ref.watch(recentFoodsProvider);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.edit_note,
                title: 'Create Custom Food',
                onTap: () async {
                  final food = await CustomFoodFormSheet.show(context);
                  if (food != null && mounted) _logFood(food);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'My Custom Foods',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        asyncFoods.when(
          data: (list) {
            final customs = list.where((f) => f.isCustom).toList();
            if (customs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No custom foods saved yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final f in customs)
                  _FoodTile(
                    food: f,
                    onTap: () => _logFood(f),
                    onQuickAdd: () => _quickLogFood(f),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }
}

enum _PhotoMode { food, label }

class _PhotoChoice {
  final _PhotoMode mode;
  final ImageSource source;
  const _PhotoChoice(this.mode, this.source);
}

// ─── Top Action Card (Matching Screenshots) ──────────────────────────────────
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppColors.primary),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Food List Tile with Circular Quick Add (+) Button ───────────────────────
class _FoodTile extends StatelessWidget {
  final FoodData food;
  final VoidCallback onTap;
  final VoidCallback onQuickAdd;

  const _FoodTile({
    required this.food,
    required this.onTap,
    required this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              if (food.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: food.imageUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => _placeholder(),
                  ),
                )
              else
                _placeholder(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${food.kcalPer100g.toStringAsFixed(0)} cal, ${food.referenceBasis}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Circular Quick Add (+) Button
              GestureDetector(
                onTap: onQuickAdd,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, color: AppColors.primary, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.restaurant, size: 22, color: AppColors.secondary),
      );
}

// ─── Recipe List Tile with Circular Quick Add (+) Button ──────────────────────
class _RecipeTile extends StatelessWidget {
  final RecipeData recipe;
  final VoidCallback onTap;
  final VoidCallback onQuickAdd;

  const _RecipeTile({
    required this.recipe,
    required this.onTap,
    required this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.menu_book, size: 22, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${recipe.servings} serving${recipe.servings == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Circular Quick Add (+) Button
              GestureDetector(
                onTap: onQuickAdd,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, color: AppColors.primary, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
