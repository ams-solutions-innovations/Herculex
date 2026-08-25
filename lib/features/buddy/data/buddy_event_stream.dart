import '../domain/buddy_event.dart';
import 'buddy_remote_gateway.dart';

/// The pure ordering machine: buffers realtime arrivals, backfills historical
/// log, applies in strictly increasing seq order, and refetches backlog on
/// any detected gap.
class BuddyEventStream {
  BuddyEventStream({
    required this.gateway,
    required this.buddySessionId,
    required int lastSeenSeq,
    required this.apply,
    required this.commitSeq,
  }) : _lastAppliedSeq = lastSeenSeq;

  final BuddyGateway gateway;
  final String buddySessionId;
  final Future<void> Function(BuddyEvent) apply;
  final Future<void> Function(int seq) commitSeq;

  int _lastAppliedSeq;
  int get lastAppliedSeq => _lastAppliedSeq;

  final List<BuddyEvent> _buffer = [];
  bool _started = false;

  /// Called from the broadcast channel callback. If [start] has not completed,
  /// the event is held in the buffer; otherwise it is routed to [onLiveEvent].
  void enqueue(BuddyEvent event) {
    if (!_started) {
      _buffer.add(event);
    } else {
      onLiveEvent(event);
    }
  }

  /// Backfills from [lastAppliedSeq], applies backlog in sequence order, then
  /// drains any events buffered while connecting.
  Future<void> start() async {
    final backlog = await gateway.fetchEventsSince(
      buddySessionId: buddySessionId,
      afterSeq: _lastAppliedSeq,
    );

    for (final event in backlog) {
      if (event.seq > _lastAppliedSeq) {
        await apply(event);
        _lastAppliedSeq = event.seq;
        await commitSeq(_lastAppliedSeq);
      }
    }

    _started = true;

    // Drain buffer: dedupe against backlog, apply any new events in order.
    _buffer.sort((a, b) => a.seq.compareTo(b.seq));
    final pending = List<BuddyEvent>.from(_buffer);
    _buffer.clear();

    for (final event in pending) {
      if (event.seq > _lastAppliedSeq) {
        if (event.seq == _lastAppliedSeq + 1) {
          await apply(event);
          _lastAppliedSeq = event.seq;
          await commitSeq(_lastAppliedSeq);
        } else {
          await _refetchBacklog();
          if (event.seq == _lastAppliedSeq + 1) {
            await apply(event);
            _lastAppliedSeq = event.seq;
            await commitSeq(_lastAppliedSeq);
          }
        }
      }
    }
  }

  /// Processes a live event:
  /// - `seq <= _lastAppliedSeq`: ignored (echo of local append or duplicate)
  /// - `seq == _lastAppliedSeq + 1`: applied immediately
  /// - `seq > _lastAppliedSeq + 1`: gap detected, refetches backlog from gateway
  Future<void> onLiveEvent(BuddyEvent event) async {
    if (!_started) {
      _buffer.add(event);
      return;
    }

    if (event.seq <= _lastAppliedSeq) {
      return;
    }

    if (event.seq == _lastAppliedSeq + 1) {
      await apply(event);
      _lastAppliedSeq = event.seq;
      await commitSeq(_lastAppliedSeq);
      return;
    }

    // Gap detected
    await _refetchBacklog();
    if (event.seq == _lastAppliedSeq + 1) {
      await apply(event);
      _lastAppliedSeq = event.seq;
      await commitSeq(_lastAppliedSeq);
    }
  }

  Future<void> _refetchBacklog() async {
    final backlog = await gateway.fetchEventsSince(
      buddySessionId: buddySessionId,
      afterSeq: _lastAppliedSeq,
    );

    for (final ev in backlog) {
      if (ev.seq == _lastAppliedSeq + 1) {
        await apply(ev);
        _lastAppliedSeq = ev.seq;
        await commitSeq(_lastAppliedSeq);
      }
    }
  }
}
