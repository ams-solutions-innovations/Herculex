import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/analytics/domain/cns_breakdown.dart';

/// Full CNS detailed breakdown: acute/chronic metrics, recent sessions with
/// residual fatigue, exercise rankings, and recovery ETA predictions.
final cnsDetailedBreakdownProvider = FutureProvider<CnsDetailedResult>((
  ref,
) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  final asOf = ref.watch(clockProvider).now();
  return CnsBreakdownEngine.compute(snapshot: snapshot, asOf: asOf);
});
