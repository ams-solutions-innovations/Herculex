import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/program_brief.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

/// The single generate -> parse -> persist -> read seam for Herculex AI
/// program design briefs (AIP-02/03/05). Modeled directly on
/// `DreamPhysiqueService` (`lib/features/profile/data/dream_physique_service.dart`)
/// for the "call Gemini, parse strictly, translate failures into a
/// user-facing exception" shape.
///
/// This is the ONLY code path in this phase that reads or writes
/// `HerculexAiProgramBriefs` (CLAUDE.md's "UI never touches drift directly"
/// rule, and RESEARCH.md's explicit warning against repeating the
/// pre-existing anti-pattern). `block_builder_view.dart` (plans 27-11/27-13)
/// and `program_review_view.dart` (plan 27-12) call into this service only.
final herculexAiBriefServiceProvider = Provider<HerculexAiBriefService>((ref) {
  final backend = ref.watch(geminiBackendProvider);
  final db = ref.watch(appDatabaseProvider);
  final clock = ref.watch(clockProvider);
  return HerculexAiBriefService(backend, db, clock);
});

/// Substrings that identify the Edge Function's daily-quota-exhausted
/// message shape (see `supabase/functions/gemini-analyze/index.ts`'s
/// `` `Today's ${featureName} (${quota.limit}/day) are used up — try again
/// tomorrow${manualFallback}.` `` 429 response). There is no typed
/// quota-exception class to catch, so detection is substring-based on the
/// stripped error text. Matching either substring is sufficient — both are
/// always present together in the real message, but only one is required so
/// a future wording tweak to either half still gets classified correctly.
const _quotaExhaustedIndicators = <String>['used up', 'try again tomorrow'];

/// A translated, user-facing failure from [HerculexAiBriefService.generateBrief].
/// [message] never contains a raw technical exception string (T-27-13).
/// [isQuotaExhausted] is the failure-category signal plan 27-11's UI uses to
/// pick between AIP-05's two distinct degradation copy strings (offline/
/// unconfigured vs over-quota) without this service needing to know the
/// final UI copy.
class HerculexAiBriefException implements Exception {
  final String message;
  final bool recoverable;
  final bool isQuotaExhausted;

  const HerculexAiBriefException(
    this.message, {
    this.recoverable = true,
    this.isQuotaExhausted = false,
  });

  @override
  String toString() => message;
}

class HerculexAiBriefService {
  HerculexAiBriefService(this._backend, this._db, this._clock);

  final GeminiBackend _backend;
  final AppDatabase _db;
  final Clock _clock;

  /// Calls the Gemini backend and strictly parses the result into a
  /// [ProgramBrief]. Any failure (network, unconfigured, quota, or malformed
  /// JSON) is translated into a [HerculexAiBriefException] carrying a
  /// non-technical message and a failure-category signal — never a raw
  /// technical exception string (AIP-05, T-27-13).
  Future<(ProgramBrief brief, Map<String, dynamic> provenance)> generateBrief({
    required Map<String, dynamic> profileInputs,
    String? userNote,
  }) async {
    try {
      final (result, provenance) = await _backend.generateProgramBrief(
        profileInputs: profileInputs,
        userNote: userNote,
      );

      try {
        return (ProgramBrief.fromJson(result), provenance);
      } on FormatException {
        throw const HerculexAiBriefException(
          'Herculex AI returned an incomplete brief. Try generating again.',
        );
      }
    } on HerculexAiBriefException {
      rethrow;
    } catch (error) {
      final detail = error.toString().replaceFirst('Exception: ', '').trim();
      final isQuotaExhausted = _quotaExhaustedIndicators.any(
        detail.contains,
      );
      final message = detail.isEmpty
          ? 'Herculex AI is temporarily unavailable. Try again later.'
          : detail;
      throw HerculexAiBriefException(message, isQuotaExhausted: isQuotaExhausted);
    }
  }

  /// Writes exactly one row to `HerculexAiProgramBriefs`. This is the only
  /// write path to that table in this phase (T-27-14). [confirmedAt] is
  /// stamped from the injected [Clock], never `DateTime.now()` directly.
  Future<void> persistBrief({
    required int programId,
    required ProgramBrief brief,
    required Map<String, dynamic> provenance,
  }) async {
    await _db
        .into(_db.herculexAiProgramBriefs)
        .insert(
          HerculexAiProgramBriefsCompanion.insert(
            programId: programId,
            briefJson: jsonEncode(brief.toJson()),
            source: const Value('herculex_ai'),
            knowledgeVersion: Value(
              provenance['knowledgeVersion'] as String?,
            ),
            modelVersion: Value(provenance['modelVersion'] as String?),
            confirmedAt: Value(_clock.now()),
            active: const Value(true),
          ),
        );
  }

  /// Live read of the most recent active brief for [programId], or `null` if
  /// none exists. Mirrors `_loadDreamPhysiquePriorities()`'s existing query
  /// shape (active = true, newest `confirmedAt` first) but as a `watch()`
  /// stream, per the house rule preferring `StreamProvider` over
  /// `FutureProvider` for drift reads.
  Stream<HerculexAiProgramBriefData?> watchBriefForProgram(int programId) {
    final query = _db.select(_db.herculexAiProgramBriefs)
      ..where((t) => t.programId.equals(programId) & t.active.equals(true))
      ..orderBy([(t) => OrderingTerm.desc(t.confirmedAt)])
      ..limit(1);
    return query.watchSingleOrNull();
  }
}
