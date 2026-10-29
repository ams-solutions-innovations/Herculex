import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_capture_providers.dart';
import 'package:herculex/features/physique/application/physique_check_in_flow.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_checkin_service.dart';
import 'package:herculex/features/physique/domain/check_in_policy.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/sheets/check_in_history_sheet.dart';
import 'package:herculex/features/physique/presentation/sheets/check_in_sheet.dart';
import 'package:herculex/features/physique/presentation/widgets/load_state_views.dart';
import 'package:herculex/features/physique/presentation/widgets/photo_thumbnail.dart';
import 'package:herculex/features/physique/presentation/widgets/physique_design_kit.dart';
import 'package:herculex/features/physique/presentation/widgets/verdict_block.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';
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

    if (goal == null || checkIns == null || photos == null) {
      final failed =
          goalAsync.hasError || checkInsAsync.hasError || photosAsync.hasError;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: physiqueCard(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Check-in',
              style: PhysiqueText.heading(context, color: hx.onSurface),
            ),
            const SizedBox(height: HxSpace.x4),
            if (failed)
              PhysiqueLoadError(
                onRetry: () {
                  ref.invalidate(physiqueGoalProvider(goalId));
                  ref.invalidate(physiqueCheckInsProvider(goalId));
                  ref.invalidate(physiquePhotosProvider(goalId));
                },
              )
            else
              const PhysiqueLoading(),
          ],
        ),
      );
    }

    final active = goal.status == 'active';
    final hasBaseline = photos.any((p) => p.role == 'baseline');
    final last = ref
        .watch(physiqueLastCheckInAtProvider(goal.id))
        .asData
        ?.value;
    final now = ref.watch(clockProvider).now();
    final eligible =
        !hasBaseline ||
        CheckInCapPolicy.isEligible(now: now, lastCheckInAt: last);
    final latest = checkIns.firstOrNull;
    final onTrack =
        latest != null &&
        CheckInVerdict.fromWire(latest.verdict) == CheckInVerdict.onTrack;
    final next = eligible ? null : CheckInCapPolicy.nextEligibleDate(last);

    final (IconData icon, Color tint, String title, String sub) = !active
        ? (
            Icons.photo_library_outlined,
            hx.secondary,
            'Check-ins',
            '${checkIns.length} ${checkIns.length == 1 ? 'check-in' : 'check-ins'} · Herculex AI',
          )
        : !hasBaseline
        ? (
            Icons.add_a_photo_outlined,
            hx.primaryText,
            'Set your baseline',
            'One photo so Herculex AI has something to compare with',
          )
        : eligible
        ? (
            Icons.photo_camera_outlined,
            hx.primaryText,
            'Check-in ready',
            'Front, side and back photo + weigh-in',
          )
        : (
            onTrack ? Icons.check_circle_rounded : Icons.schedule_rounded,
            onTrack ? hx.success : hx.secondary,
            'Checked in',
            'Next check-in ${DateFormat('EEE d MMM').format(next!)}',
          );
    final border = active && eligible
        ? hx.primary.withValues(alpha: 0.45)
        : onTrack
        ? hx.success.withValues(alpha: 0.35)
        : hx.outlineVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: physiqueCard(context, border: border),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 22, color: tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      sub,
                      style: TextStyle(
                        color: hx.secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Content(
            goal: goal,
            checkIns: checkIns,
            photos: photos,
            advancePromptVisible: advancePromptVisible,
          ),
        ],
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

  Widget _verdict(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VerdictBlock(
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
        ),
        if (active &&
            a.source == 'no_analysis' &&
            verdict == CheckInVerdict.inconclusive)
          _RetrySavedAnalysisButton(goal: goal, assessment: a),
      ],
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

class _RetrySavedAnalysisButton extends ConsumerStatefulWidget {
  const _RetrySavedAnalysisButton({
    required this.goal,
    required this.assessment,
  });

  final PhysiqueGoalData goal;
  final PhysiqueAssessmentData assessment;

  @override
  ConsumerState<_RetrySavedAnalysisButton> createState() =>
      _RetrySavedAnalysisButtonState();
}

class _RetrySavedAnalysisButtonState
    extends ConsumerState<_RetrySavedAnalysisButton> {
  bool _busy = false;
  String? _error;

  Future<void> _retry() async {
    final notices = AppNotice.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retry photo analysis?'),
        content: const Text(
          'This sends your saved photos to Herculex AI for one new review. '
          'It updates this check-in only and does not change your next '
          'check-in date.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send and retry'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(physiquePrivacyPreferencesProvider)
          .acceptConsent(dreamPhysiqueImageConsentVersion);
      final flowContext = ref.read(
        physiqueCheckInContextProvider(widget.goal.id),
      );
      await ref
          .read(physiqueCheckInFlowProvider)
          .retrySavedCheckInAnalysis(
            goal: widget.goal,
            assessmentId: widget.assessment.id,
            phase: flowContext.phase,
            weeksInPhase: flowContext.weeksInPhase,
            weeklyTrendKg: flowContext.weeklyTrendKg,
            consentGranted: true,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      notices.show(
        'AI analysis updated. Your next check-in date is unchanged.',
      );
    } on PhysiqueCheckInException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.kind) {
          PhysiqueCheckInFailure.quotaExhausted => e.message,
          PhysiqueCheckInFailure.invalidInput => e.message,
          _ =>
            "Herculex AI couldn't review the saved photos. Your check-in "
                'is unchanged; you can try again later.',
        };
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "We couldn't retry the analysis. Your check-in is unchanged.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _busy ? null : _retry,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          label: Text(_busy ? 'Retrying analysis...' : 'Retry AI analysis'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: HxSpace.x2),
            child: Text(
              _error!,
              style: PhysiqueText.label(context, color: hx.danger),
            ),
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
    final label = hasBaseline ? 'Weekly check-in' : 'Add baseline photo';
    void open() => CheckInSheet.show(context, goal: goal);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    const text = TextStyle(fontSize: 15, fontWeight: FontWeight.w800);

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
          height: 50,
          child: FilledButton.icon(
            onPressed: null,
            style: FilledButton.styleFrom(
              disabledForegroundColor: hx.onSurfaceVariant,
              disabledBackgroundColor: hx.surfaceVariant,
              shape: shape,
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
    const icon = Icon(Icons.photo_camera_outlined, size: 20);
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: advancePromptVisible
          ? OutlinedButton.icon(
              style: OutlinedButton.styleFrom(shape: shape, textStyle: text),
              onPressed: open,
              icon: icon,
              label: Text(label),
            )
          : FilledButton.icon(
              style: FilledButton.styleFrom(shape: shape, textStyle: text),
              onPressed: open,
              icon: icon,
              label: Text(label),
            ),
    );
  }
}
