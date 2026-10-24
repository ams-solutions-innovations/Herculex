import 'package:herculex/features/labs/domain/labs_models.dart';
import 'package:herculex/features/weekly_report/domain/weekly_narrative.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

abstract interface class LabsAiBackend {
  Future<Map<String, dynamic>> explainLabs(Map<String, dynamic> facts);
}

class LabsAiService {
  const LabsAiService(this.backend);
  final LabsAiBackend? backend;
  static Map<String, dynamic> facts(
    LabsSnapshot snapshot,
    Set<LabsCategory> categories,
  ) => {
    'findings': snapshot.findings
        .where((f) => categories.contains(f.category))
        .take(12)
        .map(
          (f) => {
            'category': f.category.name,
            'support': f.support,
            'observedDays': f.n,
            'before': f.before,
            'after': f.after,
            'delta': f.delta,
            'q': f.q,
            'coverage': f.coverage,
          },
        )
        .toList(),
  };
  Future<WeeklyNarrative> explain(Map<String, dynamic> facts) async {
    if (backend == null) {
      throw StateError(
        'Labs AI is not configured in this build. Local analysis is available.',
      );
    }
    final result = await backend!
        .explainLabs(facts)
        .timeout(const Duration(seconds: 45));
    final narrative = WeeklyNarrative.fromJson(result, facts: facts);
    // Labs explanations are intentionally number-free: exact numeric results
    // and their support levels are rendered only from deterministic snapshots.
    if (RegExp(
      r'\d',
    ).hasMatch('${narrative.summary} ${narrative.suggestions.join(' ')}')) {
      throw const FormatException('AI explanation introduced numeric claims');
    }
    return narrative;
  }
}

/// Kept outside GeminiBackend so existing fake backends remain compatible.
class GeminiLabsAiBackend implements LabsAiBackend {
  const GeminiLabsAiBackend(this.backend);
  final SupabaseGeminiBackend backend;
  @override
  Future<Map<String, dynamic>> explainLabs(Map<String, dynamic> facts) =>
      backend.explainLabs(facts);
}
