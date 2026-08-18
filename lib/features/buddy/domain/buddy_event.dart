/// The buddy live-workout wire contract: the event kinds, the exercise
/// reference shape, and the five payload bodies that travel over the
/// realtime broadcast channel and the durable event log.
///
/// **This file, together with everything under `lib/features/buddy/data/`,
/// is the buddy transport module** — see
/// `test/buddy/buddy_scope_boundary_test.dart`, the structural gate that
/// pins this rule: the transport module must never carry the caller-side
/// broadcast-vs-local-only decision (kept in a sibling file, deliberately
/// not imported here) as a serialised field. A change to who an action is
/// visible to must never reach the publisher, let alone the wire — it stays
/// entirely in the caller.
library;

/// The five actions a buddy session's event log can carry.
enum BuddyEventKind {
  add,
  remove,
  reorder,
  replace,
  sessionEnded;

  /// The snake_case form PostgREST/Supabase broadcast payloads use.
  String get wireName {
    switch (this) {
      case BuddyEventKind.add:
        return 'add';
      case BuddyEventKind.remove:
        return 'remove';
      case BuddyEventKind.reorder:
        return 'reorder';
      case BuddyEventKind.replace:
        return 'replace';
      case BuddyEventKind.sessionEnded:
        return 'session_ended';
    }
  }

  /// Parses [wireName]'s inverse. Returns null on any unrecognised value —
  /// callers decide how to handle an unknown kind (e.g. a future app
  /// version broadcasting a kind this build predates); this file does not
  /// throw on their behalf.
  static BuddyEventKind? fromWire(String wire) {
    for (final kind in BuddyEventKind.values) {
      if (kind.wireName == wire) return kind;
    }
    return null;
  }
}

/// A reference to a catalogue exercise row, exactly one of [uuid] (a custom
/// row's `sync_uuid`) or [slug] (a seeded row's stable natural key) —
/// mirroring `SyncIdResolver.resolveCatalogueRefForPush`'s
/// exactly-one-of contract for the same reason: seeded rows are identical
/// on every device from the bundled assets and are never pushed, so they
/// resolve by slug; custom rows only exist on the device(s) that created
/// them, so they resolve by uuid.
class BuddyExerciseRef {
  BuddyExerciseRef({this.uuid, this.slug}) {
    if ((uuid == null) == (slug == null)) {
      throw ArgumentError(
        'BuddyExerciseRef requires exactly one of uuid or slug to be set '
        '(got uuid=$uuid, slug=$slug).',
      );
    }
  }

  /// A custom exercise's `sync_uuid`. Null when [slug] is set.
  final String? uuid;

  /// A seeded exercise's stable natural key. Null when [uuid] is set.
  final String? slug;

  Map<String, dynamic> toJson() => {'uuid': uuid, 'slug': slug};

  factory BuddyExerciseRef.fromJson(Map<String, dynamic> json) =>
      BuddyExerciseRef(
        uuid: json['uuid'] as String?,
        slug: json['slug'] as String?,
      );
}

/// One event in a buddy session's log: a single actor performed a single
/// action, recorded with a monotonically increasing [seq] so both devices
/// can order and de-duplicate deliveries from the broadcast channel and the
/// durable log the same way.
class BuddyEvent {
  const BuddyEvent({
    required this.buddySessionId,
    required this.seq,
    required this.actorUserId,
    required this.kind,
    required this.payload,
  });

  final String buddySessionId;
  final int seq;
  final String actorUserId;
  final BuddyEventKind kind;
  final Map<String, dynamic> payload;

  /// Builds from a Supabase realtime broadcast payload: `seq`, `kind`,
  /// `actor`, `payload`. A broadcast is delivered on the session's own
  /// realtime channel, so the channel context (not the payload) carries
  /// the session id — [buddySessionId] defaults to the empty string here
  /// and is expected to be filled in by the caller that already knows which
  /// channel it subscribed to.
  factory BuddyEvent.fromBroadcast(Map<String, dynamic> payload) {
    final wireKind = payload['kind'] as String;
    final kind = BuddyEventKind.fromWire(wireKind);
    if (kind == null) {
      throw ArgumentError('Unknown BuddyEventKind wire value: $wireKind');
    }
    return BuddyEvent(
      buddySessionId: payload['buddySessionId'] as String? ?? '',
      seq: payload['seq'] as int,
      actorUserId: payload['actor'] as String,
      kind: kind,
      payload: Map<String, dynamic>.from(payload['payload'] as Map),
    );
  }

