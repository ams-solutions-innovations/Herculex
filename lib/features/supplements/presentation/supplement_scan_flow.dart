import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/nutrition/domain/barcode_utils.dart';
import 'package:herculex/features/nutrition/presentation/views/barcode_scanner_view.dart';
import 'package:herculex/features/supplements/application/supplement_providers.dart';
import 'package:herculex/features/supplements/data/supplement_catalogue_repository.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/presentation/supplement_ai_scan_dialog.dart';
import 'package:herculex/features/supplements/presentation/supplement_edit_sheet.dart';
import 'package:uuid/uuid.dart';

/// Unified supplement barcode + AI scan flow, mirroring food scanning:
/// 1. Opens the barcode scanner (with an option to jump to AI photo scan if
///    the tub has no barcode).
/// 2. Looks up the scanned barcode across the Supplement Database (local
///    catalogue, built-in supplement database, local Drift foods, shared
///    Supabase `product_catalogue`, and OpenFoodFacts).
/// 3. If found in the database, returns the matched supplement immediately
///    without calling AI.
/// 4. Only if the barcode is not found in the database, prompts/launches the
///    Herculex AI photo analysis with the barcode attached.
Future<SupplementLookupResult?> scanAndResolveSupplement(
  BuildContext context,
  WidgetRef ref,
) async {
  final scanned = await BarcodeScannerView.show(
    context,
    aiFallbackLabel: 'No barcode? AI photo analysis',
  );
  if (scanned == null || !context.mounted) return null;

  // User explicitly chose AI photo scan because package has no barcode.
  if (scanned == BarcodeScannerView.aiFallbackResult) {
    final aiResult = await SupplementAiScanDialog.show(context);
    if (aiResult == null) return null;
    final supp = aiResult.toSupplement(id: const Uuid().v4());
    await ref
        .read(supplementCatalogueRepositoryProvider)
        .saveToLocalCatalogue(supp);
    return SupplementLookupResult(
      supplement: supp,
      sourceLabel: 'Herculex AI analysis',
    );
  }

  final normalized = normalizeBarcode(scanned);
  final code = normalized?.value ?? scanned.trim();
  if (code.isEmpty) return null;

  // Show loading indicator during database lookup.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9B59B6)),
      ),
    ),
  );

  SupplementLookupResult? found;
  try {
    found = await ref
        .read(supplementCatalogueRepositoryProvider)
        .lookupByBarcode(code);
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  if (!context.mounted) return null;

  // Hit in the supplement database — no AI analysis needed!
  if (found != null) {
    return found;
  }

  // Miss in database → offer AI analysis just like food barcode scanning.
  final wantsAiPhoto = await _confirmSupplementAiPrompt(context, code);
  if (!context.mounted) return null;

  if (wantsAiPhoto == true) {
    final aiResult = await SupplementAiScanDialog.show(context, barcode: code);
    if (aiResult != null) {
      final supp = aiResult.toSupplement(id: const Uuid().v4(), barcode: code);
      await ref
          .read(supplementCatalogueRepositoryProvider)
          .saveToLocalCatalogue(supp);
      return SupplementLookupResult(
        supplement: supp,
        sourceLabel: 'Herculex AI analysis · barcode $code',
      );
    }
  }

  if (wantsAiPhoto == null) return null;

  // Fallback to manual entry with the scanned barcode preserved.
  return SupplementLookupResult(
    supplement: Supplement(id: const Uuid().v4(), name: '', barcode: code),
    sourceLabel: 'Barcode $code saved — fill in details manually',
  );
}

/// Top-level helper for scanning a supplement from `SupplementsView` or the
/// dashboard widget and opening `SupplementEditSheet` with the resolved data.
Future<void> scanAndAddSupplement(BuildContext context, WidgetRef ref) async {
  final resolved = await scanAndResolveSupplement(context, ref);
  if (resolved == null || !context.mounted) return;

  await SupplementEditSheet.show(
    context,
    existing: resolved.supplement,
    isNewDraft: true,
    initialScanMessage:
        '${resolved.sourceLabel}${resolved.supplement.name.isNotEmpty ? ' · "${resolved.supplement.name}"' : ''}',
  );
}

Future<bool?> _confirmSupplementAiPrompt(BuildContext context, String barcode) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome, color: Color(0xFF9B59B6), size: 22),
          SizedBox(width: 8),
          Expanded(child: Text('Supplement not in database')),
        ],
      ),
      content: Text(
        'Product with barcode ($barcode) is not in the supplement database yet.\n\n'
        'Would you like to take a photo of the package or label so Herculex AI '
        'can automatically read the serving size and micronutrients and add it to the database?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Manual entry'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.camera_alt_outlined, size: 18),
          label: const Text('AI photo analysis'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF9B59B6),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );
}
