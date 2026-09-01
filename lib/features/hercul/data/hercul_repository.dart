import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart' hide HerculRule;
import '../domain/hercul_rule.dart';

final herculRepositoryProvider = Provider<HerculRepository>((ref) {
  return HerculRepository(ref.watch(appDatabaseProvider));
});

class HerculRepository {
  final AppDatabase _db;

  HerculRepository(this._db);

  /// Fetches all imported coaching rules from the database.
  Future<List<HerculRule>> fetchRules() async {
    final rows = await _db.select(_db.herculRules).get();
    return rows.map((row) {
      final requires = List<String>.from(jsonDecode(row.requiresJson) as List);
      final whenJson = jsonDecode(row.whenJson) as List;
      final ctaJson = row.ctaJson != null
          ? jsonDecode(row.ctaJson!) as Map<String, dynamic>
          : null;

      return HerculRule(
        id: row.id,
        domain: HerculDomain.fromId(row.domain),
        priority: row.priority,
        cooldownDays: row.cooldownDays,
        requires: requires,
        when: whenJson
            .map((e) => HerculCondition.fromJson((e as Map).cast()))
            .toList(),
        copy: {
          HerculTone.normal: row.copyNormal,
          HerculTone.honest: row.copyHonest,
        },
        cta: ctaJson != null ? HerculCta.fromJson(ctaJson) : null,
      );
    }).toList();
  }

  /// Fetches the last fired timestamps for all rules.
  Future<Map<String, DateTime>> fetchMessageLog() async {
    final rows = await _db.select(_db.herculMessageLog).get();
    return {for (final row in rows) row.ruleId: row.lastFiredAt};
  }

  /// Logs that a rule was just fired.
  Future<void> logFired(String ruleId, DateTime now) async {
    await _db
        .into(_db.herculMessageLog)
        .insert(
          HerculMessageLogCompanion.insert(ruleId: ruleId, lastFiredAt: now),
          mode: InsertMode.insertOrReplace,
        );
  }
}
