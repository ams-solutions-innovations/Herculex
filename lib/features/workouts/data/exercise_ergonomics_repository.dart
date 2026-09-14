import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:herculex/features/workouts/domain/exercise_ergonomics.dart';

class ExerciseErgonomicsRepository {
  static const assetPath = 'assets/data/exercise_ergonomics.json';

  Map<String, ExerciseErgonomics> _cache = {};

  /// Loads the ergonomics corpus from assets into memory.
  Future<void> load() async {
    String raw;
    try {
      raw = await rootBundle.loadString(assetPath);
    } catch (_) {
      final file = File(assetPath);
      if (!file.existsSync()) return;
      raw = file.readAsStringSync();
    }
    
    final map = jsonDecode(raw) as Map<String, dynamic>;
    
    final result = <String, ExerciseErgonomics>{};
    for (final entry in map.entries) {
      final movementSlug = entry.key;
      final guidanceMap = entry.value as Map<String, dynamic>;
      
      final parsedGuidance = <String, ErgonomicGuidance>{};
      for (final gEntry in guidanceMap.entries) {
        parsedGuidance[gEntry.key] = ErgonomicGuidance.fromJson(gEntry.value as Map<String, dynamic>);
      }
      
      result[movementSlug] = ExerciseErgonomics(
        movementSlug: movementSlug,
        guidanceByRatio: parsedGuidance,
      );
    }
    
    _cache = result;
  }

  /// Retrieves the ergonomic guidance for a given [movementSlug].
  ExerciseErgonomics? getForMovement(String movementSlug) {
    return _cache[movementSlug];
  }
  
  /// Retrieves specific guidance for a [movementSlug] and [ratioKey].
  ErgonomicGuidance? getGuidance(String movementSlug, String ratioKey) {
    return _cache[movementSlug]?.guidanceByRatio[ratioKey];
  }
  
  /// For testing or direct injection
  void seed(Map<String, ExerciseErgonomics> data) {
    _cache = data;
  }
}
