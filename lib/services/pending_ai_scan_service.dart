import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AiScanContextType {
  supplement,
  food,
  nutritionLabel,
  exercise,
  bodyFat,
  dreamPhysique,
  workoutPhoto,
}

class PendingAiScanContext {
  final AiScanContextType type;
  final String? mealKey;
  final String? dateIso;
  final String? metricKey;
  final Map<String, dynamic>? extra;
  final DateTime createdAt;

  PendingAiScanContext({
    required this.type,
    this.mealKey,
    this.dateIso,
    this.metricKey,
    this.extra,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'mealKey': mealKey,
    'dateIso': dateIso,
    'metricKey': metricKey,
    'extra': extra,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PendingAiScanContext.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'food';
    final type = AiScanContextType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => AiScanContextType.food,
    );
    return PendingAiScanContext(
      type: type,
      mealKey: json['mealKey'] as String?,
      dateIso: json['dateIso'] as String?,
      metricKey: json['metricKey'] as String?,
      extra: json['extra'] as Map<String, dynamic>?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  bool get isExpired {
    // If older than 1 hour, consider it expired
    return DateTime.now().difference(createdAt).inHours >= 1;
  }
}

final pendingAiScanServiceProvider = Provider<PendingAiScanService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PendingAiScanService(prefs);
});

class PendingAiScanService {
  static const _key = 'herculex_pending_ai_scan_context';

  final SharedPreferences _prefs;

  PendingAiScanService(this._prefs);

  Future<void> setPendingContext(PendingAiScanContext context) async {
    await _prefs.setString(_key, jsonEncode(context.toJson()));
  }

  PendingAiScanContext? getPendingContext() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ctx = PendingAiScanContext.fromJson(map);
      if (ctx.isExpired) {
        clearPendingContext();
        return null;
      }
      return ctx;
    } catch (_) {
      clearPendingContext();
      return null;
    }
  }

  Future<void> clearPendingContext() async {
    await _prefs.remove(_key);
  }
}
