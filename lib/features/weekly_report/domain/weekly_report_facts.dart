/// The only data that leaves the device for the weekly narrative (RPT-02).
///
/// [WeeklyReportFacts.fromPayload] turns a frozen [WeeklyReportPayload] into
/// the model input: aggregates and a handful of short, sanitised strings. No
/// ids, no photos, no user notes and no raw samples (data minimisation, GDPR
/// Art. 9). Food and exercise names are user-authored text, so they are
/// stripped of control characters and capped before they can reach a prompt
/// (client side of the prompt-injection mitigation; the server adds the prompt
/// rule and its own 8000-character cap).
///
/// Sections that are null in the payload are omitted from the map entirely,
/// never sent as explicit nulls. Key order is fixed, so equal payloads encode
/// to byte-identical JSON.
///
/// Pure Dart: no Flutter, drift or wall-clock reads.
library;

import 'dart:convert';

import 'package:herculex/features/weekly_report/domain/weekly_report_payload.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';

abstract final class WeeklyReportFacts {
  /// Matches the Edge Function's `isValidWeeklyReportFacts` cap.
  static const int maxJsonLength = 8000;

  static const int _maxNameLength = 40;
  static const int _maxWarningLength = 80;
  static const int _maxStatementLength = 160;
  static const int _maxFoods = 3;
  static const int _maxMovers = 3;
  static const int _maxWarnings = 5;
  static const int _maxCorrelations = 4;

  /// Removes control characters, collapses whitespace runs to one space, trims
  /// and truncates to [maxLength] characters (whole code points, so a
  /// surrogate pair is never split).
  ///
  /// Whitespace-like controls (tab, newline, line and paragraph separators)
  /// become a space first so that "a\nb" stays two words; every other control
  /// character is dropped.
  static String sanitizeText(String input, {required int maxLength}) {
    final cleaned = input
        .replaceAll(_whitespaceControls, ' ')
        .replaceAll(_controls, '')
        .replaceAll(_whitespaceRun, ' ')
        .trim();
    if (cleaned.isEmpty) return '';
    final runes = cleaned.runes;
    if (runes.length <= maxLength) return cleaned;
    return String.fromCharCodes(runes.take(maxLength)).trim();
  }

  static final RegExp _whitespaceControls = RegExp(r'[\t\n\r\f\v\u0085  ]');
  static final RegExp _controls = RegExp(r'[\u0000-\u001F\u007F-\u009F]');
  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// Builds the facts map for [payload].
  ///
  /// The result is guaranteed to encode to at most [maxLength] characters when
  /// that is achievable. If it is too long, the content is reduced in a fixed
  /// order until it fits: top foods first, then warnings beyond two, then the
  /// text of correlation lines beyond the first, then (last resorts) all
  /// warnings, all correlations and all strength movers. [maxLength] exists so
  /// tests can exercise the ladder; production callers use the default.
  static Map<String, Object?> fromPayload(
    WeeklyReportPayload payload, {
    int maxLength = maxJsonLength,
  }) {
    Map<String, Object?> last = _build(payload, 0);
    for (var level = 0; level <= _lastLevel; level++) {
      last = _build(payload, level);
      if (jsonEncode(last).length <= maxLength) return last;
    }
    return last;
  }

  static const int _lastLevel = 6;

  static Map<String, Object?> _build(WeeklyReportPayload p, int level) {
    final nutrition = p.nutrition;
    final training = p.training;
    final recovery = p.recovery;
    final physique = p.physique;
    final tdee = p.tdee;
    return <String, Object?>{
      'week': <String, Object?>{
        'isoYear': p.isoYear,
        'isoWeek': p.isoWeek,
        'start': p.weekStartIso,
        'end': p.weekEndIso,
      },
      if (nutrition != null) 'nutrition': _nutrition(nutrition, level),
      if (training != null) 'training': _training(training, level),
      if (recovery != null) 'recovery': _recovery(recovery, level),
      if (physique != null) 'physique': _physique(physique),
      if (tdee != null)
        'tdee': <String, Object?>{
          'oldKcal': tdee.oldKcal,
          'newKcal': tdee.newKcal,
          'deltaKcal': tdee.deltaKcal,
          'material': tdee.material,
          'confidence': tdee.confidence,
        },
    };
  }

