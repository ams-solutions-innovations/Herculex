import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/gemini_backend_service.dart';
import '../../profile/domain/profile.dart';

final bodyFatAiServiceProvider = Provider<BodyFatAiService>((ref) {
  final backend = ref.watch(geminiBackendProvider);
  return BodyFatAiService(backend);
});

class BodyFatAiResult {
  final double estimatedBfPercent;
  final double? bfRangeMin;
  final double? bfRangeMax;
  final double? confidence;
  final String explanation;
  final String? fatDistribution;
  final double? leanMassKg;
  final double? fatMassKg;
  final String? recommendations;
  final bool isAiGenerated;

  const BodyFatAiResult({
    required this.estimatedBfPercent,
    this.bfRangeMin,
    this.bfRangeMax,
    this.confidence,
    required this.explanation,
    this.fatDistribution,
    this.leanMassKg,
    this.fatMassKg,
    this.recommendations,
    this.isAiGenerated = true,
  });

  factory BodyFatAiResult.fromJson(
    Map<String, dynamic> json, {
    double? userWeightKg,
  }) {
    final bf = (json['estimatedBfPercent'] as num?)?.toDouble() ?? 15.0;
    final min = (json['bfRangeMin'] as num?)?.toDouble();
    final max = (json['bfRangeMax'] as num?)?.toDouble();
    final conf = (json['confidence'] as num?)?.toDouble();
    final expl = json['explanation'] as String? ?? 'Ocena na podlagi analize.';
    final dist = json['fatDistribution'] as String?;
    final rec = json['recommendations'] as String?;

    double? lean = (json['leanMassKg'] as num?)?.toDouble();
    double? fat = (json['fatMassKg'] as num?)?.toDouble();

    if (userWeightKg != null && userWeightKg > 0) {
      fat ??= userWeightKg * (bf / 100.0);
      lean ??= userWeightKg - fat;
    }

    return BodyFatAiResult(
      estimatedBfPercent: bf,
      bfRangeMin: min,
      bfRangeMax: max,
      confidence: conf,
      explanation: expl,
      fatDistribution: dist,
      leanMassKg: lean,
      fatMassKg: fat,
      recommendations: rec,
      isAiGenerated: true,
    );
  }
}

class BodyFatAiService {
  final GeminiBackend _backend;

  BodyFatAiService(this._backend);

  /// Anthropometric US Navy Tape Measure Formula.
  /// For men: 495 / (1.0324 - 0.19077 * log10(waist - neck) + 0.15456 * log10(height)) - 450
  /// For women: 495 / (1.29579 - 0.35004 * log10(waist + hip - neck) + 0.22100 * log10(height)) - 450
  static double? calculateNavyBodyFat({
    required double heightCm,
    required double waistCm,
    required double neckCm,
    double? hipsCm,
    required bool isMale,
  }) {
    if (heightCm <= 0 || waistCm <= 0 || neckCm <= 0) return null;
    try {
      if (isMale) {
        final diff = waistCm - neckCm;
        if (diff <= 0) return null;
        final denom = 1.0324 -
            (0.19077 * (math.log(diff) / math.ln10)) +
            (0.15456 * (math.log(heightCm) / math.ln10));
        final bf = (495.0 / denom) - 450.0;
        return bf.clamp(3.0, 50.0);
      } else {
        final hip = hipsCm ?? (waistCm * 1.15); // Fallback approximation if hips not logged
        final val = waistCm + hip - neckCm;
        if (val <= 0) return null;
        final denom = 1.29579 -
            (0.35004 * (math.log(val) / math.ln10)) +
            (0.22100 * (math.log(heightCm) / math.ln10));
        final bf = (495.0 / denom) - 450.0;
        return bf.clamp(8.0, 60.0);
      }
    } catch (_) {
      return null;
    }
  }

  /// Deurenberg formula based on BMI and Age:
  /// Adult: (1.20 * BMI) + (0.23 * Age) - (10.8 * sex) - 5.4 (where sex=1 for male, 0 for female)
  static double calculateBmiBodyFat({
    required double weightKg,
    required double heightCm,
    required int ageYears,
    required bool isMale,
  }) {
    final heightM = heightCm / 100.0;
    final bmi = weightKg / (heightM * heightM);
    final sexVal = isMale ? 1 : 0;
    final bf = (1.20 * bmi) + (0.23 * ageYears) - (10.8 * sexVal) - 5.4;
    return bf.clamp(isMale ? 4.0 : 8.0, 55.0);
  }

