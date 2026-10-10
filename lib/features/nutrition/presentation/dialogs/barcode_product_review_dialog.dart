import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';
import 'package:herculex/features/nutrition/data/product_catalogue_repository.dart';
import 'package:herculex/features/nutrition/domain/food_portion.dart';
import 'package:herculex/features/nutrition/domain/nutrition_label.dart';
import 'package:herculex/features/nutrition/presentation/widgets/scan_variant_form.dart';

/// Shown after [GeminiFoodAnalyzerService.analyzeBarcodeProduct] returns for
/// a barcode the app didn't already know: the model's guess is editable, the
/// barcode itself is fixed (already known from the scan), and confirming
/// both saves the food locally and publishes it to the shared
/// `product_catalogue` so the next person who scans this barcode gets an
/// instant hit — see [ProductCatalogueRepository.publish].
///
/// A package that prints several nutrition tables (drained / not drained, as
/// sold / prepared) is shown as one form per variant. Every variant is saved
/// as a food; the chosen one carries the barcode and is returned for logging.
/// The shared catalogue holds one row per barcode, so it is only published to
/// when there is a single variant.
class BarcodeProductReviewDialog extends ConsumerStatefulWidget {
  const BarcodeProductReviewDialog({
    super.key,
    required this.imageFiles,
    required this.barcode,
  });

  final List<File> imageFiles;
  final String barcode;

  static Future<FoodData?> show(
    BuildContext context, {
    required List<File> imageFiles,
    required String barcode,
  }) {
    return showModalBottomSheet<FoodData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          BarcodeProductReviewDialog(imageFiles: imageFiles, barcode: barcode),
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
  final List<ScanVariantFields> _fields = [];
  int _selected = 0;

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
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    for (final fields in _fields) {
      fields.dispose();
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
        imageFiles: widget.imageFiles,
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
        for (final fields in _fields) {
          fields.dispose();
        }
        _fields
          ..clear()
          ..addAll(
            result.allVariants.map(
              (v) => ScanVariantFields(
                v,
                fallbackAmount: 1,
                fallbackUnit: 'serving',
              ),
            ),
          );
        _selected = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  String _labelOf(int index) {
    final label = _fields[index].label?.trim();
    return label == null || label.isEmpty ? 'Table ${index + 1}' : label;
  }

  Future<void> _saveAndPublish() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final brand = _brandCtrl.text.trim().isEmpty
        ? null
        : _brandCtrl.text.trim();
    final multiple = _fields.length > 1;

    setState(() => _saving = true);

    try {
      final repo = ref.read(nutritionRepositoryProvider);
      FoodData? chosen;
      for (var i = 0; i < _fields.length; i++) {
        final fields = _fields[i];
        final servingGrams = fields.servingGrams ?? 100;
        final portionAmount = fields.portionAmount;
        final portionUnit = fields.portionUnit;
        final isChosen = i == _selected;
        final food = await repo.createCustomFood(
          name: variantFoodName(name, fields.label, multiple: multiple),
          brand: brand,
          // One barcode maps to one food: the variant being logged keeps it,
          // so the next scan of this code finds the table the user picked.
          barcode: isChosen ? widget.barcode : null,
          kcalPer100g: fields.kcalPer100g ?? 0,
          proteinPer100g: fields.proteinPer100g,
          carbsPer100g: fields.carbsPer100g,
          fatPer100g: fields.fatPer100g,
          servingGrams: servingGrams,
          servingAmount: portionAmount,
          servingUnit: portionUnit,
          servingLabel: FoodPortion.labelFor(
            amount: portionAmount,
            unit: portionUnit,
            mass: servingGrams,
          ),
          sodiumMgPer100g: fields.sodiumMgPer100g,
          sourceMetadataJson: jsonEncode({
            'source': 'gemini',
            'confidence': _result?.confidence,
            'variant': fields.label,
            'nutrients': {
              'fiber': fields.fiberPer100g,
              'sodium': fields.sodiumMgPer100g,
            }..removeWhere((_, value) => value == null),
          }),
        );
        if (isChosen) chosen = food;
      }

      if (!multiple) {
        final fields = _fields.first;
        final servingGrams = fields.servingGrams ?? 100;
        await ref
            .read(productCatalogueRepositoryProvider)
            .publish(
              barcode: widget.barcode,
              name: name,
              brand: brand,
              kcalPer100g: fields.kcalPer100g ?? 0,
              proteinPer100g: fields.proteinPer100g,
              carbsPer100g: fields.carbsPer100g,
              fatPer100g: fields.fatPer100g,
              fiberPer100g: fields.fiberPer100g,
              sodiumMgPer100g: fields.sodiumMgPer100g,
              servingGrams: servingGrams,
              servingLabel: '${servingGrams.toStringAsFixed(0)} g',
              // Passed through to `product_catalogue_submissions` so a
              // disputed entry can later be adjudicated against what the
              // model actually claimed, and how sure it was.
              confidence: _result?.confidence,
              evidence: _result?.evidence,
            );
      }

      if (!mounted) return;
      Navigator.of(context).pop(chosen);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Error saving: $e';
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
                      'Herculex AI · Product Lookup',
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
                              child: Container(
                                height: 180,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainer,
                                  image: DecorationImage(
                                    image: FileImage(file),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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
                            'Herculex AI is searching for product online...',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Searching by barcode and packaging appearance',
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
                      'Could not reliably identify product.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _analyze,
                            child: const Text('Try again'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Enter manually'),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_error != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _analyze,
                            child: const Text('Try again'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Enter manually'),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_result != null) ...[
                    Text(
                      'Product details',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Field(controller: _nameCtrl, label: 'Product name'),
                    const SizedBox(height: 12),
                    _Field(controller: _brandCtrl, label: 'Brand'),
                    const SizedBox(height: 12),
                    if (_fields.length > 1)
                      ScanVariantChips(
                        labels: [
                          for (var i = 0; i < _fields.length; i++) _labelOf(i),
                        ],
                        selected: _selected,
                        onSelected: (i) => setState(() => _selected = i),
                      ),
                    ScanVariantForm(
                      key: ValueKey(_selected),
                      fields: _fields[_selected],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fields.length > 1
                          ? 'Verify the data before saving — all tables are '
                                'saved as foods. They are not added to the '
                                'shared database because the barcode has '
                                'several tables.'
                          : 'Verify the data before saving — '
                                'product will be added to the shared database for all users.',
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
                            : Text(
                                _fields.length > 1
                                    ? 'Save and use ${_labelOf(_selected)}'
                                    : 'Confirm and add to database',
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
  const _Field({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surfaceContainer,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
