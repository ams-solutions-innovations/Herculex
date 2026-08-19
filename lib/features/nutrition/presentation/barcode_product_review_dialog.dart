import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../data/gemini_food_analyzer_service.dart';
import '../data/product_catalogue_repository.dart';
import 'nutrition_providers.dart';

/// Shown after [GeminiFoodAnalyzerService.analyzeBarcodeProduct] returns for
/// a barcode the app didn't already know: the model's guess is editable, the
/// barcode itself is fixed (already known from the scan), and confirming
/// both saves the food locally and publishes it to the shared
/// `product_catalogue` so the next person who scans this barcode gets an
/// instant hit — see [ProductCatalogueRepository.publish].
class BarcodeProductReviewDialog extends ConsumerStatefulWidget {
  const BarcodeProductReviewDialog({
    super.key,
    required this.imageFile,
    required this.barcode,
  });

  final File imageFile;
  final String barcode;

  static Future<FoodData?> show(
    BuildContext context, {
    required File imageFile,
    required String barcode,
  }) {
    return showModalBottomSheet<FoodData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BarcodeProductReviewDialog(
        imageFile: imageFile,
        barcode: barcode,
      ),
    );
  }

  @override
  ConsumerState<BarcodeProductReviewDialog> createState() =>
      _BarcodeProductReviewDialogState();
}

