import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../widgets/premium_button.dart';
import '../domain/daily_totals.dart';
import '../domain/food_insights.dart';
import '../domain/meal_slots.dart';
import 'meal_slots_provider.dart';
import 'nutrient_settings_provider.dart';
import 'nutrition_providers.dart';

/// Final step before logging/editing: choose grams (food) or servings (recipe), pick meal, or delete.
class LogEntrySheet extends ConsumerStatefulWidget {
  final FoodEntryData? existingEntry;
  final FoodData? food;
  final RecipeData? recipe;
  final DateTime date;
  final String initialMealKey;
  final ScrollController? scrollController;

  const LogEntrySheet._({
    this.existingEntry,
    this.food,
    this.recipe,
    required this.date,
    required this.initialMealKey,
    this.scrollController,
  });

  static Future<bool?> forFood(
    BuildContext context, {
    required FoodData food,
    required DateTime date,
    required String initialMealKey,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogEntrySheetShell(
        builder: (_, scrollController) => LogEntrySheet._(
          food: food,
          date: date,
          initialMealKey: initialMealKey,
          scrollController: scrollController,
        ),
      ),
    );
  }

  static Future<bool?> forRecipe(
    BuildContext context, {
    required RecipeData recipe,
    required DateTime date,
    required String initialMealKey,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogEntrySheetShell(
        builder: (_, scrollController) => LogEntrySheet._(
          recipe: recipe,
          date: date,
          initialMealKey: initialMealKey,
          scrollController: scrollController,
        ),
      ),
    );
  }

