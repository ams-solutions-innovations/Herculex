import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/measurements/presentation/weight_picker_sheet.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:intl/intl.dart';

/// Shared bodyweight quick-log dialog, used by the dashboard's bodyweight
/// card and the global quick-add menu so both stay in sync.
Future<void> quickLogWeight(BuildContext context, WidgetRef ref) async {
  final fmt = ref.read(weightFormatProvider);
  final latestKg = await ref.read(latestBodyweightProvider.future);
  final profile = ref.read(profileProvider).valueOrNull;
  final initialKg = latestKg ?? profile?.weightKg;

  if (!context.mounted) return;
  final value = await WeightPickerSheet.show(
    context,
    initialKg: initialKg,
    previousKg: latestKg,
  );

  if (value != null && value > 0) {
    Haptics.medium();
    final dateIso = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await ref
        .read(measurementsRepositoryProvider)
        .logMeasurement(dateIso: dateIso, metric: 'bodyweight', value: value);
    ref.invalidate(latestBodyweightProvider);
    AppNotice.showWith(
      ref,
      fmt.format(value),
      title: 'Weight logged',
      kind: AppNoticeKind.info,
    );
  }
}
