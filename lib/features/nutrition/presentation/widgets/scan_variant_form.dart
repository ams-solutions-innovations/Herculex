import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/hx_pill.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/nutrition/domain/nutrition_label.dart';

/// Editable text fields for one [NutritionVariant] of a scanned product.
///
/// Both scan review dialogs hold one of these per variant, so switching
/// between "drained" and "not drained" keeps what the user already edited.
class ScanVariantFields {
  ScanVariantFields(
    NutritionVariant variant, {
    double fallbackAmount = 100,
    String fallbackUnit = 'g',
  }) : label = variant.label,
       portion = TextEditingController(
         text: _text(variant.portionAmount ?? fallbackAmount, 1),
       ),
       unit = TextEditingController(
         text: variant.servingUnit.trim().isEmpty
             ? fallbackUnit
             : variant.servingUnit,
       ),
       grams = TextEditingController(text: _text(variant.servingGrams, 0)),
       kcal = TextEditingController(text: _text(variant.kcalPer100g, 0)),
       protein = TextEditingController(text: _text(variant.proteinPer100g, 1)),
       carbs = TextEditingController(text: _text(variant.carbsPer100g, 1)),
       fat = TextEditingController(text: _text(variant.fatPer100g, 1)),
       fiber = TextEditingController(text: _text(variant.fiberPer100g, 1)),
       sodium = TextEditingController(text: _text(variant.sodiumMgPer100g, 0));

  final String? label;
  final TextEditingController portion;
  final TextEditingController unit;
  final TextEditingController grams;
  final TextEditingController kcal;
  final TextEditingController protein;
  final TextEditingController carbs;
  final TextEditingController fat;
  final TextEditingController fiber;
  final TextEditingController sodium;

  List<TextEditingController> get _all => [
    portion,
    unit,
    grams,
    kcal,
    protein,
    carbs,
    fat,
    fiber,
    sodium,
  ];

  void dispose() {
    for (final controller in _all) {
      controller.dispose();
    }
  }

  double? get servingGrams => _parse(grams);
  double get portionAmount => _parse(portion) ?? 1;
  String get portionUnit => unit.text.trim().isEmpty ? 'g' : unit.text.trim();
  double? get kcalPer100g => _parse(kcal);
  double get proteinPer100g => _parse(protein) ?? 0;
  double get carbsPer100g => _parse(carbs) ?? 0;
  double get fatPer100g => _parse(fat) ?? 0;
  double? get fiberPer100g => _parse(fiber);
  double? get sodiumMgPer100g => _parse(sodium);

  static double? _parse(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  /// Whole numbers without a trailing ".0"; null becomes an empty field.
  static String _text(double? value, int fractionDigits) {
    if (value == null) return '';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(fractionDigits);
  }
}

/// Serving, calories and macro fields for one variant.
class ScanVariantForm extends StatelessWidget {
  const ScanVariantForm({super.key, required this.fields});

  final ScanVariantFields fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _field(
                'Serving quantity',
                fields.portion,
                numeric: true,
                suffix: '×',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _field('Measure (scoop, bar…)', fields.unit)),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _field(
                'Serving (g)',
                fields.grams,
                numeric: true,
                suffix: 'g',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field(
                'kcal / 100 g',
                fields.kcal,
                numeric: true,
                suffix: 'kcal',
              ),
            ),
          ],
        ),
        Text(
          'Macronutrients / 100 g',
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _field(
                'Protein',
                fields.protein,
                numeric: true,
                suffix: 'g',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field('Carbs', fields.carbs, numeric: true, suffix: 'g'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field('Fat', fields.fat, numeric: true, suffix: 'g'),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _field('Fiber', fields.fiber, numeric: true, suffix: 'g'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                'Sodium',
                fields.sodium,
                numeric: true,
                suffix: 'mg',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
    String? suffix,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        filled: true,
        fillColor: AppColors.surfaceContainer,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

/// Pill row to choose which variant of a product is being edited and logged.
class ScanVariantChips extends StatelessWidget {
  const ScanVariantChips({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This label has ${labels.length} nutrition tables. '
          'Choose the one to log; all of them are saved as foods.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.secondary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < labels.length; i++)
              HxTextPill(
                label: labels[i],
                selected: i == selected,
                onTap: () => onSelected(i),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
