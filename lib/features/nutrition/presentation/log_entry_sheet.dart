import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../widgets/premium_button.dart';
import 'package:intl/intl.dart';

import '../domain/daily_totals.dart';
import '../domain/food_insights.dart';
import 'nutrition_providers.dart';
import 'meal_slots_provider.dart';
import 'nutrient_settings_provider.dart';

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
// Conversion factors to grams (approximate, used for calorie estimation preview).
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

  /// How many of [_quantity] portions were eaten. Kept separate from the
  /// portion size so "3 × 30 g" reads the way the user thinks about it.
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
      // Restore the unit that was previously saved.
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

    // Convert to grams for storage when a non-gram unit is chosen.
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
      // A new entry lands on the diary's date plus any extra days ticked in
      // "Add to multiple days".
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

  /// The chosen time of day applied to [date]; null when no time was picked.
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
    // Units available depend on whether it's a food or a recipe.
    final availableUnits = isFood ? _kFoodUnits : const ['servings'];
    final timestampEnabled = ref.watch(logTimestampEnabledProvider);

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
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      shrinkWrap: true,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isEditing)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                tooltip: 'Delete entry',
                onPressed: _saving ? null : _delete,
              ),
          ],
        ),
        // ── Composition badges ───────────────────────────────────────────────
        if (insights.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final i in insights) _InsightBadge(insight: i)],
          ),
        ],
        const SizedBox(height: 24),
        // ── Meal selector ────────────────────────────────────────────────────
        _label(theme, 'MEAL'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in mealSlots)
              _MealChip(
                label: m.label,
                selected: _mealKey == m.key,
                onTap: () {
                  Haptics.selection();
                  setState(() => _mealKey = m.key);
                },
              ),
          ],
        ),
        const SizedBox(height: 22),
        // ── Servings ─────────────────────────────────────────────────────────
        _label(theme, 'NUMBER OF SERVINGS'),
        const SizedBox(height: 8),
        _ServingsStepper(
          value: _servings,
          onChanged: (v) {
            Haptics.selection();
            setState(() => _servings = v);
          },
        ),
        const SizedBox(height: 22),
        // ── Portion size + unit ──────────────────────────────────────────────
        _label(theme, 'SERVING SIZE'),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _quantity,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: theme.textTheme.displayMedium?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  suffixText: isFood ? _selectedUnit : 'servings',
                  suffixStyle: theme.textTheme.titleMedium
                      ?.copyWith(color: AppColors.secondary),
                ),
              ),
            ),
          ],
        ),
        // ── Unit chips ───────────────────────────────────────────────────────
        if (isFood) ...[
          const SizedBox(height: 12),
          _label(theme, 'UNIT'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final u in availableUnits)
                _UnitChip(
                  label: u,
                  selected: _selectedUnit == u,
                  onTap: () {
                    Haptics.selection();
                    setState(() => _selectedUnit = u);
                  },
                ),
            ],
          ),
        ],
        if (_servings != 1) ...[
          const SizedBox(height: 10),
          Text(
            'Logging ${_fmtAmount(_totalAmount)} ${isFood ? _selectedUnit : 'servings'} in total.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.secondary),
          ),
        ],
        // ── Optional timestamp ───────────────────────────────────────────────
        if (timestampEnabled) ...[
          const SizedBox(height: 22),
          _label(theme, 'TIME'),
          const SizedBox(height: 8),
          _TimeRow(
            time: _time,
            onPick: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _time ?? TimeOfDay.now(),
              );
              if (picked != null) setState(() => _time = picked);
            },
            onClear: _time == null ? null : () => setState(() => _time = null),
          ),
        ],
        // ── Add to multiple days ─────────────────────────────────────────────
        if (!isEditing) ...[
          const SizedBox(height: 22),
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
        ],
        const SizedBox(height: 22),
        // ── Live nutrition preview ───────────────────────────────────────────
        _NutritionPreview(
          food: widget.food,
          recipe: widget.recipe,
          amount: _totalAmount,
          unit: isFood ? _selectedUnit : 'servings',
          date: widget.date,
        ),
        const SizedBox(height: 28),
        PremiumButton(
          text: _saving
              ? 'Saving…'
              : isEditing
                  ? 'Update Entry'
                  : _extraDays.isEmpty
                      ? 'Log'
                      : 'Log to ${_extraDays.length + 1} days',
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

Widget _label(ThemeData theme, String text) => Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: AppColors.secondary,
        letterSpacing: 1.2,
      ),
    );

/// Drops a trailing `.0` so "2 servings" doesn't read "2.0 servings".
String _fmtAmount(double v) =>
    v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── Servings stepper ────────────────────────────────────────────────────────
class _ServingsStepper extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _ServingsStepper({required this.value, required this.onChanged});

  /// Half-serving granularity — finer than that belongs in the serving size.
  static const _step = 0.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed:
                value <= _step ? null : () => onChanged(value - _step),
          ),
          Expanded(
            child: Text(
              '${_fmtAmount(value)}×',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => onChanged(value + _step),
          ),
        ],
      ),
    );
  }
}

// ─── Optional time-of-day row ────────────────────────────────────────────────
class _TimeRow extends StatelessWidget {
  final TimeOfDay? time;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _TimeRow({required this.time, required this.onPick, this.onClear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.schedule, size: 18),
            label: Text(time == null ? 'Set a time' : time!.format(context)),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  time == null ? AppColors.secondary : AppColors.primary,
              side: BorderSide(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5)),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (onClear != null)
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Clear time',
            onPressed: onClear,
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text('Optional',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.secondary)),
          ),
      ],
    );
  }
}

