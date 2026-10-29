import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/preferences/pref_value_codec.dart';
import 'package:herculex/data/sync/preferences/synced_preferences_bridge.dart';
import 'package:herculex/data/sync/preferences/syncing_shared_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userId = 'user-1';

bool _isSynced(String key) => key == 'units_metric' || key.startsWith('goals_');

void main() {
  group('PrefValueCodec', () {
    test(
      'round-trips every preference type, keeping int apart from double',
      () {
        for (final value in <Object>[
          true,
          7,
          7.0,
          72.5,
          'kg',
          <String>['a', 'b'],
        ]) {
          final decoded = PrefValueCodec.decode(PrefValueCodec.encode(value));
          expect(decoded, value);
          expect(decoded.runtimeType, value.runtimeType);
        }
      },
    );

    test('unknown or malformed envelopes decode to null', () {
      expect(PrefValueCodec.decode('not json'), isNull);
      expect(PrefValueCodec.decode('{"t":"color","v":"#fff"}'), isNull);
      expect(PrefValueCodec.decode('{"t":"int","v":"7"}'), isNull);
    });
  });

  group('SyncingSharedPreferences', () {
    test('reports local writes but not remote applies or clear()', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SyncingSharedPreferences(
        await SharedPreferences.getInstance(),
      );
      final writes = <(String, Object?)>[];
      prefs.onLocalWrite = (key, value) => writes.add((key, value));

      await prefs.setDouble('goals_goal_kg', 75);
      await prefs.remove('goals_goal_kg');
      await prefs.applyRemote('units_metric', false);
      await prefs.clear();

      expect(writes, [('goals_goal_kg', 75.0), ('goals_goal_kg', null)]);
    });
  });

  group('SyncedPreferencesBridge', () {
    late AppDatabase db;
    late SyncingSharedPreferences prefs;
    late SyncedPreferencesBridge bridge;
    late List<Set<String>> remoteChanges;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'units_metric': true});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      prefs = SyncingSharedPreferences(await SharedPreferences.getInstance());
      remoteChanges = [];
      bridge = SyncedPreferencesBridge(
        db: db,
        prefs: prefs,
        isSynced: _isSynced,
        onRemoteChange: remoteChanges.add,
      );
    });

    tearDown(() async {
      bridge.dispose();
      await db.close();
    });

    Future<List<UserPreferenceData>> rows() =>
        db.select(db.userPreferences).get();

    /// What a pull leaves behind: the row, and no outbox echo for it —
    /// committed together, as `SyncService` applies a table in one
    /// transaction.
    Future<void> pulledRow(String key, Object? value, {bool deleted = false}) =>
        db.transaction(() async {
          await db
              .into(db.userPreferences)
              .insert(
                UserPreferencesCompanion.insert(
                  prefKey: key,
                  valueJson: PrefValueCodec.encode(value ?? ''),
                  syncUuid: Value(
                    SyncedPreferencesBridge.syncUuidFor(_userId, key),
                  ),
                  deletedAt: Value(deleted ? DateTime.now() : null),
                ),
                onConflict: DoUpdate(
                  (_) => UserPreferencesCompanion(
                    valueJson: Value(PrefValueCodec.encode(value ?? '')),
                    deletedAt: Value(deleted ? DateTime.now() : null),
                  ),
                  target: [db.userPreferences.prefKey],
                ),
              );
          await db.delete(db.pendingSyncOps).go();
        });

    Future<void> settle() async {
      await pumpEventQueue();
      await bridge.flush();
      await pumpEventQueue();
      await bridge.flush();
    }

    test('mirrors a registered key while signed in', () async {
      bridge.attach(_userId);
      await prefs.setDouble('goals_goal_kg', 75);
      await settle();

      final row = (await rows()).single;
      expect(row.prefKey, 'goals_goal_kg');
      expect(PrefValueCodec.decode(row.valueJson), 75.0);
      expect(
        row.syncUuid,
        SyncedPreferencesBridge.syncUuidFor(_userId, 'goals_goal_kg'),
      );
      final ops = await db.select(db.pendingSyncOps).get();
      expect(ops.single.entityType, 'user_preferences');
    });

    test('the same account and key give the same row id on every device', () {
      expect(
        SyncedPreferencesBridge.syncUuidFor(_userId, 'units_metric'),
        SyncedPreferencesBridge.syncUuidFor(_userId, 'units_metric'),
      );
      expect(
        SyncedPreferencesBridge.syncUuidFor(_userId, 'units_metric'),
        isNot(SyncedPreferencesBridge.syncUuidFor('user-2', 'units_metric')),
      );
    });

    test('ignores unregistered keys and writes while signed out', () async {
      bridge.attach(_userId);
      await prefs.setString('dashboard_layout_v1', '[]');
      bridge.detach();
      await prefs.setDouble('goals_goal_kg', 70);
      await settle();
      expect(await rows(), isEmpty);
    });

    test('a removal soft-deletes the row', () async {
      bridge.attach(_userId);
      await prefs.setDouble('goals_goal_kg', 75);
      await settle();
      await prefs.remove('goals_goal_kg');
      await settle();
      expect((await rows()).single.deletedAt, isNotNull);
    });

    test('a pulled value lands in preferences and is announced', () async {
      bridge.attach(_userId);
      await settle();
      await pulledRow('goals_goal_kg', 68.5);
      await settle();

      expect(prefs.getDouble('goals_goal_kg'), 68.5);
      expect(remoteChanges.expand((k) => k), contains('goals_goal_kg'));
      // Applying it wrote nothing back up.
      expect(await db.select(db.pendingSyncOps).get(), isEmpty);
    });

    test('a pulled deletion removes the preference', () async {
      await prefs.setDouble('goals_goal_kg', 75);
      bridge.attach(_userId);
      await pulledRow('goals_goal_kg', 75.0, deleted: true);
      await settle();
      expect(prefs.containsKey('goals_goal_kg'), isFalse);
    });

    test('an unpushed local edit is not rolled back by a stale row', () async {
      bridge.attach(_userId);
      await prefs.setDouble('goals_goal_kg', 80);
      await settle();
      // The row still has a pending outbox op: this device's own edit.
      await (db.update(
        db.userPreferences,
      )..where((t) => t.prefKey.equals('goals_goal_kg'))).write(
        UserPreferencesCompanion(valueJson: Value(PrefValueCodec.encode(60.0))),
      );
      await settle();
      expect(prefs.getDouble('goals_goal_kg'), 80);
    });

    test(
      'seedMissing uploads local values the cloud lacks, and only those',
      () async {
        await prefs.setDouble('goals_goal_kg', 75);
        bridge.attach(_userId);
        await pulledRow('units_metric', false);
        await settle();

        await bridge.seedMissing();
        await settle();

        final byKey = {for (final r in await rows()) r.prefKey: r};
        expect(PrefValueCodec.decode(byKey['goals_goal_kg']!.valueJson), 75.0);
        // The account's value won over this device's.
        expect(PrefValueCodec.decode(byKey['units_metric']!.valueJson), false);
        expect(prefs.getBool('units_metric'), false);
      },
    );
  });
}
