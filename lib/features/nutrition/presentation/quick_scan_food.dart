import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/barcode_utils.dart';
import 'barcode_scanner_view.dart';
import 'custom_food_form_sheet.dart';
import 'log_entry_sheet.dart';
import 'nutrition_providers.dart';

/// Scan a barcode and log it to today's food diary in one flow: scan → look
/// up → (create a custom food if unknown) → log entry sheet.
///
/// Shared by the dashboard's quick-scan card and the global quick-add menu.
Future<void> scanAndLogFood(BuildContext context, WidgetRef ref) async {
  final scanned = await BarcodeScannerView.show(context);
  if (scanned == null || !context.mounted) return;
  final normalized = normalizeBarcode(scanned);
  if (normalized == null) return;
  final code = normalized.value;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  final food = await ref.read(nutritionRepositoryProvider).lookupBarcode(code);

  if (!context.mounted) return;
  Navigator.of(context).pop();

  final today = DateUtils.dateOnly(DateTime.now());
  if (food == null) {
    final created =
        await CustomFoodFormSheet.show(context, initialBarcode: code);
    if (created != null && context.mounted) {
      await LogEntrySheet.forFood(
        context,
        food: created,
        date: today,
        initialMealKey: 'snack',
      );
    }
  } else {
    await LogEntrySheet.forFood(
      context,
      food: food,
      date: today,
      initialMealKey: 'snack',
    );
  }
}
