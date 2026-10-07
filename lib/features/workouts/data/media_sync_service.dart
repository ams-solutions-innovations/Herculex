import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:herculex/features/nutrition/data/wear_sync_service.dart';

class MediaSyncService {
  final WearSyncService _wearSyncService;
  Timer? _pollingTimer;
  String _lastSyncedPayload = '';
  bool _isRunning = false;

  /// Watch transport/volume commands are handled natively in
  /// `PhoneWearListenerService`; this service only mirrors phone state out.
  MediaSyncService(this._wearSyncService);

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _pollAndSync();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      _pollAndSync();
    });
  }

  /// Polling Android media sessions every second is useful only while a
  /// workout can expose watch controls. Keeping it alive for the whole phone
  /// app lifetime needlessly wakes the phone and Wear Data Layer.
  void setWorkoutActive(bool active) {
    if (active) {
      start();
    } else {
      stop();
      _lastSyncedPayload = '';
    }
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
      final artworkBase64 = (info['thumbnailUrl'] as String?) ?? '';
      final positionMs = (info['positionMs'] as num?)?.toInt() ?? 0;
      final durationMs = (info['durationMs'] as num?)?.toInt() ?? 0;
      final volume = (info['volume'] as num?)?.toInt() ?? 8;
      final maxVolume = (info['maxVolume'] as num?)?.toInt() ?? 15;
      final volumePercent = (info['volumePercent'] as num?)?.toInt() ?? 50;
      final isSpotify = packageName.contains('spotify');
      final hasTrack = track.isNotEmpty;

      final stateMap = {
        'title': hasTrack ? track : '',
        'artist': hasTrack ? artist : '',
        'album': '',
        'isPlaying': isPlaying,
        'appName': isSpotify ? 'Spotify' : (hasTrack ? 'Music' : ''),
        'packageName': packageName,
        'isSpotify': isSpotify,
        'hasPermission': hasPermission,
        'volume': volume,
        'maxVolume': maxVolume,
        'volumePercent': volumePercent,
        // Artwork is deliberately included only in the delivered payload,
        // not in the comparison key below, so we do not resend it each poll.
        'artworkBase64': artworkBase64,
        'positionMs': positionMs,
        'durationMs': durationMs,
      };

      final stateJson = jsonEncode({
        ...stateMap,
        'positionMs': 0,
        'durationMs': 0,
      });
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
}
