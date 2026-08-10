import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/units.dart';
import '../../../theme/colors.dart';

/// Result of the Down Set auto-fill wizard: a weight held constant across
/// the chain, plus the rep range it should decrement through (inclusive).
class DownSetChainResult {
  final double weightKg;
  final int firstReps;
  final int stopReps;
  const DownSetChainResult({
    required this.weightKg,
    required this.firstReps,
    required this.stopReps,
  });
}

/// Bottom sheet opened by long-pressing a set already marked "Down Sets".
/// Since every extra set drops one rep at the same weight, the rep range
/// alone determines the chain length — no separate "number of sets" field.
class DownSetConfigSheet extends ConsumerStatefulWidget {
  final double initialWeightKg;
  final int initialReps;

  const DownSetConfigSheet({
    super.key,
    required this.initialWeightKg,
    required this.initialReps,
  });

  static Future<DownSetChainResult?> show(
    BuildContext context, {
    required double initialWeightKg,
    required int initialReps,
  }) {
    return showModalBottomSheet<DownSetChainResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DownSetConfigSheet(
        initialWeightKg: initialWeightKg,
        initialReps: initialReps,
      ),
    );
  }

  @override
  ConsumerState<DownSetConfigSheet> createState() =>
      _DownSetConfigSheetState();
}

class _DownSetConfigSheetState extends ConsumerState<DownSetConfigSheet> {
  late final TextEditingController _weight;
  late final TextEditingController _firstReps;
  late final TextEditingController _stopReps;

  WeightFormat get _fmt => ref.read(weightFormatProvider);

  @override
  void initState() {
    super.initState();
    _weight = TextEditingController(
      text: widget.initialWeightKg > 0
          ? _fmt.formatValue(widget.initialWeightKg)
          : '0',
    );
    _firstReps = TextEditingController(
      text: widget.initialReps > 0 ? widget.initialReps.toString() : '',
    );
    _stopReps = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _weight.dispose();
    _firstReps.dispose();
    _stopReps.dispose();
    super.dispose();
  }

  void _apply() {
    final weight = double.tryParse(_weight.text);
    final firstReps = int.tryParse(_firstReps.text);
    final stopReps = int.tryParse(_stopReps.text) ?? 1;
    if (weight == null || firstReps == null || firstReps < 1) return;
    final clampedStop = stopReps < 1
        ? 1
        : (stopReps > firstReps ? firstReps : stopReps);
    Navigator.of(context).pop(
      DownSetChainResult(
        weightKg: _fmt.toKg(weight),
        firstReps: firstReps,
        stopReps: clampedStop,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = _fmt.suffix.toUpperCase();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color:
              theme.bottomSheetTheme.backgroundColor ??
              AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Auto-Fill Down Sets',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Same weight every set; reps drop by 1 each time',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 20),
            _field(label: 'Weight ($unit)', controller: _weight),
            const SizedBox(height: 12),
            _field(label: 'First Set Reps', controller: _firstReps),
            const SizedBox(height: 12),
            _field(
              label: 'Stop At Reps (default 1)',
              controller: _stopReps,
              hint: '1',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('Auto-Fill'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
