part of 'wear_workout_sync_service.dart';

extension _AppleWatchWorkoutSync on WearWorkoutSyncService {
  Future<Map<String, dynamic>> _appleHealthExport(String entityId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM watch_health_exports WHERE entity_id = ?',
          variables: [Variable(entityId)],
        )
        .get();
    if (rows.isEmpty) return {'owner': 'phone', 'status': 'unclaimed'};
    return {
      'owner': rows.single.data['owner'],
      'status': rows.single.data['status'],
      'healthKitUuid': rows.single.data['healthkit_uuid'],
    };
  }

  /// Final snapshots are self-contained: offline finishes never depend on
  /// an earlier start/update having reached the phone.
  Future<bool> _handleAppleWatchWorkoutEvent(Map<String, dynamic> event) async {
    Map<String, _PhoneSetSyncState>? stateBefore;
    var committed = false;
    try {
      await _enqueueRemoteApply(() async {
        stateBefore = {
          for (final entry in _setSyncStates.entries)
            entry.key: entry.value.copy(),
        };
        final envelope = _decodeWorkoutEnvelope(
          event['session_json'] as String,
        );
        _revisionAllocator.observe(envelope.revision);
        final eventId = event['eventId'] as String;
        final action = event['action'] as String;
        if (!const [
              'updated',
              'finished',
              'discarded',
              'healthClaim',
              'healthSaved',
            ].contains(action) ||
            envelope.schemaVersion != wearSyncSchemaVersion ||
            envelope.entityId.isEmpty) {
          throw const FormatException('Unsupported Apple Watch event');
        }
        await WatchCommandInbox(
          _db,
        ).applyOnce('apple_workout', eventId, () async {
          final previous = await _db
              .customSelect(
                'SELECT * FROM apple_watch_sessions WHERE entity_id = ?',
                variables: [Variable(envelope.entityId)],
              )
              .get();
          final existing =
              await (_db.select(_db.workoutSessions)
                    ..where((t) => t.sessionUuid.equals(envelope.entityId)))
                  .getSingleOrNull();
          final data = envelope.payload;
          final health = data['healthExport'] as Map?;
          if (health?['owner'] == 'watch') {
            await _db.customStatement(
              'INSERT OR IGNORE INTO watch_health_exports (entity_id, owner, status) VALUES (?, ?, ?)',
              [envelope.entityId, 'watch', 'pending'],
            );
            if (health?['status'] == 'saved' &&
                health?['healthKitUuid'] is String) {
              await _db.customStatement(
                "UPDATE watch_health_exports SET status = 'saved', healthkit_uuid = ? WHERE entity_id = ? AND owner = 'watch'",
                [health!['healthKitUuid'], envelope.entityId],
              );
            }
          }
          final wasTerminal =
              previous.isNotEmpty && previous.single.data['terminal'] == 1;
          if (wasTerminal || existing?.endedAt != null) return;
          if (previous.isNotEmpty &&
              (previous.single.data['revision'] as int) >= envelope.revision) {
            return;
          }
          final terminal = action == 'finished' || action == 'discarded';
          final active = await _workoutsRepository.watchActiveSession().first;
          int? sessionId = existing?.id;
          // Defer a second active session until its final snapshot. Never end
          // an unrelated phone workout just to adopt an offline watch session.
          final deferred = sessionId == null && active != null && !terminal;
          if (!deferred && action != 'discarded') {
            sessionId ??= await _workoutsRepository.startSession(
              sessionUuid: envelope.entityId,
            );
            await _syncSessionStateToDrift(
              sessionId,
              data,
              sessionEntityId: envelope.entityId,
              fallbackStamp: _fallbackSetStamp(envelope),
            );
            final started = (data['startedAtEpochMs'] as num?)?.toInt();
            final name = (data['template'] as Map?)?['name'] as String?;
            await (_db.update(
              _db.workoutSessions,
            )..where((t) => t.id.equals(sessionId!))).write(
              WorkoutSessionsCompanion(
                startedAt: started == null
                    ? const Value.absent()
                    : Value(DateTime.fromMillisecondsSinceEpoch(started)),
                name: name == null ? const Value.absent() : Value(name),
              ),
            );
            if (terminal) {
              if (event['saveAsTemplate'] == true) {
                await _ref
                    .read(templatesRepositoryProvider)
                    .saveSessionAsTemplate(sessionId, name ?? 'Watch Template');
              }
              await _workoutsRepository.endSession(
                sessionId,
                endedAt: DateTime.fromMillisecondsSinceEpoch(
                  (data['endedAtEpochMs'] as num).toInt(),
                ),
                caloriesBurned: (data['activeEnergyKcal'] as num?)?.round(),
              );
            } else {
              _lastSyncedSessionId = sessionId;
              _lastSyncedEntityId = envelope.entityId;
              _captureCursor(data);
            }
          } else if (action == 'discarded' && sessionId != null) {
            await _workoutsRepository.deleteSession(sessionId);
          }
          await _db.customStatement(
            'INSERT INTO apple_watch_sessions (entity_id, revision, terminal, payload_json, session_id) '
            'VALUES (?, ?, ?, ?, ?) ON CONFLICT(entity_id) DO UPDATE SET '
            'revision=excluded.revision, terminal=excluded.terminal, payload_json=excluded.payload_json, session_id=excluded.session_id',
            [
              envelope.entityId,
              envelope.revision,
              terminal ? 1 : 0,
              envelope.encode(),
              sessionId,
            ],
          );
        });
        committed = true;
        await _wearSyncService.syncAppleHealthOwnership(
          envelope.entityId,
          await _appleHealthExport(envelope.entityId),
        );
      });
      return true;
    } catch (error, stack) {
      if (!committed && stateBefore != null) {
        _setSyncStates
          ..clear()
          ..addAll(stateBefore!);
        _persistSetSyncStates();
      }
      debugPrint('Apple Watch event retained for retry: $error\n$stack');
      return false;
    }
  }
}
