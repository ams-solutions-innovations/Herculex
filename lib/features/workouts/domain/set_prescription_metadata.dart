import 'dart:convert';

/// Backward-compatible prescription envelope in existing synced set metadata.
/// Template tables predate RPE/percentage targets; copying a program must not
/// silently discard those targets or its selected equipment/method.
abstract final class SetPrescriptionMetadata {
  static Map<String, dynamic> decode(String? raw) {
    try {
      final meta = jsonDecode(raw ?? '{}');
      if (meta is Map && meta['setPrescription'] is Map) {
        return Map<String, dynamic>.from(meta['setPrescription'] as Map);
      }
    } catch (_) {
      /* Legacy metadata has no prescription envelope. */
    }
    return {};
  }

  static String encode(String? raw, Map<String, dynamic> prescription) {
    Map<String, dynamic> meta;
    try {
      meta = Map<String, dynamic>.from(jsonDecode(raw ?? '{}') as Map);
    } catch (_) {
      meta = {if (raw != null) 'legacyMetadata': raw};
    }
    return jsonEncode({
      ...meta,
      'setPrescription': {'version': 1, ...prescription},
    });
  }
}
