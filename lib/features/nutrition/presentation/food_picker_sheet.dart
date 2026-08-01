import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../domain/barcode_utils.dart';
import '../domain/meal.dart';
import 'barcode_scanner_view.dart';
import 'custom_food_form_sheet.dart';
import 'gemini_photo_analysis_dialog.dart';
import 'label_capture_dialog.dart';
import 'log_entry_sheet.dart';
import 'nutrition_providers.dart';
import 'meal_slots_provider.dart';
import 'recipe_builder_view.dart';

/// Tabbed bottom sheet: Search · Scan · Recent · Recipes · Custom.
/// Returns true if anything was logged.
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
      initialMealKey: widget.mealKey,
    );
    if (logged == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _logRecipe(RecipeData r) async {
    final logged = await LogEntrySheet.forRecipe(
      context,
      recipe: r,
      date: widget.date,
      initialMealKey: widget.mealKey,
    );
    if (logged == true && mounted) Navigator.of(context).pop(true);
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
        meal: Meal.fromName(widget.mealKey),
        mealKey: widget.mealKey,
        date: widget.date,
      );
    } else {
      if (!mounted) return;
      logged = await GeminiPhotoAnalysisDialog.show(
        context,
        imageFile: File(picked.path),
        meal: Meal.fromName(widget.mealKey),
        mealKey: widget.mealKey,
        date: widget.date,
      );
    }

    if (logged == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slots = ref.watch(mealSlotsProvider);
    final matchingSlots = slots.where((s) => s.key == widget.mealKey).toList();
    final slot = matchingSlots.isEmpty ? null : matchingSlots.first;
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
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
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Add to ${slot?.label ?? widget.mealKey}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              isScrollable: false,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.onSurfaceVariant,
              indicatorColor: AppColors.primary,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Search'),
                Tab(text: 'Recent'),
                Tab(text: 'Recipes'),
                Tab(text: 'Custom'),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildSearchTab(controller),
                  _buildRecentTab(controller),
                  _buildRecipesTab(controller),
                  _buildCustomTab(controller),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTab(ScrollController controller) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _queryCtrl,
            onChanged: (v) => setState(() => _query = v),
            onSubmitted: (_) {},
            decoration: InputDecoration(
              hintText: 'Search foods…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.camera_alt,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    onPressed: _takePhotoAndAnalyze,
                    tooltip: 'Slikaj hrano z Gemini AI',
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    onPressed: _scan,
                    tooltip: 'Scan barcode',
                  ),
                ],
              ),
              filled: true,
              fillColor: AppColors.surfaceContainer,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),
        Expanded(child: _localResultsList(controller)),
      ],
    );
  }

  Widget _localResultsList(ScrollController controller) {
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
                    'No matches in your library yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  if ((_query ?? '').trim().isNotEmpty)
                    FilledButton.icon(
                      icon: const Icon(Icons.edit_note, size: 18),
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: list.length,
          itemBuilder: (_, i) =>
              _FoodTile(food: list[i], onTap: () => _logFood(list[i])),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildRecentTab(ScrollController controller) {
    final async = ref.watch(recentFoodsProvider);
    return async.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text(
              'Nothing logged in the last 30 days.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        return ListView.builder(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: list.length,
          itemBuilder: (_, i) =>
              _FoodTile(food: list[i], onTap: () => _logFood(list[i])),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildRecipesTab(ScrollController controller) {
    final async = ref.watch(recipesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New recipe'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final created = await Navigator.push<RecipeData>(
                  context,
                  MaterialPageRoute(builder: (_) => const RecipeBuilderView()),
                );
                if (created != null && mounted) _logRecipe(created);
              },
            ),
          ),
        ),
        Expanded(
          child: async.when(
            data: (list) {
              if (list.isEmpty) {
                return Center(
                  child: Text(
                    'No recipes yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }
              return ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: list.length,
                itemBuilder: (_, i) => _RecipeTile(
                  recipe: list[i],
                  onTap: () => _logRecipe(list[i]),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomTab(ScrollController controller) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note, size: 56, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              'Create a one-off food with its own macros.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New custom food'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
              onPressed: () async {
                final food = await CustomFoodFormSheet.show(context);
                if (food != null && mounted) _logFood(food);
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum _PhotoMode { food, label }

class _PhotoChoice {
  final _PhotoMode mode;
  final ImageSource source;
  const _PhotoChoice(this.mode, this.source);
}

class _FoodTile extends StatelessWidget {
  final FoodData food;
  final VoidCallback onTap;
  const _FoodTile({required this.food, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.4),
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
                      [
                        if (food.brand != null) food.brand!,
                        '${food.kcalPer100g.toStringAsFixed(0)} kcal/100g',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 18),
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
    child: Icon(Icons.fastfood, size: 22, color: AppColors.secondary),
  );
}

class _RecipeTile extends StatelessWidget {
  final RecipeData recipe;
  final VoidCallback onTap;
  const _RecipeTile({required this.recipe, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.restaurant_menu,
                  size: 22,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${recipe.servings} servings',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
