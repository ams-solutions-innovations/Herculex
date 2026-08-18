import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';
import 'package:herculex/features/buddy/domain/buddy_scope.dart';

void main() {
  group('BuddyEventKind', () {
    test('fromWire parses every known wire name', () {
      expect(BuddyEventKind.fromWire('add'), BuddyEventKind.add);
      expect(BuddyEventKind.fromWire('remove'), BuddyEventKind.remove);
      expect(BuddyEventKind.fromWire('reorder'), BuddyEventKind.reorder);
      expect(BuddyEventKind.fromWire('replace'), BuddyEventKind.replace);
      expect(
        BuddyEventKind.fromWire('session_ended'),
        BuddyEventKind.sessionEnded,
      );
    });

    test('fromWire returns null on an unknown wire value', () {
      expect(BuddyEventKind.fromWire('scope'), isNull);
      expect(BuddyEventKind.fromWire('bogus'), isNull);
    });

    test('wireName round-trips through fromWire for every value', () {
      for (final kind in BuddyEventKind.values) {
        expect(BuddyEventKind.fromWire(kind.wireName), kind);
      }
      expect(BuddyEventKind.remove.wireName, 'remove');
    });
  });

  group('BuddyExerciseRef', () {
    test('toJson/fromJson round-trip for a slug ref', () {
      final ref = BuddyExerciseRef(slug: 'barbell-back-squat');
      final json = ref.toJson();
      expect(json, {'uuid': null, 'slug': 'barbell-back-squat'});

      final decoded = BuddyExerciseRef.fromJson(json);
      expect(decoded.slug, 'barbell-back-squat');
      expect(decoded.uuid, isNull);
    });

    test('toJson/fromJson round-trip for a uuid ref', () {
      final ref = BuddyExerciseRef(uuid: 'abc-123');
      final json = ref.toJson();
      expect(json, {'uuid': 'abc-123', 'slug': null});

      final decoded = BuddyExerciseRef.fromJson(json);
      expect(decoded.uuid, 'abc-123');
      expect(decoded.slug, isNull);
    });

    test('throws ArgumentError when both uuid and slug are set', () {
      expect(
        () => BuddyExerciseRef(uuid: 'abc-123', slug: 'barbell-back-squat'),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when neither uuid nor slug is set', () {
      expect(() => BuddyExerciseRef(), throwsArgumentError);
    });
  });

  group('BuddyReorderPayload', () {
    test('toJson emits the full order under "order", no delta keys', () {
      final payload = BuddyReorderPayload(order: ['a', 'b', 'c']);
      final json = payload.toJson();
      expect(json, {
        'order': ['a', 'b', 'c'],
      });
      expect(json.containsKey('oldIndex'), isFalse);
      expect(json.containsKey('newIndex'), isFalse);
    });

    test('fromJson round-trips the full order', () {
      final decoded = BuddyReorderPayload.fromJson({
        'order': ['x', 'y'],
      });
      expect(decoded.order, ['x', 'y']);
    });
  });

  group('BuddyEvent', () {
    test('fromBroadcast reads seq/kind/actor/payload', () {
      final event = BuddyEvent.fromBroadcast({
        'seq': 7,
        'kind': 'add',
        'actor': 'u1',
        'payload': {'slotId': 's1'},
      });
      expect(event.seq, 7);
      expect(event.kind, BuddyEventKind.add);
      expect(event.actorUserId, 'u1');
      expect(event.payload, {'slotId': 's1'});
    });

    test('fromLogRow reads snake_case PostgREST column names', () {
      final event = BuddyEvent.fromLogRow({
        'buddy_session_id': 'session-1',
        'seq': 3,
        'actor_user_id': 'u2',
        'kind': 'remove',
        'payload': {'slotId': 's2'},
      });
      expect(event.buddySessionId, 'session-1');
      expect(event.seq, 3);
      expect(event.actorUserId, 'u2');
      expect(event.kind, BuddyEventKind.remove);
      expect(event.payload, {'slotId': 's2'});
    });
  });

  group('BuddyScopeDefaults', () {
    test('remove defaults to BuddyScope.mine', () {
      expect(
        BuddyScopeDefaults.forAction(BuddyActionKind.remove),
        BuddyScope.mine,
      );
    });

    test('add, reorder and replace default to BuddyScope.both', () {
      expect(
        BuddyScopeDefaults.forAction(BuddyActionKind.add),
        BuddyScope.both,
      );
      expect(
        BuddyScopeDefaults.forAction(BuddyActionKind.reorder),
        BuddyScope.both,
      );
      expect(
        BuddyScopeDefaults.forAction(BuddyActionKind.replace),
        BuddyScope.both,
      );
    });
  });

  group('no payload toJson() emits a "scope" key', () {
    test('across all five payload shapes', () {
      final addJson = BuddyAddPayload(
        slotId: 's1',
        ref: BuddyExerciseRef(slug: 'barbell-back-squat'),
      ).toJson();
      final removeJson = BuddyRemovePayload(slotId: 's1').toJson();
      final reorderJson = BuddyReorderPayload(order: ['s1']).toJson();
      final replaceJson = BuddyReplacePayload(
        slotId: 's1',
        ref: BuddyExerciseRef(slug: 'barbell-back-squat'),
      ).toJson();
      final sessionEndedJson = BuddySessionEndedPayload(
        endedBy: 'u1',
      ).toJson();

      for (final json in [
        addJson,
        removeJson,
        reorderJson,
        replaceJson,
        sessionEndedJson,
      ]) {
        expect(json.containsKey('scope'), isFalse);
      }
    });
  });
}
