
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';

import '../data/local/database.dart';
import '../features/workouts/presentation/workouts_providers.dart';

final aiServiceProvider = Provider<AiService>((ref) {
  return AiService(ref);
});

class AiService {
  final Ref ref;
  late final GenerativeModel? _model;
  
  AiService(this.ref) {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
    if (apiKey.isNotEmpty) {
      _model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
      );
    } else {
      _model = null;
    }
  }

  Future<ExerciseCatalogData?> identifyExerciseFromImage(XFile imageFile) async {
    if (_model == null) {
      throw Exception('Gemini API key is not configured. Please build with --dart-define=GEMINI_API_KEY=...');
    }
    
    final bytes = await imageFile.readAsBytes();
    
    final prompt = TextPart('''
Analyze this image of a gym machine or exercise equipment.
Identify the exercise or machine.
Return ONLY the name of the exercise/machine. 
If it is a chest press machine, do NOT just say "Chest Press Machine". It must be "Plate Loaded Chest Press" or "Pin Loaded Chest Press" depending on what you see.
If you don't know, return "Unknown".
''');

    final imageParts = [
      DataPart('image/jpeg', bytes),
    ];

    try {
      final response = await _model.generateContent([
        Content.multi([prompt, ...imageParts])
      ]);
      
      final text = response.text?.trim() ?? 'Unknown';
      if (text.toLowerCase() == 'unknown') return null;
      
      // Now fuzzy match this text against the catalog.
      final catalog = ref.read(exerciseCatalogProvider(const ExerciseCatalogFilter())).asData?.value ?? [];
      
      if (catalog.isEmpty) return null;
      
      // Basic fuzzy matching - find the one with the most matching words
      final words = text.toLowerCase().split(RegExp(r'\W+'));
      ExerciseCatalogData? bestMatch;
      int bestScore = 0;
      
      for (final ex in catalog) {
        final exWords = ex.name.toLowerCase().split(RegExp(r'\W+'));
        int score = 0;
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
      print('AI Error: $e');
      return null;
    }
  }
}
