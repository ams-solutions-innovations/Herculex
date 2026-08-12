import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/providers.dart';
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
  final double rating; // 1.0 - 10.0 scale
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
  final prefs = ref.watch(sharedPreferencesProvider);
  return GeminiFoodAnalyzerService(prefs);
});

class GeminiFoodAnalyzerService {
  final SharedPreferences _prefs;

  static const String _keyPrefsName = 'gemini_api_key';

  GeminiFoodAnalyzerService(this._prefs);

  bool get hasCustomApiKey {
    final customKey = _prefs.getString(_keyPrefsName);
    return customKey != null && customKey.trim().isNotEmpty;
  }

  /// No default key ships with the client. Callers must set their own key
  /// via [setApiKey] (or the `GEMINI_API_KEY` dart-define for dev builds)
  /// before any analysis call; see [apiKey] for the failure mode otherwise.
  String? get _configuredApiKey {
    final customKey = _prefs.getString(_keyPrefsName);
    if (customKey != null && customKey.trim().isNotEmpty) {
      return customKey.trim();
    }
    const envKey = String.fromEnvironment('GEMINI_API_KEY');
    if (envKey.isNotEmpty) {
      return envKey.trim();
    }
    return null;
  }

  /// Throws if no key has been configured — there is no embedded fallback.
  String get apiKey {
    final key = _configuredApiKey;
    if (key == null) {
      throw Exception(
        'Ni nastavljenega Gemini API ključa. Prosimo nastavite svoj Google Gemini API ključ (začne se z AIzaSy...).',
      );
    }
    return key;
  }

  Future<void> setApiKey(String key) async {
    await _prefs.setString(_keyPrefsName, key.trim());
  }

  Future<void> clearApiKey() async {
    await _prefs.remove(_keyPrefsName);
  }

  Future<GeminiFoodAnalysisResult> analyzeFoodPhoto({
    required File imageFile,
    String? userNote,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    // Determine mime type
    String mimeType = 'image/jpeg';
    final path = imageFile.path.toLowerCase();
    if (path.endsWith('.png')) {
      mimeType = 'image/png';
    } else if (path.endsWith('.webp')) {
      mimeType = 'image/webp';
    }

    final promptText =
        '''
Si strokovnjak za prehrano in analizo hrane. Analiziraj priloženo sliko hrane.
${userNote != null && userNote.trim().isNotEmpty ? 'Opomba uporabnika o količini, sestavinah ali pripravi: "$userNote"' : ''}

Natančno oceni:
1. Ime jedi ali sestavine (v slovenskem jeziku).
2. Oceni celotno maso obroka na sliki v gramih (estimatedServingGrams).
3. Oceni hranilne vrednosti na 100g (kcal, beljakovine, ogljikovi hidrati, maščobe, vlaknine).
4. Podaj oceno kakovosti/zdravja tega obroka (rating od 1.0 do 10.0, npr. 8.5).
5. Podaj kratko utemeljitev ocene in komentar sestave obroka (ratingReason v slovenščini).

Vrneš ISKALNI JSON objekt z naslednjo strukturo:
{
  "name": "Ime obroka v slovenščini",
  "brand": "Gemini AI",
  "estimatedServingGrams": 250.0,
  "kcalPer100g": 140.0,
  "proteinPer100g": 12.0,
  "carbsPer100g": 15.0,
  "fatPer100g": 4.0,
  "fiberPer100g": 2.5,
  "rating": 8.5,
  "ratingReason": "Kratek pregled kakovosti hrane in sestave obroka."
}
''';

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent',
    );

    final requestBody = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': promptText},
            {
              'inline_data': {'mime_type': mimeType, 'data': base64Image},
            },
          ],
        },
      ],
      'generationConfig': {
        'response_mime_type': 'application/json',
        'temperature': 0.2,
      },
    });

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
      body: requestBody,
    );

    if (response.statusCode == 401 ||
        response.body.contains('ACCESS_TOKEN_TYPE_UNSUPPORTED') ||
        response.body.contains('UNAUTHENTICATED')) {
      throw Exception(
        'Gemini API napaka (401): Neveljaven ali potekel API ključ. Prosimo nastavite svoj Google Gemini API ključ (začne se z AIzaSy...).',
      );
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Gemini API napaka (${response.statusCode}): ${response.body}',
      );
    }

    final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = responseJson['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini API ni vrnil kandidata za odgovor.');
    }

    final content = candidates[0]['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw Exception('Gemini API vrnil prazen rezultat.');
    }

    final text = parts[0]['text'] as String;
    final parsedMap = jsonDecode(text) as Map<String, dynamic>;

    return GeminiFoodAnalysisResult.fromJson(parsedMap);
  }

  /// Fallback for a low-confidence local label OCR result.
  ///
  /// Gemini receives the image and the OCR evidence, but its output is still
  /// returned as an editable draft. It never writes to the diary directly.
  Future<NutritionLabelDraft> analyzeNutritionLabel({
    required File imageFile,
    required String ocrText,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final promptText =
        '''
You are extracting a packaged-food nutrition label. Return ONLY valid JSON.
Use the nutrition values as printed per serving, never invent missing values.
The OCR text below may contain errors; use the image to correct it.
OCR evidence:
$ocrText

JSON schema:
{
  "name": "product name",
  "brand": "brand or null",
  "servingGrams": 100.0,
  "kcalPerServing": 0.0,
  "proteinPerServing": 0.0,
  "carbsPerServing": 0.0,
  "fatPerServing": 0.0,
  "fiberPerServing": 0.0,
  "sodiumMgPerServing": 0.0,
  "microsPerServing": {"vitamin_c": 0.0},
  "confidence": 0.0,
  "notes": "short uncertainty note"
}
''';
    final responseJson = await _generateJson(
      imageFile: imageFile,
      promptText: promptText,
      base64Image: base64Image,
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

  Future<Map<String, dynamic>> _generateJson({
    required File imageFile,
    required String promptText,
    required String base64Image,
  }) async {
    String mimeType = 'image/jpeg';
    final path = imageFile.path.toLowerCase();
    if (path.endsWith('.png')) mimeType = 'image/png';
    if (path.endsWith('.webp')) mimeType = 'image/webp';
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent',
    );
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': promptText},
              {
                'inline_data': {'mime_type': mimeType, 'data': base64Image},
              },
            ],
          },
        ],
        'generationConfig': {
          'response_mime_type': 'application/json',
          'temperature': 0.1,
        },
      }),
    );
    if (response.statusCode == 401 ||
        response.body.contains('ACCESS_TOKEN_TYPE_UNSUPPORTED') ||
        response.body.contains('UNAUTHENTICATED')) {
      throw Exception(
        'Gemini API napaka (401): Neveljaven ali potekel API ključ. Prosimo nastavite svoj Google Gemini API ključ (začne se z AIzaSy...).',
      );
    }
    if (response.statusCode != 200) {
      throw Exception('Gemini API napaka (${response.statusCode})');
    }
    final root = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = root['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini returned no label candidate');
    }
    final candidate = candidates.first as Map;
    final content = candidate['content'] as Map?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw Exception('Gemini returned no label');
    }
    return jsonDecode(parts.first['text'] as String) as Map<String, dynamic>;
  }
}
