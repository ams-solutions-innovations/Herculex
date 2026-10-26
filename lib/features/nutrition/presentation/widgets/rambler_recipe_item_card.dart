import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';

class RamblerRecipeItemCard extends StatelessWidget {
  final RamblerFoodItem item;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  const RamblerRecipeItemCard({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hx.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hx.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.name,
                  onChanged: (val) {
                    item.name = val;
                    onChanged();
                  },
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    fillColor: Colors.transparent,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red.shade300,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Haptics.selection();
                  onDelete();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Amount:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: hx.secondary,
                ),
              ),
              const SizedBox(width: 8),
              _gramButton(
                hx: hx,
                icon: Icons.remove,
                onTap: () {
                  if (item.servingGrams > 10) {
                    Haptics.selection();
                    item.servingGrams -= 25;
                    if (item.servingGrams < 10) item.servingGrams = 10;
                    item.portionAmount = item.servingGrams;
                    onChanged();
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '${item.servingGrams.toStringAsFixed(0)} ${item.portionUnit}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: hx.primary,
                  ),
                ),
              ),
              _gramButton(
                hx: hx,
                icon: Icons.add,
                onTap: () {
                  Haptics.selection();
                  item.servingGrams += 25;
                  item.portionAmount = item.servingGrams;
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.macroKcal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${item.totalKcal.round()} kcal',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.macroKcal,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _macroPill('P', '${item.totalProtein.toStringAsFixed(1)}g', AppColors.macroProtein),
              const SizedBox(width: 6),
              _macroPill('C', '${item.totalCarbs.toStringAsFixed(1)}g', AppColors.macroCarbs),
              const SizedBox(width: 6),
              _macroPill('F', '${item.totalFat.toStringAsFixed(1)}g', AppColors.macroFat),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gramButton({
    required HxColors hx,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: hx.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: hx.onSurface),
      ),
    );
  }

  Widget _macroPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