  static Future<bool?> forEntry(
    BuildContext context, {
    required FoodEntryData entry,
    FoodData? food,
    RecipeData? recipe,
    required DateTime date,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogEntrySheetShell(
        builder: (_, scrollController) => LogEntrySheet._(
          existingEntry: entry,
          food: food,
          recipe: recipe,
          date: date,
          initialMealKey: entry.meal,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  ConsumerState<LogEntrySheet> createState() => _LogEntrySheetState();
}

// ─── Units supported for food logging ───────────────────────────────────────
const _kFoodUnits = ['g', 'ml', 'oz', 'tsp', 'tbsp', 'cup'];
const Map<String, double> _kUnitToGrams = {
  'g': 1.0,
  'ml': 1.0,
  'oz': 28.3495,
  'tsp': 4.92892,
  'tbsp': 14.7868,
  'cup': 236.588,
};

class _LogEntrySheetState extends ConsumerState<LogEntrySheet> {
  late String _mealKey = widget.initialMealKey;
  late final TextEditingController _quantity;
  late String _selectedUnit;

  /// How many of [_quantity] portions were eaten.
  double _servings = 1;

  /// Time of day, when the timestamp field is enabled in settings.
  TimeOfDay? _time;

  /// Extra days this entry should also be copied to ("Add to multiple days").
  final Set<DateTime> _extraDays = {};

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.existingEntry;
    if (entry != null) {
      final amount = entry.portionAmount ?? entry.gramsOverride ?? entry.servings;
      _quantity = TextEditingController(
        text: amount % 1 == 0 ? amount.toStringAsFixed(0) : amount.toStringAsFixed(1),
      );
      final savedUnit = entry.portionUnit ?? _defaultUnit;
      _selectedUnit = _kFoodUnits.contains(savedUnit) ? savedUnit : _defaultUnit;
      _time = TimeOfDay.fromDateTime(entry.loggedAt);
    } else {
      _quantity = TextEditingController(
        text: widget.food != null
            ? (widget.food!.servingAmount ?? widget.food!.servingGrams ?? 100)
                .toStringAsFixed(0)
            : '1',
      );
      _selectedUnit = _defaultUnit;
    }
    _quantity.addListener(() => setState(() {}));
  }

  /// Portion size × servings, in the selected unit.
  double get _totalAmount {
    final portion = double.tryParse(_quantity.text.trim()) ?? 0;
    return portion * _servings;
  }

  /// Default unit derived from the food's reference basis.
  String get _defaultUnit {
    if (widget.recipe != null) return 'servings';
    final food = widget.food;
    if (food == null) return 'g';
    final basis = food.referenceBasis.toLowerCase();
    if (basis.contains('100 ml')) return 'ml';
    return 'g';
  }

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final total = _totalAmount;
    if (total <= 0) return;
    Haptics.success();
    setState(() => _saving = true);
    final repo = ref.read(nutritionRepositoryProvider);
    final isFood = widget.food != null || (widget.existingEntry != null && widget.existingEntry!.foodId != null);

    double? grams;
    if (isFood && _selectedUnit != 'servings') {
      final factor = _kUnitToGrams[_selectedUnit] ?? 1.0;
      grams = total * factor;
    }

    if (widget.existingEntry != null) {
      final unit = isFood ? _selectedUnit : 'servings';
      await repo.updateEntry(
        id: widget.existingEntry!.id,
        mealKey: _mealKey,
        servings: isFood ? 1 : total,
        gramsOverride: grams ?? (unit == 'g' ? total : null),
        portionAmount: total,
        portionUnit: unit,
        loggedAt: _loggedAtOn(widget.date),
      );
    } else {
      for (final date in {widget.date, ..._extraDays}) {
        if (widget.food != null) {
          await repo.logFood(
            date: date,
            mealKey: _mealKey,
            foodId: widget.food!.id,
            grams: grams ?? (_selectedUnit == 'g' ? total : null),
            portionAmount: total,
            portionUnit: _selectedUnit,
            loggedAt: _loggedAtOn(date),
          );
        } else if (widget.recipe != null) {
          await repo.logRecipe(
            date: date,
            mealKey: _mealKey,
            recipeId: widget.recipe!.id,
            servings: total,
            loggedAt: _loggedAtOn(date),
          );
        }
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  DateTime? _loggedAtOn(DateTime date) {
    final t = _time;
    if (t == null) return null;
    return DateTime(date.year, date.month, date.day, t.hour, t.minute);
  }

  Future<void> _delete() async {
    if (widget.existingEntry == null) return;
    Haptics.heavy();
    setState(() => _saving = true);
    final repo = ref.read(nutritionRepositoryProvider);
    await repo.deleteEntry(widget.existingEntry!.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _showMealPicker(BuildContext context, List<MealSlot> mealSlots) {
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
                'Select Meal',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in mealSlots)
                    GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        setState(() => _mealKey = m.key);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: _mealKey == m.key ? AppColors.primary : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          m.label,
                          style: TextStyle(
                            color: _mealKey == m.key ? Colors.white : AppColors.onSurface,
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

  void _showServingsPicker(BuildContext context) {
    Haptics.selection();
    final ctrl = TextEditingController(text: _fmtAmount(_servings));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Number of Servings',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.remove),
                        onPressed: _servings <= 0.5
                            ? null
                            : () {
                                Haptics.selection();
                                setState(() => _servings = (_servings - 0.5).clamp(0.5, 999.0));
                                ctrl.text = _fmtAmount(_servings);
                                setModalState(() {});
                              },
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: ctrl,
                          autofocus: true,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: AppColors.surfaceVariant,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: AppColors.outlineVariant),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: AppColors.outlineVariant),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                          ),
                          onChanged: (val) {
                            final parsed = double.tryParse(val.trim());
                            if (parsed != null && parsed > 0) {
                              setState(() => _servings = parsed);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          Haptics.selection();
                          setState(() => _servings = _servings + 0.5);
                          ctrl.text = _fmtAmount(_servings);
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showServingSizePicker(BuildContext context, bool isFood, List<String> availableUnits) {
    Haptics.selection();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Serving Size & Unit',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _quantity,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                    decoration: InputDecoration(
                      suffixText: isFood ? _selectedUnit : 'servings',
                      suffixStyle: TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
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
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  if (isFood) ...[
                    const SizedBox(height: 16),
                    Text('Unit', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.secondary)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final u in availableUnits)
                          GestureDetector(
                            onTap: () {
                              Haptics.selection();
                              setState(() => _selectedUnit = u);
                              setModalState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: _selectedUnit == u ? AppColors.primary : AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                u,
                                style: TextStyle(
                                  color: _selectedUnit == u ? Colors.white : AppColors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mealSlots = ref.watch(mealSlotsProvider);
    final isFood = widget.food != null || (widget.existingEntry != null && widget.existingEntry!.foodId != null);
    final isEditing = widget.existingEntry != null;
    final title = widget.food?.name ?? widget.recipe?.name ?? 'Logged Item';
    final subtitle = isFood
        ? (widget.food != null
            ? '${widget.food!.kcalPer100g.toStringAsFixed(0)} kcal / ${widget.food!.referenceBasis}'
            : 'Food item entry')
        : (widget.recipe != null
            ? '${widget.recipe!.servings} servings per recipe'
            : 'Recipe entry');
    final availableUnits = isFood ? _kFoodUnits : const ['servings'];
    final timestampEnabled = ref.watch(logTimestampEnabledProvider);

    final currentMealLabel = mealSlots
        .firstWhere((m) => m.key == _mealKey, orElse: () => MealSlot(key: _mealKey, label: _mealKey))
        .label;

    final food = widget.food;
    final insights = food == null
        ? const <FoodInsight>[]
        : FoodInsights.forPer100g(
            kcal: food.kcalPer100g,
            proteinG: food.proteinPer100g,
            carbsG: food.carbsPer100g,
            fatG: food.fatPer100g,
            fiberG: food.fiberPer100g,
            sodiumMg: food.sodiumMgPer100g,
          );

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      shrinkWrap: true,
      children: [
        // ── Top Sheet Drag Handle ────────────────────────────────────────────
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ── Top Header Bar (Close, Title, Save Checkmark) ────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Cancel',
            ),
            Text(
              isEditing ? 'Edit Food' : 'Add Food',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.check, color: AppColors.primary, size: 26),
              onPressed: _saving ? null : _save,
              tooltip: 'Save',
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Food Title & Subtitle ───────────────────────────────────────────
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ],
        ),

        // ── Composition Badges ──────────────────────────────────────────────
        if (insights.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final i in insights) _InsightBadge(insight: i)],
          ),
        ],
        const SizedBox(height: 16),

        // ── Grouped Settings Card (Meal, Servings, Serving Size, Time) ──────
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              _SettingsRow(
                label: 'Meal',
                value: currentMealLabel,
                onTap: () => _showMealPicker(context, mealSlots),
              ),
              _SettingsRow(
                label: 'Number of Servings',
                value: _fmtAmount(_servings),
                onTap: () => _showServingsPicker(context),
              ),
              _SettingsRow(
                label: 'Serving Size',
                value: '${_quantity.text.isEmpty ? '0' : _quantity.text} ${isFood ? _selectedUnit : 'servings'}',
                onTap: () => _showServingSizePicker(context, isFood, availableUnits),
              ),
              if (timestampEnabled)
                _SettingsRow(
                  label: 'Time',
                  value: _time == null ? 'Set time' : _time!.format(context),
                  showDivider: false,
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _time ?? TimeOfDay.now(),
                    );
                    if (picked != null) setState(() => _time = picked);
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Add to Multiple Days ─────────────────────────────────────────────
        if (!isEditing) ...[
          _MultiDayPicker(
            baseDate: widget.date,
            selected: _extraDays,
            onToggle: (day) {
              Haptics.selection();
              setState(() {
                if (!_extraDays.remove(day)) _extraDays.add(day);
              });
            },
          ),
          const SizedBox(height: 20),
        ],

        // ── Nutrition Breakdown & Goals Preview ──────────────────────────────
        _NutritionPreview(
          food: widget.food,
          recipe: widget.recipe,
          amount: _totalAmount,
          unit: isFood ? _selectedUnit : 'servings',
          date: widget.date,
        ),
        const SizedBox(height: 24),

        // ── Primary Action Button ────────────────────────────────────────────
        PremiumButton(
          text: _saving
              ? 'Saving…'
              : isEditing
                  ? 'Update Entry'
                  : _extraDays.isEmpty
                      ? 'Log Food'
                      : 'Log to ${_extraDays.length + 1} Days',
          onTap: _saving ? () {} : _save,
        ),

        if (isEditing) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
              label: const Text('Delete from log', style: TextStyle(color: Colors.redAccent)),
            ),
          ),
        ],
      ],
    );
  }
}

String _fmtAmount(double v) =>
    v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

// ─── Settings Row ───────────────────────────────────────────────────────────
class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool showDivider;

