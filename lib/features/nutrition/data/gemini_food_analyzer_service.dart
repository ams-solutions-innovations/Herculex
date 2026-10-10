import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/nutrition/domain/nutrition_label.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

class GeminiFoodAnalysisResult {
  final String name;
  final String? brand;
  final double estimatedServingGrams;
  final double portionAmount;
  final String portionUnit;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double? fiberPer100g;
  final double rating;
  final String ratingReason;

  const GeminiFoodAnalysisResult({
    required this.name,
    this.brand = 'Herculex AI',
    required this.estimatedServingGrams,
    required this.portionAmount,
    required this.portionUnit,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.fiberPer100g,
    required this.rating,
    required this.ratingReason,
  });

  factory GeminiFoodAnalysisResult.fromJson(Map<String, dynamic> json) {
    return GeminiFoodAnalysisResult(
      name: json['name'] as String? ?? 'Unknown food',
      brand: json['brand'] as String? ?? 'Herculex AI',
      estimatedServingGrams:
          (json['estimatedServingGrams'] as num?)?.toDouble() ?? 100.0,
      portionAmount: (json['portionAmount'] as num?)?.toDouble() ?? 1.0,
      portionUnit: json['portionUnit'] as String? ?? 'serving',
      kcalPer100g: (json['kcalPer100g'] as num?)?.toDouble() ?? 0.0,
      proteinPer100g: (json['proteinPer100g'] as num?)?.toDouble() ?? 0.0,
      carbsPer100g: (json['carbsPer100g'] as num?)?.toDouble() ?? 0.0,
      fatPer100g: (json['fatPer100g'] as num?)?.toDouble() ?? 0.0,
      fiberPer100g: (json['fiberPer100g'] as num?)?.toDouble(),
      rating: (json['rating'] as num?)?.toDouble() ?? 7.0,
      ratingReason:
          json['ratingReason'] as String? ?? 'Evaluated with Herculex AI.',
    );
  }
}

/// Result of a `barcode_product` Gemini lookup — the model identifies the
/// scanned product from its photo/barcode and searches the web for its real
/// nutrition facts. [found] is false when Gemini couldn't confidently
/// identify the product; callers must check it rather than trusting zeros.
class GeminiBarcodeProductResult {
  final bool found;
  final String name;
  final String? brand;
  final double servingGrams;
  final double portionAmount;
  final String portionUnit;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double? fiberPer100g;
  final double? sodiumMgPer100g;
  final double confidence;

  /// Extra nutrition tables when the package prints one per product state
  /// (drained / not drained, as sold / prepared). Empty for a single table;
  /// use [allVariants] rather than reading this directly.
  final List<NutritionVariant> variants;

  /// The URLs the grounded search actually read, when the server returned
  /// any. Carried through to `product_catalogue_submissions` on publish:
  /// the model's own answer is not evidence of anything, but the pages it
  /// read are, and without them a wrong shared number is unfalsifiable.
  final List<String> groundingSources;

  const GeminiBarcodeProductResult({
    required this.found,
    required this.name,
    this.brand,
    required this.servingGrams,
    required this.portionAmount,
    required this.portionUnit,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.fiberPer100g,
    this.sodiumMgPer100g,
    required this.confidence,
    this.variants = const [],
    this.groundingSources = const [],
  });

  /// Every nutrition table found, never empty: the top-level values stand in
  /// as the single variant when the model reported no [variants].
  List<NutritionVariant> get allVariants => variants.length > 1
      ? variants
      : [
          NutritionVariant(
            servingGrams: servingGrams,
            portionAmount: portionAmount,
            servingUnit: portionUnit,
            kcalPer100g: kcalPer100g,
            proteinPer100g: proteinPer100g,
            carbsPer100g: carbsPer100g,
            fatPer100g: fatPer100g,
            fiberPer100g: fiberPer100g,
            sodiumMgPer100g: sodiumMgPer100g,
          ),
        ];