// ─── Add to multiple days ────────────────────────────────────────────────────
class _MultiDayPicker extends StatelessWidget {
  final DateTime baseDate;
  final Set<DateTime> selected;
  final ValueChanged<DateTime> onToggle;

  const _MultiDayPicker({
    required this.baseDate,
    required this.selected,
    required this.onToggle,
  });

  /// The candidates are weekdays (Monday to Friday) of the current week (or next
  /// week if baseDate is Friday/weekend), excluding baseDate itself.
  List<DateTime> get _candidates {
    final cleanBase = DateUtils.dateOnly(baseDate);
    final weekday = cleanBase.weekday;
    final DateTime startMonday;
    if (weekday >= 5) {
      // If Friday, Saturday, or Sunday, show next week's Mon-Fri
      startMonday = DateUtils.addDaysToDate(cleanBase, 8 - weekday);
    } else {
      // If Mon, Tue, Wed, or Thu, show current week's Mon-Fri
      startMonday = DateUtils.addDaysToDate(cleanBase, -(weekday - 1));
    }
    return [
      for (var i = 0; i < 5; i++)
        DateUtils.addDaysToDate(startMonday, i),
    ]..remove(cleanBase);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(theme, 'ADD TO MULTIPLE DAYS'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final day in _candidates)
              _MealChip(
                label: DateFormat('EEE d').format(day),
                selected: selected.contains(day),
                onTap: () => onToggle(day),
              ),
          ],
        ),
      ],
    );
  }
}

// ─── Live nutrition preview ──────────────────────────────────────────────────

/// Resolves what the pending entry actually contributes and renders it as an
/// energy-split bar plus grams, with micronutrients folded into a drop-down
/// so the common case stays compact (§3).
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

  /// Cached resolution, rebuilt only when the inputs actually change.
  /// Without this the future restarts on every keystroke and the card blanks
  /// out between frames.
  Future<DailyTotals>? _future;
  String? _futureKey;

  Future<DailyTotals> _cachedResolve() {
    final key = '${widget.food?.id}|${widget.recipe?.id}|'
        '${widget.amount}|${widget.unit}';
    if (_futureKey != key || _future == null) {
      _futureKey = key;
      _future = _resolve();
    }
    return _future!;
  }

  /// Builds a throwaway entry so the preview goes through exactly the same
  /// resolver the diary uses — no parallel maths to drift out of sync.
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
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _label(theme, 'THIS ENTRY ADDS')),
                  Text('${t.kcal.round()}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.macroKcal)),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('kcal',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.secondary)),
                  ),
                ],
              ),
              if (targets != null && targets.kcal > 0)
                Text(
                  '${(t.kcal / targets.kcal * 100).round()}% of today\'s calorie goal',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.secondary),
                ),
              const SizedBox(height: 14),
              // Energy split bar — the three shares always fill the width.
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      Expanded(
                        flex: (split.proteinShare * 1000).round().clamp(0, 1000),
                        child: ColoredBox(color: AppColors.macroProtein),
                      ),
                      Expanded(
                        flex: (split.carbsShare * 1000).round().clamp(0, 1000),
                        child: ColoredBox(color: AppColors.macroCarbs),
                      ),
                      Expanded(
                        flex: (split.fatShare * 1000).round().clamp(0, 1000),
                        child: ColoredBox(color: AppColors.macroFat),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _macroCell(theme, 'Protein', t.proteinG, split.proteinShare,
                      targets?.proteinG, AppColors.macroProtein),
                  _macroCell(theme, 'Carbs', t.carbsG, split.carbsShare,
                      targets?.carbsG, AppColors.macroCarbs),
                  _macroCell(theme, 'Fat', t.fatG, split.fatShare,
                      targets?.fatG, AppColors.macroFat),
                ],
              ),
              if (t.hasMicros) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => setState(() => _showMicros = !_showMicros),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Text('More nutrients',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _showMicros ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Icons.expand_more,
                              size: 18, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topLeft,
                  child: !_showMicros
                      ? const SizedBox(width: double.infinity)
                      : _micros(theme, t),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _macroCell(ThemeData theme, String label, double grams, double share,
          int? target, Color color) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondary)),
              ],
            ),
            const SizedBox(height: 2),
            Text('${grams.round()} g',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              target != null && target > 0
                  ? '${(grams / target * 100).round()}% of goal'
                  : '${(share * 100).round()}% of energy',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppColors.secondary, fontSize: 10),
            ),
          ],
        ),
      );

  Widget _micros(ThemeData theme, DailyTotals t) {
    final rows = <(String, String)>[
      if (t.fiberG > 0) ('Fibre', '${t.fiberG.toStringAsFixed(1)} g'),
      if (t.sodiumMg > 0) ('Sodium', '${t.sodiumMg.round()} mg'),
      if (t.potassiumMg > 0) ('Potassium', '${t.potassiumMg.round()} mg'),
      if (t.cholesterolMg > 0)
        ('Cholesterol', '${t.cholesterolMg.round()} mg'),
      for (final e in t.micros.entries)
        if (e.value > 0) (e.key, e.value.toStringAsFixed(1)),
    ];
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('No micronutrient data for this food.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
      );
    }
    return Column(
      children: [
        for (final (name, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                    child: Text(name,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.secondary))),
                Text(value,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Shell that provides the DraggableScrollableSheet wrapper ───────────────
class _LogEntrySheetShell extends StatelessWidget {
  final Widget Function(BuildContext, ScrollController) builder;
  const _LogEntrySheetShell({required this.builder});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: builder(context, scrollController),
      ),
    );
  }
}

// ─── Meal chip ───────────────────────────────────────────────────────────────
class _MealChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MealChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─── Unit chip ───────────────────────────────────────────────────────────────
class _UnitChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _UnitChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
