import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';

class RamblerRecipeEditDialog extends StatefulWidget {
  final RamblerFoodItem item;

  const RamblerRecipeEditDialog({super.key, required this.item});

  static Future<bool?> show(BuildContext context, RamblerFoodItem item) {
    return showDialog<bool>(
      context: context,
      builder: (_) => RamblerRecipeEditDialog(item: item),
    );
  }

  @override
  State<RamblerRecipeEditDialog> createState() =>
      _RamblerRecipeEditDialogState();
}

class _RamblerRecipeEditDialogState extends State<RamblerRecipeEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _gramsCtrl;
  late final TextEditingController _kcalCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _carbsCtrl;
  late final TextEditingController _fatCtrl;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameCtrl = TextEditingController(text: item.name);
    _gramsCtrl =
        TextEditingController(text: item.servingGrams.toStringAsFixed(0));
    _kcalCtrl =
        TextEditingController(text: item.kcalPer100g.toStringAsFixed(0));
    _proteinCtrl =
        TextEditingController(text: item.proteinPer100g.toStringAsFixed(1));
    _carbsCtrl =
        TextEditingController(text: item.carbsPer100g.toStringAsFixed(1));
    _fatCtrl =
        TextEditingController(text: item.fatPer100g.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _gramsCtrl.dispose();
    _kcalCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final item = widget.item;
    item.name =
        _nameCtrl.text.trim().isEmpty ? item.name : _nameCtrl.text.trim();
    final g = double.tryParse(_gramsCtrl.text.trim()) ?? item.servingGrams;
    item.servingGrams = g > 0 ? g : 10;
    item.portionAmount = item.servingGrams;
    item.kcalPer100g =
        double.tryParse(_kcalCtrl.text.trim()) ?? item.kcalPer100g;
    item.proteinPer100g =
        double.tryParse(_proteinCtrl.text.trim()) ?? item.proteinPer100g;
    item.carbsPer100g =
        double.tryParse(_carbsCtrl.text.trim()) ?? item.carbsPer100g;
    item.fatPer100g =
        double.tryParse(_fatCtrl.text.trim()) ?? item.fatPer100g;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: hx.surfaceContainer,
      title: Text(
        'Edit Ingredient Nutrition',
        style:
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Ingredient Name',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gramsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (g)',
                suffixText: 'g',
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nutritional Values (per 100g)',
              style: theme.textTheme.labelMedium?.copyWith(
                color: hx.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _kcalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Calories',
                      suffixText: 'kcal',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _proteinCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Protein',
                      suffixText: 'g',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _carbsCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Carbs',
                      suffixText: 'g',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _fatCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Fat',
                      suffixText: 'g',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: hx.primary,
            shape: const StadiumBorder(),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
