import 'dart:async';

import 'package:herculex/features/measurements/data/measurements_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalProfileRepository {
  /// Public so the synced-preferences registry can name it.
  static const prefsKey = 'herculex.profile';
  static const _kProfileKey = prefsKey;

  final SharedPreferences _prefs;
  final _controller = StreamController<Profile?>.broadcast();
  MeasurementsRepository? _measurementsRepo;

  LocalProfileRepository(this._prefs);

  void setMeasurementsRepository(MeasurementsRepository repo) {
    _measurementsRepo = repo;
  }

  Profile? get currentProfile {
    final raw = _prefs.getString(_kProfileKey);
    if (raw == null) return null;
    try {
      return Profile.decode(raw);
    } catch (_) {
      return null;
    }
  }

  Stream<Profile?> watch() {
    return Stream<Profile?>.multi((multi) {
      scheduleMicrotask(() {
        if (!multi.isClosed) {
          multi.add(currentProfile);
        }
      });
      final sub = _controller.stream.listen(
        multi.add,
        onError: multi.addError,
        onDone: multi.close,
      );
      multi.onCancel = sub.cancel;
    });
  }

  Future<void> save(Profile profile, {bool syncToLog = true}) async {
    final oldWeight = currentProfile?.weightKg;
    await _prefs.setString(_kProfileKey, profile.encode());
    if (!_controller.isClosed) {
      _controller.add(profile);
    }

    if (syncToLog && profile.weightKg != null && _measurementsRepo != null) {
      if (oldWeight != profile.weightKg) {
        final todayIso = DateFormat('yyyy-MM-dd').format(DateTime.now());
        await _measurementsRepo!.logMeasurement(
          dateIso: todayIso,
          metric: 'bodyweight',
          value: profile.weightKg!,
        );
      }
    }
  }

  /// Re-reads the stored profile and tells listeners — for when it changed
  /// underneath this repository (pulled from another device), not through
  /// [save]. On a fresh web session this is what lets the router skip
  /// onboarding once the account's profile arrives.
  void reloadFromStorage() {
    if (!_controller.isClosed) {
      _controller.add(currentProfile);
    }
  }

  Future<void> clear() async {
    await _prefs.remove(_kProfileKey);
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  void dispose() => _controller.close();
}
