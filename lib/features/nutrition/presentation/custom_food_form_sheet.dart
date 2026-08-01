import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../widgets/premium_button.dart';
import '../domain/barcode_utils.dart';
import 'nutrition_providers.dart';

class CustomFoodFormSheet extends ConsumerStatefulWidget {
  final String? initialName;
  final String? initialBarcode;
  final FoodData? existingFood;

  const CustomFoodFormSheet({
    super.key,
    this.initialName,
    this.initialBarcode,
    this.existingFood,
  });

  static Future<FoodData?> show(
    BuildContext context, {
    String? initialName,
    String? initialBarcode,
    FoodData? existingFood,
  }) {
    return showModalBottomSheet<FoodData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: CustomFoodFormSheet(
          initialName: initialName,
          initialBarcode: initialBarcode,
          existingFood: existingFood,
        ),
      ),
    );
  }

  @override
  ConsumerState<CustomFoodFormSheet> createState() =>
      _CustomFoodFormSheetState();
}

class _CustomFoodFormSheetState extends ConsumerState<CustomFoodFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _barcode;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late final TextEditingController _servingG;
  late final TextEditingController _sodium;
  late final TextEditingController _potassium;
  late final TextEditingController _cholesterol;

  // Additional expanded nutrient controllers
  late final TextEditingController _sugars;
  late final TextEditingController _transFat;
  late final TextEditingController _saturatedFat;
  late final TextEditingController _fiber;
  late final TextEditingController _calcium;
  late final TextEditingController _iron;
  late final TextEditingController _vitaminC;
  late final TextEditingController _vitaminD;
  late final TextEditingController _zinc;
  late final TextEditingController _magnesium;
  late final TextEditingController _manganese;
  late final TextEditingController _selenium;
  late final TextEditingController _phosphorus;
  late final TextEditingController _copper;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ef = widget.existingFood;
    _name = TextEditingController(text: ef?.name ?? widget.initialName ?? '');
    _brand = TextEditingController(text: ef?.brand ?? '');
    _barcode = TextEditingController(
      text: ef?.barcode ?? widget.initialBarcode ?? '',
    );
    _kcal = TextEditingController(
      text: ef != null ? ef.kcalPer100g.toStringAsFixed(0) : '',
    );
    _protein = TextEditingController(
      text: ef != null ? ef.proteinPer100g.toStringAsFixed(1) : '',
    );
    _carbs = TextEditingController(
      text: ef != null ? ef.carbsPer100g.toStringAsFixed(1) : '',
    );
    _fat = TextEditingController(
      text: ef != null ? ef.fatPer100g.toStringAsFixed(1) : '',
    );
    _servingG = TextEditingController(
      text: ef?.servingGrams != null
          ? ef!.servingGrams!.toStringAsFixed(0)
          : '',
    );
    _sodium = TextEditingController(
      text: ef?.sodiumMgPer100g != null
          ? ef!.sodiumMgPer100g!.toStringAsFixed(0)
          : '',
    );
    _potassium = TextEditingController(
      text: ef?.potassiumMgPer100g != null
          ? ef!.potassiumMgPer100g!.toStringAsFixed(0)
          : '',
    );
    _cholesterol = TextEditingController(
      text: ef?.cholesterolMgPer100g != null
          ? ef!.cholesterolMgPer100g!.toStringAsFixed(0)
          : '',
    );

    // Parse existing sourceMetadataJson if available
    Map<String, dynamic> existingMicros = {};
    if (ef?.sourceMetadataJson != null) {
      try {
        final decoded = jsonDecode(ef!.sourceMetadataJson!);
        if (decoded is Map && decoded['nutrients'] is Map) {
          existingMicros = Map<String, dynamic>.from(decoded['nutrients']);
        }
      } catch (_) {}
    }

    String fmt(String key) {
      final val = existingMicros[key];
      if (val is num) return val.toString();
      return '';
    }

    _sugars = TextEditingController(text: fmt('sugars'));
    _transFat = TextEditingController(text: fmt('trans_fat'));
    _saturatedFat = TextEditingController(text: fmt('saturated_fat'));
    _fiber = TextEditingController(text: fmt('fiber'));
    _calcium = TextEditingController(text: fmt('calcium'));
    _iron = TextEditingController(text: fmt('iron'));
    _vitaminC = TextEditingController(text: fmt('vitamin_c'));
    _vitaminD = TextEditingController(text: fmt('vitamin_d'));
    _zinc = TextEditingController(text: fmt('zinc'));
    _magnesium = TextEditingController(text: fmt('magnesium'));
    _manganese = TextEditingController(text: fmt('manganese'));
    _selenium = TextEditingController(text: fmt('selenium'));
    _phosphorus = TextEditingController(text: fmt('phosphorus'));
    _copper = TextEditingController(text: fmt('copper'));
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _brand,
      _barcode,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _servingG,
      _sodium,
      _potassium,
      _cholesterol,
      _sugars,
      _transFat,
      _saturatedFat,
      _fiber,
      _calcium,
      _iron,
      _vitaminC,
      _vitaminD,
      _zinc,
      _magnesium,
      _manganese,
      _selenium,
      _phosphorus,
      _copper,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final kcal = double.tryParse(_kcal.text.trim());
    if (name.isEmpty || kcal == null || kcal <= 0) {
      setState(() => _error = 'Name and kcal/100g are required');
      return;
    }
    final rawBarcode = _barcode.text.trim();
    final normalizedBarcode = rawBarcode.isEmpty
        ? null
        : normalizeBarcode(rawBarcode);
    if (rawBarcode.isNotEmpty && normalizedBarcode == null) {
      setState(
        () =>
            _error = 'Barcode must be a valid EAN-8, UPC-A, EAN-13 or GTIN-14',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final microsMap = <String, double>{};
    void addIfPresent(String key, TextEditingController ctrl) {
      final v = double.tryParse(ctrl.text.trim());
      if (v != null) microsMap[key] = v;
    }
    addIfPresent('sugars', _sugars);
    addIfPresent('trans_fat', _transFat);
    addIfPresent('saturated_fat', _saturatedFat);
    addIfPresent('fiber', _fiber);
    addIfPresent('calcium', _calcium);
    addIfPresent('iron', _iron);
    addIfPresent('vitamin_c', _vitaminC);
    addIfPresent('vitamin_d', _vitaminD);
    addIfPresent('zinc', _zinc);
    addIfPresent('magnesium', _magnesium);
    addIfPresent('manganese', _manganese);
    addIfPresent('selenium', _selenium);
    addIfPresent('phosphorus', _phosphorus);
    addIfPresent('copper', _copper);

    final metadataJson = microsMap.isNotEmpty
        ? jsonEncode({'nutrients': microsMap})
        : widget.existingFood?.sourceMetadataJson;

    final repo = ref.read(nutritionRepositoryProvider);
    final FoodData food;
    if (widget.existingFood != null) {
      food = await repo.updateCustomFood(
        id: widget.existingFood!.id,
        name: name,
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        barcode: normalizedBarcode?.value,
        kcalPer100g: kcal,
        proteinPer100g: double.tryParse(_protein.text.trim()) ?? 0,
        carbsPer100g: double.tryParse(_carbs.text.trim()) ?? 0,
        fatPer100g: double.tryParse(_fat.text.trim()) ?? 0,
        servingGrams: double.tryParse(_servingG.text.trim()),
        referenceBasis: widget.existingFood?.referenceBasis ?? '100 g',
        servingAmount: widget.existingFood?.servingAmount,
        servingUnit: widget.existingFood?.servingUnit,
        sourceMetadataJson: metadataJson,
        sodiumMgPer100g: double.tryParse(_sodium.text.trim()),
        potassiumMgPer100g: double.tryParse(_potassium.text.trim()),
        cholesterolMgPer100g: double.tryParse(_cholesterol.text.trim()),
      );
    } else {
      food = await repo.createCustomFood(
        name: name,
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        barcode: normalizedBarcode?.value,
        kcalPer100g: kcal,
        proteinPer100g: double.tryParse(_protein.text.trim()) ?? 0,
        carbsPer100g: double.tryParse(_carbs.text.trim()) ?? 0,
        fatPer100g: double.tryParse(_fat.text.trim()) ?? 0,
        servingGrams: double.tryParse(_servingG.text.trim()),
        sourceMetadataJson: metadataJson,
        sodiumMgPer100g: double.tryParse(_sodium.text.trim()),
        potassiumMgPer100g: double.tryParse(_potassium.text.trim()),
        cholesterolMgPer100g: double.tryParse(_cholesterol.text.trim()),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(food);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existingFood != null;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
            Text(
              isEditing ? 'Edit custom food' : 'Custom food',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'All values per 100 g/ml',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 24),
            _Field(label: 'Name *', controller: _name),
            const SizedBox(height: 14),
            _Field(label: 'Brand', controller: _brand),
            const SizedBox(height: 14),
            _Field(label: 'Barcode (optional)', controller: _barcode),
            const SizedBox(height: 14),
            _Field(label: 'kcal / 100g *', controller: _kcal, numeric: true),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: 'Protein g',
                    controller: _protein,
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: 'Carbs g',
                    controller: _carbs,
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: 'Fat g',
                    controller: _fat,
                    numeric: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Default serving (g)',
              controller: _servingG,
              numeric: true,
            ),
            const SizedBox(height: 20),
            Text(
              'MINERALS (optional, per 100g)',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: 'Sodium mg',
                    controller: _sodium,
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: 'Potassium mg',
                    controller: _potassium,
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: 'Cholesterol mg',
                    controller: _cholesterol,
                    numeric: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Additional Nutrients (Sugars, Fats, Vitamins…)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Sugars g',
                          controller: _sugars,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Fiber g',
                          controller: _fiber,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Saturated Fat g',
                          controller: _saturatedFat,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Trans Fat g',
                          controller: _transFat,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Calcium mg',
                          controller: _calcium,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Iron mg',
                          controller: _iron,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Vitamin C mg',
                          controller: _vitaminC,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Vitamin D µg',
                          controller: _vitaminD,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Zinc mg',
                          controller: _zinc,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Magnesium mg',
                          controller: _magnesium,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Manganese mg',
                          controller: _manganese,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Selenium µg',
                          controller: _selenium,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Phosphorus mg',
                          controller: _phosphorus,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Copper mg',
                          controller: _copper,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 28),
            PremiumButton(
              text: _saving ? 'Saving…' : 'Save food',
              onTap: _saving ? () {} : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool numeric;
  const _Field({
    required this.label,
    required this.controller,
    this.numeric = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.secondary,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: numeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
              : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceContainer,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
