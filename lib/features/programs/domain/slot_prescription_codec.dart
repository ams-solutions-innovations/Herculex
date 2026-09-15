import 'dart:convert';

import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

/// Versioned JSON wire/storage format for [SlotPrescription].
///
/// This is the canonical codec `program_day_exercises.prescription_codec_json`
/// stores and every future reader must use — see D-01/PRES-01. There is no
/// legacy-shape fallback (D-04): a version mismatch decodes to `null` rather
/// than attempting a soft migration.
abstract final class SlotPrescriptionCodec {
  static const int wireVersion = 1;

  /// Encodes [prescription] into the versioned wire format.
  static String encode(SlotPrescription prescription) {
    return jsonEncode({
      'codecVersion': wireVersion,
      'name': prescription.name,
      'note': prescription.note,
      'segments': [
        for (final segment in prescription.segments)
          {
            'sets': segment.sets,
            'repsMin': segment.repsMin,
            'repsMax': segment.repsMax,
            'intent': segment.intent.id,
            'percentOf1Rm': segment.percentOf1Rm,
            'setType': segment.setType.id,
            'restSeconds': segment.restSeconds,
            if (segment.meta.isNotEmpty) 'meta': segment.meta,
          },
      ],
    });
  }

  /// Decodes [raw] back into a [SlotPrescription], or `null` if [raw] is
  /// missing, malformed, or was written by an incompatible codec version.
  static SlotPrescription? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['codecVersion'] != wireVersion) return null;

      final rawSegments = decoded['segments'] as List;
      return SlotPrescription(
        name: decoded['name'] as String,
        note: decoded['note'] as String?,
        segments: [
          for (final rawSegment in rawSegments)
            _decodeSegment(rawSegment as Map<String, dynamic>),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  static WorkSegment _decodeSegment(Map<String, dynamic> raw) {
    final meta = raw['meta'];
    return WorkSegment(
      sets: (raw['sets'] as num).toInt(),
      repsMin: (raw['repsMin'] as num).toInt(),
      repsMax: (raw['repsMax'] as num).toInt(),
      intent: Intent.fromId(raw['intent'] as String?),
      percentOf1Rm: (raw['percentOf1Rm'] as num?)?.toDouble(),
      setType: SetType.fromId(raw['setType'] as String?),
      restSeconds: (raw['restSeconds'] as num?)?.toInt(),
      meta: meta is Map
          ? Map<String, Object?>.from(meta)
          : const <String, Object?>{},
    );
  }
}
