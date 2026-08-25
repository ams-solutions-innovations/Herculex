import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/buddy_event.dart';
import 'buddy_event_stream.dart';
import 'buddy_remote_gateway.dart';

enum BuddyConnectionState { connecting, live, degraded, ended }

/// Manages the private Supabase Realtime broadcast channel and presence
/// subscription for a buddy session.
class BuddyChannelService {
  BuddyChannelService({
    required SupabaseClient client,
    required BuddyGateway gateway,
  })  : _client = client,
        _gateway = gateway;

  final SupabaseClient _client;
  final BuddyGateway _gateway;

  RealtimeChannel? _channel;
  BuddyEventStream? _stream;

  final _stateCtrl = StreamController<BuddyConnectionState>.broadcast();
  final _presentUserIdsCtrl = StreamController<List<String>>.broadcast();

  Stream<BuddyConnectionState> get state => _stateCtrl.stream;
  Stream<List<String>> get presentUserIds => _presentUserIdsCtrl.stream;

  Future<void> connect({
    required String buddySessionId,
    required int lastSeenSeq,
    required String userId,
    String? displayName,
    required Future<void> Function(BuddyEvent) apply,
    required Future<void> Function(int seq) commitSeq,
  }) async {
    if (_client.auth.currentSession == null) {
      throw StateError(
        'Cannot connect buddy channel without an active auth session',
      );
    }

    _stateCtrl.add(BuddyConnectionState.connecting);

    Future<void> wrappedApply(BuddyEvent event) async {
      await apply(event);
      if (event.kind == BuddyEventKind.sessionEnded) {
        await disconnect();
      }
    }

    _stream = BuddyEventStream(
      gateway: _gateway,
      buddySessionId: buddySessionId,
      lastSeenSeq: lastSeenSeq,
      apply: wrappedApply,
      commitSeq: commitSeq,
    );

    final channel = _client.channel(
      'buddy:$buddySessionId',
      opts: const RealtimeChannelConfig(private: true),
    );
    _channel = channel;

    channel.onBroadcast(
      event: 'buddy_event',
      callback: (payload) {
        final event = BuddyEvent.fromBroadcast(payload);
        _stream?.enqueue(event);
      },
    );

    channel.onPresenceSync((_) {
      final presenceList = channel.presenceState();
      final ids = <String>{};
      for (final state in presenceList) {
        for (final presence in state.presences) {
          final uid = presence.payload['user_id'] as String?;
          if (uid != null && uid.isNotEmpty) {
            ids.add(uid);
          }
        }
      }
      _presentUserIdsCtrl.add(ids.toList());
    });

    channel.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        try {
          await channel.track({
            'user_id': userId,
            'display_name': displayName ?? 'Buddy',
          });
        } catch (_) {}
        try {
          await _stream?.start();
          _stateCtrl.add(BuddyConnectionState.live);
        } catch (e) {
          _stateCtrl.add(BuddyConnectionState.degraded);
        }
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _stateCtrl.add(BuddyConnectionState.degraded);
      }
    });
  }

  Future<void> disconnect() async {
    if (_channel != null) {
      final ch = _channel!;
      _channel = null;
      _stream = null;
      try {
        await ch.untrack();
      } catch (_) {}
      try {
        await _client.removeChannel(ch);
      } catch (_) {}
      _stateCtrl.add(BuddyConnectionState.ended);
    }
  }

  void dispose() {
    disconnect();
    _stateCtrl.close();
    _presentUserIdsCtrl.close();
  }
}
