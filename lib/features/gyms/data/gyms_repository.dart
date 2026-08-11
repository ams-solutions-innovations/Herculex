import 'package:drift/drift.dart';

import '../../../data/local/database.dart';

/// Gym profiles (V2 §10). Single facade over the [Gyms] table.
class GymsRepository {
  final AppDatabase _db;

  GymsRepository(this._db);

  Stream<List<GymData>> watchGyms() {
    return (_db.select(_db.gyms)
          ..orderBy([
            (t) => OrderingTerm(expression: t.isDefault, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.name),
          ]))
        .watch();
  }

  Future<GymData?> getDefaultGym() {
    return (_db.select(_db.gyms)
          ..where((t) => t.isDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int> createGym(String name, {bool isDefault = false}) async {
    return _db.transaction(() async {
      if (isDefault) await _clearDefault();
      return _db.into(_db.gyms).insert(
            GymsCompanion.insert(name: name, isDefault: Value(isDefault)),
          );
    });
  }

  Future<void> renameGym(int id, String name) async {
    await (_db.update(_db.gyms)..where((t) => t.id.equals(id)))
        .write(GymsCompanion(name: Value(name)));
  }

  Future<void> setDefaultGym(int id) async {
    await _db.transaction(() async {
      await _clearDefault();
      await (_db.update(_db.gyms)..where((t) => t.id.equals(id)))
          .write(const GymsCompanion(isDefault: Value(true)));
    });
  }

  /// Sessions and saved machine settings referencing the gym keep their rows;
  /// their `gymId` is nulled out (set-null) before the gym itself is deleted.
  Future<void> deleteGym(int id) async {
    await _db.transaction(() async {
      await (_db.update(_db.workoutSessions)..where((t) => t.gymId.equals(id)))
          .write(const WorkoutSessionsCompanion(gymId: Value(null)));
      await (_db.update(_db.machineSettings)
            ..where((t) => t.gymId.equals(id)))
          .write(const MachineSettingsCompanion(gymId: Value(null)));
      await (_db.delete(_db.gyms)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<void> _clearDefault() async {
    await (_db.update(_db.gyms)..where((t) => t.isDefault.equals(true)))
        .write(const GymsCompanion(isDefault: Value(false)));
  }
}
