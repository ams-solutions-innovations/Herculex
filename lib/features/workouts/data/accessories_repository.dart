import 'package:drift/drift.dart';

import '../../../data/local/database.dart';

/// Accessories + bands catalogs and their per-set attachments (V2 §5–§8).
class AccessoriesRepository {
  final AppDatabase _db;

  AccessoriesRepository(this._db);

  // ── Catalogs ─────────────────────────────────────────────────────────────

  Stream<List<AccessoryData>> watchAccessories() {
    return (_db.select(
      _db.accessories,
    )..orderBy([(t) => OrderingTerm(expression: t.id)])).watch();
  }

  Future<int> createCustomAccessory(
    String name, {
    double forearmMultiplier = 1.0,
  }) {
    return _db
        .into(_db.accessories)
        .insert(
          AccessoriesCompanion.insert(
            name: name,
            kind: 'custom',
            forearmMultiplier: Value(forearmMultiplier),
            isCustom: const Value(true),
          ),
        );
  }

  Stream<List<BandData>> watchBands() {
    return (_db.select(
      _db.bands,
    )..orderBy([(t) => OrderingTerm(expression: t.tensionKg)])).watch();
  }

  Future<int> createCustomBand({
    required String name,
    required String color,
    required double tensionKg,
  }) {
    return _db
        .into(_db.bands)
        .insert(
          BandsCompanion.insert(
            name: name,
            color: color,
            tensionKg: tensionKg,
            isCustom: const Value(true),
          ),
        );
  }

  // ── Per-set attachments ──────────────────────────────────────────────────

  Stream<List<SetAccessoryData>> watchSetAccessories(int setEntryId) {
    return (_db.select(
      _db.setAccessories,
    )..where((t) => t.setEntryId.equals(setEntryId))).watch();
  }

  /// Toggles an accessory on a set; returns true when now attached.
  Future<bool> toggleSetAccessory({
    required int setEntryId,
    required int accessoryId,
  }) async {
    final existing =
        await (_db.select(_db.setAccessories)..where(
              (t) =>
                  t.setEntryId.equals(setEntryId) &
                  t.accessoryId.equals(accessoryId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await (_db.delete(
        _db.setAccessories,
      )..where((t) => t.id.equals(existing.id))).go();
      return false;
    }
    await _db
        .into(_db.setAccessories)
        .insert(
          SetAccessoriesCompanion.insert(
            setEntryId: setEntryId,
            accessoryId: accessoryId,
          ),
        );
    return true;
  }

  /// Copies the previous set's accessory selection onto a new set so toggles
  /// persist down the exercise without re-tapping (Hevy-style UX, §26).
  Future<void> copySetAccessories({
    required int fromSetId,
    required int toSetId,
  }) async {
    final rows = await (_db.select(
      _db.setAccessories,
    )..where((t) => t.setEntryId.equals(fromSetId))).get();
    await _db.batch((b) {
      b.insertAll(_db.setAccessories, [
        for (final r in rows)
          SetAccessoriesCompanion.insert(
            setEntryId: toSetId,
            accessoryId: r.accessoryId,
          ),
      ]);
    });
  }

  Stream<List<SetBandData>> watchSetBands(int setEntryId) {
    return (_db.select(
      _db.setBands,
    )..where((t) => t.setEntryId.equals(setEntryId))).watch();
  }

  Future<int> attachBand({
    required int setEntryId,
    required int bandId,
    int count = 1,
    required bool isResistance,
  }) {
    return _db
        .into(_db.setBands)
        .insert(
          SetBandsCompanion.insert(
            setEntryId: setEntryId,
            bandId: bandId,
            count: Value(count),
            mode: Value(isResistance ? 'resistance' : 'assistance'),
          ),
        );
  }

  Future<void> detachBand(int setBandId) async {
    await (_db.delete(_db.setBands)..where((t) => t.id.equals(setBandId))).go();
  }
}
