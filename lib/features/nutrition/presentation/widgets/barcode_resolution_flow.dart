import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/env.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/data/product_catalogue_repository.dart';
import 'package:herculex/features/nutrition/presentation/dialogs/barcode_product_review_dialog.dart';
import 'package:herculex/features/nutrition/presentation/sheets/custom_food_form_sheet.dart';
import 'package:herculex/features/nutrition/presentation/sheets/product_photos_sheet.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';

/// Resolves a scanned barcode the local catalogue doesn't have:
///
/// 1. Check the shared/public `product_catalogue` — a community-contributed
///    hit needs no photo or AI call at all.
/// 2. Otherwise, offer to photograph the product so Gemini can search the
///    web for its nutrition facts; the result is editable before saving,
///    and saving both logs it locally and publishes it back to the shared
///    catalogue for the next scan.
/// 3. If the user declines the photo prompt, Supabase isn't configured, or
///    the AI lookup doesn't pan out, falls back to today's blank
///    manual-entry form.
///
/// Shared by `quick_scan_food.dart`'s `scanAndLogFood` and
/// `food_picker_sheet.dart`'s `_scan()`, which used to duplicate this
/// lookup-miss handling inline.
Future<FoodData?> resolveUnknownBarcode(
  BuildContext context,
  WidgetRef ref,
  String barcode,
) async {
  if (Env.hasSupabase) {
    final public = await ref
        .read(productCatalogueRepositoryProvider)
        .lookupByBarcode(barcode);
    if (public != null) {
      return ref
          .read(nutritionRepositoryProvider)
          .createCustomFood(
            name: public.name,
            brand: public.brand,
            barcode: barcode,
            kcalPer100g: public.kcalPer100g,
            proteinPer100g: public.proteinPer100g,
            carbsPer100g: public.carbsPer100g,
            fatPer100g: public.fatPer100g,
            servingGrams: public.servingGrams,
            servingLabel: public.servingLabel,
            referenceBasis: public.referenceBasis,
            sodiumMgPer100g: public.sodiumMgPer100g,
            potassiumMgPer100g: public.potassiumMgPer100g,
            cholesterolMgPer100g: public.cholesterolMgPer100g,
            sourceMetadataJson: jsonEncode({
              'source': 'community',
              'nutrients': {'fiber': public.fiberPer100g}
                ..removeWhere((_, value) => value == null),
            }),
          );
    }

    if (!context.mounted) return null;
    final wantsPhoto = await _confirmPhotoPrompt(context);
    if (wantsPhoto == true) {
      if (!context.mounted) return null;
      final imageFiles = await ProductPhotosSheet.show(
        context,
        requireTable: false,
        confirmLabel: 'Find nutrition facts',
        pendingContext: () => PendingAiScanContext(
          type: AiScanContextType.food,
          extra: {'barcode': barcode},
        ),
      );
      if (imageFiles != null && imageFiles.isNotEmpty) {
        if (!context.mounted) return null;
        final food = await BarcodeProductReviewDialog.show(
          context,
          imageFiles: imageFiles,
          barcode: barcode,
        );
        if (food != null) return food;
      }
    }
  }

  if (!context.mounted) return null;
  return CustomFoodFormSheet.show(context, initialBarcode: barcode);
}

Future<bool?> _confirmPhotoPrompt(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Product not found'),
      content: const Text(
        'This product is not in our database. Would you like to take a photo so Herculex AI '
        'can find the nutrition facts online?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Enter manually'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Photograph product'),
        ),
      ],
    ),
  );
}