  factory GeminiBarcodeProductResult.fromJson(Map<String, dynamic> json) {
    return GeminiBarcodeProductResult(
      found: json['found'] as bool? ?? false,
      name: json['name'] as String? ?? 'Unknown product',
      brand: json['brand'] as String?,
      servingGrams: (json['servingGrams'] as num?)?.toDouble() ?? 100.0,
      portionAmount: (json['portionAmount'] as num?)?.toDouble() ?? 1.0,
      portionUnit: json['portionUnit'] as String? ?? 'serving',
      kcalPer100g: (json['kcalPer100g'] as num?)?.toDouble() ?? 0.0,
      proteinPer100g: (json['proteinPer100g'] as num?)?.toDouble() ?? 0.0,
      carbsPer100g: (json['carbsPer100g'] as num?)?.toDouble() ?? 0.0,
      fatPer100g: (json['fatPer100g'] as num?)?.toDouble() ?? 0.0,
      fiberPer100g: (json['fiberPer100g'] as num?)?.toDouble(),
      sodiumMgPer100g: (json['sodiumMgPer100g'] as num?)?.toDouble(),
      confidence: ((json['confidence'] as num?)?.toDouble() ?? 0.0).clamp(
        0.0,
        1.0,
      ),
      variants: [
        for (final v in (json['variants'] as List? ?? const []))
          if (v is Map) _barcodeVariantFromJson(Map<String, dynamic>.from(v)),
      ],
      groundingSources:
          (json['groundingSources'] as List?)?.whereType<String>().toList() ??
          const [],
    );
  }

  static NutritionVariant _barcodeVariantFromJson(Map<String, dynamic> json) {
    double? number(String key) => (json[key] as num?)?.toDouble();
    return NutritionVariant(
      label: (json['label'] as String?)?.trim(),
      servingGrams: number('servingGrams'),
      portionAmount: number('portionAmount'),
      servingUnit: json['portionUnit'] as String? ?? 'g',
      kcalPer100g: number('kcalPer100g'),
      proteinPer100g: number('proteinPer100g'),
      carbsPer100g: number('carbsPer100g'),
      fatPer100g: number('fatPer100g'),
      fiberPer100g: number('fiberPer100g'),
      sodiumMgPer100g: number('sodiumMgPer100g'),
    );
  }

  /// What gets stored alongside the community submission. Null when the
  /// lookup was ungrounded — an absent evidence trail is more honest than an
  /// empty one that looks like it was checked.
  Object? get evidence =>
      groundingSources.isEmpty ? null : {'groundingSources': groundingSources};
}

class RamblerFoodItem {
  String name;
  double servingGrams;
  double portionAmount;
  String portionUnit;
  double kcalPer100g;
  double proteinPer100g;
  double carbsPer100g;
  double fatPer100g;
  double? fiberPer100g;
  double confidence;

  RamblerFoodItem({
    required this.name,
    required this.servingGrams,
    required this.portionAmount,
    this.portionUnit = 'g',
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.fiberPer100g,
    this.confidence = 0.9,
  });

  double get totalKcal => (kcalPer100g * servingGrams / 100);
  double get totalProtein => (proteinPer100g * servingGrams / 100);
  double get totalCarbs => (carbsPer100g * servingGrams / 100);
  double get totalFat => (fatPer100g * servingGrams / 100);

  factory RamblerFoodItem.fromJson(Map<String, dynamic> json) {
    final servingGrams = (json['servingGrams'] as num?)?.toDouble() ?? 100.0;
    return RamblerFoodItem(
      name: json['name'] as String? ?? 'Food item',
      servingGrams: servingGrams,
      portionAmount:
          (json['portionAmount'] as num?)?.toDouble() ?? servingGrams,
      portionUnit: json['portionUnit'] as String? ?? 'g',
      kcalPer100g: (json['kcalPer100g'] as num?)?.toDouble() ?? 0.0,
      proteinPer100g: (json['proteinPer100g'] as num?)?.toDouble() ?? 0.0,
      carbsPer100g: (json['carbsPer100g'] as num?)?.toDouble() ?? 0.0,
      fatPer100g: (json['fatPer100g'] as num?)?.toDouble() ?? 0.0,
      fiberPer100g: (json['fiberPer100g'] as num?)?.toDouble(),
      confidence: ((json['confidence'] as num?)?.toDouble() ?? 0.9).clamp(
        0.0,
        1.0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'servingGrams': servingGrams,
    'portionAmount': portionAmount,
    'portionUnit': portionUnit,
    'kcalPer100g': kcalPer100g,
    'proteinPer100g': proteinPer100g,
    'carbsPer100g': carbsPer100g,
    'fatPer100g': fatPer100g,
    'fiberPer100g': fiberPer100g,
    'confidence': confidence,
  };
}

class RamblerFoodResult {
  final String? suggestedMealKey;
  final String? summary;
  final List<RamblerFoodItem> items;

  const RamblerFoodResult({
    this.suggestedMealKey,
    this.summary,
    required this.items,
  });

  factory RamblerFoodResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final itemsList = <RamblerFoodItem>[];
    if (rawItems is List) {
      for (final it in rawItems) {
        if (it is Map<String, dynamic>) {
          itemsList.add(RamblerFoodItem.fromJson(it));
        } else if (it is Map) {
          itemsList.add(
            RamblerFoodItem.fromJson(Map<String, dynamic>.from(it)),
          );
        }
      }
    }
    return RamblerFoodResult(
      suggestedMealKey: json['suggestedMealKey'] as String?,
      summary: json['summary'] as String?,
      items: itemsList,
    );
  }
}

final geminiFoodAnalyzerServiceProvider = Provider<GeminiFoodAnalyzerService>((
  ref,
) {
  return GeminiFoodAnalyzerService(ref.watch(geminiBackendProvider));
});

class GeminiFoodAnalyzerService {
  GeminiFoodAnalyzerService(this._backend);

