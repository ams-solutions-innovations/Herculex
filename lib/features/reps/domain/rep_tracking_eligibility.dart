import 'rep_movement.dart';

/// The closed set of `ExerciseCatalog.slug` values assisted rep tracking is
/// offered for (REP-01).
///
/// Keyed on `slug`, never on `name` or `id`: the catalogue importer rewrites
/// display names and matches rows on slug by design
/// (`lib/data/local/tables.dart`), so a slug is the only identity that
/// survives a catalogue re-import.
///
/// **This list is closed. Do not widen it without recording fixture traces
/// for the new slug first** (REP-06). Every exclusion below is a decision,
/// not an oversight:
///
///  * Every **assisted** and **band-assisted** variant
///    (`assisted-pull-up-machine-wide-grip`, `band-assisted-dip`, …) — the
///    assistance changes the acceleration profile enough that it needs its
///    own calibration; borrowing the unassisted profile would mis-scale both
///    the count thresholds and the RPE features.
///  * `trx-hanging-dip` and `bench-dip` — unstable (suspended) and seated
///    kinematics respectively; neither produces the vertical translation the
///    detector keys on.
///  * `negative-pull-up` and `scapular-pull-up` — no countable concentric
///    cycle at all, so there is nothing to detect.
///  * `typewriter-pull-up`, `commando-pull-up`, `behind-the-neck-pull-up`,
///    `towel-pull-up` and `ring-l-sit-pull-up` — asymmetric or too low-volume
///    to gather enough real traces to validate against.
const Set<String> eligibleRepSlugs = {
  // Pull-up family → RepMovement.pullUp
  'pull-up',
  'pull-up-wide-grip',
  'pull-up-super-wide',
  'pull-up-neutral-grip',
  'chin-up-supinated',
  // Dip family → RepMovement.dip
  'chest-dips',
  'ring-dips',
};

const Set<String> _pullUpSlugs = {
  'pull-up',
  'pull-up-wide-grip',
  'pull-up-super-wide',
  'pull-up-neutral-grip',
  'chin-up-supinated',
};

const Set<String> _dipSlugs = {'chest-dips', 'ring-dips'};

/// Whether assisted rep tracking may be offered for [slug] at all.
///
/// Null (an exercise with no slug — custom or pre-v17 catalogue rows) is
/// never eligible.
bool isEligible(String? slug) => slug != null && eligibleRepSlugs.contains(slug);

/// The movement family [slug] belongs to, or null when it is ineligible.
///
/// 10-02 uses this to pick per-movement detector defaults and 10-05 uses it
/// to keep calibration profiles for pull-ups and dips separate.
RepMovement? movementFor(String slug) {
  if (_pullUpSlugs.contains(slug)) return RepMovement.pullUp;
  if (_dipSlugs.contains(slug)) return RepMovement.dip;
  return null;
}
