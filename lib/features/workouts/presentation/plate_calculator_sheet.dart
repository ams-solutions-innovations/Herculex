import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/units.dart';
import '../../../features/profile/domain/profile.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';

/// Available barbell types (weight in kg).
enum BarType {
  olympic(20, 'Olympic (20 kg)'),
  womens(15, "Women's (15 kg)"),
  ez(10, 'EZ-Curl (10 kg)'),
  trap(25, 'Trap Bar (25 kg)'),
  none(0, 'No Bar / Machine');

  final double weightKg;
  final String label;
  const BarType(this.weightKg, this.label);
}

/// Standard plate denominations in kg (heaviest first).
const _platesKg = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25, 0.5, 0.25];
const _platesLb = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5, 1.25];

// ── Plate colour mapping ────────────────────────────────────────────────────
final _plateColorsKg = <double, Color>{
  25.0: const Color(0xFFE53935), // red
  20.0: const Color(0xFF1E88E5), // blue
  15.0: const Color(0xFFFFB300), // yellow
  10.0: const Color(0xFF43A047), // green
  5.0: const Color(0xFF757575), // grey
  2.5: const Color(0xFF757575),
  1.25: const Color(0xFF37474F),
  0.5: const Color(0xFF78909C),
  0.25: const Color(0xFF90A4AE),
};
final _plateColorsLb = <double, Color>{
  45.0: const Color(0xFF1E88E5),
  35.0: const Color(0xFFFFB300),
  25.0: const Color(0xFFE53935),
  10.0: const Color(0xFF43A047),
  5.0: const Color(0xFF757575),
  2.5: const Color(0xFF757575),
  1.25: const Color(0xFF37474F),
};

class PlateCalculatorSheet extends ConsumerStatefulWidget {
  /// Pre-filled target weight in kg (from the active set field). May be null.
  final double? initialWeightKg;

  const PlateCalculatorSheet({super.key, this.initialWeightKg});

  static Future<void> show(BuildContext context, {double? weightKg}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlateCalculatorSheet(initialWeightKg: weightKg),
    );
  }

  @override
  ConsumerState<PlateCalculatorSheet> createState() =>
      _PlateCalculatorSheetState();
}

class _PlateCalculatorSheetState extends ConsumerState<PlateCalculatorSheet> {
  late final TextEditingController _ctrl;
  BarType _bar = BarType.olympic;

