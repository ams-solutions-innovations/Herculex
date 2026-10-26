import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';

class RamblerRecipeSummaryCard extends StatefulWidget {
  final List<RamblerFoodItem> items;
  final int servings;
  final ValueChanged<int> onServingsChanged;

  const RamblerRecipeSummaryCard({
    super.key,
    required this.items,
    required this.servings,
    required this.onServingsChanged,
  });

  @override
  State<RamblerRecipeSummaryCard> createState() =>
      _RamblerRecipeSummaryCardState();
}

class _RamblerRecipeSummaryCardState extends State<RamblerRecipeSummaryCard> {
  bool _showPerServing = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    final totalGrams =
        widget.items.fold<double>(0, (s, i) => s + i.servingGrams);
    final totalKcal = widget.items.fold<double>(0, (s, i) => s + i.totalKcal);
    final totalP = widget.items.fold<double>(0, (s, i) => s + i.totalProtein);
    final totalC = widget.items.fold<double>(0, (s, i) => s + i.totalCarbs);
    final totalF = widget.items.fold<double>(0, (s, i) => s + i.totalFat);

    final servings = widget.servings > 0 ? widget.servings : 1;
    final perServingGrams =
        servings > 0 ? (totalGrams / servings).round() : totalGrams.round();
    final displayKcal = _showPerServing ? totalKcal / servings : totalKcal;
    final displayP = _showPerServing ? totalP / servings : totalP;
    final displayC = _showPerServing ? totalC / servings : totalC;
    final displayF = _showPerServing ? totalF / servings : totalF;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Servings',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: hx.secondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: hx.surfaceContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: hx.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 18),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            if (widget.servings > 1) {
                              Haptics.selection();
                              widget.onServingsChanged(widget.servings - 1);
                            }
                          },
                        ),
                        Expanded(
                          child: Text(
                            '${widget.servings} ${widget.servings == 1 ? 'serving' : 'servings'}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            Haptics.selection();
                            widget.onServingsChanged(widget.servings + 1);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Serving Size',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: hx.secondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: hx.surfaceContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: hx.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '~$perServingGrams g / serving',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: hx.primary,
                          ),
                        ),
                        Text(
                          '${totalGrams.round()}g total recipe',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: hx.secondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hx.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hx.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: hx.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.pie_chart_outline_rounded,
                          size: 16,
                          color: hx.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _showPerServing
                            ? 'Nutrition Per Serving'
                            : 'Total Recipe Nutrition',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Per serving',
                            style: TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('Total', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    selected: {_showPerServing},
                    onSelectionChanged: (val) {
                      setState(() => _showPerServing = val.first);
                    },
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _macroCell(
                    'Calories',
                    '${displayKcal.round()} kcal',
                    AppColors.macroKcal,
                  ),
                  _macroCell(
                    'Protein',
                    '${displayP.toStringAsFixed(1)}g',
                    AppColors.macroProtein,
                  ),
                  _macroCell(
                    'Carbs',
                    '${displayC.toStringAsFixed(1)}g',
                    AppColors.macroCarbs,
                  ),
                  _macroCell(
                    'Fat',
                    '${displayF.toStringAsFixed(1)}g',
                    AppColors.macroFat,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _macroCell(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppColors.secondary),
        ),
      ],
    );
  }
}
