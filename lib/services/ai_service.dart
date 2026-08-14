import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/local/database.dart';
import '../features/workouts/presentation/workouts_providers.dart';
import 'gemini_backend_service.dart';

final aiServiceProvider = Provider<AiService>((ref) {
  return AiService(ref);
});

class AiService {
  AiService(this.ref) : _gemini = ref.read(geminiBackendProvider);

  final Ref ref;
  final GeminiBackend _gemini;

  Future<ExerciseCatalogData?> identifyExerciseFromImage(
    XFile imageFile,
  ) async {
    try {
      final text = await _gemini.identifyExercise(
        imageBytes: await imageFile.readAsBytes(),
        mimeType: _mimeType(imageFile.path),
      );
      if (text.toLowerCase() == 'unknown') return null;

      final catalog =
          ref
              .read(exerciseCatalogProvider(const ExerciseCatalogFilter()))
              .asData
              ?.value ??
          [];

      if (catalog.isEmpty) return null;

      final words = text.toLowerCase().split(RegExp(r'\W+'));
      ExerciseCatalogData? bestMatch;
      var bestScore = 0;

      for (final ex in catalog) {
        final exWords = ex.name.toLowerCase().split(RegExp(r'\W+'));
        var score = 0;
        for (final w in words) {
          if (exWords.contains(w)) score++;
        }
        if (score > bestScore) {
          bestScore = score;
          bestMatch = ex;
        }
      }

      return bestMatch;
    } catch (e) {
      // The image picker is an assistive shortcut. Failure should not block
      // manual exercise search or logging.
      debugPrint('AI Error: $e');
      return null;
    }
  }

  String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
