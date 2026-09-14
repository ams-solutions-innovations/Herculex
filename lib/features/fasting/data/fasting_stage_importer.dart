import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/fasting/domain/fasting_stage.dart';

class FastingStageImporter {
  static const assetPath = 'assets/data/fasting_stages.json';

  static List<FastingStage> parseFromJson(String raw) {
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => FastingStage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Loads the bundled fasting stages asset and seeds the local database.
  static Future<List<FastingStage>> loadStagesFromAsset() async {
    String raw;
    try {
      raw = await rootBundle.loadString(assetPath);
    } catch (_) {
      final file = File(assetPath);
      if (!file.existsSync()) return [];
      raw = file.readAsStringSync();
    }

    return parseFromJson(raw);
  }

  static Future<void> runFromAsset(AppDatabase db) async {
    final stages = await loadStagesFromAsset();
    if (stages.isEmpty) return;

    await db.batch((batch) {
      for (final stage in stages) {
        batch.insert(
          db.fastingStages,
          FastingStagesCompanion.insert(
            hour: Value(stage.hour),
            stageName: stage.stageName,
            stageCategory: stage.stageCategory,
            shortMessage: stage.shortMessage,
            detail: Value(stage.detail),
            icon: Value(stage.icon),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }
}
