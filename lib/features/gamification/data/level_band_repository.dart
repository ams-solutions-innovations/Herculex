import 'dart:convert';

import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// When the user entered their current band. Ranks I–V count XP from
/// [xpAtEntry].
class BandEntry {
  const BandEntry({
    required this.band,
    required this.xpAtEntry,
    this.enteredAt,
  });

  static const initial = BandEntry(band: LevelBand.novice, xpAtEntry: 0);

  final LevelBand band;
  final int xpAtEntry;
  final DateTime? enteredAt;

  Map<String, Object?> toJson() => {
    'band': band.name,
    'xpAtEntry': xpAtEntry,
    'enteredAt': enteredAt?.toUtc().toIso8601String(),
  };

  factory BandEntry.fromJson(Map<String, dynamic> json) => BandEntry(
    band: LevelBand.values.byName(json['band'] as String),
    xpAtEntry: (json['xpAtEntry'] as num).toInt(),
    enteredAt: json['enteredAt'] == null
        ? null
        : DateTime.parse(json['enteredAt'] as String).toLocal(),
  );
}

/// Local record of the user's band. Bands only ever go up: a strength
/// standard, once met, stays met even if bodyweight or a log changes later.
class LevelBandRepository {
  LevelBandRepository(this._preferences);

  static const _key = 'gamification_band_v1';
  final SharedPreferences _preferences;

  BandEntry get current {
    final raw = _preferences.getString(_key);
    if (raw == null) return BandEntry.initial;
    try {
      return BandEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A corrupted local-only reward record must never block the screen.
      return BandEntry.initial;
    }
  }

  /// Moves to [band] when it is above the stored one, starting its ranks at
  /// [totalXp]. Returns the entry in force afterwards.
  Future<BandEntry> promoteIfHigher({
    required LevelBand band,
    required int totalXp,
    required DateTime at,
  }) async {
    final existing = current;
    if (band.index <= existing.band.index) return existing;
    final promoted = BandEntry(band: band, xpAtEntry: totalXp, enteredAt: at);
    await _preferences.setString(_key, jsonEncode(promoted.toJson()));
    return promoted;
  }
}
