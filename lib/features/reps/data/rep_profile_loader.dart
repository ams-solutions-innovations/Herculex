import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../domain/rep_tracking_profile.dart';

/// Loads `assets/data/rep_tracking_profiles.json` into
/// [RepProfileRegistry].
///
/// Separate from the registry itself so the domain layer stays free of
/// `rootBundle` — the registry parses a string and is testable without a
/// widget binding, and this file is the only place that knows the asset path.
///
/// Called once from `main()`, before the first frame. It must run on every
/// launch, unlike the catalogue import, which only runs on install and
/// migration: the registry lives in memory and starts empty every time.
class RepProfileLoader {
  const RepProfileLoader._();

  static const assetPath = 'assets/data/rep_tracking_profiles.json';

  /// Best-effort. A missing or malformed asset leaves the registry empty,
  /// which reports every exercise as unsupported — the feature disappears
  /// rather than appearing with guessed thresholds, and the rest of the app
  /// starts normally. Startup must never fail over an optional feature's
  /// data file.
  static Future<void> load() async {
    try {
      final body = await rootBundle.loadString(assetPath);
      final registry = RepProfileRegistry.loadFromJson(body);
      assert(() {
        debugPrint('rep tracking: loaded ${registry.length} exercise profiles');
        return true;
      }());
    } catch (error, stack) {
      // Deliberately swallowed — see the doc comment above.
      assert(() {
        debugPrint('rep tracking: profile load failed ($error)\n$stack');
        return true;
      }());
    }
  }
}
