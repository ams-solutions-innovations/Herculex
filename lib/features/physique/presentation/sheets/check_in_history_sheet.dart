import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_sheet.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/presentation/dialogs/delete_check_in_dialog.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/widgets/photo_thumbnail.dart';
import 'package:herculex/features/physique/presentation/widgets/sheet_snackbar_scope.dart';
import 'package:herculex/features/physique/presentation/widgets/verdict_block.dart';
import 'package:herculex/features/physique/presentation/widgets/verdict_chip.dart';
import 'package:intl/intl.dart';

/// Check-ins newest first, with a detail view and (for the active goal) a
/// confirmed delete. Deleting removes the photo file but never reopens the
/// weekly slot (PHYS-06).
class CheckInHistorySheet extends ConsumerStatefulWidget {
  const CheckInHistorySheet({super.key, required this.goalId});

  final int goalId;

  static Future<void> show(BuildContext context, {required int goalId}) {
    return HxSheet.show<void>(
      context,
      builder: (_) =>
          SheetSnackBarScope(child: CheckInHistorySheet(goalId: goalId)),
    );
  }

  @override
  ConsumerState<CheckInHistorySheet> createState() =>
      _CheckInHistorySheetState();
}

class _CheckInHistorySheetState extends ConsumerState<CheckInHistorySheet> {
  int? _selectedId;

  static String _pathFor(
    PhysiqueAssessmentData a,
    List<PhysiquePhotoData> photos,
  ) {
    for (final p in photos) {
      if (p.assessmentId == a.id && p.role == 'checkin') return p.relativePath;
    }
    return '';
  }

  Future<void> _delete(PhysiqueAssessmentData a) async {
    final ok = await DeleteCheckInDialog.show(context);
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final store = ref.read(physiquePhotoStoreProvider);
    try {
      final paths = await ref
          .read(physiqueAssessmentRepositoryProvider)
          .deleteCheckIn(a.id);
      for (final path in paths) {
        await store.delete(path);
      }
    } on Object {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "We couldn't save your photo. Check your free storage and try "
            'again.',
          ),
        ),
      );
      return;
    }
    if (mounted) setState(() => _selectedId = null);
  }

  @override
  Widget build(BuildContext context) {
    final goalId = widget.goalId;
    final checkIns =
        ref.watch(physiqueCheckInsProvider(goalId)).asData?.value ??
        const <PhysiqueAssessmentData>[];
    final photos =
        ref.watch(physiquePhotosProvider(goalId)).asData?.value ??
        const <PhysiquePhotoData>[];
    final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
    final active = goal?.status == 'active';
    PhysiqueAssessmentData? selected;
    for (final a in checkIns) {
      if (a.id == _selectedId) selected = a;
    }

    final Widget body;
    if (selected != null) {
      final current = selected;
      body = _Detail(
        assessment: current,
        path: _pathFor(current, photos),
        canDelete: active,
        onBack: () => setState(() => _selectedId = null),
        onDelete: () => _delete(current),
        onReview: () => context.push(AppRoutes.nutritionTargets),
        onLog: () => context.push(AppRoutes.measurements),
      );
    } else if (checkIns.isEmpty) {
      body = const _Empty();
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in checkIns)
            _Row(
              assessment: a,
              path: _pathFor(a, photos),
              onTap: () => setState(() => _selectedId = a.id),
            ),
        ],
      );
    }

    return HxSheet(
      title: selected == null ? 'Check-ins' : 'Check-in',
      child: body,
    );
  }
}

final _dateFormat = DateFormat('EEE, MMM d');

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HxSpace.x8),
      child: Column(
        children: [
          Icon(Icons.photo_camera_outlined, size: 32, color: hx.tertiary),
          const SizedBox(height: HxSpace.x3),
          Text(
            'No check-ins yet',
            style: PhysiqueText.heading(context, color: hx.onSurface),
          ),
          const SizedBox(height: HxSpace.x1),
          Text(
            'Take your first photo to set a baseline. You can check in once a '
            'week.',
            textAlign: TextAlign.center,
            style: PhysiqueText.body(context, color: hx.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.assessment,
    required this.path,
    required this.onTap,
  });

  final PhysiqueAssessmentData assessment;
  final String path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final reason = (assessment.reason ?? '').trim();
    return InkWell(
      onTap: onTap,
      borderRadius: HxRadius.mdAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HxSpace.x2),
        child: Row(
          children: [
            PhotoThumbnail(relativePath: path),
            const SizedBox(width: HxSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _dateFormat.format(assessment.assessedAt),
                    style: PhysiqueText.bodyStrong(
                      context,
                      color: hx.onSurface,
                    ),
                  ),
                  const SizedBox(height: HxSpace.x1),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: VerdictChip(
                      verdict: CheckInVerdict.fromWire(assessment.verdict),
                    ),
                  ),
                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: HxSpace.x1),
                    Text(
                      reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhysiqueText.label(
                        context,
                        color: hx.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.assessment,
    required this.path,
    required this.canDelete,
    required this.onBack,
    required this.onDelete,
    required this.onReview,
    required this.onLog,
  });

  final PhysiqueAssessmentData assessment;
  final String path;
  final bool canDelete;
  final VoidCallback onBack;
  final VoidCallback onDelete;
  final VoidCallback onReview;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final low = assessment.directionBandLow;
    final high = assessment.directionBandHigh;
    final band = (low != null && high != null)
        ? CheckInBand.clamped(low, high)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('All check-ins'),
        ),
        Text(
          _dateFormat.format(assessment.assessedAt),
          style: PhysiqueText.heading(context, color: hx.onSurface),
        ),
        const SizedBox(height: HxSpace.x3),
        PhotoThumbnail(relativePath: path, width: 180, height: 240),
        const SizedBox(height: HxSpace.x4),
        VerdictBlock(
          verdict: CheckInVerdict.fromWire(assessment.verdict),
          band: band,
          confidence: AssessmentConfidence.fromWire(assessment.confidence),
          reason: assessment.reason ?? '',
          onReviewTargets: onReview,
          onLogMeasurements: onLog,
        ),
        if (canDelete) ...[
          const SizedBox(height: HxSpace.x4),
          OutlinedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete check-in'),
          ),
        ],
      ],
    );
  }
}