class _BarcodeProductReviewDialogState
    extends ConsumerState<BarcodeProductReviewDialog> {
  final _nameCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _gramsCtrl = TextEditingController();
  final _kcalCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _fiberCtrl = TextEditingController();
  final _sodiumCtrl = TextEditingController();

  bool _analyzing = true;
  bool _saving = false;
  bool _notFound = false;
  String? _error;
  GeminiBarcodeProductResult? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _analyze());
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _brandCtrl,
      _gramsCtrl,
      _kcalCtrl,
      _proteinCtrl,
      _carbsCtrl,
      _fatCtrl,
      _fiberCtrl,
      _sodiumCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _analyze() async {
    setState(() {
      _analyzing = true;
      _error = null;
      _notFound = false;
    });

    try {
      final analyzer = ref.read(geminiFoodAnalyzerServiceProvider);
      final result = await analyzer.analyzeBarcodeProduct(
        imageFile: widget.imageFile,
        barcode: widget.barcode,
      );

      if (!mounted) return;
      if (!result.found) {
        setState(() {
          _analyzing = false;
          _notFound = true;
        });
        return;
      }

      setState(() {
        _analyzing = false;
        _result = result;
        _nameCtrl.text = result.name;
        _brandCtrl.text = result.brand ?? '';
        _gramsCtrl.text = result.servingGrams.toStringAsFixed(0);
        _kcalCtrl.text = result.kcalPer100g.toStringAsFixed(0);
        _proteinCtrl.text = result.proteinPer100g.toStringAsFixed(1);
        _carbsCtrl.text = result.carbsPer100g.toStringAsFixed(1);
        _fatCtrl.text = result.fatPer100g.toStringAsFixed(1);
        _fiberCtrl.text = (result.fiberPer100g ?? 0).toStringAsFixed(1);
        _sodiumCtrl.text = (result.sodiumMgPer100g ?? 0).toStringAsFixed(0);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _saveAndPublish() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final brand = _brandCtrl.text.trim().isEmpty
        ? null
        : _brandCtrl.text.trim();
    final servingGrams = double.tryParse(_gramsCtrl.text) ?? 100;
    final kcalPer100g = double.tryParse(_kcalCtrl.text) ?? 0;
    final proteinPer100g = double.tryParse(_proteinCtrl.text) ?? 0;
    final carbsPer100g = double.tryParse(_carbsCtrl.text) ?? 0;
    final fatPer100g = double.tryParse(_fatCtrl.text) ?? 0;
    final fiberPer100g = double.tryParse(_fiberCtrl.text);
    final sodiumMgPer100g = double.tryParse(_sodiumCtrl.text);

    setState(() => _saving = true);

    try {
      final repo = ref.read(nutritionRepositoryProvider);
      final food = await repo.createCustomFood(
        name: name,
        brand: brand,
        barcode: widget.barcode,
        kcalPer100g: kcalPer100g,
        proteinPer100g: proteinPer100g,
        carbsPer100g: carbsPer100g,
        fatPer100g: fatPer100g,
        servingGrams: servingGrams,
        servingLabel: '${servingGrams.toStringAsFixed(0)} g',
        sodiumMgPer100g: sodiumMgPer100g,
        sourceMetadataJson: jsonEncode({
          'source': 'gemini',
          'confidence': _result?.confidence,
          'nutrients': {
            'fiber': fiberPer100g,
            'sodium': sodiumMgPer100g,
          }..removeWhere((_, value) => value == null),
        }),
      );

      await ref
          .read(productCatalogueRepositoryProvider)
          .publish(
            barcode: widget.barcode,
            name: name,
            brand: brand,
            kcalPer100g: kcalPer100g,
            proteinPer100g: proteinPer100g,
            carbsPer100g: carbsPer100g,
            fatPer100g: fatPer100g,
            fiberPer100g: fiberPer100g,
            sodiumMgPer100g: sodiumMgPer100g,
            servingGrams: servingGrams,
            servingLabel: '${servingGrams.toStringAsFixed(0)} g',
          );

      if (!mounted) return;
      Navigator.of(context).pop(food);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Napaka pri shranjevanju: $e';
      });
    }
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
                  Expanded(
                    child: Text(
                      'Gemini AI · iskanje izdelka',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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
                  const SizedBox(height: 8),
                  Text(
                    'Koda: ${widget.barcode}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    _ErrorPanel(error: _error!),
                    const SizedBox(height: 16),
                  ],
                  if (_analyzing) ...[
                    const SizedBox(height: 40),
                    Center(
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          const Text(
                            'Gemini AI isce izdelek na spletu...',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Iskanje po barkodi in videzu embalaze',
                            style: TextStyle(
                              color: AppColors.secondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ] else if (_notFound) ...[
                    const SizedBox(height: 24),
                    Icon(
                      Icons.search_off,
                      size: 48,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Izdelka ni bilo mogoce zanesljivo prepoznati.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _analyze,
                            child: const Text('Poskusi znova'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Vnesi rocno'),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_result != null) ...[
                    Text(
                      'Podrobnosti izdelka',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Field(controller: _nameCtrl, label: 'Ime izdelka'),
                    const SizedBox(height: 12),
                    _Field(controller: _brandCtrl, label: 'Znamka'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _Field(
                            controller: _gramsCtrl,
                            label: 'Serving (g)',
                            suffix: 'g',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Field(
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
                          child: _Field(
                            controller: _proteinCtrl,
                            label: 'Beljakovine',
                            suffix: 'g',
                            decimal: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Field(
                            controller: _carbsCtrl,
                            label: 'Oglj. hidrati',
                            suffix: 'g',
                            decimal: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Field(
                            controller: _fatCtrl,
                            label: 'Mascobe',
                            suffix: 'g',
                            decimal: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _Field(
                            controller: _fiberCtrl,
                            label: 'Vlaknine',
                            suffix: 'g',
                            decimal: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Field(
                            controller: _sodiumCtrl,
                            label: 'Natrij',
                            suffix: 'mg',
                            decimal: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Preveri, ali so podatki pravilni, preden shranis — '
                      'izdelek bo dodan v skupno bazo za vse uporabnike.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _saving ? null : _saveAndPublish,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _saving
                            ? const CircularProgressIndicator()
                            : const Text(
                                'Potrdi in dodaj v skupno bazo',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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

class _Field extends StatelessWidget {
  const _Field({
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
