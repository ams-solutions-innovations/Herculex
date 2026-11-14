import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_pill.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/meal_slots_provider.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';

/// Bottom sheet for logging quick calories + protein either for a single meal
/// or as a rough full-day estimate when the user hasn't tracked all day.
class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({
    super.key,
    required this.date,
    required this.mealKey,
    this.isFullDay = false,
    this.existingEntry,
  });

  final DateTime date;
  final String mealKey;
  final bool isFullDay;
  final FoodEntryData? existingEntry;

  static Future<bool?> show(
    BuildContext context, {
    required DateTime date,
    required String mealKey,
    bool isFullDay = false,
    FoodEntryData? existingEntry,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickAddSheet(
        date: date,
        mealKey: mealKey,
        isFullDay: isFullDay,
        existingEntry: existingEntry,
      ),
    );
  }

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kcalCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _nameCtrl;
  late bool _isFullDay;
  late String _mealKey;
  bool _saving = false;

  bool get _isEditing => widget.existingEntry != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingEntry;
    _isFullDay = existing != null
        ? existing.snapshotBasis == NutritionRepository.quickAddDayBasis
        : widget.isFullDay;
    _mealKey = existing?.meal ?? widget.mealKey;

    _kcalCtrl = TextEditingController(
      text: existing?.snapshotKcal != null
          ? _formatNum(existing!.snapshotKcal!)
          : '',
    );
    _proteinCtrl = TextEditingController(
      text: existing?.snapshotProteinG != null && existing!.snapshotProteinG! > 0
          ? _formatNum(existing.snapshotProteinG!)
          : '',
    );
    final existingName = existing?.snapshotName;
    final isDefaultName =
        existingName == 'Quick Add' || existingName == 'Full Day Estimate';
    _nameCtrl = TextEditingController(
      text: (existingName != null && !isDefaultName) ? existingName : '',
    );
  }

  String _formatNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void dispose() {
    _kcalCtrl.dispose();
    _proteinCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  double? _parsePositive(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final val = double.tryParse(normalized);
    if (val == null || val.isNaN || val.isInfinite || val < 0) return null;
    return val;
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final kcal = _parsePositive(_kcalCtrl.text) ?? 0;
    final protein = _parsePositive(_proteinCtrl.text) ?? 0;
    if (kcal == 0 && protein == 0) {
      AppNotice.show(
        context,
        'Enter calories or protein to save.',
        kind: AppNoticeKind.error,
      );
      return;
    }

    setState(() => _saving = true);
    Haptics.success();

    try {
      final repo = ref.read(nutritionRepositoryProvider);
      if (_isEditing) {
        await repo.updateQuickAddEntry(
          id: widget.existingEntry!.id,
          kcal: kcal,
          proteinG: protein,
          mealKey: _mealKey,
          name: _nameCtrl.text,
          isFullDay: _isFullDay,
        );
      } else {
        await repo.logQuickAdd(
          date: widget.date,
          kcal: kcal,
          proteinG: protein,
          mealKey: _mealKey,
          name: _nameCtrl.text,
          isFullDay: _isFullDay,
        );
      }
      if (!mounted) return;
      AppNotice.show(
        context,
        _isEditing
            ? 'Updated ${kcal.round()} kcal'
            : _isFullDay
            ? 'Logged full day estimate (${kcal.round()} kcal)'
            : 'Quick added ${kcal.round()} kcal',
        kind: AppNoticeKind.success,
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existingEntry;
    if (existing == null || _saving) return;
    setState(() => _saving = true);
    Haptics.medium();
    try {
      await ref.read(nutritionRepositoryProvider).deleteEntry(existing.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final slots = ref.watch(mealSlotsProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color:
              theme.bottomSheetTheme.backgroundColor ?? hx.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                SizedBox(height: HxSpace.x4),
                Row(
                  children: [
                    Icon(
                      _isFullDay ? Icons.today_rounded : Icons.bolt_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isFullDay
                                ? 'Quick Add · Full Day'
                                : 'Quick Add Food',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _isFullDay
                                ? 'Roughly estimate full-day calories & protein'
                                : 'Log just calories & protein',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: hx.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isEditing)
                      IconButton(
                        onPressed: _saving ? null : _delete,
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                        tooltip: 'Delete entry',
                      ),
                  ],
                ),
                SizedBox(height: HxSpace.x4),

                // Mode selector: Meal Quick Add vs Full Day Estimate
                Row(
                  children: [
                    HxTextPill(
                      label: 'Single Meal',
                      selected: !_isFullDay,
                      onTap: () => setState(() => _isFullDay = false),
                    ),
                    const SizedBox(width: 8),
                    HxTextPill(
                      label: 'Full Day Estimate',
                      selected: _isFullDay,
                      onTap: () => setState(() => _isFullDay = true),
                    ),
                  ],
                ),
                SizedBox(height: HxSpace.x4),

                // Calories & Protein inputs
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _kcalCtrl,
                        autofocus: !_isEditing,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Calories (kcal)',
                          hintText: 'e.g. 650',
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return null;
                          if (_parsePositive(val) == null) {
                            return 'Invalid number';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _proteinCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Protein (g)',
                          hintText: 'e.g. 40',
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return null;
                          if (_parsePositive(val) == null) {
                            return 'Invalid number';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: HxSpace.x3),

                // Optional label
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Label (optional)',
                    hintText: _isFullDay ? 'Full Day Estimate' : 'Quick Add',
                    border: const OutlineInputBorder(),
                  ),
                ),

                // Meal slot selector (shown for single meal so user can pick slot)
                if (!_isFullDay && slots.isNotEmpty) ...[
                  SizedBox(height: HxSpace.x3),
                  Text(
                    'MEAL',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hx.secondary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final slot in slots)
                        HxTextPill(
                          label: slot.label,
                          selected: _mealKey == slot.key,
                          onTap: () => setState(() => _mealKey = slot.key),
                        ),
                    ],
                  ),
                ],
                SizedBox(height: HxSpace.x5),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      _isEditing
                          ? 'Save Changes'
                          : _isFullDay
                          ? 'Log Full Day Estimate'
                          : 'Quick Add',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

