import 'dart:convert';

/// Small, versioned extension to the existing set metadata. This keeps a
/// template's chosen bodyweight variant and timed target through snapshotting.
class CalisthenicsSetPlan {
  const CalisthenicsSetPlan(this.variant, this.durationSeconds);
  final String variant;
  final int? durationSeconds;
  String encode() => jsonEncode({
    'calisthenicsPlan': {
      'version': 1,
      'variant': variant,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
    },
  });

  static CalisthenicsSetPlan? decode(String? source) {
    if (source == null) return null;
    try {
      final json = jsonDecode(source);
      if (json is! Map || json['calisthenicsPlan'] is! Map) return null;
      final plan = json['calisthenicsPlan'] as Map;
      final variant = plan['variant'];
      if (plan['version'] != 1 ||
          !['band', 'bodyweight', 'weighted'].contains(variant)) {
        return null;
      }
      final seconds = plan['durationSeconds'];
      return CalisthenicsSetPlan(
        variant as String,
        seconds is int && seconds > 0 ? seconds : null,
      );
    } catch (_) {
      return null;
    }
  }
}
