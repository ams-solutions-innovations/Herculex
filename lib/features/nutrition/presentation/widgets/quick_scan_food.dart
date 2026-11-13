import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/features/nutrition/application/meal_slots_provider.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/domain/barcode_utils.dart';
import 'package:herculex/features/nutrition/presentation/sheets/log_entry_sheet.dart';
import 'package:herculex/features/nutrition/presentation/views/barcode_scanner_view.dart';
import 'package:herculex/features/nutrition/presentation/widgets/barcode_resolution_flow.dart';

/// Scan a barcode and log it to today's food diary in one flow: scan → look
/// up → (create a custom food if unknown) → log entry sheet.
///
/// Shared by the dashboard's quick-scan card and the global quick-add menu.
Future<void> scanAndLogFood(BuildContext context, WidgetRef ref) async {
  final scanned = await BarcodeScannerView.show(context);
  if (scanned == null || !context.mounted) return;
  final normalized = normalizeBarcode(scanned);
  if (normalized == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Barcode not recognized. Please try again.'),
      ),
    );
    return;
  }
  final code = normalized.value;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  FoodData? food;
  Object? lookupError;
  try {
    food = await ref
        .read(nutritionRepositoryProvider)
        .lookupBarcode(code)
        .timeout(const Duration(seconds: 15));
  } catch (error) {
    // A local catalogue or network error should not strand the scan behind
    // an endless spinner; let the user continue through the unknown-product
    // flow and enter the food manually if necessary.
    lookupError = error;
  } finally {
    if (context.mounted) Navigator.of(context).pop();
  }

  if (!context.mounted) return;
  if (lookupError != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not check the food database. Continue below.'),
      ),
    );
  }

  // Resolve an unknown product before asking where to log it. This keeps the
  // photo/manual fallback visible immediately after an unsuccessful scan.
  food ??= await resolveUnknownBarcode(context, ref, code);
  if (food == null || !context.mounted) return;

  final mealSlots = ref.read(mealSlotsProvider);
  final mealKey = await showHxPicker<String>(
    context,
    title: 'Select meal',
    selected: '',
    options: [
      for (final meal in mealSlots)
        HxPickerOption(value: meal.key, label: meal.label, icon: meal.icon),
    ],
  );
  if (mealKey == null || !context.mounted) return;

  await LogEntrySheet.forFood(
    context,
    food: food,
    date: DateUtils.dateOnly(DateTime.now()),
    initialMealKey: mealKey,
  );
}
