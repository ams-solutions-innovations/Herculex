import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/health/application/health_providers.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/presentation/sheets/weekly_adaptation_sheet.dart';

/// Offers a recovery adaptation exactly when a scheduled workout is started.
/// It intentionally never renders inside the live workout, where the planned
/// sets are already immutable and a warning would be too late to be useful.
Future<void> offerStartWorkoutAdaptation(
  BuildContext context,
  WidgetRef ref, {
  required int scheduleId,
}) async {
  final activity = await ref.read(activityBasedAdjustmentProvider.future);
  final cns = await ref.read(cnsTrendsProvider.future);
  final cnsFactor = cns.deloadSuggested
      ? 0.5
      : (cns.currentLoad >= 0.7 ? 0.8 : 1.0);
  final factor = math.min(activity.volumeFactor, cnsFactor);
  if (factor >= 1) return;

  final reason = cns.deloadSuggested
      ? 'CNS load is well above your established capacity. Today uses a deload-level reduction.'
      : cns.currentLoad >= 0.7
      ? 'CNS fatigue is elevated. Compound work is kept concise and accessory/isolation volume is reduced.'
      : activity.message;
  final proposal = await ref
      .read(weeklyAdaptationRepositoryProvider)
      .proposeForLowRecovery(scheduleId, volumeFactor: factor, reason: reason);
  if (proposal != null && context.mounted) {
    await showWeeklyAdaptationSheet(
      context,
      repository: ref.read(weeklyAdaptationRepositoryProvider),
      proposal: proposal,
      skipOnDecline: false,
    );
  }
}