  final GeminiBackend _backend;

  Future<GeminiFoodAnalysisResult> analyzeFoodPhoto({
    required File imageFile,
    String? userNote,
  }) async {
    final parsedMap = await _backend.analyzeFoodPhoto(
      imageBytes: await imageFile.readAsBytes(),
      mimeType: _mimeType(imageFile.path),
      userNote: userNote,
    );
    return GeminiFoodAnalysisResult.fromJson(parsedMap);
  }

  /// Reads the nutrition table from one or two photos (the product and/or its
  /// table). A label that prints several tables, such as drained / not
  /// drained, comes back as several variants.
  ///
  /// Gemini runs server-side in the Edge Function and the output is an
  /// editable draft; it never writes to the diary directly.
  Future<NutritionLabelDraft> analyzeNutritionLabel({
    required List<File> imageFiles,
  }) async {
    final responseJson = await _backend.analyzeNutritionLabel(
      images: await _images(imageFiles),
    );
    final rawVariants = responseJson['variants'];
    final variants = <NutritionVariant>[
      if (rawVariants is List)
        for (final raw in rawVariants)
          if (raw is Map) _labelVariant(Map<String, dynamic>.from(raw)),
    ];
    // A function deployed before variants existed answers with one flat table.
    if (variants.isEmpty) variants.add(_labelVariant(responseJson));
    return NutritionLabelDraft(
      name: responseJson['name'] as String? ?? 'Scanned food',
      brand: responseJson['brand'] as String?,
      variants: variants,
      confidence: ((responseJson['confidence'] as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0),
      evidence: jsonEncode(responseJson),
      warning: responseJson['notes'] as String?,
    );
  }

  NutritionVariant _labelVariant(Map<String, dynamic> json) {
    final serving = (json['servingGrams'] as num?)?.toDouble();
    final factor = serving == null || serving <= 0 ? 1 : 100 / serving;
    final micros = <String, double>{};
    final rawMicros = json['microsPerServing'];
    if (rawMicros is Map) {
      for (final item in rawMicros.entries) {
        if (item.value is num) {
          micros[item.key.toString()] = (item.value as num).toDouble() * factor;
        }
      }
    }
    double? per100(String key) =>
        NutritionVariant.per100((json[key] as num?)?.toDouble(), serving);
    final label = (json['label'] as String?)?.trim();
    return NutritionVariant(
      label: label == null || label.isEmpty ? null : label,
      servingGrams: serving,
      portionAmount: (json['portionAmount'] as num?)?.toDouble() ?? serving,
      servingUnit: json['portionUnit'] as String? ?? 'g',
      kcalPer100g: per100('kcalPerServing'),
      proteinPer100g: per100('proteinPerServing'),
      carbsPer100g: per100('carbsPerServing'),
      fatPer100g: per100('fatPerServing'),
      fiberPer100g: per100('fiberPerServing'),
      sodiumMgPer100g: per100('sodiumMgPerServing'),
      microsPer100g: micros,
    );
  }

  Future<GeminiBarcodeProductResult> analyzeBarcodeProduct({
    required List<File> imageFiles,
    required String barcode,
    String? userNote,
  }) async {
    final parsedMap = await _backend.analyzeBarcodeProduct(
      images: await _images(imageFiles),
      barcode: barcode,
      userNote: userNote,
    );
    return GeminiBarcodeProductResult.fromJson(parsedMap);
  }

  Future<List<GeminiImage>> _images(List<File> files) async => [
    for (final file in files)
      GeminiImage(
        bytes: await file.readAsBytes(),
        mimeType: _mimeType(file.path),
      ),
  ];

  Future<RamblerFoodResult> analyzeRamblerText({
    required String text,
    String? preferredMealKey,
  }) async {
    final parsedMap = await _backend.analyzeRamblerText(
      text: text,
      preferredMealKey: preferredMealKey,
    );
    return RamblerFoodResult.fromJson(parsedMap);
  }

  String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
