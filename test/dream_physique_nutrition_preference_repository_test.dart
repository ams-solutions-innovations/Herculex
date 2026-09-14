import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/profile/data/dream_physique_nutrition_preference_repository.dart';
import 'package:herculex/features/profile/domain/dream_physique_nutrition_recommendation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'persists only the member choice, dismissal and analysis timestamp',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = DreamPhysiqueNutritionPreferenceRepository(
        preferences,
      );
      addTearDown(repository.dispose);

      await repository.save(
        DreamPhysiqueNutritionPreference(
          summaryAnalyzedAt: DateTime.utc(2026, 9, 11),
          selectedDirection: PhysiqueNutritionDirection.maingain,
        ),
      );

      expect(
        repository.current?.selectedDirection,
        PhysiqueNutritionDirection.maingain,
      );
      final saved =
          jsonDecode(
                preferences.getString(
                  'herculex.dream_physique_nutrition_preference.v1',
                )!,
              )
              as Map<String, dynamic>;
      expect(
        saved.keys,
        containsAll(['summaryAnalyzedAt', 'selectedDirection', 'dismissed']),
      );
      expect(saved.containsKey('photo'), isFalse);
      expect(saved.containsKey('imagePath'), isFalse);
      expect(saved.containsKey('weightKg'), isFalse);
    },
  );
}
