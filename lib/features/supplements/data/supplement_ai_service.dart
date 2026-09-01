import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/services/gemini_backend_service.dart';

final supplementAiServiceProvider = Provider<SupplementAiService>((ref) {
  final backend = ref.watch(geminiBackendProvider);
  return SupplementAiService(backend);
});

class SupplementAiResult {
  final String name;
  final String? brand;
  final double? doseAmount;
  final String? doseUnit;
  final Map<String, double> nutrients;
  final SupplementSchedule schedule;
  final String? timeHHMM;
  final String? description;
  final double confidence;

  const SupplementAiResult({
    required this.name,
    this.brand,
    this.doseAmount,
    this.doseUnit,
    this.nutrients = const {},
    this.schedule = SupplementSchedule.none,
    this.timeHHMM,
    this.description,
    this.confidence = 0.0,
  });

  Supplement toSupplement({String? id, String? barcode}) {
    return Supplement(
      id: id ?? '',
      name: name,
      brand: brand,
      barcode: barcode,
      doseAmount: doseAmount,
      doseUnit: doseUnit,
      nutrients: nutrients,
      schedule: schedule,
      timeHHMM: schedule == SupplementSchedule.time ? timeHHMM : null,
    );
  }
}

class SupplementAiService {
  final GeminiBackend _backend;

  SupplementAiService(this._backend);

  Future<SupplementAiResult> analyzeSupplementPhoto({
    required File imageFile,
    String? userNote,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final mime = _mimeType(imageFile.path);

    final raw = await _backend.analyzeSupplementPhoto(
      imageBytes: bytes,
      mimeType: mime,
      userNote: userNote,
    );

    return _parseResult(raw);
  }

  SupplementAiResult _parseResult(Map<String, dynamic> data) {
    final name = (data['name'] as String?)?.trim() ?? 'Neznano dopolnilo';
    final brand = (data['brand'] as String?)?.trim();
    final doseAmount = (data['doseAmount'] as num?)?.toDouble();
    final doseUnit = data['doseUnit'] as String?;

    // Parse nutrients map
    final rawNutrients = data['nutrients'];
    final nutrients = <String, double>{};
    if (rawNutrients is Map) {
      rawNutrients.forEach((key, value) {
        if (key is String && value is num && value > 0) {
          final normalizedKey = _normalizeNutrientKey(key);
          nutrients[normalizedKey] = value.toDouble();
        }
      });
    }

    // Parse schedule
    final schedStr = (data['schedule'] as String?)?.toLowerCase() ?? 'none';
    SupplementSchedule schedule = SupplementSchedule.none;
    if (schedStr == 'post_workout' || schedStr == 'postworkout') {
      schedule = SupplementSchedule.postWorkout;
    } else if (schedStr == 'time') {
      schedule = SupplementSchedule.time;
    }

    final timeHHMM = data['timeHHMM'] as String?;
    final description = data['description'] as String?;
    final confidence = (data['confidence'] as num?)?.toDouble() ?? 0.85;

    return SupplementAiResult(
      name: name,
      brand: brand != null && brand.isNotEmpty ? brand : null,
      doseAmount: doseAmount != null && doseAmount > 0 ? doseAmount : null,
      doseUnit: doseUnit != null && supplementDoseUnits.contains(doseUnit)
          ? doseUnit
          : (doseAmount != null ? 'g' : null),
      nutrients: nutrients,
      schedule: schedule,
      timeHHMM: timeHHMM,
      description: description,
      confidence: confidence,
    );
  }

  String _normalizeNutrientKey(String raw) {
    final lower = raw
        .toLowerCase()
        .trim()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    if (lower == 'vit_d' || lower == 'vitamind' || lower == 'vitamin_d3')
      return 'vitamin_d';
    if (lower == 'vit_c' || lower == 'vitaminc') return 'vitamin_c';
    if (lower == 'vit_b12' || lower == 'b12') return 'vitamin_b12';
    if (lower == 'omega3' || lower == 'omega_3_fatty_acids') return 'omega_3';
    if (lower == 'sat_fat') return 'saturated_fat';
    return lower;
  }

  String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
