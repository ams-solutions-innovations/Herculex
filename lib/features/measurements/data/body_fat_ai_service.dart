import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

final bodyFatAiServiceProvider = Provider<BodyFatAiService>((ref) {
  final backend = ref.watch(geminiBackendProvider);
  final sanitizer = ref.watch(physiquePhotoSanitizerProvider);
  return BodyFatAiService(backend, sanitizer: sanitizer);
});

class BodyFatAiException implements Exception {
  final String message;
  final bool recoverable;

  const BodyFatAiException(this.message, {this.recoverable = true});

  @override
  String toString() => message;
}

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
    final rawBf = json['estimatedBfPercent'];
    if (rawBf is! num || !rawBf.toDouble().isFinite) {
      throw const FormatException(
        'Body fat response is missing estimatedBfPercent.',
      );
    }
    final bf = rawBf.toDouble();
    final min = (json['bfRangeMin'] as num?)?.toDouble();
    final max = (json['bfRangeMax'] as num?)?.toDouble();
    final conf = (json['confidence'] as num?)?.toDouble();
    final expl =
        json['explanation'] as String? ?? 'Estimate based on analysis.';
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
  static const int maxPhotos = 4;

  final GeminiBackend _backend;
  final PhysiquePhotoSanitizer? _sanitizer;

  BodyFatAiService(this._backend, {PhysiquePhotoSanitizer? sanitizer})
    : _sanitizer = sanitizer;

  /// Anthropometric US Navy Tape Measure Formula.
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
        final denom =
            1.0324 -
            (0.19077 * (math.log(diff) / math.ln10)) +
            (0.15456 * (math.log(heightCm) / math.ln10));
        final bf = (495.0 / denom) - 450.0;
        return bf.clamp(3.0, 50.0);
      } else {
        final hip = hipsCm ?? (waistCm * 1.15);
        final val = waistCm + hip - neckCm;
        if (val <= 0) return null;
        final denom =
            1.29579 -
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
    if (heightCm < 100.0) return isMale ? 15.0 : 22.0;
    final heightM = heightCm / 100.0;
    final bmi = weightKg / (heightM * heightM);
    if (bmi < 10.0 || bmi > 80.0) return isMale ? 15.0 : 22.0;
    final sexVal = isMale ? 1 : 0;
    final bf = (1.20 * bmi) + (0.23 * ageYears) - (10.8 * sexVal) - 5.4;
    return bf.clamp(isMale ? 4.0 : 8.0, 55.0);
  }

  Future<BodyFatAiResult> estimateBodyFat({
    required List<File> imageFiles,
    bool consentGranted = false,
    bool blurFaces = false,
    Profile? profile,
    Map<String, double>? measurements,
    String? userNote,
  }) async {
    if (imageFiles.isNotEmpty && !consentGranted) {
      throw const BodyFatAiException(
        'Confirm the photo privacy notice before starting the analysis.',
        recoverable: false,
      );
    }
    if (imageFiles.length > maxPhotos) {
      throw const BodyFatAiException(
        'Select up to 4 photos for body fat analysis.',
        recoverable: false,
      );
    }

    final isMale = profile?.sex != BiologicalSex.female;
    final weightKg = profile?.weightKg;
    final heightCm = profile?.heightCm;
    final age = profile?.ageYears ?? 25;

    final waistCm = measurements?['waist'];
    final neckCm = measurements?['neck'];
    final hipsCm = measurements?['hips'];
    final chestCm = measurements?['chest'];

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
        biometrics['navyFormulaReferenceBf'] = double.parse(
          navyBf.toStringAsFixed(1),
        );
      }
    }

    double? bmiBf;
    if (weightKg != null &&
        heightCm != null &&
        weightKg > 0 &&
        heightCm >= 100.0) {
      bmiBf = calculateBmiBodyFat(
        weightKg: weightKg,
        heightCm: heightCm,
        ageYears: age,
        isMale: isMale,
      );
      biometrics['bmiFormulaReferenceBf'] = double.parse(
        bmiBf.toStringAsFixed(1),
      );
    }

    // Formula-only mode (no images uploaded): require real anthropometric data
    // rather than inventing a 15% / 22% placeholder.
    if (imageFiles.isEmpty) {
      final estimated = navyBf ?? bmiBf;
      if (estimated == null) {
        throw const BodyFatAiException(
          'Enter your height and weight (or waist and neck measurements) first, or attach a physique photo.',
          recoverable: false,
        );
      }
      final fatMass = weightKg != null ? weightKg * (estimated / 100.0) : null;
      final leanMass = weightKg != null && fatMass != null
          ? weightKg - fatMass
          : null;

      return BodyFatAiResult(
        estimatedBfPercent: double.parse(estimated.toStringAsFixed(1)),
        bfRangeMin: double.parse((estimated - 1.5).toStringAsFixed(1)),
        bfRangeMax: double.parse((estimated + 1.5).toStringAsFixed(1)),
        confidence: navyBf != null ? 0.8 : 0.65,
        explanation: navyBf != null
            ? 'Calculated using the US Navy anthropometric formula based on waist, neck, and height measurements.'
            : 'Estimate calculated based on BMI (body mass index), age, and sex.',
        fatDistribution:
            'Attach a physique photo for more detailed visual analysis of definition and fat distribution.',
        leanMassKg: leanMass != null
            ? double.parse(leanMass.toStringAsFixed(1))
            : null,
        fatMassKg: fatMass != null
            ? double.parse(fatMass.toStringAsFixed(1))
            : null,
        recommendations:
            'Add a photo for more accurate visual analysis with Herculex AI.',
        isAiGenerated: false,
      );
    }

    try {
      final imagesPayload = <Map<String, dynamic>>[];
      for (final file in imageFiles) {
        if (!await file.exists()) continue;
        final Uint8List sanitizedBytes;
        if (blurFaces && _sanitizer != null) {
          final staged = await _sanitizer.stage(file, blurFaces: true);
          try {
            sanitizedBytes = await _sanitizer.analysisBytes(staged.file);
          } finally {
            await _sanitizer.discard(staged);
          }
        } else {
          final rawBytes = await file.readAsBytes();
          sanitizedBytes = await compute(downscaleForAnalysis, rawBytes);
        }
        imagesPayload.add({'bytes': sanitizedBytes, 'mimeType': 'image/jpeg'});
      }

      if (imagesPayload.isEmpty) {
        throw const BodyFatAiException(
          'Selected photos are no longer available on this device.',
          recoverable: false,
        );
      }

      final resultJson = await _backend.estimateBodyFat(
        images: imagesPayload,
        biometrics: biometrics,
        userNote: userNote,
      );

      try {
        return BodyFatAiResult.fromJson(resultJson, userWeightKg: weightKg);
      } on FormatException {
        throw const BodyFatAiException(
          'Herculex AI returned an incomplete body fat estimate. Your photos are still selected; please try again.',
        );
      }
    } on BodyFatAiException {
      rethrow;
    } on PhotoSanitizeException {
      throw const BodyFatAiException(
        'One of the selected photos could not be processed. Please choose a valid JPEG, PNG, or WebP image.',
        recoverable: false,
      );
    } catch (error) {
      final detail = error.toString().replaceFirst('Exception: ', '').trim();
      final message = detail.isEmpty
          ? 'Herculex AI body fat analysis is temporarily unavailable.'
          : detail;
      throw BodyFatAiException(
        '$message Your photos are still selected; please try again.',
      );
    }
  }
}
