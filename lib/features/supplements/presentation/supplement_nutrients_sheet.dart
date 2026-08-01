import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/colors.dart';
import '../../nutrition/domain/nutrient_definitions.dart';

/// Lets the user say what one dose of a supplement contains, in the same
/// nutrient vocabulary the food diary uses — so a 5 g creatine scoop or a
/// 2 g omega-3 capsule lands in the day's micronutrient totals (§4).
class SupplementNutrientsSheet extends StatefulWidget {
  final Map<String, double> initial;

  const SupplementNutrientsSheet({super.key, required this.initial});

  /// Returns the edited map, or null when the user backs out.
  static Future<Map<String, double>?> show(
    BuildContext context,
    Map<String, double> initial,
  ) {
    return showModalBottomSheet<Map<String, double>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupplementNutrientsSheet(initial: initial),
    );
  }

  @override
  State<SupplementNutrientsSheet> createState() =>
      _SupplementNutrientsSheetState();
}

class _SupplementNutrientsSheetState extends State<SupplementNutrientsSheet> {
  /// One controller per tracked nutrient, so switching between fields never
  /// loses a half-typed value.
  late final Map<String, TextEditingController> _controllers = {
    for (final d in trackedNutrients)
      d.id: TextEditingController(
        text: widget.initial[d.id] == null ? '' : _fmt(widget.initial[d.id]!),
      ),
  };

  /// Only nutrients with a value are shown by default; the rest live behind
  /// "Add nutrient" so the sheet doesn't open as a wall of twenty fields.
  late final Set<String> _shown = {
    for (final d in trackedNutrients)
      if ((widget.initial[d.id] ?? 0) > 0) d.id,
  };

  static String _fmt(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final out = <String, double>{};
    for (final d in trackedNutrients) {
      if (!_shown.contains(d.id)) continue;
      final value = double.tryParse(_controllers[d.id]!.text.trim());
      if (value != null && value > 0) out[d.id] = value;
    }
    Navigator.of(context).pop(out);
  }

  Future<void> _addNutrient() async {
    final remaining = [
      for (final d in trackedNutrients)
        if (!_shown.contains(d.id)) d,
    ];
    if (remaining.isEmpty) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final d in remaining)
              ListTile(
                title: Text(d.label),
                trailing: Text(d.unit,
                    style: TextStyle(color: AppColors.secondary)),
                onTap: () => Navigator.of(context).pop(d.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _shown.add(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [
      for (final d in trackedNutrients)
        if (_shown.contains(d.id)) d,
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
              24, 16, 24, MediaQuery.viewInsetsOf(context).bottom + 28),
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
            Text('Per dose',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'What one dose contains. These amounts are added to your daily '
              'nutrient totals each time you tick the supplement off.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 20),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No nutrients yet — add the ones listed on the label.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.secondary),
                ),
              )
            else
              for (final d in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(d.label, style: theme.textTheme.bodyMedium),
                      ),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _controllers[d.id],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          ],
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.surfaceContainer,
                            suffixText: d.unit,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Remove',
                        onPressed: () => setState(() {
                          _shown.remove(d.id);
                          _controllers[d.id]!.clear();
                        }),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _addNutrient,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add nutrient'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.4)),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: const StadiumBorder(),
              ),
              child: const Text('Done',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
