import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remote_food.dart';

/// Thin wrapper over the public OpenFoodFacts API. No auth required.
/// Attribution string must appear somewhere in-app per OFF terms — we render
/// it in the food picker footer.
class OpenFoodFactsClient {
  static const _userAgent = 'Herculex/0.1 (personal-testing)';
  static const _base = 'https://world.openfoodfacts.org';

  final http.Client _http;
  OpenFoodFactsClient([http.Client? client]) : _http = client ?? http.Client();

  /// Returns null if barcode not found or product has no usable nutrition data.
  Future<RemoteFood?> lookupBarcode(String barcode) async {
    final uri = Uri.parse('$_base/api/v2/product/$barcode.json');
    final resp = await _http.get(uri, headers: {'User-Agent': _userAgent});
    if (resp.statusCode != 200) return null;

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (body['status'] != 1) return null;
    final product = body['product'] as Map<String, dynamic>?;
    if (product == null) return null;
    return _toRemoteFood(product, barcode: barcode);
  }

  Future<List<RemoteFood>> search(String query, {int pageSize = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final uri = Uri.parse('$_base/cgi/search.pl').replace(
      queryParameters: {
        'search_terms': trimmed,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': pageSize.toString(),
        'fields': [
          'code',
          'product_name',
          'brands',
          'nutriments',
          'serving_quantity',
          'serving_size',
          'image_small_url',
        ].join(','),
      },
    );
    final resp = await _http.get(uri, headers: {'User-Agent': _userAgent});
    if (resp.statusCode != 200) return const [];

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final products = (body['products'] as List?) ?? const [];
    return products
        .map((p) => _toRemoteFood(p as Map<String, dynamic>))
        .whereType<RemoteFood>()
        .toList();
  }

  RemoteFood? _toRemoteFood(Map<String, dynamic> p, {String? barcode}) {
    final name = (p['product_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;

    final nutriments =
        (p['nutriments'] as Map?)?.cast<String, dynamic>() ?? const {};
    final kcal =
        _toDouble(nutriments['energy-kcal_100g']) ??
        // some products only report kJ
        ((_toDouble(nutriments['energy-kj_100g']) ?? 0) / 4.184);
    if (kcal <= 0) return null;

    final brand = (p['brands'] as String?)?.split(',').first.trim();
    final servingGrams = _toDouble(p['serving_quantity']);
    final servingLabel = (p['serving_size'] as String?)?.trim();
    final imageUrl = p['image_small_url'] as String?;
    final code = (p['code'] as String?) ?? barcode;

    return RemoteFood(
      barcode: code,
      name: name,
      brand: brand?.isEmpty ?? true ? null : brand,
      kcalPer100g: kcal,
      proteinPer100g: _toDouble(nutriments['proteins_100g']) ?? 0,
      carbsPer100g: _toDouble(nutriments['carbohydrates_100g']) ?? 0,
      fatPer100g: _toDouble(nutriments['fat_100g']) ?? 0,
      fiberPer100g: _toDouble(nutriments['fiber_100g']),
      servingGrams: servingGrams,
      servingLabel: servingLabel,
      imageUrl: imageUrl,
    );
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  void dispose() => _http.close();
}
