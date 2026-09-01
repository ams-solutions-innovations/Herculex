import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/notifications/toast/hx_toast_controller.dart';
import 'package:herculex/core/notifications/toast/hx_toast_model.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';
import 'package:intl/intl.dart';

/// Shared bodyweight quick-log dialog, used by the dashboard's bodyweight
/// card and the global quick-add menu so both stay in sync.
Future<void> quickLogWeight(BuildContext context, WidgetRef ref) async {
  final fmt = ref.read(weightFormatProvider);
  final latestKg = await ref.read(latestBodyweightProvider.future);
  final profile = ref.read(profileProvider).valueOrNull;
  final initialKg = latestKg ?? profile?.weightKg;

  final initialText = initialKg != null ? fmt.formatValue(initialKg) : '';
  final ctrl = TextEditingController(text: initialText);
  if (initialText.isNotEmpty) {
    ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: initialText.length,
    );
  }
  if (!context.mounted) return;
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
    await ref
        .read(measurementsRepositoryProvider)
        .logMeasurement(
          dateIso: dateIso,
          metric: 'bodyweight',
          // Measurements are stored in kilograms regardless of display unit.
          value: fmt.toKg(value),
        );
    ref.invalidate(latestBodyweightProvider);
    ref
        .read(hxToastControllerProvider.notifier)
        .show(
          HxToastItem.weightLogged(
            weightFormatted: fmt.format(fmt.toKg(value)),
          ),
        );
  }
}
