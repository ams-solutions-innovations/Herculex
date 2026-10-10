import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/fasting/presentation/fasting_food_log_dialog.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';
import 'package:herculex/features/nutrition/domain/food_portion.dart';
import 'package:herculex/features/nutrition/domain/meal.dart';
import 'package:herculex/features/nutrition/domain/nutrition_label.dart';
import 'package:herculex/features/nutrition/presentation/widgets/scan_variant_form.dart';

/// Reviews a nutrition label read by Herculex AI from one or two photos.
///
/// A label with several tables (drained / not drained, as sold / prepared) is
/// shown as one editable form per variant. Every variant is saved as its own
/// food; the variant chosen with the chips is the one logged to the diary.
class LabelCaptureDialog extends ConsumerStatefulWidget {
  final List<File> imageFiles;
  final Meal meal;
  final String? mealKey;
  final DateTime date;

  const LabelCaptureDialog({
    super.key,
    required this.imageFiles,
    required this.meal,
    this.mealKey,
    required this.date,
  });

  static Future<bool?> show(
    BuildContext context, {
    required List<File> imageFiles,
    required Meal meal,
    String? mealKey,
    required DateTime date,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LabelCaptureDialog(
        imageFiles: imageFiles,
        meal: meal,
        mealKey: mealKey,
        date: date,
      ),
    );
  }

  @override
  ConsumerState<LabelCaptureDialog> createState() => _LabelCaptureDialogState();
}

class _LabelCaptureDialogState extends ConsumerState<LabelCaptureDialog> {
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final List<ScanVariantFields> _fields = [];
  NutritionLabelDraft? _draft;
  int _selected = 0;
  bool _analyzing = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _extract());
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    for (final fields in _fields) {
      fields.dispose();
    }
    super.dispose();
  }

  Future<void> _extract() async {
    try {
      final gemini = ref.read(geminiFoodAnalyzerServiceProvider);
      final draft = await gemini.analyzeNutritionLabel(
        imageFiles: widget.imageFiles,
      );
      if (!mounted) return;
      _fill(draft);
      setState(() {
        _draft = draft;
        _analyzing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error =
            'Herculex AI analysis failed: ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  void _fill(NutritionLabelDraft draft) {
    _name.text = draft.name;
    _brand.text = draft.brand ?? '';
    for (final fields in _fields) {
      fields.dispose();
    }
    _fields
      ..clear()
      ..addAll(draft.variants.map(ScanVariantFields.new));
    _selected = 0;
  }

  String _labelOf(int index) {
    final label = _fields[index].label?.trim();
    return label == null || label.isEmpty ? 'Table ${index + 1}' : label;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Product name is required.');
      return;
    }
    final multiple = _fields.length > 1;
    for (var i = 0; i < _fields.length; i++) {
      final kcal = _fields[i].kcalPer100g;
      if (kcal == null || kcal <= 0) {
        setState(() {
          _error = multiple
              ? 'Calories / 100 g are required (${_labelOf(i)}).'
              : 'Calories / 100 g are required.';
          _selected = i;
        });
        return;
      }
    }
    final proceed = await confirmEndFastOnFoodLog(context, ref);
    if (!proceed || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(nutritionRepositoryProvider);
      final brand = _brand.text.trim().isEmpty ? null : _brand.text.trim();
      final draft = _draft;
      ({int foodId, double amount, String unit})? toLog;
      for (var i = 0; i < _fields.length; i++) {
        final fields = _fields[i];
        final kcal = fields.kcalPer100g!;
        final portionAmount = fields.portionAmount;
        final portionUnit = fields.portionUnit;
        final food = await repo.createCustomFood(
          name: variantFoodName(name, fields.label, multiple: multiple),
          brand: brand,
          kcalPer100g: kcal,
          proteinPer100g: fields.proteinPer100g,
          carbsPer100g: fields.carbsPer100g,
          fatPer100g: fields.fatPer100g,
          servingGrams: fields.servingGrams,
          servingLabel: FoodPortion.labelFor(
            amount: portionAmount,
            unit: portionUnit,
            mass: fields.servingGrams,
          ),
          servingAmount: portionAmount,
          servingUnit: portionUnit,
          sodiumMgPer100g: fields.sodiumMgPer100g,
          sourceMetadataJson: jsonEncode({
            'source': 'gemini',
            'confidence': draft?.confidence,
            'rawEvidence': draft?.evidence,
            'warning': draft?.warning,
            'variant': fields.label,
            'nutrients': {
              'energy_kcal': kcal,
              'protein': fields.proteinPer100g,
              'carbohydrates': fields.carbsPer100g,
              'fat': fields.fatPer100g,
              'fiber': fields.fiberPer100g,
              'sodium': fields.sodiumMgPer100g,
            }..removeWhere((_, value) => value == null),
          }),
        );
        if (i == _selected) {
          toLog = (foodId: food.id, amount: portionAmount, unit: portionUnit);
        }
      }
      await repo.logFood(
        date: widget.date,
        meal: widget.meal,
        mealKey: widget.mealKey,
        foodId: toLog!.foodId,
        portionAmount: toLog.amount,
        portionUnit: toLog.unit,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to save: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.55,
      maxChildSize: 0.97,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                color: AppColors.outlineVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.document_scanner_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Nutrition label scan',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Row(
              children: [
                for (final file in widget.imageFiles)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: file == widget.imageFiles.last ? 0 : 8,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          file,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_analyzing)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Herculex AI is reading the label…'),
                  ],
                ),
              )
            else ...[
              if (_draft != null) _ConfidenceBanner(draft: _draft!),
              if (_error != null) _ErrorBanner(message: _error!),
              if (_fields.isEmpty)
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                )
              else ...[
                const SizedBox(height: 12),
                _field('Product name', _name),
                _field('Brand (optional)', _brand),
                if (_fields.length > 1)
                  ScanVariantChips(
                    labels: [
                      for (var i = 0; i < _fields.length; i++) _labelOf(i),
                    ],
                    selected: _selected,
                    onSelected: (i) => setState(() => _selected = i),
                  ),
                // Keyed so each variant keeps its own focus and scroll state.
                ScanVariantForm(
                  key: ValueKey(_selected),
                  fields: _fields[_selected],
                ),
                const SizedBox(height: 16),
                if (_draft?.warning != null)
                  _ErrorBanner(message: _draft!.warning!),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _saving
                        ? 'Saving…'
                        : _fields.length > 1
                        ? 'Log ${_labelOf(_selected)} to ${widget.meal.label}'
                        : 'Review and add to ${widget.meal.label}',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nothing is saved without this review. You can adjust values before logging.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surfaceContainer,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

class _ConfidenceBanner extends StatelessWidget {
  final NutritionLabelDraft draft;
  const _ConfidenceBanner({required this.draft});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surfaceContainer,
      child: ListTile(
        dense: true,
        leading: Icon(Icons.auto_awesome, color: AppColors.primary),
        title: const Text('Herculex AI'),
        subtitle: Text(
          'Confidence ${(draft.confidence * 100).round()}% — check label',
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message, style: const TextStyle(color: Colors.orange)),
  );
}
