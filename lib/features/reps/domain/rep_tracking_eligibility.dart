import 'rep_movement.dart';
import 'rep_tracking_profile.dart';

/// Whether assisted rep tracking may be offered for [slug] at all.
///
/// Eligibility used to be a hand-maintained set of seven slugs. It is now
/// derived from `assets/data/rep_tracking_profiles.json` via
/// [RepProfileRegistry], which carries a capability profile for **every**
/// catalogue row — the tier, the sensor site the exercise needs, the detection
/// channels and the amplitude floors.
///
/// Keyed on `slug`, never on `name` or `id`: the catalogue importer rewrites
/// display names and matches rows on slug by design
/// (`lib/data/local/tables.dart`), so a slug is the only identity that
/// survives a catalogue re-import.
///
/// Null (an exercise with no slug — custom or pre-v17 catalogue rows) is never
/// eligible, and neither is a slug the registry has never heard of. So is
/// every slug, if the registry has not loaded: the failure direction is always
/// "offer nothing", never "offer with guessed thresholds".
bool isEligible(String? slug) =>
    RepProfileRegistry.instance[slug]?.isTrackable ?? false;

/// The movement family [slug] belongs to, or null when it is ineligible.
///
/// The detector uses this to pick per-family thresholds and the calibration
/// layer uses it to keep profiles for different movements apart. A family is a
/// calibration key — see [RepMovement] for why the fifteen are drawn where
/// they are.
RepMovement? movementFor(String slug) =>
    RepProfileRegistry.instance[slug]?.family;

/// The full capability profile for [slug], or null when unknown.
///
/// Prefer this over [isEligible]/[movementFor] wherever the caller also needs
/// the sensor site or the reason — one lookup instead of three, and the
/// [RepTrackingProfile.reason] string is what lets the UI explain *why* an
/// exercise offers nothing rather than just staying silent.
RepTrackingProfile? profileFor(String? slug) =>
    RepProfileRegistry.instance[slug];

/// The sensor site [slug] needs, or null when it is ineligible.
///
/// This is the value that removes a manual choice from the user: a pull-up is
/// [SensorSite.pocket] because the hands are anchored and the wrist genuinely
/// cannot see the rep, and a bench press is [SensorSite.wrist]. Neither is a
/// preference to be configured.
SensorSite? sensorSiteFor(String? slug) =>
    RepProfileRegistry.instance[slug]?.site;
