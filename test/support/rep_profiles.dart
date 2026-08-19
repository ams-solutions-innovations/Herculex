import 'dart:io';

import 'package:herculex/features/reps/domain/rep_tracking_profile.dart';

/// Installs the real capability profiles asset into [RepProfileRegistry].
///
/// Any test that exercises eligibility, the capture service or a tracker
/// widget needs this: those paths resolve an exercise slug through the
/// registry, and an unloaded registry correctly reports every exercise as
/// unsupported — so without it a test sees "manual, no movement" rather than
/// the behaviour it meant to assert.
///
/// Reads the asset from disk rather than through `rootBundle` so it works in
/// a plain `flutter test` with no widget binding.
void loadRepProfilesForTest() {
  RepProfileRegistry.loadFromJson(
    File('assets/data/rep_tracking_profiles.json').readAsStringSync(),
  );
}
