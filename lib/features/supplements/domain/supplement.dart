import 'dart:convert';

/// Schedule type for a supplement reminder.
enum SupplementSchedule {
  none,        // no reminder
  time,        // remind at a specific time of day
  postWorkout, // remind when the workout ends
}

extension SupplementScheduleX on SupplementSchedule {
  String get id {
    switch (this) {
      case SupplementSchedule.none:        return 'none';
      case SupplementSchedule.time:        return 'time';
      case SupplementSchedule.postWorkout: return 'post_workout';
    }
  }

  static SupplementSchedule fromId(String id) {
    switch (id) {
      case 'time':         return SupplementSchedule.time;
      case 'post_workout': return SupplementSchedule.postWorkout;
      default:             return SupplementSchedule.none;
    }
  }
}

/// Units a dose can be expressed in. Dose maths never converts between these —
/// a nutrient contribution is stated in the nutrient's own unit — so this is
/// purely how the dose is written down and displayed.
const supplementDoseUnits = ['g', 'mg', 'µg', 'ml', 'IU', 'capsule', 'scoop'];

/// A supplement the user wants to track daily.
class Supplement {
  final String id;
  final String name;

  /// Manufacturer, when the user scanned or typed one.
  final String? brand;

  /// EAN/UPC from the barcode scanner; also the key used to re-look-up the
  /// product later.
  final String? barcode;

  /// How much is taken per dose, e.g. 5 with [doseUnit] `g` for creatine.
  final double? doseAmount;
  final String? doseUnit;

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
    this.barcode,
    this.doseAmount,
    this.doseUnit,
    this.nutrients = const {},
    this.schedule = SupplementSchedule.none,
    this.timeHHMM,
  });

  /// `Creatine Monohydrate · 5 g` — the row subtitle in the tracker.
  String? get doseLabel {
    final amount = doseAmount;
    final unit = doseUnit;
    if (amount == null || unit == null) return null;
    final fmt = amount.truncateToDouble() == amount
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(1);
    return '$fmt $unit';
  }

  bool get contributesNutrients =>
      nutrients.values.any((v) => v > 0);

  Supplement copyWith({
    String? name,
    String? brand,
    String? barcode,
    double? doseAmount,
    String? doseUnit,
    Map<String, double>? nutrients,
    SupplementSchedule? schedule,
    String? timeHHMM,
    bool clearTime = false,
    bool clearBrand = false,
    bool clearBarcode = false,
    bool clearDose = false,
  }) {
    return Supplement(
      id: id,
      name: name ?? this.name,
      brand: clearBrand ? null : (brand ?? this.brand),
      barcode: clearBarcode ? null : (barcode ?? this.barcode),
      doseAmount: clearDose ? null : (doseAmount ?? this.doseAmount),
      doseUnit: clearDose ? null : (doseUnit ?? this.doseUnit),
      nutrients: nutrients ?? this.nutrients,
      schedule: schedule ?? this.schedule,
      timeHHMM: clearTime ? null : (timeHHMM ?? this.timeHHMM),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (brand != null) 'brand': brand,
        if (barcode != null) 'barcode': barcode,
        if (doseAmount != null) 'doseAmount': doseAmount,
        if (doseUnit != null) 'doseUnit': doseUnit,
        if (nutrients.isNotEmpty) 'nutrients': nutrients,
        'schedule': schedule.id,
        if (timeHHMM != null) 'timeHHMM': timeHHMM,
      };

  factory Supplement.fromJson(Map<String, dynamic> json) => Supplement(
        id: json['id'] as String,
        name: json['name'] as String,
        brand: json['brand'] as String?,
        barcode: json['barcode'] as String?,
        doseAmount: (json['doseAmount'] as num?)?.toDouble(),
        doseUnit: json['doseUnit'] as String?,
        nutrients: _nutrientsFromJson(json['nutrients']),
        schedule: SupplementScheduleX.fromId((json['schedule'] as String?) ?? 'none'),
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
    return list.map((e) => Supplement.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<Supplement> supplements) =>
      jsonEncode(supplements.map((s) => s.toJson()).toList());
}
