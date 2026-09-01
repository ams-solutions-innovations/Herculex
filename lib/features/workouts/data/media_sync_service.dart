import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../nutrition/data/wear_sync_service.dart';

class MediaSyncService {
  final WearSyncService _wearSyncService;
  Timer? _pollingTimer;
  String _lastSyncedPayload = '';
  bool _isRunning = false;

  MediaSyncService(this._wearSyncService) {
    WearSyncService.onWatchMediaCommand = _handleWatchMediaCommand;
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _pollAndSync();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      _pollAndSync();
    });
  }

  void stop() {
    _isRunning = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _pollAndSync() async {
    try {
      final info = await _wearSyncService.getMediaInfoNative();
      final track = (info['track'] as String?) ?? '';
      final artist = (info['artist'] as String?) ?? '';
      final isPlaying = (info['isPlaying'] as bool?) ?? false;
      final packageName = (info['packageName'] as String?) ?? '';
      final hasPermission = (info['hasPermission'] as bool?) ?? false;
      final isSpotify = packageName.contains('spotify');
      final hasTrack = track.isNotEmpty;

      final stateMap = {
        'title': hasTrack ? track : '',
        'artist': hasTrack ? artist : '',
        'album': '',
        'isPlaying': isPlaying,
        'appName': isSpotify ? 'Spotify' : (hasTrack ? 'Music' : ''),
        'isSpotify': isSpotify,
        'hasPermission': hasPermission,
      };

      final stateJson = jsonEncode(stateMap);
      if (stateJson != _lastSyncedPayload) {
        _lastSyncedPayload = stateJson;

        final payloadMap = Map<String, dynamic>.from(stateMap);
        payloadMap['updatedAtEpochMs'] = DateTime.now().millisecondsSinceEpoch;
        final payloadJson = jsonEncode(payloadMap);

        await _wearSyncService.syncMediaState(payloadJson);
        debugPrint(
          'MediaSyncService: Synced media state -> $track (${isPlaying ? "playing" : "paused"})',
        );
      }
    } catch (e) {
      // Best-effort polling: e.g. permission not granted or emulator environment
    }
  }

  Future<void> _handleWatchMediaCommand(String? commandJson) async {
    if (commandJson == null || commandJson.isEmpty) return;
    debugPrint('MediaSyncService: Received command from watch: $commandJson');
    try {
      final map = jsonDecode(commandJson) as Map<String, dynamic>;
      final action = map['action'] as String? ?? '';

      switch (action) {
        case 'play_pause':
        case 'play':
        case 'pause':
          await _wearSyncService.sendMediaActionNative('playPause');
          break;
        case 'next':
          await _wearSyncService.sendMediaActionNative('next');
          break;
        case 'previous':
          await _wearSyncService.sendMediaActionNative('previous');
          break;
      }

      // Fast sync after transport command
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _pollAndSync();
    } catch (e) {
      debugPrint('MediaSyncService: Failed to handle watch command: $e');
    }
  }
}
