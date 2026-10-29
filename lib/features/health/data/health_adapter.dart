import 'package:health/health.dart';

abstract class HealthAdapter {
  Future<void> configure();

  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  });

  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  });

  Future<int?> getTotalStepsInInterval(DateTime startTime, DateTime endTime);

  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
  });

  Future<bool> writeHealthData({
    required num value,
    required HealthDataType type,
    required DateTime startTime,
    required DateTime endTime,
  });

  Future<bool> writeWorkoutData({
    required HealthWorkoutActivityType activityType,
    required String title,
    required DateTime start,
    required DateTime end,
    required int totalEnergyBurned,
    required HealthDataUnit totalEnergyBurnedUnit,
  });
}

/// For platforms with no health store (the web): never authorized, reads
/// nothing, writes nothing. Health samples are device-only and never synced,
/// so there is nothing to fall back to.
class UnavailableHealthAdapter implements HealthAdapter {
  const UnavailableHealthAdapter();

  @override
  Future<void> configure() async {}

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async => false;

  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async => false;

  @override
  Future<int?> getTotalStepsInInterval(
    DateTime startTime,
    DateTime endTime,
  ) async => null;

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
  }) async => const [];

  @override
  Future<bool> writeHealthData({
    required num value,
    required HealthDataType type,
    required DateTime startTime,
    required DateTime endTime,
  }) async => false;

  @override
  Future<bool> writeWorkoutData({
    required HealthWorkoutActivityType activityType,
    required String title,
    required DateTime start,
    required DateTime end,
    required int totalEnergyBurned,
    required HealthDataUnit totalEnergyBurnedUnit,
  }) async => false;
}

class PluginHealthAdapter implements HealthAdapter {
  PluginHealthAdapter({Health? health}) : _health = health ?? Health();

  final Health _health;

  @override
  Future<void> configure() async {
    try {
      await _health.configure();
    } catch (_) {
      // Ignore configure errors on non-supported platforms
    }
  }

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) {
    return _health.hasPermissions(types, permissions: permissions);
  }

  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) {
    return _health.requestAuthorization(types, permissions: permissions);
  }

  @override
  Future<int?> getTotalStepsInInterval(DateTime startTime, DateTime endTime) {
    return _health.getTotalStepsInInterval(startTime, endTime);
  }

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
  }) {
    return _health.getHealthDataFromTypes(
      types: types,
      startTime: startTime,
      endTime: endTime,
    );
  }

  @override
  Future<bool> writeHealthData({
    required num value,
    required HealthDataType type,
    required DateTime startTime,
    required DateTime endTime,
  }) {
    return _health.writeHealthData(
      value: value.toDouble(),
      type: type,
      startTime: startTime,
      endTime: endTime,
    );
  }

  @override
  Future<bool> writeWorkoutData({
    required HealthWorkoutActivityType activityType,
    required String title,
    required DateTime start,
    required DateTime end,
    required int totalEnergyBurned,
    required HealthDataUnit totalEnergyBurnedUnit,
  }) {
    return _health.writeWorkoutData(
      activityType: activityType,
      title: title,
      start: start,
      end: end,
      totalEnergyBurned: totalEnergyBurned,
      totalEnergyBurnedUnit: totalEnergyBurnedUnit,
    );
  }
}
