import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/fasting/presentation/fasting_food_log_dialog.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';
import 'package:herculex/features/nutrition/data/nutrition_label_ocr_service.dart';
import 'package:herculex/features/nutrition/domain/food_portion.dart';
import 'package:herculex/features/nutrition/domain/meal.dart';
import 'package:herculex/features/nutrition/domain/nutrition_label.dart';

class LabelCaptureDialog extends ConsumerStatefulWidget {
  final File imageFile;
  final Meal meal;
  final String? mealKey;
  final DateTime date;

  const LabelCaptureDialog({
    super.key,
    required this.imageFile,
    required this.meal,
    this.mealKey,
    required this.date,
  });

  static Future<bool?> show(
    BuildContext context, {
    required File imageFile,
    required Meal meal,
    String? mealKey,
    required DateTime date,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LabelCaptureDialog(
        imageFile: imageFile,
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
  final _serving = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _fiber = TextEditingController();
  final _sodium = TextEditingController();
  NutritionLabelDraft? _draft;
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
    for (final controller in [
      _name,
      _brand,
      _serving,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _fiber,
      _sodium,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _extract() async {
    try {
      final gemini = ref.read(geminiFoodAnalyzerServiceProvider);
      final draft = await NutritionLabelOcrService(
        gemini,
      ).extract(widget.imageFile);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _analyzing = false;
        _error = null;
      });
      _fill(draft);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = 'OCR/Gemini analiza ni uspela: $e';
      });
    }
  }

  void _fill(NutritionLabelDraft draft) {
    _name.text = draft.name;
    _brand.text = draft.brand ?? '';
    _serving.text = draft.servingGrams?.toStringAsFixed(0) ?? '';
    _kcal.text = draft.kcalPer100g?.toStringAsFixed(0) ?? '';
    _protein.text = draft.proteinPer100g?.toStringAsFixed(1) ?? '';
    _carbs.text = draft.carbsPer100g?.toStringAsFixed(1) ?? '';
    _fat.text = draft.fatPer100g?.toStringAsFixed(1) ?? '';
    _fiber.text = draft.fiberPer100g?.toStringAsFixed(1) ?? '';
    _sodium.text = draft.sodiumMgPer100g?.toStringAsFixed(0) ?? '';
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final kcal = double.tryParse(_kcal.text.replaceAll(',', '.'));
    final serving = double.tryParse(_serving.text.replaceAll(',', '.'));
    final portionAmount = _draft?.portionAmount ?? serving ?? 100;
    final portionUnit = _draft?.servingUnit.trim().isNotEmpty == true
        ? _draft!.servingUnit
        : 'g';
    if (name.isEmpty || kcal == null || kcal <= 0) {
      setState(() => _error = 'Name and calories / 100g are required.');
      return;
    }
    final proceed = await confirmEndFastOnFoodLog(context, ref);
    if (!proceed || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(nutritionRepositoryProvider);
      final metadata = jsonEncode({
        'source': _draft?.source.name ?? LabelExtractionSource.ocr.name,
        'confidence': _draft?.confidence,
        'rawEvidence': _draft?.evidence,
        'warning': _draft?.warning,
        'nutrients': {
          'energy_kcal': kcal,
          'protein': double.tryParse(_protein.text.replaceAll(',', '.')),
          'carbohydrates': double.tryParse(_carbs.text.replaceAll(',', '.')),
          'fat': double.tryParse(_fat.text.replaceAll(',', '.')),
          'fiber': double.tryParse(_fiber.text.replaceAll(',', '.')),
          'sodium': double.tryParse(_sodium.text.replaceAll(',', '.')),
        }..removeWhere((_, value) => value == null),
      });
      final food = await repo.createCustomFood(
        name: name,
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        kcalPer100g: kcal,
        proteinPer100g:
            double.tryParse(_protein.text.replaceAll(',', '.')) ?? 0,
        carbsPer100g: double.tryParse(_carbs.text.replaceAll(',', '.')) ?? 0,
        fatPer100g: double.tryParse(_fat.text.replaceAll(',', '.')) ?? 0,
        servingGrams: serving,
        servingLabel: FoodPortion.labelFor(
          amount: portionAmount,
          unit: portionUnit,
          mass: serving,
        ),
        servingAmount: portionAmount,
        servingUnit: portionUnit,
        sourceMetadataJson: metadata,
      );
      await repo.logFood(
        date: widget.date,
        meal: widget.meal,
        mealKey: widget.mealKey,
        foodId: food.id,
        portionAmount: portionAmount,
        portionUnit: portionUnit,
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
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                widget.imageFile,
                height: 150,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),
            if (_analyzing)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'OCR is reading the label; Gemini will refine the result if needed…',
                    ),
                  ],
                ),
              )
            else ...[
              if (_draft != null) _SourceBanner(draft: _draft!),
              if (_error != null) _ErrorBanner(message: _error!),
              const SizedBox(height: 12),
              _field('Product name', _name),
              _field('Brand (optional)', _brand),
              Row(
                children: [
                  Expanded(
                    child: _field('Serving (g)', _serving, numeric: true),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _field('kcal / 100 g', _kcal, numeric: true)),
                ],
              ),
              Text(
                'Macronutrients / 100 g',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              Row(
                children: [
                  Expanded(child: _field('Protein g', _protein, numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _field('Carbs g', _carbs, numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _field('Fat g', _fat, numeric: true)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _field('Fiber g', _fiber, numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _field('Sodium mg', _sodium, numeric: true)),
                ],
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
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surfaceContainer,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

class _SourceBanner extends StatelessWidget {
  final NutritionLabelDraft draft;
  const _SourceBanner({required this.draft});

  @override
  Widget build(BuildContext context) {
    final source = draft.source == LabelExtractionSource.gemini
        ? 'Gemini fallback'
        : 'On-device OCR';
    return Card(
      color: AppColors.surfaceContainer,
      child: ListTile(
        dense: true,
        leading: Icon(
          draft.source == LabelExtractionSource.gemini
              ? Icons.auto_awesome
              : Icons.phone_android,
          color: AppColors.primary,
        ),
        title: Text(source),
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
