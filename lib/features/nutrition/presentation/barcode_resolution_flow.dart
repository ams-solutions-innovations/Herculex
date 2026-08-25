import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/env.dart';
import '../../../data/local/database.dart';
import '../../../services/pending_ai_scan_service.dart';
import '../../../theme/colors.dart';
import '../data/product_catalogue_repository.dart';
import 'barcode_product_review_dialog.dart';
import 'custom_food_form_sheet.dart';
import 'nutrition_providers.dart';

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
      final imageFile = await _pickProductPhoto(context, ref, barcode);
      if (imageFile != null) {
        if (!context.mounted) return null;
        final food = await BarcodeProductReviewDialog.show(
          context,
          imageFile: imageFile,
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
        'This product is not in our database. Would you like to take a photo so Gemini AI '
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

Future<File?> _pickProductPhoto(
  BuildContext context,
  WidgetRef ref,
  String barcode,
) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.camera_alt, color: AppColors.primary),
            title: const Text('Take photo with camera'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose image from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  await ref.read(pendingAiScanServiceProvider).setPendingContext(
        PendingAiScanContext(
          type: AiScanContextType.food,
          extra: {'barcode': barcode},
        ),
      );
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 85,
  );
  await ref.read(pendingAiScanServiceProvider).clearPendingContext();
  if (picked == null) return null;
  return File(picked.path);
}
