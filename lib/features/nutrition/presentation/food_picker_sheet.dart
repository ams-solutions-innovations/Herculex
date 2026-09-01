import 'dart:io';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../../../services/pending_ai_scan_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../theme/tokens/hx_colors.dart';
import '../../fasting/presentation/fasting_food_log_dialog.dart';
import '../domain/barcode_utils.dart';
import '../domain/meal.dart';
import '../domain/meal_slots.dart';
import 'barcode_resolution_flow.dart';
import 'barcode_scanner_view.dart';
import 'custom_food_form_sheet.dart';
import 'gemini_photo_analysis_dialog.dart';
import 'label_capture_dialog.dart';
import 'log_entry_sheet.dart';
import 'meal_slots_provider.dart';
import 'nutrition_providers.dart';
import 'rambler_food_dialog.dart';
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
    await LogEntrySheet.forFood(
      context,
      food: f,
      date: widget.date,
      initialMealKey: _activeMealKey,
    );
  }

  Future<void> _quickLogFood(FoodData f) async {
    final proceed = await confirmEndFastOnFoodLog(context, ref);
    if (!proceed || !mounted) return;

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
  }

  Future<void> _logRecipe(RecipeData r) async {
    await LogEntrySheet.forRecipe(
      context,
      recipe: r,
      date: widget.date,
      initialMealKey: _activeMealKey,
    );
  }

  Future<void> _quickLogRecipe(RecipeData r) async {
    final proceed = await confirmEndFastOnFoodLog(context, ref);
    if (!proceed || !mounted) return;

    Haptics.success();
    final repo = ref.read(nutritionRepositoryProvider);
    await repo.logRecipe(
      date: widget.date,
      mealKey: _activeMealKey,
      recipeId: r.id,
      servings: 1.0,
    );
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
      final created = await resolveUnknownBarcode(context, ref, code);
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
              title: const Text('Take a photo of food with camera'),
              subtitle: const Text(
                'Gemini AI will estimate composition and nutritional values',
              ),
              onTap: () => Navigator.pop(
                ctx,
                const _PhotoChoice(_PhotoMode.food, ImageSource.camera),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose photo from gallery'),
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
              title: const Text('Take a photo of nutrition label'),
              subtitle: const Text(
                'OCR reads the label; Gemini resolves low-confidence scans',
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

    await ref
        .read(pendingAiScanServiceProvider)
        .setPendingContext(
          PendingAiScanContext(
            type: choice.mode == _PhotoMode.label
                ? AiScanContextType.nutritionLabel
                : AiScanContextType.food,
            mealKey: _activeMealKey,
            dateIso: widget.date.toIso8601String(),
          ),
        );

    final picked = await picker.pickImage(
      source: choice.source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    await ref.read(pendingAiScanServiceProvider).clearPendingContext();
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

  Future<void> _openRambler() async {
    final logged = await RamblerFoodDialog.show(
      context,
      date: widget.date,
      initialMealKey: _activeMealKey,
    );
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
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _activeMealKey == m.key
                              ? AppColors.primary
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          m.label,
                          style: TextStyle(
                            color: _activeMealKey == m.key
                                ? Colors.white
                                : AppColors.onSurface,
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
      builder: (_, controller) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
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

              // ── Quick Action Cards: Rambler AI & Skeniraj kodo ─────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.mic_rounded,
                        title: 'Rambler',
                        subtitle: 'Voice & Text AI',
                        color: const Color(0xFF64B5F6),
                        onTap: _openRambler,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.qr_code_scanner_rounded,
                        title: 'Skeniraj kodo',
                        subtitle: 'Črtna koda & kamera',
                        color: AppColors.primary,
                        onTap: _scan,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Category Tabs (All, My Meals, My Recipes, My Foods) ─────────
              TabBar(
                controller: _tabs,
                isScrollable: false,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.secondary,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2.5,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'My Meals'),
                  Tab(text: 'My Recipes'),
                  Tab(text: 'My Foods'),
                ],
              ),
              Divider(
                height: 1,
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
              ),

              // ── Tab Views + Floating Search Bar ────────────────────────────
              Expanded(
                child: Stack(
                  children: [
                    TabBarView(
                      controller: _tabs,
                      children: [
                        _buildAllTab(controller),
                        _buildMyMealsTab(controller),
                        _buildMyRecipesTab(controller),
                        _buildMyFoodsTab(controller),
                      ],
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: math.max(
                        24.0,
                        MediaQuery.paddingOf(context).bottom + 14.0,
                      ),
                      child: _buildFloatingSearchBar(theme),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingSearchBar(ThemeData theme) {
    final hx = context.hx;
    final isDark = hx.isDark;
    final hasQuery = _queryCtrl.text.isNotEmpty;

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
        controller: _queryCtrl,
        onChanged: (v) => setState(() => _query = v),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: hx.onSurface,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search for a food, recipe, or meal',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: hx.secondary.withValues(alpha: 0.85),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 22,
            color: hx.primary,
          ),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasQuery)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 20,
                    color: hx.secondary,
                  ),
                  onPressed: () {
                    _queryCtrl.clear();
                    setState(() => _query = null);
                  },
                  tooltip: 'Clear',
                ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: hx.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.camera_alt_outlined,
                      size: 18,
                      color: hx.primary,
                    ),
                  ),
                  onPressed: _takePhotoAndAnalyze,
                  tooltip: 'Photo food with AI',
                ),
              ),
            ],
          ),
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

  // ─── ALL TAB ───────────────────────────────────────────────────────────────
  Widget _buildAllTab(ScrollController controller) {
    final queryText = (_query ?? '').trim();

    // 1. If searching, show standard search results from catalogue
    if (queryText.isNotEmpty) {
      final asyncFoods = ref.watch(foodSearchProvider(queryText));
      final currentHour = ref.watch(clockProvider).now().hour;
      final asyncSuggested = ref.watch(
        suggestedFoodsProvider(
          FoodSuggestionParams(hour: currentHour, mealKey: _activeMealKey),
        ),
      );
      final asyncRecent = ref.watch(recentlyLoggedFoodsProvider);

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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                          initialName: queryText,
                        );
                        if (food != null && mounted) _logFood(food);
                      },
                    ),
                  ],
                ),
              ),
            );
          }

          final suggestedIds =
              asyncSuggested.valueOrNull?.map((e) => e.id).toSet() ?? {};
          final recentList = asyncRecent.valueOrNull ?? [];
          final recentIds = recentList.map((e) => e.id).toList();

          final sortedList = List<FoodData>.from(list);
          sortedList.sort((a, b) {
            final aSuggested = suggestedIds.contains(a.id);
            final bSuggested = suggestedIds.contains(b.id);
            if (aSuggested && !bSuggested) return -1;
            if (!aSuggested && bSuggested) return 1;

            final aRecentIdx = recentIds.indexOf(a.id);
            final bRecentIdx = recentIds.indexOf(b.id);
            final aIsRecent = aRecentIdx != -1;
            final bIsRecent = bRecentIdx != -1;

            if (aIsRecent && !bIsRecent) return -1;
            if (!aIsRecent && bIsRecent) return 1;
            if (aIsRecent && bIsRecent) return aRecentIdx.compareTo(bRecentIdx);

            return 0;
          });

          return ListView.builder(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            itemCount: sortedList.length,
            itemBuilder: (_, i) => _FoodTile(
              food: sortedList[i],
              onTap: () => _logFood(sortedList[i]),
              onQuickAdd: () => _quickLogFood(sortedList[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      );
    }

    // 2. Default state: Suggested (time/meal-based) + Recent (chronological newest to oldest) + Fallback (All foods)
    final currentHour = ref.watch(clockProvider).now().hour;
    final asyncSuggested = ref.watch(
      suggestedFoodsProvider(
        FoodSuggestionParams(hour: currentHour, mealKey: _activeMealKey),
      ),
    );
    final asyncRecent = ref.watch(recentlyLoggedFoodsProvider);
    final asyncAll = ref.watch(foodSearchProvider(null));

    // Show loading while primary data streams initialize
    if (asyncRecent.isLoading &&
        !asyncRecent.hasValue &&
        asyncSuggested.isLoading &&
        !asyncSuggested.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final suggestedFoods = asyncSuggested.valueOrNull ?? const <FoodData>[];
    final recentFoods = asyncRecent.valueOrNull ?? const <FoodData>[];
    final allFoods = asyncAll.valueOrNull ?? const <FoodData>[];

    final slots = ref.watch(mealSlotsProvider);
    final activeSlot = slots.firstWhereOrNull((s) => s.key == _activeMealKey);
    final mealLabel = activeSlot?.label ?? _activeMealKey;

    // If user has never logged any foods yet, fallback to all foods catalogue
    if (suggestedFoods.isEmpty && recentFoods.isEmpty) {
      if (allFoods.isEmpty) {
        if (asyncAll.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No foods in catalogue.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create custom food'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
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

      return ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
        children: [
          _buildSectionHeader(
            icon: Icons.restaurant_menu,
            title: 'All Foods',
            subtitle: 'Catalogue',
            iconColor: AppColors.primary,
          ),
          for (final food in allFoods)
            _FoodTile(
              food: food,
              onTap: () => _logFood(food),
              onQuickAdd: () => _quickLogFood(food),
            ),
        ],
      );
    }

    final suggestedIds = suggestedFoods.map((f) => f.id).toSet();
    final remainingRecent = recentFoods
        .where((f) => !suggestedIds.contains(f.id))
        .toList();

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
      children: [
        // ── Suggested Section ──
        if (suggestedFoods.isNotEmpty) ...[
          _buildSectionHeader(
            icon: Icons.auto_awesome,
            title: 'Suggested',
            subtitle: 'for $mealLabel',
            iconColor: AppColors.primary,
          ),
          for (final food in suggestedFoods)
            _FoodTile(
              food: food,
              onTap: () => _logFood(food),
              onQuickAdd: () => _quickLogFood(food),
            ),
          const SizedBox(height: 8),
        ],

        // ── Recent Section (Most recent to oldest) ──
        if (remainingRecent.isNotEmpty) ...[
          _buildSectionHeader(
            icon: Icons.history,
            title: 'Recent',
            subtitle: 'Most recent first',
            iconColor: AppColors.secondary,
          ),
          for (final food in remainingRecent)
            _FoodTile(
              food: food,
              onTap: () => _logFood(food),
              onQuickAdd: () => _quickLogFood(food),
            ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor ?? AppColors.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── MY MEALS TAB ──────────────────────────────────────────────────────────
  Widget _buildMyMealsTab(ScrollController controller) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
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
                    MaterialPageRoute(
                      builder: (_) => const RecipeBuilderView(isMeal: true),
                    ),
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
                    const SnackBar(
                      content: Text('Copying previous meal functionality'),
                    ),
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
              Image.asset(
                'assets/images/my_meals_empty.png',
                width: 200,
                height: 140,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 20),
              Text(
                'Log Your Go-To Meals Faster.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Create and save your favorite meals to log quickly again and again.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
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
                    MaterialPageRoute(
                      builder: (_) => const RecipeBuilderView(),
                    ),
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
                    const SnackBar(
                      content: Text('Discover recipes coming soon'),
                    ),
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.sort, size: 16),
              label: const Text('Date Created'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.secondary,
                side: BorderSide(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                ),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.secondary,
                    ),
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
    final asyncFoods = ref.watch(customFoodsProvider(null));
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
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
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        asyncFoods.when(
          data: (customs) {
            if (customs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No custom foods saved yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.secondary,
                    ),
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
              // Animated Quick Add (+) Button
              _QuickAddButton(onTap: onQuickAdd),
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
                child: Icon(
                  Icons.menu_book,
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
              // Animated Quick Add (+) Button
              _QuickAddButton(onTap: onQuickAdd),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Interactive Quick Add (+) Animated Feedback Button ──────────────────────
class _QuickAddButton extends StatefulWidget {
  final VoidCallback onTap;

  const _QuickAddButton({required this.onTap});

  @override
  State<_QuickAddButton> createState() => _QuickAddButtonState();
}

class _QuickAddButtonState extends State<_QuickAddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.75,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.75,
          end: 1.25,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.25,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
    ]).animate(_animCtrl);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
    setState(() => _isSuccess = true);
    _animCtrl.forward(from: 0.0);

    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) {
        setState(() => _isSuccess = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) =>
            Transform.scale(scale: _scaleAnim.value, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _isSuccess
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            boxShadow: _isSuccess
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.45),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: _isSuccess
                ? const Icon(
                    Icons.check_rounded,
                    key: ValueKey('check'),
                    color: Colors.white,
                    size: 20,
                  )
                : Icon(
                    Icons.add_rounded,
                    key: const ValueKey('add'),
                    color: AppColors.primary,
                    size: 20,
                  ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
