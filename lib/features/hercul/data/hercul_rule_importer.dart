import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:herculex/data/local/database.dart' hide HerculRule;
import 'package:herculex/features/hercul/domain/hercul_rule.dart';

/// Imports the authored coaching rules (`assets/data/hercul_rules.json`) into
/// the database. Idempotent: upserts by [HerculRules.id]. Safe to re-run
/// on every app upgrade so new rules or copy tweaks take effect immediately.
class HerculRuleImporter {
  static const assetPath = 'assets/data/hercul_rules.json';

  /// Loads the bundled asset and imports it. Falls back to direct file I/O
  /// if the asset bundle is unavailable (e.g. during unit tests).
  static Future<void> runFromAsset(AppDatabase db) async {
    String raw;
    try {
      raw = await rootBundle.loadString(assetPath);
    } catch (_) {
      final file = File(assetPath);
      if (!file.existsSync()) return;
      raw = file.readAsStringSync();
    }

    final list = jsonDecode(raw) as List;
    final rules = list
        .map((e) => HerculRule.fromJson(e as Map<String, dynamic>))
        .toList();

    await db.batch((batch) {
      for (final rule in rules) {
        batch.insert(
          db.herculRules,
          HerculRulesCompanion.insert(
            id: rule.id,
            domain: rule.domain.name,
            priority: rule.priority,
            cooldownDays: rule.cooldownDays,
            requiresJson: jsonEncode(rule.requires),
            whenJson: jsonEncode(
              rule.when
                  .map(
                    (c) => {
                      'signal': c.signal,
                      'op': c.op.id,
                      if (c.arg != null) 'arg': c.arg,
                      if (c.value != null) 'value': c.value,
                      if (c.upper != null) 'upper': c.upper,
                      if (c.text != null) 'text': c.text,
                    },
                  )
                  .toList(),
            ),
            copyNormal: rule.copy[HerculTone.normal]!,
            copyHonest: rule.copy[HerculTone.honest]!,
            ctaJson: Value(
              rule.cta != null
                  ? jsonEncode({
                      'type': rule.cta!.type,
                      'value': rule.cta!.value,
                    })
                  : null,
            ),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }
}