  static Map<String, Object?> _nutrition(NutritionSection n, int level) {
    final foods = <Map<String, Object?>>[];
    for (final f in n.topFoods) {
      final name = sanitizeText(f.name, maxLength: _maxNameLength);
      if (name.isEmpty) continue;
      foods.add(<String, Object?>{'name': name, 'count': f.count});
      if (foods.length == _maxFoods) break;
    }
    return <String, Object?>{
      'daysLogged': n.daysLogged,
      'avgKcal': n.avgKcal,
      'avgProteinG': n.avgProteinG,
      if (n.targetKcal != null) 'targetKcal': n.targetKcal,
      if (n.targetProteinG != null) 'targetProteinG': n.targetProteinG,
      if (n.adherenceDays != null) 'adherenceDays': n.adherenceDays,
      if (level < 1 && foods.isNotEmpty) 'topFoods': foods,
    };
  }

  static Map<String, Object?> _training(TrainingSection t, int level) {
    final movers = <Map<String, Object?>>[];
    if (level < 6) {
      for (final m in t.e1rmMovers) {
        final name = sanitizeText(m.exerciseName, maxLength: _maxNameLength);
        if (name.isEmpty) continue;
        movers.add(<String, Object?>{
          'exercise': name,
          'e1rmKg': _round1(m.e1rmKg),
          'deltaKg': _round1(m.deltaKg),
        });
        if (movers.length == _maxMovers) break;
      }
    }
    return <String, Object?>{
      'sessions': t.sessions,
      'tonnageKg': _round1(t.tonnageKg),
      if (t.prevWeekTonnageKg != null)
        'prevWeekTonnageKg': _round1(t.prevWeekTonnageKg!),
      if (movers.isNotEmpty) 'e1rmMovers': movers,
    };
  }

  static Map<String, Object?> _recovery(RecoverySection r, int level) {
    final warningLimit = level >= 4 ? 0 : (level >= 2 ? 2 : _maxWarnings);
    final warnings = <String>[];
    for (final w in r.recoveryWarnings) {
      if (warnings.length == warningLimit) break;
      final text = sanitizeText(w, maxLength: _maxWarningLength);
      if (text.isNotEmpty) warnings.add(text);
    }

    final correlations = <Map<String, Object?>>[];
    if (level < 5) {
      for (final c in r.correlations) {
        if (correlations.length == _maxCorrelations) break;
        final statement = sanitizeText(
          c.statement,
          maxLength: _maxStatementLength,
        );
        if (statement.isEmpty) continue;
        final keepText = level < 3 || correlations.isEmpty;
        correlations.add(<String, Object?>{
          'kind': sanitizeText(c.kind, maxLength: _maxNameLength),
          if (keepText) 'statement': statement,
          'n': c.sampleSize,
        });
      }
    }

    return <String, Object?>{
      if (r.avgSleepHours != null) 'avgSleepHours': _round1(r.avgSleepHours!),
      if (r.avgSteps != null) 'avgSteps': r.avgSteps,
      if (r.avgRestingHr != null) 'avgRestingHr': _round1(r.avgRestingHr!),
      if (r.cnsReadinessPct != null) 'cnsReadinessPct': r.cnsReadinessPct,
      'cnsDeloadSuggested': r.cnsDeloadSuggested,
      if (warnings.isNotEmpty) 'recoveryWarnings': warnings,
      if (correlations.isNotEmpty) 'correlations': correlations,
    };
  }

  static Map<String, Object?> _physique(PhysiqueSection s) {
    final verdict = s.checkInVerdict;
    final confidence = s.checkInConfidence;
    return <String, Object?>{
      if (verdict != null)
        'checkInVerdict': sanitizeText(verdict, maxLength: _maxNameLength),
      if (confidence != null)
        'checkInConfidence': sanitizeText(
          confidence,
          maxLength: _maxNameLength,
        ),
      if (s.bodyweightKg != null) 'bodyweightKg': _round1(s.bodyweightKg!),
      if (s.bodyweightDeltaKg != null)
        'bodyweightDeltaKg': _round1(s.bodyweightDeltaKg!),
    };
  }

  static double _round1(double v) => (v * 10).round() / 10;
}
