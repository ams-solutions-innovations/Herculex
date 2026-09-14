import 'dart:async';
import 'dart:convert';

import 'package:herculex/features/profile/domain/dream_physique_nutrition_recommendation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The member-owned response to an optional nutrition suggestion.
///
/// It only stores a direction, dismissal flag and analysis timestamp. No photo
/// data, body measurements, or AI response is duplicated here.
class DreamPhysiqueNutritionPreference {
  const DreamPhysiqueNutritionPreference({
    required this.summaryAnalyzedAt,
    this.selectedDirection,
    this.dismissed = false,
  });

  final DateTime summaryAnalyzedAt;
  final PhysiqueNutritionDirection? selectedDirection;
  final bool dismissed;

  Map<String, dynamic> toJson() => {
    'summaryAnalyzedAt': summaryAnalyzedAt.toUtc().toIso8601String(),
    'selectedDirection': selectedDirection?.name,
    'dismissed': dismissed,
  };

  factory DreamPhysiqueNutritionPreference.fromJson(Map<String, dynamic> json) {
    final timestamp = json['summaryAnalyzedAt'];
    final parsedTimestamp = timestamp is String
        ? DateTime.tryParse(timestamp)
        : null;
    if (parsedTimestamp == null || json['dismissed'] is! bool) {
      throw const FormatException(
        'Invalid Dream Physique nutrition preference.',
      );
    }
    final rawDirection = json['selectedDirection'];
    PhysiqueNutritionDirection? selectedDirection;
    if (rawDirection is String) {
      for (final value in PhysiqueNutritionDirection.values) {
        if (value.name == rawDirection) {
          selectedDirection = value;
          break;
        }
      }
    }
    if (rawDirection != null && selectedDirection == null) {
      throw const FormatException(
        'Invalid Dream Physique nutrition direction.',
      );
    }
    return DreamPhysiqueNutritionPreference(
      summaryAnalyzedAt: parsedTimestamp.toUtc(),
      selectedDirection: selectedDirection,
      dismissed: json['dismissed'] as bool,
    );
  }
}

class DreamPhysiqueNutritionPreferenceRepository {
  static const _storageKey = 'herculex.dream_physique_nutrition_preference.v1';

  DreamPhysiqueNutritionPreferenceRepository(this._preferences) {
    _controller.onListen = () {
      scheduleMicrotask(() {
        if (!_controller.isClosed) _controller.add(current);
      });
    };
  }

  final SharedPreferences _preferences;
  final _controller =
      StreamController<DreamPhysiqueNutritionPreference?>.broadcast();

  DreamPhysiqueNutritionPreference? get current {
    final raw = _preferences.getString(_storageKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return DreamPhysiqueNutritionPreference.fromJson(
        Map<String, dynamic>.from(json),
      );
    } catch (_) {
      return null;
    }
  }

  Stream<DreamPhysiqueNutritionPreference?> watch() => _controller.stream;

  Future<void> save(DreamPhysiqueNutritionPreference preference) async {
    await _preferences.setString(_storageKey, jsonEncode(preference.toJson()));
    _controller.add(preference);
  }

  void dispose() => _controller.close();
}
