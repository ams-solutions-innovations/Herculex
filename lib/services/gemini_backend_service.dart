import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';

final geminiBackendProvider = Provider<GeminiBackend>((ref) {
  if (!Env.hasSupabase) return const UnconfiguredGeminiBackend();
  return SupabaseGeminiBackend(Supabase.instance.client);
});

abstract interface class GeminiBackend {
  Future<Map<String, dynamic>> analyzeFoodPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  });

  Future<Map<String, dynamic>> analyzeNutritionLabel({
    required List<int> imageBytes,
    required String mimeType,
    required String ocrText,
  });

  Future<String> identifyExercise({
    required List<int> imageBytes,
    required String mimeType,
  });
}

class UnconfiguredGeminiBackend implements GeminiBackend {
  const UnconfiguredGeminiBackend();

  @override
  Future<Map<String, dynamic>> analyzeFoodPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async {
    throw _notConfigured();
  }

  @override
  Future<Map<String, dynamic>> analyzeNutritionLabel({
    required List<int> imageBytes,
    required String mimeType,
    required String ocrText,
  }) async {
    throw _notConfigured();
  }

  @override
  Future<String> identifyExercise({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    throw _notConfigured();
  }

  Exception _notConfigured() => Exception(
    'AI analysis is not configured. Build with Supabase credentials and deploy '
    'the gemini-analyze Edge Function with a server-side GEMINI_API_KEY secret.',
  );
}

class SupabaseGeminiBackend implements GeminiBackend {
  const SupabaseGeminiBackend(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> analyzeFoodPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async {
    final data = await _invoke({
      'kind': 'food_photo',
      'image': _imagePayload(imageBytes, mimeType),
      'userNote': userNote,
    });
    return _resultMap(data);
  }

  @override
  Future<Map<String, dynamic>> analyzeNutritionLabel({
    required List<int> imageBytes,
    required String mimeType,
    required String ocrText,
  }) async {
    final data = await _invoke({
      'kind': 'nutrition_label',
      'image': _imagePayload(imageBytes, mimeType),
      'ocrText': ocrText,
    });
    return _resultMap(data);
  }

  @override
  Future<String> identifyExercise({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    final data = await _invoke({
      'kind': 'exercise_identification',
      'image': _imagePayload(imageBytes, mimeType),
    });
    final text = data['text'];
    if (text is String) return text.trim();
    throw Exception('AI analysis returned an invalid exercise response.');
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke(
        'gemini-analyze',
        body: body,
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw Exception('AI analysis returned an invalid response.');
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] is String) {
        throw Exception(details['error'] as String);
      }
      throw Exception(
        'AI analysis failed (${error.status}). Please try again later.',
      );
    }
  }

  Map<String, dynamic> _resultMap(Map<String, dynamic> data) {
    final result = data['result'];
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('AI analysis returned an invalid JSON result.');
  }

  Map<String, String> _imagePayload(List<int> imageBytes, String mimeType) => {
    'mimeType': mimeType,
    'data': base64Encode(imageBytes),
  };
}
