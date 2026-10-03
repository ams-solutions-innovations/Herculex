import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/env.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const dreamPhysiqueImageConsentVersion = 'dream_physique_images_v1';

final geminiBackendProvider = Provider<GeminiBackend>((ref) {
  if (!Env.hasSupabase) return const UnconfiguredGeminiBackend();
  return SupabaseGeminiBackend(Supabase.instance.client);
});

final physiqueCheckInBackendProvider = Provider<PhysiqueCheckInBackend>((ref) {
  final backend = ref.watch(geminiBackendProvider);
  if (backend is PhysiqueCheckInBackend) {
    return backend as PhysiqueCheckInBackend;
  }
  return const UnconfiguredGeminiBackend();
});

/// Separate from [GeminiBackend] so existing test fakes of that interface keep
/// compiling. Returns evidence only; the AI never writes to the database.
abstract interface class PhysiqueCheckInBackend {
  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  analyzePhysiqueCheckIn({
    required List<Map<String, dynamic>> baselineImages,
    required Map<String, dynamic> currentImage,
    required Map<String, dynamic> context,
    String? userNote,
  });
}

final weeklyReportBackendProvider = Provider<WeeklyReportBackend>((ref) {
  final backend = ref.watch(geminiBackendProvider);
  if (backend is WeeklyReportBackend) {
    return backend as WeeklyReportBackend;
  }
  return const UnconfiguredGeminiBackend();
});

/// Separate from [GeminiBackend] so existing test fakes of that interface keep
/// compiling. Returns evidence only; the AI never writes to the database.
abstract interface class WeeklyReportBackend {
  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  generateWeeklyReportNarrative({required Map<String, dynamic> facts});
}

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

  Future<Map<String, dynamic>> identifyExerciseDetailed({
    required List<int> imageBytes,
    required String mimeType,
  });

  Future<Map<String, dynamic>> analyzeSupplementPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  });

  Future<Map<String, dynamic>> analyzeBarcodeProduct({
    required List<int> imageBytes,
    required String mimeType,
    required String barcode,
    String? userNote,
  });

  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  });

  Future<Map<String, dynamic>> analyzeDreamPhysique({
    required List<Map<String, dynamic>> currentImages,
    required List<Map<String, dynamic>> targetImages,
    Map<String, dynamic>? biometrics,
    String? userNote,
  });

  Future<Map<String, dynamic>> analyzeRamblerText({
    required String text,
    String? preferredMealKey,
  });

  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  generateProgramBrief({
    required Map<String, dynamic> profileInputs,
    String? userNote,
  });
}

