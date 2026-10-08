import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/components/hx_pill.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/check_in_policy.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/sheets/check_in_history_sheet.dart';
import 'package:herculex/features/physique/presentation/sheets/check_in_sheet.dart';
import 'package:herculex/features/physique/presentation/widgets/load_state_views.dart';
import 'package:herculex/features/physique/presentation/widgets/photo_thumbnail.dart';
import 'package:herculex/features/physique/presentation/widgets/verdict_block.dart';
import 'package:intl/intl.dart';

const _aiUnavailableReason =
    "Herculex AI couldn't review this photo, so this check-in is inconclusive.";

/// Latest verdict, the cap-aware check-in button and the thumbnail strip
/// (PHYS-06, PHYS-07). The cap shown here is cosmetic: the repository
/// re-checks it inside a transaction (D-13).
class CheckInCard extends ConsumerWidget {
  const CheckInCard({
    super.key,
    required this.goalId,
    required this.advancePromptVisible,
  });

  final int goalId;
  final bool advancePromptVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final goalAsync = ref.watch(physiqueGoalProvider(goalId));
    final checkInsAsync = ref.watch(physiqueCheckInsProvider(goalId));
    final photosAsync = ref.watch(physiquePhotosProvider(goalId));
    final goal = goalAsync.asData?.value;
    final checkIns = checkInsAsync.asData?.value;
    final photos = photosAsync.asData?.value;

    Widget body;
    if (goal == null || checkIns == null || photos == null) {
      final failed =
          goalAsync.hasError || checkInsAsync.hasError || photosAsync.hasError;
      body = failed
          ? PhysiqueLoadError(
              onRetry: () {
                ref.invalidate(physiqueGoalProvider(goalId));
                ref.invalidate(physiqueCheckInsProvider(goalId));
                ref.invalidate(physiquePhotosProvider(goalId));
              },
            )
          : const PhysiqueLoading();
    } else {
      body = _Content(
        goal: goal,
        checkIns: checkIns,
        photos: photos,
        advancePromptVisible: advancePromptVisible,
      );
    }

    return SizedBox(
      width: double.infinity,
      child: HxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: HxSpace.x2,
              runSpacing: HxSpace.x1,
              children: [
                Text(
                  'Check-in',
                  style: PhysiqueText.heading(context, color: hx.onSurface),
                ),
                const HxTextPill(label: 'Herculex AI'),
              ],
            ),
            const SizedBox(height: HxSpace.x4),
            body,
          ],
        ),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.goal,
    required this.checkIns,
    required this.photos,
    required this.advancePromptVisible,
  });

  final PhysiqueGoalData goal;
  final List<PhysiqueAssessmentData> checkIns;
  final List<PhysiquePhotoData> photos;
  final bool advancePromptVisible;

  VerdictBlock _verdict(
    BuildContext context,
    WidgetRef ref,
    PhysiqueAssessmentData a,
    bool active,
  ) {
    final verdict = CheckInVerdict.fromWire(a.verdict);
    CheckInBand? band;
    final lo = a.directionBandLow;
    final hi = a.directionBandHigh;
    if (lo != null && hi != null && lo.isFinite && hi.isFinite) {
      band = CheckInBand.clamped(lo, hi);
    }
    final reason = (a.reason ?? '').trim();
    final status = ref.read(physiquePhaseStatusProvider(goal.id));
    final phase = DietPhase.values.firstWhere(
      (p) => p.name == status?.current?.phaseType,
      orElse: () => DietPhase.maintain,
    );
    return VerdictBlock(
      verdict: verdict,
      band: band,
      confidence: AssessmentConfidence.fromWire(a.confidence),
      reason: reason.isEmpty && verdict == CheckInVerdict.inconclusive
          ? _aiUnavailableReason
          : reason,
      onReviewTargets: active
          ? () => context.push(
              AppRoutes.nutritionTargets,
              extra: ref
                  .read(physiqueRoadmapEligibilityProvider(goal.id))
                  .coerce(phase),
            )
          : null,
      onLogMeasurements: active
          ? () => context.push(AppRoutes.measurements)
          : null,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final active = goal.status == 'active';
    final hasBaseline = photos.any((p) => p.role == 'baseline');
    final latest = checkIns.isEmpty ? null : checkIns.first;

    final strip = <Widget>[];
    for (final a in checkIns.take(3)) {
      final photo = photos
          .where((p) => p.assessmentId == a.id && p.role == 'checkin')
          .firstOrNull;
      strip.add(PhotoThumbnail(relativePath: photo?.relativePath ?? ''));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (latest != null)
          _verdict(context, ref, latest, active)
        else ...[
          Text(
            'No check-ins yet',
            style: PhysiqueText.bodyStrong(context, color: hx.onSurface),
          ),
          const SizedBox(height: HxSpace.x1),
          Text(
            'Take your first photo to set a baseline. You can check in once a '
            'week.',
            style: PhysiqueText.body(context, color: hx.onSurfaceVariant),
          ),
        ],
        if (!hasBaseline) ...[
          const SizedBox(height: HxSpace.x3),
          Text(
            'Add a baseline photo so Herculex AI has something to compare '
            'with.',
            style: PhysiqueText.body(context, color: hx.onSurfaceVariant),
          ),
        ],
        if (active) ...[
          const SizedBox(height: HxSpace.x4),
          _ActionButton(
            goal: goal,
            hasBaseline: hasBaseline,
            advancePromptVisible: advancePromptVisible,
          ),
          if (goal.roadmapAcceptedAt != null) ...[
            const SizedBox(height: HxSpace.x2),
            _UpdateRoadmapButton(goal: goal),
          ],
        ],
        if (strip.isNotEmpty) ...[
          const SizedBox(height: HxSpace.x4),
          Wrap(spacing: HxSpace.x2, runSpacing: HxSpace.x2, children: strip),
        ],
        if (checkIns.isNotEmpty)
          TextButton(
            onPressed: () => CheckInHistorySheet.show(context, goalId: goal.id),
            child: const Text('See all check-ins'),
          ),
      ],
    );
  }
}