  Future<BodyFatAiResult> estimateBodyFat({
    required List<File> imageFiles,
    Profile? profile,
    Map<String, double>? measurements,
    String? userNote,
  }) async {
    final isMale = profile?.sex != BiologicalSex.female;
    final weightKg = profile?.weightKg;
    final heightCm = profile?.heightCm;
    final age = profile?.ageYears ?? 25;

    final waistCm = measurements?['waist'];
    final neckCm = measurements?['neck'];
    final hipsCm = measurements?['hips'];
    final chestCm = measurements?['chest'];

    // Biometrics payload for Gemini
    final biometrics = <String, dynamic>{
      'sex': isMale ? 'male' : 'female',
      ...?heightCm != null ? {'heightCm': heightCm} : null,
      ...?weightKg != null ? {'weightKg': weightKg} : null,
      'ageYears': age,
      ...?waistCm != null ? {'waistCm': waistCm} : null,
      ...?neckCm != null ? {'neckCm': neckCm} : null,
      ...?hipsCm != null ? {'hipsCm': hipsCm} : null,
      ...?chestCm != null ? {'chestCm': chestCm} : null,
    };

    // Calculate reference mathematical baselines
    double? navyBf;
    if (heightCm != null && waistCm != null && neckCm != null) {
      navyBf = calculateNavyBodyFat(
        heightCm: heightCm,
        waistCm: waistCm,
        neckCm: neckCm,
        hipsCm: hipsCm,
        isMale: isMale,
      );
      if (navyBf != null) {
        biometrics['navyFormulaReferenceBf'] = double.parse(navyBf.toStringAsFixed(1));
      }
    }

    double? bmiBf;
    if (weightKg != null && heightCm != null) {
      bmiBf = calculateBmiBodyFat(
        weightKg: weightKg,
        heightCm: heightCm,
        ageYears: age,
        isMale: isMale,
      );
      biometrics['bmiFormulaReferenceBf'] = double.parse(bmiBf.toStringAsFixed(1));
    }

    if (imageFiles.isEmpty) {
      // Return formula-based calculation if no images provided
      final estimated = navyBf ?? bmiBf ?? (isMale ? 16.0 : 23.0);
      final fatMass = weightKg != null ? weightKg * (estimated / 100.0) : null;
      final leanMass = weightKg != null && fatMass != null ? weightKg - fatMass : null;

      return BodyFatAiResult(
        estimatedBfPercent: double.parse(estimated.toStringAsFixed(1)),
        bfRangeMin: double.parse((estimated - 1.5).toStringAsFixed(1)),
        bfRangeMax: double.parse((estimated + 1.5).toStringAsFixed(1)),
        confidence: navyBf != null ? 0.8 : 0.65,
        explanation: navyBf != null
            ? 'Izračunano po antropometrični formuli US Navy na podlagi meritev obsegov pasu, vratu in višine.'
            : 'Ocena izračunana na podlagi ITM (indeksa telesne mase), starosti in spola.',
        fatDistribution: 'Za podrobnejšo vizualno analizo definicije in porazdelitve maščobe priložite fotografijo telesa.',
        leanMassKg: leanMass != null ? double.parse(leanMass.toStringAsFixed(1)) : null,
        fatMassKg: fatMass != null ? double.parse(fatMass.toStringAsFixed(1)) : null,
        recommendations: 'Dodajte fotografijo za natančnejšo vizualno analizo z Gemini AI.',
        isAiGenerated: false,
      );
    }

    try {
      final imagesPayload = <Map<String, dynamic>>[];
      for (final file in imageFiles) {
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final mime = _mimeType(file.path);
          imagesPayload.add({'bytes': bytes, 'mimeType': mime});
        }
      }

      if (imagesPayload.isEmpty) {
        throw Exception('Izbrane slike ne obstajajo na napravi.');
      }

      final resultJson = await _backend.estimateBodyFat(
        images: imagesPayload,
        biometrics: biometrics,
        userNote: userNote,
      );

      return BodyFatAiResult.fromJson(resultJson, userWeightKg: weightKg);
    } catch (e) {
      // Fallback in case of network or API error
      final fallbackBf = navyBf ?? bmiBf ?? (isMale ? 15.0 : 22.0);
      final fatMass = weightKg != null ? weightKg * (fallbackBf / 100.0) : null;
      final leanMass = weightKg != null && fatMass != null ? weightKg - fatMass : null;

      return BodyFatAiResult(
        estimatedBfPercent: double.parse(fallbackBf.toStringAsFixed(1)),
        bfRangeMin: double.parse((fallbackBf - 2.0).toStringAsFixed(1)),
        bfRangeMax: double.parse((fallbackBf + 2.0).toStringAsFixed(1)),
        confidence: 0.70,
        explanation: 'Ocena narejena na podlagi biometričnih formul (US Navy / BMI) zaradi nedostopnosti AI strežnika: $e',
        fatDistribution: 'Standardna porazdelitev glede na vaš profil.',
        leanMassKg: leanMass != null ? double.parse(leanMass.toStringAsFixed(1)) : null,
        fatMassKg: fatMass != null ? double.parse(fatMass.toStringAsFixed(1)) : null,
        recommendations: 'Preverite povezavo s strežnikom za polno multimodalno vizualno analizo.',
        isAiGenerated: false,
      );
    }
  }

  String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