class UnconfiguredGeminiBackend
    implements GeminiBackend, PhysiqueCheckInBackend, WeeklyReportBackend {
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

  @override
  Future<Map<String, dynamic>> identifyExerciseDetailed({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    throw _notConfigured();
  }

  @override
  Future<Map<String, dynamic>> analyzeSupplementPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async {
    throw _notConfigured();
  }

  @override
  Future<Map<String, dynamic>> analyzeBarcodeProduct({
    required List<int> imageBytes,
    required String mimeType,
    required String barcode,
    String? userNote,
  }) async {
    throw _notConfigured();
  }

  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    throw _notConfigured();
  }

  @override
  Future<Map<String, dynamic>> analyzeDreamPhysique({
    required List<Map<String, dynamic>> currentImages,
    required List<Map<String, dynamic>> targetImages,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    throw _notConfigured();
  }

  @override
  Future<Map<String, dynamic>> analyzeRamblerText({
    required String text,
    String? preferredMealKey,
  }) async {
    throw _notConfigured();
  }

  @override
  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  generateProgramBrief({
    required Map<String, dynamic> profileInputs,
    String? userNote,
  }) async {
    throw _notConfigured();
  }

  @override
  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  analyzePhysiqueCheckIn({
    required List<Map<String, dynamic>> baselineImages,
    required Map<String, dynamic> currentImage,
    required Map<String, dynamic> context,
    String? userNote,
  }) async {
    throw _notConfigured();
  }

  @override
  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  generateWeeklyReportNarrative({required Map<String, dynamic> facts}) async {
    throw _notConfigured();
  }

  Exception _notConfigured() => Exception(
    'AI analysis is not configured. Build with Supabase credentials and deploy '
    'the gemini-analyze Edge Function with a server-side GEMINI_API_KEY secret.',
  );
}

class SupabaseGeminiBackend
    implements GeminiBackend, PhysiqueCheckInBackend, WeeklyReportBackend {
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
    if (text is String && text.isNotEmpty) return text.trim();
    final result = data['result'];
    if (result is Map && result['identifiedName'] is String) {
      return (result['identifiedName'] as String).trim();
    }
    throw Exception('AI analysis returned an invalid exercise response.');
  }

  @override
  Future<Map<String, dynamic>> identifyExerciseDetailed({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    final data = await _invoke({
      'kind': 'exercise_identification',
      'image': _imagePayload(imageBytes, mimeType),
    });
    final result = data['result'];
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    final text = data['text'];
    return {
      'identifiedName': text is String ? text.trim() : 'Unknown',
      'confidence': text != null && text != 'Unknown' ? 0.8 : 0.0,
    };
  }

  @override
  Future<Map<String, dynamic>> analyzeSupplementPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async {
    final data = await _invoke({
      'kind': 'supplement_photo',
      'image': _imagePayload(imageBytes, mimeType),
      'userNote': userNote,
    });
    return _resultMap(data);
  }

  @override
  Future<Map<String, dynamic>> analyzeBarcodeProduct({
    required List<int> imageBytes,
    required String mimeType,
    required String barcode,
    String? userNote,
  }) async {
    final data = await _invoke({
      'kind': 'barcode_product',
      'image': _imagePayload(imageBytes, mimeType),
      'barcode': barcode,
      'userNote': userNote,
    });
    return _resultMap(data);
  }

  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    final payloadImages = images.map((img) {
      final bytes = img['bytes'] as List<int>;
      final mime = img['mimeType'] as String;
      return _imagePayload(bytes, mime);
    }).toList();

    final data = await _invoke({
      'kind': 'body_fat_estimate',
      'images': payloadImages,
      'biometrics': biometrics,
      'userNote': userNote,
    });
    return _resultMap(data);
  }

  @override
  Future<Map<String, dynamic>> analyzeDreamPhysique({
    required List<Map<String, dynamic>> currentImages,
    required List<Map<String, dynamic>> targetImages,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    final payloadCurrent = currentImages.map((img) {
      final bytes = img['bytes'] as List<int>;
      final mime = img['mimeType'] as String;
      return _imagePayload(bytes, mime);
    }).toList();
    final payloadTarget = targetImages.map((img) {
      final bytes = img['bytes'] as List<int>;
      final mime = img['mimeType'] as String;
      return _imagePayload(bytes, mime);
    }).toList();

    final data = await _invoke({
      'kind': 'dream_physique',
      'currentImages': payloadCurrent,
      'targetImages': payloadTarget,
      'biometrics': biometrics,
      'userNote': userNote,
      // DreamPhysiqueService only reaches this call after the user has
      // accepted the matching, versioned notice in the UI. The Edge Function
      // rejects requests from older clients that do not send this assertion.
      'privacyConsent': {
        'version': dreamPhysiqueImageConsentVersion,
        'granted': true,
      },
    });
    return _resultMap(data);
  }

  @override
  Future<Map<String, dynamic>> analyzeRamblerText({
    required String text,
    String? preferredMealKey,
  }) async {
    final data = await _invoke({
      'kind': 'rambler_food',
      'text': text,
      'mealKey': preferredMealKey,
    });
    return _resultMap(data);
  }

  @override
  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  generateProgramBrief({
    required Map<String, dynamic> profileInputs,
    String? userNote,
  }) async {
    final data = await _invoke({
      'kind': 'program_brief',
      'profileInputs': profileInputs,
      'userNote': userNote,
    });
    return _resultWithProvenance(data);
  }

  @override
  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  analyzePhysiqueCheckIn({
    required List<Map<String, dynamic>> baselineImages,
    required Map<String, dynamic> currentImage,
    required Map<String, dynamic> context,
    String? userNote,
  }) async {
    Map<String, String> encode(Map<String, dynamic> img) =>
        _imagePayload(img['bytes'] as List<int>, img['mimeType'] as String);

    final data = await _invoke({
      'kind': 'physique_checkin',
      'baselineImages': baselineImages.map(encode).toList(),
      'currentImages': [encode(currentImage)],
      'checkinContext': context,
      'userNote': userNote,
      // The caller only reaches this after the user accepted the matching,
      // versioned photo privacy notice; the Edge Function rejects requests
      // without this assertion.
      'privacyConsent': {
        'version': dreamPhysiqueImageConsentVersion,
        'granted': true,
      },
    });
    return _resultWithProvenance(data);
  }

  @override
  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  generateWeeklyReportNarrative({required Map<String, dynamic> facts}) async {
    // No privacyConsent: the facts are numeric aggregates, not photos.
    final data = await _invoke({'kind': 'weekly_report', 'facts': facts});
    return _resultWithProvenance(data);
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions
          .invoke('gemini-analyze', body: body)
          .timeout(const Duration(seconds: 45));
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw Exception('AI analysis returned an invalid response.');
    } on TimeoutException {
      throw Exception(
        'AI analysis timed out. Please check your internet connection and try again.',
      );
    } on SocketException {
      throw Exception(
        'Cannot connect to the server. Please check your internet connection.',
      );
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] is String) {
        throw Exception(details['error'] as String);
      }
      throw Exception(
        'AI analysis failed (${error.status}). Please try again.',
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error connecting to Herculex AI: $e');
    }
  }

  Map<String, dynamic> _resultMap(Map<String, dynamic> data) {
    final result = data['result'];
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('AI analysis returned an invalid JSON result.');
  }

  (Map<String, dynamic> result, Map<String, dynamic> provenance)
  _resultWithProvenance(Map<String, dynamic> data) {
    final result = _resultMap(data);
    final provenance = data['provenance'];
    return (
      result,
      provenance is Map<String, dynamic>
          ? provenance
          : provenance is Map
          ? Map<String, dynamic>.from(provenance)
          : <String, dynamic>{},
    );
  }

  Map<String, String> _imagePayload(List<int> imageBytes, String mimeType) => {
    'mimeType': mimeType,
    'data': base64Encode(imageBytes),
  };
}
