import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env.dart';

/// A row from the shared/public `product_catalogue` table — community
/// nutrition data keyed by barcode, contributed via the AI barcode-lookup
/// flow. Pure DTO, no Drift dependency, mirrors [RemoteFood]'s shape.
class PublicProduct {
  final String barcode;
  final String name;
  final String? brand;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double? fiberPer100g;
  final double? sodiumMgPer100g;
  final double? potassiumMgPer100g;
  final double? cholesterolMgPer100g;
  final double? servingGrams;
  final String? servingLabel;
  final String referenceBasis;

  const PublicProduct({
    required this.barcode,
    required this.name,
    this.brand,
    required this.kcalPer100g,
    this.proteinPer100g = 0,
    this.carbsPer100g = 0,
    this.fatPer100g = 0,
    this.fiberPer100g,
    this.sodiumMgPer100g,
    this.potassiumMgPer100g,
    this.cholesterolMgPer100g,
    this.servingGrams,
    this.servingLabel,
    this.referenceBasis = '100 g',
  });

  factory PublicProduct.fromRow(Map<String, dynamic> row) => PublicProduct(
    barcode: row['barcode'] as String,
    name: row['name'] as String,
    brand: row['brand'] as String?,
    kcalPer100g: (row['kcal_per_100g'] as num).toDouble(),
    proteinPer100g: (row['protein_per_100g'] as num?)?.toDouble() ?? 0,
    carbsPer100g: (row['carbs_per_100g'] as num?)?.toDouble() ?? 0,
    fatPer100g: (row['fat_per_100g'] as num?)?.toDouble() ?? 0,
    fiberPer100g: (row['fiber_per_100g'] as num?)?.toDouble(),
    sodiumMgPer100g: (row['sodium_mg_per_100g'] as num?)?.toDouble(),
    potassiumMgPer100g: (row['potassium_mg_per_100g'] as num?)?.toDouble(),
    cholesterolMgPer100g: (row['cholesterol_mg_per_100g'] as num?)?.toDouble(),
    servingGrams: (row['serving_grams'] as num?)?.toDouble(),
    servingLabel: row['serving_label'] as String?,
    referenceBasis: row['reference_basis'] as String? ?? '100 g',
  );
}

final productCatalogueRepositoryProvider = Provider<ProductCatalogueRepository>(
  (ref) => const ProductCatalogueRepository(),
);

/// Client for the shared/public `product_catalogue` table
/// (supabase/migrations/0012_product_catalogue.sql). Reads go straight to
/// the table (public-select RLS, no user_id scoping — unlike every other
/// table in this app, which goes through the per-user sync engine). Writes
/// go through the `product-catalogue-publish` Edge Function, the table's
/// only write path by design.
class ProductCatalogueRepository {
  const ProductCatalogueRepository();

  Future<PublicProduct?> lookupByBarcode(String barcode) async {
    if (!Env.hasSupabase) return null;
    try {
      final row = await Supabase.instance.client
          .from('product_catalogue')
          .select()
          .eq('barcode', barcode)
          .maybeSingle();
      if (row == null) return null;
      return PublicProduct.fromRow(row);
    } catch (_) {
      // Offline or transient failure — treat as "not in the shared
      // catalogue" so the caller falls through to the AI/manual flow rather
      // than surfacing a hard error for what is just an optimization.
      return null;
    }
  }

  /// Publishes a user-reviewed product to the shared catalogue. Failures are
  /// swallowed by design — this is a community contribution, not the user's
  /// own save, so it must never block or fail their local flow.
  Future<void> publish({
    required String barcode,
    required String name,
    String? brand,
    required double kcalPer100g,
    double proteinPer100g = 0,
    double carbsPer100g = 0,
    double fatPer100g = 0,
    double? fiberPer100g,
    double? sodiumMgPer100g,
    double? potassiumMgPer100g,
    double? cholesterolMgPer100g,
    double? servingGrams,
    String? servingLabel,
    String referenceBasis = '100 g',
  }) async {
    if (!Env.hasSupabase) return;
    try {
      await Supabase.instance.client.functions.invoke(
        'product-catalogue-publish',
        body: {
          'barcode': barcode,
          'name': name,
          'brand': brand,
          'kcalPer100g': kcalPer100g,
          'proteinPer100g': proteinPer100g,
          'carbsPer100g': carbsPer100g,
          'fatPer100g': fatPer100g,
          'fiberPer100g': fiberPer100g,
          'sodiumMgPer100g': sodiumMgPer100g,
          'potassiumMgPer100g': potassiumMgPer100g,
          'cholesterolMgPer100g': cholesterolMgPer100g,
          'servingGrams': servingGrams,
          'servingLabel': servingLabel,
          'referenceBasis': referenceBasis,
        },
      );
    } catch (_) {
      // Non-fatal — see doc comment above.
    }
  }
}