  @override
  void initState() {
    super.initState();
    final fmt = ref.read(weightFormatProvider);
    final initVal = widget.initialWeightKg;
    _ctrl = TextEditingController(
      text: initVal != null && initVal > 0 ? fmt.formatValue(initVal) : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isMetric => ref.read(unitsProvider) == MeasurementUnit.metric;

  /// Returns a map of plate → count per side.
  Map<double, int> _calculate(double totalKg) {
    final barKg = _bar.weightKg;
    var remaining = (totalKg - barKg) / 2;
    if (remaining <= 0) return {};

    final plates = _isMetric ? _platesKg : _platesLb;
    // Convert remaining to display unit if imperial
    if (!_isMetric) {
      remaining = remaining / 0.45359237;
    }

    final result = <double, int>{};
    for (final plate in plates) {
      if (remaining <= 0) break;
      final count = (remaining / plate).floor();
      if (count > 0) {
        result[plate] = count;
        remaining -= count * plate;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = ref.watch(weightFormatProvider);
    final bottomPad = MediaQuery.of(context).padding.bottom + 12;
    final suffix = fmt.suffix;

    final raw = double.tryParse(_ctrl.text);
    // Convert display value to kg for calculation.
    final totalKg = raw != null ? fmt.toKg(raw) : null;
    final plates = totalKg != null ? _calculate(totalKg) : <double, int>{};
    final barKg = _bar.weightKg;
    final barDisplay = _isMetric ? barKg : barKg / 0.45359237;
    final platesColors = _isMetric ? _plateColorsKg : _plateColorsLb;

    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        padding: EdgeInsets.only(bottom: bottomPad),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: AppColors.outlineVariant),
          ),
        ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Icon(Icons.fitness_center_outlined,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Plate Calculator',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.outlineVariant),
            // Bar selector
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BAR TYPE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: BarType.values.map((b) {
                        final selected = b == _bar;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              Haptics.light();
                              setState(() => _bar = b);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.outlineVariant,
                                ),
                              ),
                              child: Text(
                                b.label,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: selected
                                      ? Colors.white
                                      : AppColors.onSurfaceVariant,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Target weight input
                  Text(
                    'TARGET WEIGHT',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ctrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: theme.textTheme.headlineMedium?.copyWith(
                        color: AppColors.secondary.withValues(alpha: 0.5),
                      ),
                      suffixText: suffix,
                      suffixStyle: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.secondary,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  // Bar weight hint
                  if (_bar != BarType.none)
                    Text(
                      'Bar: ${barDisplay.toStringAsFixed(barDisplay.truncateToDouble() == barDisplay ? 0 : 1)} $suffix  •  '
                      'Each side: ${totalKg != null && totalKg > barKg ? _fmtSide(totalKg, fmt) : "—"}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: AppColors.outlineVariant),
            // Plates result
            if (totalKg != null && totalKg > barKg && plates.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  'PLATES PER SIDE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              // Visual plate stack
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _PlateStack(plates: plates, colors: platesColors),
              ),
              const SizedBox(height: 12),
              // Plate list
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  children: plates.entries.map((e) {
                    final col = platesColors[e.key] ?? AppColors.secondary;
                    final plateDisplay = _isMetric
                        ? e.key
                        : e.key; // already in display unit
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: col,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${_fmtPlate(plateDisplay)} $suffix',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '× ${e.value}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ] else if (totalKg != null && plates.isEmpty && totalKg > 0) ...[
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  totalKg <= barKg
                      ? 'Bar only — no plates needed'
                      : 'Cannot be loaded with standard plates',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    ),
    );
  }

  String _fmtSide(double totalKg, WeightFormat fmt) {
    final side = (totalKg - _bar.weightKg) / 2;
    if (_isMetric) {
      return '${_fmtPlate(side)} kg';
    } else {
      final sideLb = side / 0.45359237;
      return '${_fmtPlate(sideLb)} lb';
    }
  }

  String _fmtPlate(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

// ── Visual plate stack ──────────────────────────────────────────────────────

class _PlateStack extends StatelessWidget {
  final Map<double, int> plates;
  final Map<double, Color> colors;

  const _PlateStack({required this.plates, required this.colors});

  @override
  Widget build(BuildContext context) {
    // Expand to individual plate list (e.g. 2×25 → [25, 25]).
    final expanded = <double>[];
    for (final e in plates.entries) {
      for (var i = 0; i < e.value; i++) {
        expanded.add(e.key);
      }
    }

    // Bar line + plates laid out horizontally.
    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left half of bar
          Container(
            width: 40,
            height: 6,
            color: AppColors.outline,
          ),
          // Plates left → right (first = nearest bar, last = outermost)
          ...expanded.map((p) {
            final col = colors[p] ?? AppColors.secondary;
            final h = _plateHeight(p);
            return Container(
              width: 14,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: col,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
          // Center sleeve
          Container(
            width: 18,
            height: 8,
            color: AppColors.secondary,
          ),
          // Mirror
          ...expanded.reversed.map((p) {
            final col = colors[p] ?? AppColors.secondary;
            final h = _plateHeight(p);
            return Container(
              width: 14,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: col,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
          // Right half of bar
          Container(
            width: 40,
            height: 6,
            color: AppColors.outline,
          ),
        ],
      ),
    );
  }

  double _plateHeight(double kg) {
    if (kg >= 25) return 56;
    if (kg >= 20) return 50;
    if (kg >= 15) return 44;
    if (kg >= 10) return 38;
    if (kg >= 5) return 32;
    if (kg >= 2.5) return 26;
    return 20;
  }
}
