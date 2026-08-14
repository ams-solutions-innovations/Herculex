import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import '../data/gemini_food_analyzer_service.dart';
import '../domain/meal.dart';
import 'nutrition_providers.dart';

class GeminiPhotoAnalysisDialog extends ConsumerStatefulWidget {
  const GeminiPhotoAnalysisDialog({
    super.key,
    required this.imageFile,
    required this.meal,
    this.mealKey,
    required this.date,
  });

  final File imageFile;
  final Meal meal;
  final String? mealKey;
  final DateTime date;

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
      builder: (_) => GeminiPhotoAnalysisDialog(
        imageFile: imageFile,
        meal: meal,
        mealKey: mealKey,
        date: date,
      ),
    );
  }

  @override
  ConsumerState<GeminiPhotoAnalysisDialog> createState() =>
      _GeminiPhotoAnalysisDialogState();
}

class _GeminiPhotoAnalysisDialogState
    extends ConsumerState<GeminiPhotoAnalysisDialog> {
  final _noteCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _gramsCtrl = TextEditingController();
  final _kcalCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _fiberCtrl = TextEditingController();

  bool _analyzing = false;
  bool _saving = false;
  String? _error;
  GeminiFoodAnalysisResult? _result;

  @override
  void dispose() {
    _noteCtrl.dispose();
    _nameCtrl.dispose();
    _gramsCtrl.dispose();
    _kcalCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    _fiberCtrl.dispose();
    super.dispose();
  }

  Future<void> _startAnalysis() async {
    setState(() {
      _analyzing = true;
      _error = null;
    });

    try {
      final analyzer = ref.read(geminiFoodAnalyzerServiceProvider);
      final result = await analyzer.analyzeFoodPhoto(
        imageFile: widget.imageFile,
        userNote: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _result = result;
        _nameCtrl.text = result.name;
        _gramsCtrl.text = result.estimatedServingGrams.toStringAsFixed(0);
        _kcalCtrl.text = result.kcalPer100g.toStringAsFixed(0);
        _proteinCtrl.text = result.proteinPer100g.toStringAsFixed(1);
        _carbsCtrl.text = result.carbsPer100g.toStringAsFixed(1);
        _fatCtrl.text = result.fatPer100g.toStringAsFixed(1);
        _fiberCtrl.text = (result.fiberPer100g ?? 0).toStringAsFixed(1);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _saveAndLog() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final servingGrams = double.tryParse(_gramsCtrl.text) ?? 100;
    final kcalPer100g = double.tryParse(_kcalCtrl.text) ?? 0;
    final proteinPer100g = double.tryParse(_proteinCtrl.text) ?? 0;
    final carbsPer100g = double.tryParse(_carbsCtrl.text) ?? 0;
    final fatPer100g = double.tryParse(_fatCtrl.text) ?? 0;

    setState(() => _saving = true);

    try {
      final repo = ref.read(nutritionRepositoryProvider);
      final food = await repo.createCustomFood(
        name: name,
        brand: _result?.brand ?? 'Gemini AI',
        kcalPer100g: kcalPer100g,
        proteinPer100g: proteinPer100g,
        carbsPer100g: carbsPer100g,
        fatPer100g: fatPer100g,
        servingGrams: servingGrams,
        servingLabel: '${servingGrams.toStringAsFixed(0)} g',
      );

      await repo.logFood(
        date: widget.date,
        meal: widget.meal,
        mealKey: widget.mealKey,
        foodId: food.id,
        grams: servingGrams,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Napaka pri shranjevanju: $e';
      });
    }
  }

  Color _ratingColor(double rating) {
    if (rating >= 8.0) return Colors.green.shade600;
    if (rating >= 6.0) return Colors.amber.shade700;
    return Colors.orange.shade800;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
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
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Gemini AI Analiza hrane',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(16),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        image: DecorationImage(
                          image: FileImage(widget.imageFile),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    _ErrorPanel(error: _error!),
                    const SizedBox(height: 16),
                  ],
                  if (_result == null && !_analyzing) ...[
                    Text(
                      'Opomba / Sestava hrane (neobvezno)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dodajte opombo o kolicini ali sestavinah, da bo analiza natancnejsa.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Napisite opombo (npr. 150g riza, 2 jajci)',
                        filled: true,
                        fillColor: AppColors.surfaceContainer,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _startAnalysis,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text(
                          'Analiziraj z Gemini AI',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ] else if (_analyzing) ...[
                    const SizedBox(height: 40),
                    Center(
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          const Text(
                            'Gemini AI analizira sliko in sestavine...',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Racunanje hranilnih vrednosti in ocene obroka',
                            style: TextStyle(
                              color: AppColors.secondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ] else if (_result != null) ...[
                    _RatingPanel(
                      result: _result!,
                      color: _ratingColor(_result!.rating),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Podrobnosti obroka',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _NumberField(controller: _nameCtrl, label: 'Ime hrane'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            controller: _gramsCtrl,
                            label: 'Celotna masa (g)',
                            suffix: 'g',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _NumberField(
                            controller: _kcalCtrl,
                            label: 'Kalorije / 100g',
                            suffix: 'kcal',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Makronutrienti (na 100g)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            controller: _proteinCtrl,
                            label: 'Beljakovine',
                            suffix: 'g',
                            decimal: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _NumberField(
                            controller: _carbsCtrl,
                            label: 'Oglj. hidrati',
                            suffix: 'g',
                            decimal: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _NumberField(
                            controller: _fatCtrl,
                            label: 'Mascobe',
                            suffix: 'g',
                            decimal: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _saving ? null : _saveAndLog,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _saving
                            ? const CircularProgressIndicator()
                            : Text(
                                'Dodaj v ${widget.meal.label}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => setState(() => _result = null),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Ponovno analiziraj sliko'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade300),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.red.shade300),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingPanel extends StatelessWidget {
  const _RatingPanel({required this.result, required this.color});

  final GeminiFoodAnalysisResult result;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, size: 16, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  'Ocena hrane: ${result.rating.toStringAsFixed(1)} / 10',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            result.ratingReason,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.suffix,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String label;
  final String? suffix;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: suffix == null
          ? TextInputType.text
          : TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        filled: true,
        fillColor: AppColors.surfaceContainer,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
