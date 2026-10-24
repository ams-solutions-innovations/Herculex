import 'dart:async';
import 'dart:convert';
import 'package:herculex/features/labs/domain/labs_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Device-only, versioned records. Separate keys avoid overwriting histories
/// when unrelated check-ins and supplement events arrive concurrently.
class LabsRepository {
  LabsRepository(this.prefs);
  final SharedPreferences prefs;
  int privacyEpoch = 0;
  static const prefix = 'herculex_labs_v1_';
  final changes = StreamController<void>.broadcast();
  LabsConsent get consent {
    final raw = prefs.getString('${prefix}consent');
    if (raw == null) return const LabsConsent();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> || json['version'] != 1) {
        return const LabsConsent();
      }
      return LabsConsent.fromJson(json);
    } on FormatException {
      return const LabsConsent();
    } on TypeError {
      return const LabsConsent();
    }
  }

  Future<void> saveConsent(LabsConsent next) async {
    privacyEpoch++;
    await prefs.setString('${prefix}consent', jsonEncode(next.toJson()));
    changes.add(null);
  }

  List<Map<String, dynamic>> records(String kind) =>
      prefs
          .getKeys()
          .where((k) => k.startsWith('$prefix${kind}_'))
          .map(
            (k) => Map<String, dynamic>.from(jsonDecode(prefs.getString(k)!)),
          )
          .toList()
        ..sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));

  Future<void> put(String kind, String id, Map<String, dynamic> value) async {
    await prefs.setString(
      '$prefix${kind}_$id',
      jsonEncode({'version': 1, ...value}),
    );
    changes.add(null);
  }

  Future<void> checkIn(
    DateTime at,
    Map<String, double> values, {
    String note = '',
  }) async {
    if (!consent.allows(LabsCategory.context)) {
      throw StateError('Daily context consent required');
    }
    if (values.values.any((v) => !v.isFinite || v < 0) ||
        values.entries.any(
          (e) =>
              !['caffeine_mg', 'alcohol_units'].contains(e.key) && e.value > 5,
        )) {
      throw ArgumentError('Check-in scores must be between 0 and 5');
    }
    await put('checkin', labsDate(at), {
      'at': labsDay(at).toIso8601String(),
      'values': values,
      'note': note,
    });
  }

  Future<void> addChange(
    LabsCategory category,
    String title,
    DateTime at, {
    String? end,
    Map<String, dynamic> details = const {},
  }) async {
    if (!consent.allows(category)) {
      throw StateError('Category consent required');
    }
    await put('event', const Uuid().v4(), {
      'at': at.toIso8601String(),
      'category': category.name,
      'title': title,
      'end': end,
      'details': details,
    });
  }

  static const templates = {
    'rest': ('Rest between sets', 'Longer vs usual rest', 'e1rm', 'kg'),
    'supersets': (
      'Standard sets vs supersets',
      'Superset configuration',
      'training_minutes',
      'min',
    ),
    'time': ('Training time', 'Earlier vs usual training', 'energy', '/5'),
    'protein': (
      'Protein distribution',
      'More even distribution',
      'hunger',
      '/5',
    ),
  };
  Future<void> startExperiment(
    String template,
    DateTime now,
    double target, {
    String baselineDescription = 'Usual routine',
    String changeDescription = 'Selected single change',
  }) async {
    final t = templates[template]!;
    final required = switch (template) {
      'protein' => {LabsCategory.nutrition, LabsCategory.context},
      'time' => {LabsCategory.training, LabsCategory.context},
      'rest' => {LabsCategory.training, LabsCategory.strength},
      _ => {LabsCategory.training, LabsCategory.techniques},
    };
    if (!consent.enabled || !consent.categories.containsAll(required)) {
      throw StateError(
        'Enable the categories needed for this experiment in privacy settings.',
      );
    }
    if (!target.isFinite || target <= 0) {
      throw ArgumentError('Choose a positive meaningful change');
    }
    final id = const Uuid().v4();
    await put('experiment', id, {
      'id': id,
      'at': labsDay(now).toIso8601String(),
      'template': template,
      'title': t.$1,
      'change': t.$2,
      'metric': t.$3,
      'unit': t.$4,
      'baselineDescription': baselineDescription,
      'changeDescription': changeDescription,
      'target': target,
      'direction': ['supersets', 'protein'].contains(template)
          ? 'decrease'
          : 'increase',
      'status': 'active',
      'categories': required.map((c) => c.name).toList(),
      'baselineEnd': DateTime(
        now.year,
        now.month,
        now.day + 14,
      ).toIso8601String(),
      'end': DateTime(now.year, now.month, now.day + 28).toIso8601String(),
      'protocol':
          '14 days of your usual routine, then 14 days changing only the selected factor. '
          'Keep exercise selection, effort and other routines comparable. Record deviations. '
          'This unblinded baseline/intervention comparison is descriptive, not causal proof.',
    });
  }

  Future<void> stopExperiment(
    Map<String, dynamic> experiment, {
    DateTime? at,
  }) => put('experiment', experiment['id'], {
    ...experiment,
    'status': 'stopped',
    'stoppedAt': (at ?? DateTime.now()).toIso8601String(),
  });

  Future<void> deleteAnalysis() async {
    privacyEpoch++;
    for (final key
        in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      await prefs.remove(key);
    }
    changes.add(null);
  }

  Future<void> deleteReports() async {
    privacyEpoch++;
    for (final key
        in prefs
            .getKeys()
            .where((k) => k.startsWith('${prefix}report_'))
            .toList()) {
      await prefs.remove(key);
    }
    changes.add(null);
  }

  /// Called at the canonical supplement write path, including notification
  /// actions. Old checklist ticks have unknown historical dose.
  static Future<void> recordIntake(
    SharedPreferences prefs,
    String id,
    bool taken,
    DateTime at, {
    DateTime? recordedAt,
  }) async {
    final repo = LabsRepository(prefs);
    try {
      final c = repo.consent;
      if (!c.allows(LabsCategory.supplements)) return;
      final configs =
          jsonDecode(prefs.getString('supplements_config_v1') ?? '[]') as List;
      final matches = configs.where((s) => s['id'] == id);
      var product = matches.isEmpty
          ? <String, dynamic>{'id': id}
          : Map<String, dynamic>.from(matches.first);
      final key = '${prefix}intake_${labsDate(at)}_$id';
      final previousRaw = prefs.getString(key);
      if (previousRaw != null) {
        final previous = jsonDecode(previousRaw) as Map;
        product = Map<String, dynamic>.from(previous['product'] as Map);
      } else if (labsDay(at).isBefore(labsDay(recordedAt ?? DateTime.now()))) {
        // A backdated tick confirms use, not the dose that was used then.
        product = {'id': product['id'], 'name': product['name']};
      }
      await prefs.setString(
        key,
        jsonEncode({
          'version': 1,
          'at': at.toIso8601String(),
          'product': product,
          'taken': taken,
          'status': taken ? 'taken' : 'confirmed_skipped',
        }),
      );
    } finally {
      await repo.changes.close();
    }
  }
}
