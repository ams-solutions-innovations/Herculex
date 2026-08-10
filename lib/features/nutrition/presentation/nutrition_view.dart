import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../data/nutrition_repository.dart';
import '../domain/daily_totals.dart';
import '../domain/meal_slots.dart';
import '../domain/nutrient_definitions.dart';
import 'food_picker_sheet.dart';
import 'goals_providers.dart';
import 'log_entry_sheet.dart';
import 'macro_rings.dart';
import 'nutrition_providers.dart';
import 'meal_slots_provider.dart';
import 'nutrient_settings_provider.dart';

class NutritionView extends ConsumerStatefulWidget {
  const NutritionView({super.key});

  @override
  ConsumerState<NutritionView> createState() => _NutritionViewState();
}

class _NutritionViewState extends ConsumerState<NutritionView> {
  // Large virtual page space; page 5000 == today.
  static const int _kCenter = 5000;
  late final PageController _pageCtrl;
  bool _settling = false;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: _kCenter);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  DateTime _pageToDate(int page) {
    final today = DateUtils.dateOnly(DateTime.now());
    return DateUtils.addDaysToDate(today, page - _kCenter);
  }

  int _dateToPage(DateTime date) {
    final today = DateUtils.dateOnly(DateTime.now());
    return _kCenter + date.difference(today).inDays;
  }

  void _onPageChanged(int page) {
    if (_settling) return;
    final today = DateUtils.dateOnly(DateTime.now());
    final candidate = _pageToDate(page);
    if (candidate.isAfter(today)) {
      // Snap back — can't go to future
      _settling = true;
      _pageCtrl
          .animateToPage(
            _dateToPage(today),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          )
          .then((_) => _settling = false);
      return;
    }
    ref.read(selectedDateProvider.notifier).state = candidate;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = ref.watch(selectedDateProvider);

    // If date was changed externally (date picker), sync the page controller.
    final targetPage = _dateToPage(date);
    if (_pageCtrl.hasClients &&
        _pageCtrl.page?.round() != targetPage &&
        !_settling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pageCtrl.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: _buildDateHeader(context, date, theme),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, page) {
                  final pageDate = _pageToDate(page);
                  return _DayPage(date: pageDate);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateHeader(
    BuildContext context,
    DateTime date,
    ThemeData theme,
  ) {
    final today = DateTime.now();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final label = isToday ? 'Today' : DateFormat('EEE, MMM d').format(date);

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.donut_small_outlined),
            tooltip: 'Nutrient overview',
            onPressed: () => context.push('/nutrient-overview'),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    final prev = DateUtils.addDaysToDate(date, -1);
                    ref.read(selectedDateProvider.notifier).state = prev;
                  },
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: today.add(const Duration(days: 30)),
                    );
                    if (picked != null) {
                      ref.read(selectedDateProvider.notifier).state =
                          DateUtils.dateOnly(picked);
                    }
                  },
                  child: Text(
                    label,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: isToday
                      ? null
                      : () {
                          final next = DateUtils.addDaysToDate(date, 1);
                          ref.read(selectedDateProvider.notifier).state = next;
                        },
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Nutrition options',
            onSelected: (value) {
              switch (value) {
                case 'targets':
                  context.push('/nutrition-targets');
                  break;
                case 'nutrients':
                  context.push('/nutrition-nutrients');
                  break;
                case 'meal_slots':
                  context.push('/nutrition-meal-slots');
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'targets',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Targets & dieting'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'nutrients',
                child: Row(
                  children: [
                    Icon(Icons.science_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Edit nutrients shown'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'meal_slots',
                child: Row(
                  children: [
                    Icon(Icons.tune_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Edit meal slots'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Per-day page rendered inside the PageView ────────────────────────────────

class _DayPage extends ConsumerWidget {
  final DateTime date;
  const _DayPage({required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final totalsAsync = ref.watch(dailyTotalsProvider(date));
    final totals = totalsAsync.asData?.value ?? DailyTotals.empty;
    final entriesByMeal = ref.watch(entriesByMealProvider(date));
    final configuredSlots = ref.watch(mealSlotsProvider);
    final visibleNutrients = ref.watch(visibleNutrientIdsProvider);
    final targets =
        ref.watch(effectiveTargetsProvider(date)).asData?.value ??
        ref.watch(baselineTargetsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: MacroRings(totals: totals, targets: targets),
        ),
        if (targets == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Text(
              'Add your weight, height, and age in profile to compute macro targets.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ),
        if (totals.hasMicros)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _MineralsRow(
              totals: totals,
              theme: theme,
              visibleIds: visibleNutrients,
            ),
          ),
        const SizedBox(height: 24),
        entriesByMeal.when(
          data: (byMeal) {
            final slots = [
              ...configuredSlots,
              for (final key in byMeal.keys)
                if (!configuredSlots.any((slot) => slot.key == key))
                  MealSlot(key: key, label: key),
            ];
            return Column(
              children: [
                for (final meal in slots) ...[
                  _MealAccordion(
                    meal: meal,
                    entries: byMeal[meal.key] ?? const [],
                    date: date,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error: $e'),
        ),
      ],
    );
  }
}

/// Expandable meal accordion. Header shows macro grams; tapping the macro row
/// toggles to % of that meal's total kcal. The "+ Add" button lives at the
/// bottom of the expanded body.
class _MealAccordion extends StatefulWidget {
  final MealSlot meal;
  final List<FoodEntryData> entries;
  final DateTime date;

  const _MealAccordion({
    required this.meal,
    required this.entries,
    required this.date,
  });

  @override
  State<_MealAccordion> createState() => _MealAccordionState();
}

/// What the meal header's macro chip shows. Tapping the chip advances through
/// the cycle: share of the meal's energy → grams → kilocalories (§3).
enum MacroDisplayMode {
  percent,
  grams,
  kcal;

  MacroDisplayMode get next =>
      MacroDisplayMode.values[(index + 1) % MacroDisplayMode.values.length];
}

class _MealAccordionState extends State<_MealAccordion>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  MacroDisplayMode _macroMode = MacroDisplayMode.percent;

  late final AnimationController _ctrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 0.0,
    );
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  /// Compute per-meal macro totals synchronously from entry metadata stored
  /// on FoodEntryData. Full precision requires async repo calls; we approximate
  /// here using the cached kcal-equivalent fields when available, but the
  /// accurate path is the async _EntryTile which resolves per-food macros.
  /// For the header summary we use a FutureBuilder per accordion.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          InkWell(
            onTap: _toggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
              child: Row(
                children: [
                  Icon(widget.meal.icon, size: 20, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.meal.label,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${widget.entries.length} item${widget.entries.length == 1 ? '' : 's'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                        _MealCalorieGoal(
                          entries: widget.entries,
                          mealKey: widget.meal.key,
                          date: widget.date,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Macro summary — tapping cycles % → g → kcal
                  if (widget.entries.isNotEmpty)
                    _MealMacroSummary(
                      entries: widget.entries,
                      mode: _macroMode,
                      onToggle: () =>
                          setState(() => _macroMode = _macroMode.next),
                    ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Body (animated) ─────────────────────────────────────────────
          SizeTransition(
            sizeFactor: _expandAnim,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(height: 1, indent: 16, endIndent: 16),
                if (widget.entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Nothing logged.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  )
                else
                  for (final e in widget.entries) _EntryTile(entry: e),
                // ── + Add button at bottom ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => FoodPickerSheet.show(
                        context,
                        date: widget.date,
                        mealKey: widget.meal.key,
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add food'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolves per-meal macro totals asynchronously and renders a compact
/// "P · C · F" chip. Tapping cycles between grams and % of meal kcal.
class _MealMacroSummary extends ConsumerWidget {
  final List<FoodEntryData> entries;
  final MacroDisplayMode mode;
  final VoidCallback onToggle;

  const _MealMacroSummary({
    required this.entries,
    required this.mode,
    required this.onToggle,
  });

  Future<DailyTotals> _sumMacros(NutritionRepository repo) async {
    var t = DailyTotals.empty;
    for (final e in entries) {
      final m = await repo.macrosForEntry(e);
      t = t.plus(
        kcal: m.kcal,
        proteinG: m.proteinG,
        carbsG: m.carbsG,
        fatG: m.fatG,
      );
    }
    return t;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(nutritionRepositoryProvider);
    final theme = Theme.of(context);

    return FutureBuilder<DailyTotals>(
      future: _sumMacros(repo),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final t = snap.data!;
        final totalKcal = t.kcal;

        // Percentages are of the meal's own energy, so they always sum to
        // ~100 % regardless of how the day's targets are set.
        String fmt(double grams, double kcalPer1g) => switch (mode) {
          MacroDisplayMode.percent =>
            totalKcal > 0
                ? '${(grams * kcalPer1g / totalKcal * 100).round()}%'
                : '—',
          MacroDisplayMode.grams => '${grams.toStringAsFixed(0)}g',
          MacroDisplayMode.kcal => '${(grams * kcalPer1g).round()} kcal',
        };

        return GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MacroChip(
                  'P',
                  fmt(t.proteinG, 4),
                  AppColors.macroProtein,
                  theme,
                ),
                const SizedBox(width: 6),
                _MacroChip('C', fmt(t.carbsG, 4), AppColors.macroCarbs, theme),
                const SizedBox(width: 6),
                _MacroChip('F', fmt(t.fatG, 9), AppColors.macroFat, theme),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// `320 of 600 kcal` under the meal name (§3). Renders just the consumed
/// figure when the slot has no configured goal, and a slim bar once it does.
class _MealCalorieGoal extends ConsumerWidget {
  final List<FoodEntryData> entries;
  final String mealKey;
  final DateTime date;

  const _MealCalorieGoal({
    required this.entries,
    required this.mealKey,
    required this.date,
  });

  Future<double> _sumKcal(NutritionRepository repo) async {
    var kcal = 0.0;
    for (final e in entries) {
      kcal += (await repo.macrosForEntry(e)).kcal;
    }
    return kcal;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final goal = ref.watch(
      mealGoalKcalProvider((mealKey: mealKey, date: date)),
    );

    if (entries.isEmpty && goal == null) return const SizedBox.shrink();

    return FutureBuilder<double>(
      future: _sumKcal(ref.watch(nutritionRepositoryProvider)),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 16);
        final eaten = snap.data!.round();
        final label = goal == null ? '$eaten kcal' : '$eaten of $goal kcal';
        final over = goal != null && eaten > goal;

        return Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: over ? Colors.redAccent : AppColors.secondary,
                  fontWeight: over ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (goal != null && goal > 0) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    width: 110,
                    child: LinearProgressIndicator(
                      value: (eaten / goal).clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: AppColors.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        over ? Colors.redAccent : AppColors.macroKcal,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MacroChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final ThemeData theme;

  const _MacroChip(this.label, this.value, this.color, this.theme);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          value,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EntryTile extends ConsumerWidget {
  final FoodEntryData entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(nutritionRepositoryProvider);

    return FutureBuilder<_EntryDisplay>(
      future: _resolve(ref, repo),
      builder: (context, snap) {
        final display = snap.data;
        return Dismissible(
          key: ValueKey('entry_${entry.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: Colors.redAccent.withValues(alpha: 0.85),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => repo.deleteEntry(entry.id),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            dense: true,
            title: Text(
              display?.name ?? 'Loading…',
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            subtitle: Text(
              display?.subtitleWithMacros ?? '',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            trailing: Text(
              display == null ? '' : '${display.kcal.toStringAsFixed(0)} kcal',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: display == null
                ? null
                : () => _showEntryDetail(context, theme, display, ref),
          ),
        );
      },
    );
  }

  Future<_EntryDisplay> _resolve(
    WidgetRef ref,
    NutritionRepository repo,
  ) async {
    final macros = await repo.macrosForEntry(entry);
    final name = await _resolveName(ref);
    final portionText = entry.foodId != null
        ? '${(entry.gramsOverride ?? 0).toStringAsFixed(0)} g'
        : '${entry.servings.toStringAsFixed(entry.servings.truncateToDouble() == entry.servings ? 0 : 1)} serv';
    return _EntryDisplay(
      name: name,
      portionText: portionText,
      kcal: macros.kcal,
      proteinG: macros.proteinG,
      carbsG: macros.carbsG,
      fatG: macros.fatG,
      sodiumMg: macros.sodiumMg,
      potassiumMg: macros.potassiumMg,
      cholesterolMg: macros.cholesterolMg,
    );
  }

  void _showEntryDetail(
    BuildContext context,
    ThemeData theme,
    _EntryDisplay display,
    WidgetRef ref,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        final repo = ref.read(nutritionRepositoryProvider);
        final mealSlots = ref.read(mealSlotsProvider);
        final hasMicros =
            display.sodiumMg > 0 ||
            display.potassiumMg > 0 ||
            display.cholesterolMg > 0;
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: theme.bottomSheetTheme.backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                            display.name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            display.subtitleWithMacros,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.drive_file_move_outlined),
                      tooltip: 'Move to meal',
                      onSelected: (targetMealKey) async {
                        Haptics.selection();
                        Navigator.of(modalContext).pop();
                        await repo.updateEntry(
                          id: entry.id,
                          mealKey: targetMealKey,
                        );
                        if (!context.mounted) return;
                        final targetLabel = mealSlots
                            .firstWhere(
                              (s) => s.key == targetMealKey,
                              orElse: () => MealSlot(key: targetMealKey, label: targetMealKey),
                            )
                            .label;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Moved ${display.name} to $targetLabel'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      itemBuilder: (context) => [
                        for (final slot in mealSlots)
                          PopupMenuItem(
                            value: slot.key,
                            enabled: slot.key != entry.meal,
                            child: Row(
                              children: [
                                Icon(
                                  slot.icon,
                                  size: 18,
                                  color: slot.key == entry.meal
                                      ? AppColors.secondary
                                      : AppColors.primary,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  slot.label,
                                  style: TextStyle(
                                    fontWeight: slot.key == entry.meal
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.edit, color: AppColors.primary),
                      tooltip: 'Edit entry',
                      onPressed: () async {
                        Navigator.of(modalContext).pop();
                        FoodData? food;
                        RecipeData? recipe;
                        if (entry.foodId != null) {
                          final foods = await repo.searchFoods('');
                          food = foods
                              .where((f) => f.id == entry.foodId)
                              .firstOrNull;
                        } else if (entry.recipeId != null) {
                          final recipes = await repo.watchRecipes().first;
                          recipe = recipes
                              .where((r) => r.id == entry.recipeId)
                              .firstOrNull;
                        }
                        if (!context.mounted) return;
                        LogEntrySheet.forEntry(
                          context,
                          entry: entry,
                          food: food,
                          recipe: recipe,
                          date:
                              DateTime.tryParse(entry.dateIso) ?? DateTime.now(),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      tooltip: 'Delete entry',
                      onPressed: () async {
                        Navigator.of(modalContext).pop();
                        await repo.deleteEntry(entry.id);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '${display.kcal.toStringAsFixed(0)} kcal',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'MOVE TO MEAL',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final slot in mealSlots)
                      ChoiceChip(
                        avatar: Icon(
                          slot.icon,
                          size: 16,
                          color: slot.key == entry.meal
                              ? Colors.white
                              : AppColors.primary,
                        ),
                        label: Text(slot.label),
                        selected: slot.key == entry.meal,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: slot.key == entry.meal
                              ? Colors.white
                              : AppColors.onSurface,
                          fontWeight: slot.key == entry.meal
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                        onSelected: (selected) async {
                          if (slot.key == entry.meal) return;
                          Haptics.selection();
                          Navigator.of(modalContext).pop();
                          await repo.updateEntry(
                            id: entry.id,
                            mealKey: slot.key,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Moved ${display.name} to ${slot.label}'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                  ],
                ),
                if (hasMicros) ...[
                  const SizedBox(height: 16),
                  Text(
                    'MINERALS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  microRow('Sodium', display.sodiumMg, 'mg', theme),
                  microRow('Potassium', display.potassiumMg, 'mg', theme),
                  microRow('Cholesterol', display.cholesterolMg, 'mg', theme),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(modalContext).pop();
                      FoodData? food;
                      RecipeData? recipe;
                      if (entry.foodId != null) {
                        final foods = await repo.searchFoods('');
                        food = foods
                            .where((f) => f.id == entry.foodId)
                            .firstOrNull;
                      } else if (entry.recipeId != null) {
                        final recipes = await repo.watchRecipes().first;
                        recipe = recipes
                            .where((r) => r.id == entry.recipeId)
                            .firstOrNull;
                      }
                      if (!context.mounted) return;
                      LogEntrySheet.forEntry(
                        context,
                        entry: entry,
                        food: food,
                        recipe: recipe,
                        date: DateTime.tryParse(entry.dateIso) ?? DateTime.now(),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit Quantity or Meal'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String> _resolveName(WidgetRef ref) async {
    if (entry.foodId != null) {
      final list = await ref.read(foodSearchProvider(null).future);
      return list
          .firstWhere(
            (f) => f.id == entry.foodId,
            orElse: () => _placeholderFood(),
          )
          .name;
    }
    if (entry.recipeId != null) {
      final list = await ref.read(recipesProvider.future);
      return list
          .firstWhere(
            (r) => r.id == entry.recipeId,
            orElse: () => _placeholderRecipe(),
          )
          .name;
    }
    return '—';
  }

  FoodData _placeholderFood() => FoodData(
    id: 0,
    name: '—',
    kcalPer100g: 0,
    proteinPer100g: 0,
    carbsPer100g: 0,
    fatPer100g: 0,
    referenceBasis: '100 g',
    source: 'local',
    isCustom: false,
    createdAt: DateTime.now(),
  );

  RecipeData _placeholderRecipe() =>
      RecipeData(id: 0, name: '—', servings: 1, createdAt: DateTime.now());
}

class _EntryDisplay {
  final String name;
  final String portionText;
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double sodiumMg;
  final double potassiumMg;
  final double cholesterolMg;

  _EntryDisplay({
    required this.name,
    required this.portionText,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.sodiumMg = 0,
    this.potassiumMg = 0,
    this.cholesterolMg = 0,
  });

  String get subtitleWithMacros {
    final p = proteinG.toStringAsFixed(0);
    final c = carbsG.toStringAsFixed(0);
    final f = fatG.toStringAsFixed(0);
    return '$portionText  •  P: ${p}g  C: ${c}g  F: ${f}g';
  }
}

class _MineralsRow extends StatefulWidget {
  final DailyTotals totals;
  final ThemeData theme;
  final Set<String> visibleIds;
  const _MineralsRow({
    required this.totals,
    required this.theme,
    required this.visibleIds,
  });

  @override
  State<_MineralsRow> createState() => _MineralsRowState();
}

class _MineralsRowState extends State<_MineralsRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.totals;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.science_outlined,
                      size: 15,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'MICRONUTRIENTS',
                      style: widget.theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              for (final definition in trackedNutrients)
                if (widget.visibleIds.contains(definition.id)) ...[
                  _NutrientProgressBar(
                    definition: definition,
                    value:
                        t.nutrient(definition.id) ??
                        _fallbackValue(t, definition.id),
                    theme: widget.theme,
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ],
        ),
      ),
    );
  }

  double? _fallbackValue(DailyTotals t, String id) {
    switch (id) {
      case 'fiber':
        return t.fiberG > 0 ? t.fiberG : null;
      case 'sodium':
        return t.sodiumMg > 0 ? t.sodiumMg : null;
      case 'potassium':
        return t.potassiumMg > 0 ? t.potassiumMg : null;
      case 'cholesterol':
        return t.cholesterolMg > 0 ? t.cholesterolMg : null;
      default:
        return null;
    }
  }
}

class _NutrientProgressBar extends StatelessWidget {
  final NutrientDefinition definition;
  final double? value;
  final ThemeData theme;

  const _NutrientProgressBar({
    required this.definition,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final current = value ?? 0.0;
    final target = definition.dailyTarget;
    final hasTarget = target != null && target > 0;
    final pct = hasTarget ? (current / target * 100).round() : null;
    final progress = hasTarget ? (current / target).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              definition.label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              value == null
                  ? '0 / ${target?.toStringAsFixed(0) ?? '—'} ${definition.unit} (0%)'
                  : '${current.toStringAsFixed(definition.unit == 'g' || definition.unit == 'µg' ? 1 : 0)} / ${target != null ? target.toStringAsFixed(definition.unit == 'g' || definition.unit == 'µg' ? 1 : 0) : '—'} ${definition.unit} ${pct != null ? '($pct%)' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: value == null ? AppColors.secondary : AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(
              progress >= 1.0 ? Colors.green : AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

Widget microRow(String label, double value, String unit, ThemeData theme) {
  if (value <= 0) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        Text(
          '${value.toStringAsFixed(0)} $unit',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
