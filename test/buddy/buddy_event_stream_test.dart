import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/buddy/data/buddy_event_stream.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';

import 'fake_buddy_gateway.dart';

void main() {
  late FakeBuddyGateway gateway;
  const sessionId = 'session-123';

  setUp(() {
    gateway = FakeBuddyGateway();
  });

  BuddyEvent makeEvent(int seq) => BuddyEvent(
    buddySessionId: sessionId,
    seq: seq,
    actorUserId: 'user-a',
    kind: BuddyEventKind.add,
    payload: {'slotId': 'slot-$seq'},
  );

  test('start applies backlog 1..5 in order and updates lastAppliedSeq', () async {
    for (var i = 1; i <= 5; i++) {
      gateway.events.add(makeEvent(i));
    }

    final applied = <int>[];
    final committed = <int>[];

    final stream = BuddyEventStream(
      gateway: gateway,
      buddySessionId: sessionId,
      lastSeenSeq: 0,
      apply: (e) async => applied.add(e.seq),
      commitSeq: (s) async => committed.add(s),
    );

    await stream.start();

    expect(applied, [1, 2, 3, 4, 5]);
    expect(committed, [1, 2, 3, 4, 5]);
    expect(stream.lastAppliedSeq, 5);
  });

  test('events enqueued before start are buffered, deduped, and drained', () async {
    gateway.events.addAll([makeEvent(1), makeEvent(2), makeEvent(3)]);

    final applied = <int>[];
    final committed = <int>[];

    final stream = BuddyEventStream(
      gateway: gateway,
      buddySessionId: sessionId,
      lastSeenSeq: 0,
      apply: (e) async => applied.add(e.seq),
      commitSeq: (s) async => committed.add(s),
    );

    // Enqueue event 2 (already in backlog) and event 4 (gap event committed while connecting)
    stream.enqueue(makeEvent(2));
    stream.enqueue(makeEvent(4));

    // Put event 4 in gateway so gap refetch can find it
    gateway.events.add(makeEvent(4));

    await stream.start();

    expect(applied, [1, 2, 3, 4]);
    expect(committed, [1, 2, 3, 4]);
    expect(stream.lastAppliedSeq, 4);
  });

  test('onLiveEvent with seq == lastAppliedSeq + 1 applies immediately without gateway fetch', () async {
    final applied = <int>[];
    final stream = BuddyEventStream(
      gateway: gateway,
      buddySessionId: sessionId,
      lastSeenSeq: 2,
      apply: (e) async => applied.add(e.seq),
      commitSeq: (_) async {},
    );
    await stream.start();

    final fetchCountBefore = gateway.fetchCallCount;
    await stream.onLiveEvent(makeEvent(3));

    expect(applied, [3]);
    expect(stream.lastAppliedSeq, 3);
    expect(gateway.fetchCallCount, fetchCountBefore);
  });

  test('onLiveEvent with seq <= lastAppliedSeq is dropped', () async {
    final applied = <int>[];
    final stream = BuddyEventStream(
      gateway: gateway,
      buddySessionId: sessionId,
      lastSeenSeq: 3,
      apply: (e) async => applied.add(e.seq),
      commitSeq: (_) async {},
    );
    await stream.start();

    await stream.onLiveEvent(makeEvent(2));
    await stream.onLiveEvent(makeEvent(3));

    expect(applied, isEmpty);
    expect(stream.lastAppliedSeq, 3);
  });

  test('onLiveEvent with gap triggers fetchEventsSince with lastAppliedSeq', () async {
    final applied = <int>[];
    final stream = BuddyEventStream(
      gateway: gateway,
      buddySessionId: sessionId,
      lastSeenSeq: 2,
      apply: (e) async => applied.add(e.seq),
      commitSeq: (_) async {},
    );
    await stream.start();

    // Gateway has missing event 3 and live event 4
    gateway.events.addAll([makeEvent(3), makeEvent(4)]);

    await stream.onLiveEvent(makeEvent(4));

    expect(applied, [3, 4]);
    expect(stream.lastAppliedSeq, 4);
    expect(gateway.fetchAfterSeqs.last, 2);
  });

  test('commitSeq is only called after apply completes; throw leaves seq unadvanced', () async {
    gateway.events.add(makeEvent(1));
    gateway.events.add(makeEvent(2));

    final committed = <int>[];

    final stream = BuddyEventStream(
      gateway: gateway,
      buddySessionId: sessionId,
      lastSeenSeq: 0,
      apply: (e) async {
        if (e.seq == 2) throw Exception('apply error');
      },
      commitSeq: (s) async => committed.add(s),
    );

    await expectLater(stream.start(), throwsA(isA<Exception>()));

    expect(committed, [1]);
    expect(stream.lastAppliedSeq, 1);
  });

  test('replaying start with advanced lastSeenSeq applies nothing', () async {
    gateway.events.addAll([makeEvent(1), makeEvent(2)]);
    final applied = <int>[];

    final stream = BuddyEventStream(
      gateway: gateway,
      buddySessionId: sessionId,
      lastSeenSeq: 2,
      apply: (e) async => applied.add(e.seq),
      commitSeq: (_) async {},
    );
    await stream.start();

    expect(applied, isEmpty);
    expect(stream.lastAppliedSeq, 2);
  });

  test('out of order onLiveEvents converge correctly', () async {
    final applied = <int>[];
    final stream = BuddyEventStream(
      gateway: gateway,
      buddySessionId: sessionId,
      lastSeenSeq: 3,
      apply: (e) async => applied.add(e.seq),
      commitSeq: (_) async {},
    );
    await stream.start();

    gateway.events.addAll([makeEvent(4), makeEvent(5)]);

    // Arrives 5 first, then 4
    await stream.onLiveEvent(makeEvent(5));
    await stream.onLiveEvent(makeEvent(4));

    expect(applied, [4, 5]);
    expect(stream.lastAppliedSeq, 5);
  });
}
