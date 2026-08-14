import 'package:drift/drift.dart';

import '../../../data/local/database.dart';
import '../domain/rep_calibration.dart';
import '../domain/rep_tracking_eligibility.dart';

/// The single read/write surface for assisted rep tracking's local-only
/// state: global consent, per-exercise opt-in, and the confirmed-set
/// observations 10-05 trains calibration profiles on.
///
/// Nothing this class touches leaves the device — the three tables carry no
/// sync columns and have no outbox trigger (REP-04, asserted by
/// `test/rep_local_only_test.dart`).
class RepTrackingRepository {
  final AppDatabase _db;

  RepTrackingRepository(this._db);

  /// In-memory, per-session cache of [profileFor], keyed by the same
  /// four-part tuple `observationsFor` filters on. Recomputing a profile
  /// from ~30 rows is cheap, but a set-completion flow may read it several
  /// times in quick succession (panel, review sheet, "how this was
  /// measured" expander) — the cache just avoids redundant work, not
  /// staleness: [recordObservation] evicts the matching key so the very
  /// next read reflects the set just confirmed.
  final Map<String, CalibrationProfile> _profileCache = {};

  static String _profileCacheKey({
    required String slug,
    required String source,
    String? placement,
    required String sensorType,
  }) => '$slug|$source|${placement ?? ''}|$sensorType';

  // ── Consent ────────────────────────────────────────────────────────────

  /// The single settings row, or null if the consent screen has never been
  /// reached. `consentGrantedAt == null` on a present row means the same
  /// thing as no row at all: consent has not been given.
  Future<RepTrackingSettingData?> settings() {
    return (_db.select(
      _db.repTrackingSettings,
    )..limit(1)).getSingleOrNull();
  }

