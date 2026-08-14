import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/gemini_backend_service.dart';
import '../domain/nutrition_label.dart';

class GeminiFoodAnalysisResult {
  final String name;
  final String? brand;
  final double estimatedServingGrams;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double? fiberPer100g;
  final double rating;
  final String ratingReason;

  const GeminiFoodAnalysisResult({
    required this.name,
    this.brand = 'Gemini AI',
    required this.estimatedServingGrams,
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
      name: json['name'] as String? ?? 'Neznana hrana',
      brand: json['brand'] as String? ?? 'Gemini AI',
      estimatedServingGrams:
          (json['estimatedServingGrams'] as num?)?.toDouble() ?? 100.0,
      kcalPer100g: (json['kcalPer100g'] as num?)?.toDouble() ?? 0.0,
      proteinPer100g: (json['proteinPer100g'] as num?)?.toDouble() ?? 0.0,
      carbsPer100g: (json['carbsPer100g'] as num?)?.toDouble() ?? 0.0,
      fatPer100g: (json['fatPer100g'] as num?)?.toDouble() ?? 0.0,
      fiberPer100g: (json['fiberPer100g'] as num?)?.toDouble(),
      rating: (json['rating'] as num?)?.toDouble() ?? 7.0,
      ratingReason: json['ratingReason'] as String? ?? 'Ocenjeno z Gemini AI.',
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

  /// Fallback for a low-confidence local label OCR result.
  ///
  /// Gemini receives the image and the OCR evidence through the server-side
  /// Edge Function, but the output is still returned as an editable draft. It
  /// never writes to the diary directly.
  Future<NutritionLabelDraft> analyzeNutritionLabel({
    required File imageFile,
    required String ocrText,
  }) async {
    final responseJson = await _backend.analyzeNutritionLabel(
      imageBytes: await imageFile.readAsBytes(),
      mimeType: _mimeType(imageFile.path),
      ocrText: ocrText,
    );
    final serving = (responseJson['servingGrams'] as num?)?.toDouble();
    final factor = serving == null || serving <= 0 ? 1 : 100 / serving;
    final micros = <String, double>{};
    final rawMicros = responseJson['microsPerServing'];
    if (rawMicros is Map) {
      for (final item in rawMicros.entries) {
        if (item.value is num) {
          micros[item.key.toString()] = (item.value as num).toDouble() * factor;
        }
      }
    }
    final confidence = ((responseJson['confidence'] as num?)?.toDouble() ?? 0.5)
        .clamp(0.0, 1.0);
    return NutritionLabelDraft(
      name: responseJson['name'] as String? ?? 'Scanned food',
      brand: responseJson['brand'] as String?,
      servingGrams: serving,
      kcalPer100g: NutritionLabelDraft.per100(
        (responseJson['kcalPerServing'] as num?)?.toDouble(),
        serving,
      ),
      proteinPer100g: NutritionLabelDraft.per100(
        (responseJson['proteinPerServing'] as num?)?.toDouble(),
        serving,
      ),
      carbsPer100g: NutritionLabelDraft.per100(
        (responseJson['carbsPerServing'] as num?)?.toDouble(),
        serving,
      ),
      fatPer100g: NutritionLabelDraft.per100(
        (responseJson['fatPerServing'] as num?)?.toDouble(),
        serving,
      ),
      fiberPer100g: NutritionLabelDraft.per100(
        (responseJson['fiberPerServing'] as num?)?.toDouble(),
        serving,
      ),
      sodiumMgPer100g: NutritionLabelDraft.per100(
        (responseJson['sodiumMgPerServing'] as num?)?.toDouble(),
        serving,
      ),
      microsPer100g: micros,
      confidence: confidence,
      source: LabelExtractionSource.gemini,
      evidence: jsonEncode(responseJson),
      warning: responseJson['notes'] as String?,
    );
  }

  String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
