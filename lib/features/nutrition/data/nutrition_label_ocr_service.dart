import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/nutrition_label.dart';
import 'gemini_food_analyzer_service.dart';

class NutritionLabelOcrService {
  static const geminiFallbackThreshold = 0.75;

  final GeminiFoodAnalyzerService gemini;

  const NutritionLabelOcrService(this.gemini);

  Future<NutritionLabelDraft> extract(File imageFile) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(imageFile.path),
      );
      final ocrDraft = parse(recognized.text);
      if (ocrDraft.confidence >= geminiFallbackThreshold &&
          ocrDraft.hasCoreNutrition) {
        return ocrDraft;
      }

      try {
        return await gemini.analyzeNutritionLabel(
          imageFile: imageFile,
          ocrText: recognized.text,
        );
      } catch (_) {
        return ocrDraft.withWarning(
          'OCR ni dovolj zanesljiv, Gemini fallback pa ni uspel. Preveri vsa polja pred shranjevanjem.',
        );
      }
    } finally {
      await recognizer.close();
    }
  }

  static NutritionLabelDraft parse(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final serving = _firstNumber(text, [
      RegExp(
        r'(?:serving size|portion size|porcija|porcija vsebuje)[^\d]{0,20}([\d]+(?:[.,][\d]+)?)\s*g',
        caseSensitive: false,
      ),
    ]);
    final kcal = _firstNumber(text, [
      RegExp(
        r'(?:calories|energy|kalorij|energija)[^\d]{0,20}([\d]+(?:[.,][\d]+)?)',
        caseSensitive: false,
      ),
    ]);
    final protein = _firstNumber(text, [
      RegExp(
        r'(?:protein|beljakovin)[^\d]{0,20}([\d]+(?:[.,][\d]+)?)\s*g?',
        caseSensitive: false,
      ),
    ]);
    final carbs = _firstNumber(text, [
      RegExp(
        r'(?:total carbohydrate|carbohydrate|carbs|ogljikovih hidrat)[^\d]{0,20}([\d]+(?:[.,][\d]+)?)\s*g?',
        caseSensitive: false,
      ),
    ]);
    final fat = _firstNumber(text, [
      RegExp(
        r'(?:total fat|fat|maščob|mascob)[^\d]{0,20}([\d]+(?:[.,][\d]+)?)\s*g?',
        caseSensitive: false,
      ),
    ]);
    final fiber = _firstNumber(text, [
      RegExp(
        r'(?:dietary fiber|fiber|vlaknin)[^\d]{0,20}([\d]+(?:[.,][\d]+)?)\s*g?',
        caseSensitive: false,
      ),
    ]);
    final sodium = _firstNumber(text, [
      RegExp(
        r'(?:sodium|natrij)[^\d]{0,20}([\d]+(?:[.,][\d]+)?)\s*mg?',
        caseSensitive: false,
      ),
    ]);
    final core = [kcal, protein, carbs, fat].whereType<double>().length;
    final confidence = core == 4
        ? (0.15 + core / 4 * 0.65 + (serving == null ? 0 : 0.2))
        : (0.15 + core / 4 * 0.55 + (serving == null ? 0 : 0.1));
    final name = _guessName(lines);
    final factor = serving == null || serving <= 0 ? 1 : 100 / serving;
    return NutritionLabelDraft(
      name: name,
      servingGrams: serving,
      kcalPer100g: kcal == null ? null : kcal * factor,
      proteinPer100g: protein == null ? null : protein * factor,
      carbsPer100g: carbs == null ? null : carbs * factor,
      fatPer100g: fat == null ? null : fat * factor,
      fiberPer100g: fiber == null ? null : fiber * factor,
      sodiumMgPer100g: sodium == null ? null : sodium * factor,
      confidence: confidence,
      source: LabelExtractionSource.ocr,
      evidence: text,
    );
  }

  static String _guessName(List<String> lines) {
    for (final line in lines) {
      if (line.length < 2 || line.length > 80) continue;
      if (RegExp(
        r'(nutrition|hranil|calories|protein|fat|carb|energy|porcija|serving)',
        caseSensitive: false,
      ).hasMatch(line)) {
        continue;
      }
      return line;
    }
    return 'Scanned food';
  }

  static double? _firstNumber(String text, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      return double.tryParse(match.group(1)!.replaceAll(',', '.'));
    }
    return null;
  }
}