/// New photo, new analysis, new roadmap. Waits one check-in window after the
/// last analysis, like the check-in itself; the repository-side flow checks
/// again, this only decides what the button says.
class _UpdateRoadmapButton extends ConsumerWidget {
  const _UpdateRoadmapButton({required this.goal});

  final PhysiqueGoalData goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref
        .watch(physiqueLatestAnalysisProvider(goal.id))
        .asData
        ?.value
        ?.assessedAt;
    final now = ref.watch(clockProvider).now();
    final eligible = CheckInCapPolicy.isEligible(now: now, lastCheckInAt: last);
    if (!eligible) {
      final next = CheckInCapPolicy.nextEligibleDate(last)!;
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('update-roadmap-locked'),
          onPressed: null,
          icon: const Icon(Icons.schedule_rounded, size: 20),
          label: Text(
            'Next roadmap update ${DateFormat('EEE, MMM d').format(next)}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('update-roadmap'),
        onPressed: () =>
            CheckInSheet.show(context, goal: goal, updateRoadmap: true),
        icon: const Icon(Icons.update_rounded, size: 20),
        label: const Text('Update roadmap'),
      ),
    );
  }
}

class _ActionButton extends ConsumerWidget {
  const _ActionButton({
    required this.goal,
    required this.hasBaseline,
    required this.advancePromptVisible,
  });

  final PhysiqueGoalData goal;
  final bool hasBaseline;
  final bool advancePromptVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final last = ref
        .watch(physiqueLastCheckInAtProvider(goal.id))
        .asData
        ?.value;
    final now = ref.watch(clockProvider).now();
    final eligible =
        !hasBaseline ||
        CheckInCapPolicy.isEligible(now: now, lastCheckInAt: last);
    final label = hasBaseline ? 'Add check-in' : 'Add baseline photo';
    void open() => CheckInSheet.show(context, goal: goal);

    if (!eligible) {
      final next = CheckInCapPolicy.nextEligibleDate(last)!;
      return Semantics(
        container: true,
        button: true,
        enabled: false,
        label:
            'Check-in locked until ${DateFormat('EEEE, MMMM d').format(next)}',
        excludeSemantics: true,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: null,
            style: FilledButton.styleFrom(
              disabledForegroundColor: hx.onSurfaceVariant,
              disabledBackgroundColor: hx.surfaceVariant,
            ),
            icon: const Icon(Icons.schedule_rounded, size: 20),
            label: Text(
              'Next check-in available ${DateFormat('EEE, MMM d').format(next)}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: advancePromptVisible
          ? OutlinedButton(onPressed: open, child: Text(label))
          : FilledButton(onPressed: open, child: Text(label)),
    );
  }
}
