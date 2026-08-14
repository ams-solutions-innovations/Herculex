import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../data/rep_tracking_repository.dart';

final repTrackingRepositoryProvider = Provider<RepTrackingRepository>((ref) {
  return RepTrackingRepository(ref.watch(appDatabaseProvider));
});

/// The single settings row. Null, or a row whose `consentGrantedAt` is null,
/// both mean "consent screen not completed".
final repTrackingSettingsProvider = FutureProvider<RepTrackingSettingData?>((
  ref,
) {
  return ref.watch(repTrackingRepositoryProvider).settings();
});

/// Whether tracking may run for one catalogue slug. False whenever consent is
/// absent, regardless of the per-exercise preference.
final repTrackingEnabledForProvider = FutureProvider.family<bool, String>((
  ref,
  slug,
) {
  return ref.watch(repTrackingRepositoryProvider).isEnabledFor(slug);
});
