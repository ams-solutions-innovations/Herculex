import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/preferences/pref_value_codec.dart';
import 'package:herculex/data/sync/preferences/syncing_shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Keeps the registered SharedPreferences keys and the synced
/// `user_preferences` table in step, so the profile and settings follow the
/// account to every device.
///
/// * A local write to a registered key (while signed in) upserts its row; the
///   outbox triggers push it like any other synced row.
/// * Rows that change in the table — almost always because a pull brought
///   them — are written back into SharedPreferences without echoing, and
///   [onRemoteChange] tells the app which keys moved so it can refresh the
///   providers that read them.
/// * After the account's first full pull, [seedMissing] uploads registered
///   keys the cloud doesn't have yet. Keys it *does* have were already applied
///   over the local ones: on a second device, the account's settings win.
///
/// Which keys sync is the app layer's decision ([isSynced]); this class knows
/// nothing about features.
class SyncedPreferencesBridge {
  SyncedPreferencesBridge({
    required AppDatabase db,
    required SyncingSharedPreferences prefs,
    required bool Function(String key) isSynced,
    required void Function(Set<String> keys) onRemoteChange,
  }) : _db = db,
       _prefs = prefs,
       _isSynced = isSynced,
       _onRemoteChange = onRemoteChange;

  final AppDatabase _db;
  final SyncingSharedPreferences _prefs;
  final bool Function(String key) _isSynced;
  final void Function(Set<String> keys) _onRemoteChange;

  String? _userId;
  StreamSubscription<List<UserPreferenceData>>? _rowsSub;

  /// Serialises table writes and remote applies, so a burst of local edits
  /// and a pull can't interleave.
  Future<void> _queue = Future.value();

  Future<void> _enqueue(Future<void> Function() task) =>
      _queue = _queue.then((_) => task()).catchError((Object _) {});

  /// Same id for the same account and key on every device, so they all
  /// write one remote row instead of racing to create their own.
  static String syncUuidFor(String userId, String key) =>
      const Uuid().v5(Namespace.url.value, 'herculex:user-pref:$userId:$key');

  /// Starts mirroring for [userId] (on sign-in or a restored session).
  void attach(String userId) {
    _userId = userId;
    _prefs.onLocalWrite = _onLocalWrite;
    _rowsSub ??= _db
        .select(_db.userPreferences)
        .watch()
        .listen((rows) => unawaited(_enqueue(() => _applyRows(rows))));
  }

  /// Stops mirroring (sign-out). Preferences written while signed out stay
  /// local until the next [seedMissing].
  void detach() {
    _userId = null;
    _prefs.onLocalWrite = null;
    unawaited(_rowsSub?.cancel());
    _rowsSub = null;
  }

  void dispose() => detach();

  /// Uploads every registered key that has a local value but no row yet.
  Future<void> seedMissing() => _enqueue(() async {
    if (_userId == null) return;
    final known = {
      for (final row in await _db.select(_db.userPreferences).get())
        row.prefKey,
    };
    for (final key in _prefs.getKeys()) {
      if (!_isSynced(key) || known.contains(key)) continue;
      final value = _prefs.get(key);
      if (value != null) await _upsert(key, value);
    }
  });

  /// Lets a test wait for queued work.
  Future<void> flush() => _queue;

  void _onLocalWrite(String key, Object? value) {
    if (_userId == null || !_isSynced(key)) return;
    unawaited(_enqueue(() => _upsert(key, value)));
  }

  Future<void> _upsert(String key, Object? value) async {
    final userId = _userId;
    if (userId == null) return;
    final now = DateTime.now();
    if (value == null) {
      await (_db.update(
        _db.userPreferences,
      )..where((t) => t.prefKey.equals(key) & t.deletedAt.isNull())).write(
        UserPreferencesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      return;
    }
    final encoded = PrefValueCodec.encode(value);
    await _db
        .into(_db.userPreferences)
        .insert(
          UserPreferencesCompanion.insert(
            prefKey: key,
            valueJson: encoded,
            syncUuid: Value(syncUuidFor(userId, key)),
            updatedAt: Value(now),
          ),
          onConflict: DoUpdate(
            (_) => UserPreferencesCompanion(
              valueJson: Value(encoded),
              deletedAt: const Value(null),
              updatedAt: Value(now),
            ),
            target: [_db.userPreferences.prefKey],
          ),
        );
  }

  Future<void> _applyRows(List<UserPreferenceData> rows) async {
    if (_userId == null) return;
    // A row with an unpushed local edit is this device's own newer value —
    // possibly from a snapshot that predates a later edit. Applying it could
    // roll the preference back, so local wins until the push lands.
    final pendingUuids = {
      for (final op in await (_db.select(
        _db.pendingSyncOps,
      )..where((t) => t.entityType.equals('user_preferences'))).get())
        op.entityId,
    };

    final changed = <String>{};
    for (final row in rows) {
      if (!_isSynced(row.prefKey)) continue;
      if (pendingUuids.contains(row.syncUuid)) continue;
      final Object? remote;
      if (row.deletedAt != null) {
        remote = null;
      } else {
        remote = PrefValueCodec.decode(row.valueJson);
        // Malformed, or a type a newer app version wrote: leave it alone.
        if (remote == null) continue;
      }
      if (_sameValue(_prefs.get(row.prefKey), remote)) continue;
      await _prefs.applyRemote(row.prefKey, remote);
      changed.add(row.prefKey);
    }
    if (changed.isNotEmpty) _onRemoteChange(changed);
  }

  static bool _sameValue(Object? a, Object? b) => a is List && b is List
      ? const ListEquality<Object?>().equals(a, b)
      : a == b;
}
