import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/cns_breakdown.dart';
import 'analytics_providers.dart';

/// Full CNS detailed breakdown: acute/chronic metrics, recent sessions with
/// residual fatigue, exercise rankings, and recovery ETA predictions.
final cnsDetailedBreakdownProvider = FutureProvider<CnsDetailedResult>((
  ref,
) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  final asOf = ref.watch(clockProvider).now();
  return CnsBreakdownEngine.compute(snapshot: snapshot, asOf: asOf);
});
