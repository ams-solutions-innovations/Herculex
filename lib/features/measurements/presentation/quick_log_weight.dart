import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/units.dart';
import '../../../theme/haptics.dart';
import '../../workouts/presentation/workouts_providers.dart';

/// Shared bodyweight quick-log dialog, used by the dashboard's bodyweight
/// card and the global quick-add menu so both stay in sync.
Future<void> quickLogWeight(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final fmt = ref.read(weightFormatProvider);
  final value = await showDialog<double>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Quick Log Bodyweight'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Weight',
          suffixText: fmt.suffix,
          hintText: fmt.isMetric ? 'e.g. 75.5' : 'e.g. 166',
        ),
        onSubmitted: (v) => Navigator.pop(dialogCtx, double.tryParse(v)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogCtx, double.tryParse(ctrl.text)),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (value != null && value > 0) {
    Haptics.medium();
    final dateIso = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await ref.read(measurementsRepositoryProvider).logMeasurement(
          dateIso: dateIso,
          metric: 'bodyweight',
          // Measurements are stored in kilograms regardless of display unit.
          value: fmt.toKg(value),
        );
    ref.invalidate(latestBodyweightProvider);
  }
}
