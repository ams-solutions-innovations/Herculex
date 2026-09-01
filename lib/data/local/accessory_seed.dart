import 'package:drift/drift.dart';

import 'database.dart';

/// Seeds the default accessory + band catalogs (v10). Idempotent — skips when
/// non-custom rows already exist, so re-runs (fresh installs after upgrades,
/// test databases) never duplicate.
class AccessorySeed {
  static const defaultAccessories = [
    ('Belt', 'belt', 1.0),
    ('Knee Sleeves', 'knee_sleeves', 1.0),
    ('Wrist Wraps', 'wrist_wraps', 1.0),
    ('Straps', 'straps', 1.0),
    ('Fat Grips', 'fat_grips', 1.6),
    ('Chains', 'chains', 1.0),
  ];

  /// Common loop-band colors with conservative average tensions (kg).
  static const defaultBands = [
    ('Red (Light)', 'red', 5.0),
    ('Blue', 'blue', 10.0),
    ('Green', 'green', 20.0),
    ('Black', 'black', 30.0),
    ('Purple', 'purple', 40.0),
    ('Orange (Heavy)', 'orange', 50.0),
  ];

  static Future<void> run(AppDatabase db) async {
    final hasAccessories =
        await (db.select(db.accessories)
              ..where((t) => t.isCustom.equals(false))
              ..limit(1))
            .get();
    if (hasAccessories.isEmpty) {
      await db.batch((b) {
        b.insertAll(db.accessories, [
          for (final (name, kind, forearm) in defaultAccessories)
            AccessoriesCompanion.insert(
              name: name,
              kind: kind,
              forearmMultiplier: Value(forearm),
            ),
        ]);
      });
    }

    final hasBands =
        await (db.select(db.bands)
              ..where((t) => t.isCustom.equals(false))
              ..limit(1))
            .get();
    if (hasBands.isEmpty) {
      await db.batch((b) {
        b.insertAll(db.bands, [
          for (final (name, color, tension) in defaultBands)
            BandsCompanion.insert(name: name, color: color, tensionKg: tension),
        ]);
      });
    }
  }
}