  /// Records that the user completed the consent screen at [version].
  ///
  /// Insert-or-update against the single row — this table is a singleton by
  /// convention, and a second row would create two disagreeing gates.
  Future<void> grantConsent({required int version}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await settings();
      if (existing == null) {
        await _db
            .into(_db.repTrackingSettings)
            .insert(
              RepTrackingSettingsCompanion.insert(
                consentGrantedAt: Value(now),
                consentVersion: Value(version),
              ),
            );
      } else {
        await (_db.update(
          _db.repTrackingSettings,
        )..where((t) => t.id.equals(existing.id))).write(
          RepTrackingSettingsCompanion(
            consentGrantedAt: Value(now),
            consentVersion: Value(version),
          ),
        );
      }
    });
  }

  /// Revokes consent and erases every motion-derived row.
  ///
  /// One transaction, deliberately: clearing the gate but leaving the
  /// observations behind would be a partial revoke, which is worse than no
  /// control at all — the user asked for the data to be gone, not hidden
  /// (T-10-04). Prefs go too, so a later re-consent starts from every
  /// exercise off rather than from a stale opt-in the user has forgotten.
  Future<void> revokeConsent() async {
    await _db.transaction(() async {
      await _db.update(_db.repTrackingSettings).write(
        const RepTrackingSettingsCompanion(consentGrantedAt: Value(null)),
      );
      await _db.delete(_db.repTrackingExercisePrefs).go();
      await _db.delete(_db.repSetObservations).go();
    });
  }

  /// Persists the consent screen's sensor-source choice and, for `phone`,
  /// its placement (REP-02). Called from `rep_tracking_consent_view.dart`
  /// immediately after [grantConsent] — added by 10-04 because neither
  /// `RepTrackingSettings.defaultSource` nor `.phonePlacement` had a writer
  /// before this plan, and the consent screen is the only place either may
  /// be set. Never defaults [placement] itself; the caller decides whether
  /// one was actually chosen.
  Future<void> updateSensorPreferences({
    required String source,
    String? placement,
  }) async {
    await _db.transaction(() async {
      final existing = await settings();
      final companion = RepTrackingSettingsCompanion(
        defaultSource: Value(source),
        phonePlacement: Value(placement),
      );
      if (existing == null) {
        await _db
            .into(_db.repTrackingSettings)
            .insert(
              RepTrackingSettingsCompanion.insert(
                defaultSource: Value(source),
                phonePlacement: Value(placement),
              ),
            );
      } else {
        await (_db.update(
          _db.repTrackingSettings,
        )..where((t) => t.id.equals(existing.id))).write(companion);
      }
    });
  }

  // ── Per-exercise opt-in ────────────────────────────────────────────────

  /// Enables or disables tracking for [slug].
  ///
  /// Throws [ArgumentError] for an ineligible slug rather than writing a row
  /// that nothing will ever read — a silent no-op here would look like a
  /// working opt-in in the UI.
  Future<void> setExerciseEnabled(String slug, bool enabled) async {
    if (!isEligible(slug)) {
      throw ArgumentError.value(
        slug,
        'slug',
        'not an assisted-rep-tracking eligible exercise',
      );
    }
    await _db
        .into(_db.repTrackingExercisePrefs)
        .insert(
          RepTrackingExercisePrefsCompanion.insert(
            exerciseSlug: slug,
            enabled: Value(enabled),
            updatedAt: DateTime.now(),
          ),
          // `insertOnConflictUpdate` would target the primary key (`id`),
          // which a fresh companion never supplies — the conflict actually
          // raised is on the `exercise_slug` unique key, so the target has
          // to be named explicitly or the second toggle throws 2067.
          onConflict: DoUpdate(
            (old) => RepTrackingExercisePrefsCompanion(
              enabled: Value(enabled),
              updatedAt: Value(DateTime.now()),
            ),
            target: [_db.repTrackingExercisePrefs.exerciseSlug],
          ),
        );
  }

  /// Whether tracking may run for [slug] right now.
  ///
  /// Consent is checked **first and short-circuits** (T-10-03): a pref row
  /// left over from before a revoke, or written by a future bug, can never
  /// re-enable tracking on its own.
  Future<bool> isEnabledFor(String slug) async {
    final s = await settings();
    if (s?.consentGrantedAt == null) return false;
    if (!isEligible(slug)) return false;
    final pref =
        await (_db.select(_db.repTrackingExercisePrefs)
              ..where((t) => t.exerciseSlug.equals(slug))
              ..limit(1))
            .getSingleOrNull();
    return pref?.enabled ?? false;
  }

  /// The stored preference row for [slug], or null when the user has never
  /// touched it.
  Future<RepTrackingExercisePrefData?> prefFor(String slug) {
    return (_db.select(_db.repTrackingExercisePrefs)
          ..where((t) => t.exerciseSlug.equals(slug))
          ..limit(1))
        .getSingleOrNull();
  }

  // ── Observations ───────────────────────────────────────────────────────

  /// Persists one confirmed set's derived features and outcome.
  ///
  /// [featuresJson] is the derived feature vector (schema owned by 10-02).
  /// Raw samples are never passed here and there is no column that could
  /// hold them (REP-04).
  Future<void> recordObservation({
    required String exerciseSlug,
    required int sessionId,
    int? setEntryId,
    required DateTime recordedAt,
    required String source,
    String? placement,
    required String sensorType,
    required int detectedReps,
    required int confirmedReps,
    required double confidence,
    int? suggestedRpeX10,
    int? confirmedRpeX10,
    required String featuresJson,
  }) async {
    await _db
        .into(_db.repSetObservations)
        .insert(
          RepSetObservationsCompanion.insert(
            exerciseSlug: exerciseSlug,
            sessionId: sessionId,
            setEntryId: Value(setEntryId),
            recordedAt: recordedAt,
            source: source,
            placement: Value(placement),
            sensorType: sensorType,
            detectedReps: detectedReps,
            confirmedReps: confirmedReps,
            confidence: confidence,
            suggestedRpeX10: Value(suggestedRpeX10),
            confirmedRpeX10: Value(confirmedRpeX10),
            featuresJson: featuresJson,
          ),
        );
    // The set just confirmed changes this exact key's training set — evict
    // it so the next read (10-05) recomputes rather than serving a profile
    // that predates this observation.
    _profileCache.remove(
      _profileCacheKey(
        slug: exerciseSlug,
        source: source,
        placement: placement,
        sensorType: sensorType,
      ),
    );
  }

  /// The training set for one exact (slug, source, placement, sensorType)
  /// tuple, oldest first.
  ///
  /// The tuple is exact on purpose: a profile learned from a wrist sensor
  /// must not be fed phone-in-pocket rows, and linear-acceleration and
  /// raw-accelerometer traces are not interchangeable. A null [placement]
  /// matches only rows whose stored placement is null — it is the wrist
  /// case, not a wildcard.
  Future<List<RepSetObservationData>> observationsFor({
    required String slug,
    required String source,
    String? placement,
    required String sensorType,
  }) {
    final q = _db.select(_db.repSetObservations)
      ..where((t) => t.exerciseSlug.equals(slug))
      ..where((t) => t.source.equals(source))
      ..where((t) => t.sensorType.equals(sensorType))
      ..where(
        (t) => placement == null
            ? t.placement.isNull()
            : t.placement.equals(placement),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.recordedAt)]);
    return q.get();
  }

  /// The learning profile for one exact (slug, source, placement,
  /// sensorType) tuple — `CalibrationProfile.fromObservations` over that
  /// tuple's [observationsFor]. Cached per key for the session; see
  /// [_profileCache]'s doc for the invalidation contract.
  Future<CalibrationProfile> profileFor({
    required String slug,
    required String source,
    String? placement,
    required String sensorType,
  }) async {
    final key = _profileCacheKey(
      slug: slug,
      source: source,
      placement: placement,
      sensorType: sensorType,
    );
    final cached = _profileCache[key];
    if (cached != null) return cached;

    final rows = await observationsFor(
      slug: slug,
      source: source,
      placement: placement,
      sensorType: sensorType,
    );
    final profile = CalibrationProfile.fromObservations(rows);
    _profileCache[key] = profile;
    return profile;
  }
}
