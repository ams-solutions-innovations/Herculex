enum HealthReadStatus { available, denied, unavailable, error, empty }

class HealthRead<T> {
  const HealthRead({
    required this.status,
    required this.readAt,
    this.value,
    this.dataTypes = const [],
    this.platform,
    this.message,
    this.error,
  });

  factory HealthRead.available({
    required T value,
    required DateTime readAt,
    List<String> dataTypes = const [],
    String? platform,
    String? message,
  }) {
    return HealthRead<T>(
      status: HealthReadStatus.available,
      value: value,
      readAt: readAt,
      dataTypes: dataTypes,
      platform: platform,
      message: message,
    );
  }

  factory HealthRead.denied({
    required DateTime readAt,
    List<String> dataTypes = const [],
    String? platform,
    String? message,
    Object? error,
  }) {
    return HealthRead<T>(
      status: HealthReadStatus.denied,
      readAt: readAt,
      dataTypes: dataTypes,
      platform: platform,
      message: message ?? 'Permission denied',
      error: error,
    );
  }

  factory HealthRead.unavailable({
    required DateTime readAt,
    List<String> dataTypes = const [],
    String? platform,
    String? message,
    Object? error,
  }) {
    return HealthRead<T>(
      status: HealthReadStatus.unavailable,
      readAt: readAt,
      dataTypes: dataTypes,
      platform: platform,
      message: message ?? 'Health data unavailable on this device',
      error: error,
    );
  }

  factory HealthRead.error({
    required DateTime readAt,
    List<String> dataTypes = const [],
    String? platform,
    String? message,
    Object? error,
  }) {
    return HealthRead<T>(
      status: HealthReadStatus.error,
      readAt: readAt,
      dataTypes: dataTypes,
      platform: platform,
      message: message ?? 'Health read failed',
      error: error,
    );
  }

  factory HealthRead.empty({
    required DateTime readAt,
    List<String> dataTypes = const [],
    String? platform,
    String? message,
  }) {
    return HealthRead<T>(
      status: HealthReadStatus.empty,
      readAt: readAt,
      dataTypes: dataTypes,
      platform: platform,
      message: message ?? 'No health data for this period',
    );
  }

  final HealthReadStatus status;
  final T? value;
  final List<String> dataTypes;
  final String? platform;
  final DateTime readAt;
  final String? message;
  final Object? error;

  bool get isAvailable => status == HealthReadStatus.available;
  bool get hasTrustedValue => isAvailable && value != null;
}

class DailyHealthRead {
  const DailyHealthRead({
    required this.dateIso,
    required this.steps,
    required this.activeKcal,
    required this.restingHr,
    required this.sleepHours,
    required this.waterMl,
    required this.foodKcal,
    required this.weightKg,
    required this.readAt,
  });

  final String dateIso;
  final HealthRead<double> steps;
  final HealthRead<double> activeKcal;
  final HealthRead<double> restingHr;
  final HealthRead<double> sleepHours;
  final HealthRead<double> waterMl;
  final HealthRead<double> foodKcal;
  final HealthRead<double> weightKg;
  final DateTime readAt;

  List<HealthRead<double>> get metricReads => [
    steps,
    activeKcal,
    restingHr,
    sleepHours,
    waterMl,
    foodKcal,
    weightKg,
  ];

  bool get hasAnyAvailableMetric => metricReads.any((read) => read.isAvailable);

  HealthReadStatus get overallStatus {
    if (hasAnyAvailableMetric) return HealthReadStatus.available;
    if (metricReads.every((read) => read.status == HealthReadStatus.denied)) {
      return HealthReadStatus.denied;
    }
    if (metricReads.every(
      (read) => read.status == HealthReadStatus.unavailable,
    )) {
      return HealthReadStatus.unavailable;
    }
    if (metricReads.any((read) => read.status == HealthReadStatus.error)) {
      return HealthReadStatus.error;
    }
    if (metricReads.every((read) => read.status == HealthReadStatus.empty)) {
      return HealthReadStatus.empty;
    }
    return HealthReadStatus.empty;
  }

  HealthRead<double>? readForKind(String kind) {
    switch (kind) {
      case 'steps':
        return steps;
      case 'active_kcal':
        return activeKcal;
      case 'resting_hr':
        return restingHr;
      case 'sleep_hours':
        return sleepHours;
      case 'water_ml':
        return waterMl;
      case 'food_kcal':
        return foodKcal;
      case 'weight_kg':
        return weightKg;
    }
    return null;
  }
}