  /// Builds from a row of the durable event log table as PostgREST returns
  /// it: `buddy_session_id`, `seq`, `actor_user_id`, `kind`, `payload`.
  factory BuddyEvent.fromLogRow(Map<String, dynamic> row) {
    final wireKind = row['kind'] as String;
    final kind = BuddyEventKind.fromWire(wireKind);
    if (kind == null) {
      throw ArgumentError('Unknown BuddyEventKind wire value: $wireKind');
    }
    return BuddyEvent(
      buddySessionId: row['buddy_session_id'] as String,
      seq: row['seq'] as int,
      actorUserId: row['actor_user_id'] as String,
      kind: kind,
      payload: Map<String, dynamic>.from(row['payload'] as Map),
    );
  }
}

/// Adds an exercise at [slotId], optionally positioned after [afterSlotId]
/// (null means "at the start") with an optional [equipmentVariant] label.
class BuddyAddPayload {
  BuddyAddPayload({
    required this.slotId,
    required this.ref,
    this.afterSlotId,
    this.equipmentVariant,
  });

  final String slotId;
  final BuddyExerciseRef ref;
  final String? afterSlotId;
  final String? equipmentVariant;

  Map<String, dynamic> toJson() => {
    'slotId': slotId,
    'ref': ref.toJson(),
    'afterSlotId': afterSlotId,
    'equipmentVariant': equipmentVariant,
  };

  factory BuddyAddPayload.fromJson(Map<String, dynamic> json) =>
      BuddyAddPayload(
        slotId: json['slotId'] as String,
        ref: BuddyExerciseRef.fromJson(json['ref'] as Map<String, dynamic>),
        afterSlotId: json['afterSlotId'] as String?,
        equipmentVariant: json['equipmentVariant'] as String?,
      );
}

/// Removes the exercise at [slotId].
class BuddyRemovePayload {
  BuddyRemovePayload({required this.slotId});

  final String slotId;

  Map<String, dynamic> toJson() => {'slotId': slotId};

  factory BuddyRemovePayload.fromJson(Map<String, dynamic> json) =>
      BuddyRemovePayload(slotId: json['slotId'] as String);
}

/// The full, absolute slot ordering after a reorder — never a from/to index
/// pair, so an out-of-order or dropped delivery can never leave the two
/// devices' orderings inconsistent.
class BuddyReorderPayload {
  BuddyReorderPayload({required this.order});

  final List<String> order;

  Map<String, dynamic> toJson() => {'order': order};

  factory BuddyReorderPayload.fromJson(Map<String, dynamic> json) =>
      BuddyReorderPayload(order: (json['order'] as List).cast<String>());
}

/// Replaces the exercise at [slotId] with [ref].
class BuddyReplacePayload {
  BuddyReplacePayload({required this.slotId, required this.ref});

  final String slotId;
  final BuddyExerciseRef ref;

  Map<String, dynamic> toJson() => {'slotId': slotId, 'ref': ref.toJson()};

  factory BuddyReplacePayload.fromJson(Map<String, dynamic> json) =>
      BuddyReplacePayload(
        slotId: json['slotId'] as String,
        ref: BuddyExerciseRef.fromJson(json['ref'] as Map<String, dynamic>),
      );
}

/// The session was ended by [endedBy] (a user id).
class BuddySessionEndedPayload {
  BuddySessionEndedPayload({required this.endedBy});

  final String endedBy;

  Map<String, dynamic> toJson() => {'endedBy': endedBy};

  factory BuddySessionEndedPayload.fromJson(Map<String, dynamic> json) =>
      BuddySessionEndedPayload(endedBy: json['endedBy'] as String);
}
