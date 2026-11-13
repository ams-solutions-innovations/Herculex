import 'dart:convert';

/// Schedule type for a supplement reminder.
enum SupplementSchedule {
  none, // no reminder
  time, // remind at a specific time of day
  postWorkout, // remind when the workout ends
}

extension SupplementScheduleX on SupplementSchedule {
  String get id {
    switch (this) {
      case SupplementSchedule.none:
        return 'none';
      case SupplementSchedule.time:
        return 'time';
      case SupplementSchedule.postWorkout:
        return 'post_workout';
    }
  }

  static SupplementSchedule fromId(String id) {
    switch (id) {
      case 'time':
        return SupplementSchedule.time;
      case 'post_workout':
        return SupplementSchedule.postWorkout;
      default:
        return SupplementSchedule.none;
    }
  }
}

/// Units a dose can be expressed in. Dose maths never converts between these —
/// a nutrient contribution is stated in the nutrient's own unit — so this is
/// purely how the dose is written down and displayed.
const supplementDoseUnits = ['g', 'mg', 'µg', 'ml', 'IU', 'capsule', 'scoop'];

String _formatAmount(double amount) => amount.truncateToDouble() == amount
    ? amount.toStringAsFixed(0)
    : amount.toStringAsFixed(1);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _isoDay(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// A supplement the user wants to track daily.
class Supplement {
  final String id;
  final String name;

  /// Manufacturer. No longer asked for in the UI, but kept so supplements saved
  /// by older versions keep their value.
  final String? brand;

  /// Stable key of the [SupplementPreset] this was created from (`creatine`,
  /// `omega3`, …), or null for a custom supplement. Gives Labs and reports one
  /// canonical identity per product instead of a free-text name.
  final String? presetKey;

  /// How much is taken per dose, e.g. 5 with [doseUnit] `g` for creatine.
  final double? doseAmount;
  final String? doseUnit;

  /// Optional loading phase (creatine): [loadingDoseAmount] per day, in
  /// [doseUnit], for [loadingDays] days starting on [loadingStartIso]. After
  /// that the normal [doseAmount] applies again.
  final double? loadingDoseAmount;
  final int? loadingDays;
  final String? loadingStartIso;

  /// What one dose contributes, keyed by the tracked-nutrient IDs used by the
  /// food diary (`vitamin_d`, `magnesium`, …). Values are in that nutrient's
  /// own unit, so they can be added to food totals directly.
  final Map<String, double> nutrients;

  final SupplementSchedule schedule;

  /// Only set when [schedule] == [SupplementSchedule.time].
  /// Stored as "HH:MM" (24-hour).
  final String? timeHHMM;

  const Supplement({
    required this.id,
    required this.name,
    this.brand,
    this.presetKey,
    this.doseAmount,
    this.doseUnit,
    this.loadingDoseAmount,
    this.loadingDays,
    this.loadingStartIso,
    this.nutrients = const {},
    this.schedule = SupplementSchedule.none,
    this.timeHHMM,
  });

  // ── Loading phase ─────────────────────────────────────────────────────────

  bool get hasLoadingPhase =>
      loadingDoseAmount != null &&
      loadingDoseAmount! > 0 &&
      (loadingDays ?? 0) > 0 &&
      DateTime.tryParse(loadingStartIso ?? '') != null;

  /// First day of the loading phase, or null when there is none.
  DateTime? get loadingStart {
    if (!hasLoadingPhase) return null;
    return _dateOnly(DateTime.parse(loadingStartIso!));
  }

  /// Last day (inclusive) of the loading phase, or null when there is none.
  DateTime? get loadingEnd {
    final start = loadingStart;
    if (start == null) return null;
    return DateTime(start.year, start.month, start.day + loadingDays! - 1);
  }

  /// Whether [date] falls inside the loading phase.
  bool isLoadingOn(DateTime date) {
    final start = loadingStart;
    final end = loadingEnd;
    if (start == null || end == null) return false;
    final d = _dateOnly(date);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  /// The dose that applies on [date]: the loading dose inside the loading
  /// phase, otherwise the normal dose.
  double? doseAmountFor(DateTime date) =>
      isLoadingOn(date) ? loadingDoseAmount : doseAmount;

  /// `5 g` / `20 g` for [date] — the row subtitle in the tracker.
  String? doseLabelFor(DateTime date) {
    final amount = doseAmountFor(date);
    final unit = doseUnit;
    if (amount == null || unit == null) return null;
    return '${_formatAmount(amount)} $unit';
  }

  /// The normal (maintenance) dose, e.g. `5 g`.
  String? get doseLabel {
    final amount = doseAmount;
    final unit = doseUnit;
    if (amount == null || unit == null) return null;
    return '${_formatAmount(amount)} $unit';
  }

  bool get contributesNutrients => nutrients.values.any((v) => v > 0);

  Supplement copyWith({
    String? name,
    String? brand,
    double? doseAmount,
    String? doseUnit,
    double? loadingDoseAmount,
    int? loadingDays,
    String? loadingStartIso,
    Map<String, double>? nutrients,
    SupplementSchedule? schedule,
    String? timeHHMM,
    bool clearTime = false,
    bool clearBrand = false,
    bool clearDose = false,
    bool clearLoading = false,
  }) {
    return Supplement(
      id: id,
      name: name ?? this.name,
      brand: clearBrand ? null : (brand ?? this.brand),
      presetKey: presetKey,
      doseAmount: clearDose ? null : (doseAmount ?? this.doseAmount),
      doseUnit: clearDose ? null : (doseUnit ?? this.doseUnit),
      loadingDoseAmount: clearLoading
          ? null
          : (loadingDoseAmount ?? this.loadingDoseAmount),
      loadingDays: clearLoading ? null : (loadingDays ?? this.loadingDays),
      loadingStartIso: clearLoading
          ? null
          : (loadingStartIso ?? this.loadingStartIso),
      nutrients: nutrients ?? this.nutrients,
      schedule: schedule ?? this.schedule,
      timeHHMM: clearTime ? null : (timeHHMM ?? this.timeHHMM),
    );
  }

  /// ISO `yyyy-MM-dd` for a loading start date.
  static String isoDay(DateTime d) => _isoDay(d);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (brand != null) 'brand': brand,
    if (presetKey != null) 'presetKey': presetKey,
    if (doseAmount != null) 'doseAmount': doseAmount,
    if (doseUnit != null) 'doseUnit': doseUnit,
    if (loadingDoseAmount != null) 'loadingDoseAmount': loadingDoseAmount,
    if (loadingDays != null) 'loadingDays': loadingDays,
    if (loadingStartIso != null) 'loadingStartIso': loadingStartIso,
    if (nutrients.isNotEmpty) 'nutrients': nutrients,
    'schedule': schedule.id,
    if (timeHHMM != null) 'timeHHMM': timeHHMM,
  };

  /// Tolerant of older shapes: a stored `barcode` key from the scanner era is
  /// simply ignored.
  factory Supplement.fromJson(Map<String, dynamic> json) => Supplement(
    id: json['id'] as String,
    name: json['name'] as String,
    brand: json['brand'] as String?,
    presetKey: json['presetKey'] as String?,
    doseAmount: (json['doseAmount'] as num?)?.toDouble(),
    doseUnit: json['doseUnit'] as String?,
    loadingDoseAmount: (json['loadingDoseAmount'] as num?)?.toDouble(),
    loadingDays: (json['loadingDays'] as num?)?.toInt(),
    loadingStartIso: json['loadingStartIso'] as String?,
    nutrients: _nutrientsFromJson(json['nutrients']),
    schedule: SupplementScheduleX.fromId(
      (json['schedule'] as String?) ?? 'none',
    ),
    timeHHMM: json['timeHHMM'] as String?,
  );

  /// Tolerant of the pre-v2 shape (no `nutrients` key) and of malformed
  /// values, so a bad write can never brick the supplement list.
  static Map<String, double> _nutrientsFromJson(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, double>{};
    raw.forEach((key, value) {
      final amount = value is num ? value.toDouble() : null;
      if (key is String && amount != null && amount > 0) out[key] = amount;
    });
    return out;
  }

  static List<Supplement> listFromJson(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Supplement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<Supplement> supplements) =>
      jsonEncode(supplements.map((s) => s.toJson()).toList());
}
