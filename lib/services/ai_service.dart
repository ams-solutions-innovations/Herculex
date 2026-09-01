import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';
import 'package:herculex/services/gemini_backend_service.dart';
import 'package:image_picker/image_picker.dart';

final aiServiceProvider = Provider<AiService>((ref) {
  return AiService(ref);
});

class ExerciseAiScanResult {
  final String identifiedName;
  final String? primaryMuscle;
  final String? equipment;
  final String? category;
  final String? description;
  final double confidence;
  final ExerciseCatalogData? bestMatch;
  final List<ExerciseCatalogData> alternativeMatches;

  const ExerciseAiScanResult({
    required this.identifiedName,
    this.primaryMuscle,
    this.equipment,
    this.category,
    this.description,
    this.confidence = 0.0,
    this.bestMatch,
    this.alternativeMatches = const [],
  });
}

class AiService {
  AiService(this.ref) : _gemini = ref.read(geminiBackendProvider);

  final Ref ref;
  final GeminiBackend _gemini;

  Future<ExerciseCatalogData?> identifyExerciseFromImage(
    XFile imageFile,
  ) async {
    final result = await identifyExerciseDetailedFromImage(imageFile);
    return result?.bestMatch;
  }

  Future<ExerciseAiScanResult?> identifyExerciseDetailedFromImage(
    XFile imageFile,
  ) async {
    try {
      final rawBytes = await imageFile.readAsBytes();
      final mime = _mimeType(imageFile.path);

      final data = await _gemini.identifyExerciseDetailed(
        imageBytes: rawBytes,
        mimeType: mime,
      );

      final identifiedName =
          (data['identifiedName'] as String?)?.trim() ?? 'Unknown';
      if (identifiedName.toLowerCase() == 'unknown' || identifiedName.isEmpty) {
        return null;
      }

      final primaryMuscle = data['primaryMuscle'] as String?;
      final equipment = data['equipment'] as String?;
      final category = data['category'] as String?;
      final description = data['description'] as String?;
      final confidence = (data['confidence'] as num?)?.toDouble() ?? 0.85;

      final catalog =
          ref
              .read(exerciseCatalogProvider(const ExerciseCatalogFilter()))
              .asData
              ?.value ??
          [];

      if (catalog.isEmpty) {
        return ExerciseAiScanResult(
          identifiedName: identifiedName,
          primaryMuscle: primaryMuscle,
          equipment: equipment,
          category: category,
          description: description,
          confidence: confidence,
        );
      }

      final searchWords = identifiedName
          .toLowerCase()
          .split(RegExp(r'\W+'))
          .where((w) => w.length > 2)
          .toSet();

      final scored = <({ExerciseCatalogData exercise, int score})>[];

      for (final ex in catalog) {
        var score = 0;
        final exNameLower = ex.name.toLowerCase();
        final exWords = exNameLower.split(RegExp(r'\W+')).toSet();

        // Exact name match
        if (exNameLower == identifiedName.toLowerCase()) {
          score += 15;
        }

        // Substring match
        if (exNameLower.contains(identifiedName.toLowerCase()) ||
            identifiedName.toLowerCase().contains(exNameLower)) {
          score += 6;
        }

        // Keyword overlap
        for (final w in searchWords) {
          if (exWords.contains(w)) {
            score += 3;
          } else if (exNameLower.contains(w)) {
            score += 2;
          }
        }

        // Muscle match bonus
        if (primaryMuscle != null &&
            ex.primaryMuscle.toLowerCase() == primaryMuscle.toLowerCase()) {
          score += 3;
        }

        // Equipment match bonus
        if (equipment != null &&
            (ex.equipment.toLowerCase().contains(equipment.toLowerCase()) ||
                ex.modality.toLowerCase().contains(equipment.toLowerCase()))) {
          score += 2;
        }

        if (score > 0) {
          scored.add((exercise: ex, score: score));
        }
      }

      scored.sort((a, b) => b.score.compareTo(a.score));

      final bestMatch = scored.isNotEmpty ? scored.first.exercise : null;
      final alternatives = scored.length > 1
          ? scored
                .sublist(1, scored.length.clamp(1, 5))
                .map((s) => s.exercise)
                .toList()
          : <ExerciseCatalogData>[];

      return ExerciseAiScanResult(
        identifiedName: identifiedName,
        primaryMuscle: primaryMuscle ?? bestMatch?.primaryMuscle,
        equipment: equipment ?? bestMatch?.equipment,
        category: category,
        description: description,
        confidence: confidence,
        bestMatch: bestMatch,
        alternativeMatches: alternatives,
      );
    } catch (e) {
      debugPrint('AI Error in identifyExerciseDetailedFromImage: $e');
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