  const _SettingsRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.primary.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
            color: AppColors.outlineVariant.withValues(alpha: 0.3),
          ),
      ],
    );
  }
}

// ─── Composition badge ───────────────────────────────────────────────────────
class _InsightBadge extends StatelessWidget {
  final FoodInsight insight;
  const _InsightBadge({required this.insight});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (insight.tone) {
      InsightTone.positive => (const Color(0xFF30D158), Icons.check_circle),
      InsightTone.caution => (Colors.orangeAccent, Icons.info_outline),
      InsightTone.neutral => (AppColors.secondary, Icons.circle_outlined),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            insight.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add to Multiple Days Picker ─────────────────────────────────────────────
class _MultiDayPicker extends StatelessWidget {
  final DateTime baseDate;
  final Set<DateTime> selected;
  final ValueChanged<DateTime> onToggle;

  const _MultiDayPicker({
    required this.baseDate,
    required this.selected,
    required this.onToggle,
  });

  List<DateTime> get _candidates {
    final cleanBase = DateUtils.dateOnly(baseDate);
    final weekday = cleanBase.weekday;
    final DateTime startMonday;
    if (weekday >= 5) {
      startMonday = DateUtils.addDaysToDate(cleanBase, 8 - weekday);
    } else {
      startMonday = DateUtils.addDaysToDate(cleanBase, -(weekday - 1));
    }
    return [
      for (var i = 0; i < 7; i++) DateUtils.addDaysToDate(startMonday, i),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleanBase = DateUtils.dateOnly(baseDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add to Multiple Days',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.secondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final day in _candidates) ...[
              _buildDayChip(day, isBase: DateUtils.isSameDay(day, cleanBase), isSelected: selected.contains(day)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildDayChip(DateTime day, {required bool isBase, required bool isSelected}) {
    final dayName = DateFormat('EEE').format(day);
    final dayNum = DateFormat('d').format(day);
    final active = isBase || isSelected;

    return GestureDetector(
      onTap: isBase ? null : () => onToggle(day),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dayName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: active ? AppColors.primary : AppColors.secondary,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? AppColors.primary : AppColors.surfaceContainer,
              border: Border.all(
                color: active ? AppColors.primary : AppColors.outlineVariant.withValues(alpha: 0.5),
                width: active ? 1.5 : 1,
              ),
            ),
            child: Center(
              child: Text(
                dayNum,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.white : AppColors.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Live Nutrition Preview & Donut Breakdown ────────────────────────────────
class _NutritionPreview extends ConsumerStatefulWidget {
  final FoodData? food;
  final RecipeData? recipe;
  final double amount;
  final String unit;
  final DateTime date;

  const _NutritionPreview({
    required this.food,
    required this.recipe,
    required this.amount,
    required this.unit,
    required this.date,
  });

  @override
  ConsumerState<_NutritionPreview> createState() => _NutritionPreviewState();
}

class _NutritionPreviewState extends ConsumerState<_NutritionPreview> {
  bool _showMicros = false;
  Future<DailyTotals>? _future;
  String? _futureKey;

  Future<DailyTotals> _cachedResolve() {
    final key = '${widget.food?.id}|${widget.recipe?.id}|${widget.amount}|${widget.unit}';
    if (_futureKey != key || _future == null) {
      _futureKey = key;
      _future = _resolve();
    }
    return _future!;
  }

  Future<DailyTotals> _resolve() async {
    final repo = ref.read(nutritionRepositoryProvider);
    if (widget.amount <= 0) return DailyTotals.empty;

    final draft = FoodEntryData(
      id: -1,
      dateIso: DateFormat('yyyy-MM-dd').format(widget.date),
      meal: 'preview',
      foodId: widget.food?.id,
      recipeId: widget.recipe?.id,
      servings: widget.recipe != null ? widget.amount : 1,
      gramsOverride: widget.unit == 'g' ? widget.amount : null,
      portionAmount: widget.food != null ? widget.amount : null,
      portionUnit: widget.food != null ? widget.unit : null,
      loggedAt: widget.date,
    );
    return repo.macrosForEntry(draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targets = ref.watch(effectiveTargetsProvider(widget.date)).asData?.value ??
        ref.watch(baselineTargetsProvider);

    return FutureBuilder<DailyTotals>(
      future: _cachedResolve(),
      builder: (context, snap) {
        final t = snap.data;
        if (t == null || t.kcal <= 0) {
          return const SizedBox.shrink();
        }
        final split = MacroSplit.fromGrams(
          proteinG: t.proteinG,
          carbsG: t.carbsG,
          fatG: t.fatG,
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
              // ── Macro Donut Ring + 3 Macro Columns ────────────────────────
              Row(
                children: [
                  SizedBox(
                    width: 86,
                    height: 86,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(86, 86),
                          painter: _MacroDonutPainter(
                            proteinG: t.proteinG,
                            carbsG: t.carbsG,
                            fatG: t.fatG,
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
                              '${t.kcal.round()}',
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
                          grams: t.carbsG,
                          label: 'Net Carbs',
                          color: AppColors.macroCarbs,
                        ),
                        _macroColumn(
                          theme,
                          share: split.fatShare,
                          grams: t.fatG,
                          label: 'Fat',
                          color: AppColors.macroFat,
                        ),
                        _macroColumn(
                          theme,
                          share: split.proteinShare,
                          grams: t.proteinG,
                          label: 'Protein',
                          color: AppColors.macroProtein,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Percent of Your Daily Goals Header & Bars ─────────────────
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
                      value: t.kcal,
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
                      value: t.carbsG,
                      target: targets?.carbsG.toDouble(),
                      color: AppColors.macroCarbs,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _goalBarCell(
                      theme,
                      label: 'Fat',
                      value: t.fatG,
                      target: targets?.fatG.toDouble(),
                      color: AppColors.macroFat,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _goalBarCell(
                      theme,
                      label: 'Protein',
                      value: t.proteinG,
                      target: targets?.proteinG.toDouble(),
                      color: AppColors.macroProtein,
                    ),
                  ),
                ],
              ),

              // ── Optional Micronutrients Accordion ─────────────────────────
              if (t.hasMicros) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => setState(() => _showMicros = !_showMicros),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'More nutrients',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _showMicros ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Icons.expand_more, size: 18, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topLeft,
                  child: !_showMicros ? const SizedBox.shrink() : _microsList(theme, t),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _macroColumn(
    ThemeData theme, {
    required double share,
    required double grams,
    required String label,
    required Color color,
  }) {
    final pct = (share * 100).round();
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
          '${_fmtAmount(grams)}g',
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
    final pct = (target != null && target > 0) ? (value / target).clamp(0.0, 1.0) : 0.0;
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
                      ? NumberFormat('#,###').format(target.round())
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

  Widget _microsList(ThemeData theme, DailyTotals t) {
    final rows = <(String, String)>[
      if (t.fiberG > 0) ('Fibre', '${t.fiberG.toStringAsFixed(1)} g'),
      if (t.sodiumMg > 0) ('Sodium', '${t.sodiumMg.round()} mg'),
      if (t.potassiumMg > 0) ('Potassium', '${t.potassiumMg.round()} mg'),
      if (t.cholesterolMg > 0) ('Cholesterol', '${t.cholesterolMg.round()} mg'),
      for (final e in t.micros.entries)
        if (e.value > 0) (e.key, e.value.toStringAsFixed(1)),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          for (final (name, val) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(name, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
                  Text(val, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Custom Painter for Macro Donut Ring ──────────────────────────────────────
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
      oldDelegate.fatG != fatG ||
      oldDelegate.proteinColor != proteinColor ||
      oldDelegate.carbsColor != carbsColor ||
      oldDelegate.fatColor != fatColor;
}

// ─── Shell for DraggableScrollableSheet ──────────────────────────────────────
class _LogEntrySheetShell extends StatelessWidget {
  final Widget Function(BuildContext, ScrollController) builder;
  const _LogEntrySheetShell({required this.builder});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: builder(context, scrollController),
      ),
    );
  }
}
