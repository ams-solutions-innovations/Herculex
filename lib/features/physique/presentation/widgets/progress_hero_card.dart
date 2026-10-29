import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_pill.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/goal_display_copy.dart';
import 'package:herculex/features/physique/domain/goal_progress.dart';
import 'package:herculex/features/physique/presentation/widgets/load_state_views.dart';
import 'package:herculex/features/physique/presentation/widgets/photo_thumbnail.dart';
import 'package:herculex/features/physique/presentation/widgets/physique_design_kit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/// The lead card of the progress screen: how much of the body-fat distance is
/// covered, how long the goal has run, and start, latest and goal photos side
/// by side.
class ProgressHeroCard extends ConsumerWidget {
  const ProgressHeroCard({super.key, required this.goalId});

  final int goalId;

  Future<void> _pickDream(
    BuildContext context,
    WidgetRef ref,
    String uuid,
  ) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (picked == null) return;
    final ok = await ref
        .read(physiqueDreamPhotoRepositoryProvider)
        .save(File(picked.path), goalUuid: uuid);
    ref.invalidate(physiqueDreamPhotoProvider(uuid));
    if (!ok && context.mounted) {
      AppNotice.show(
        context,
        'Could not save the photo',
        kind: AppNoticeKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final async = ref.watch(physiqueGoalProvider(goalId));
    final goal = async.asData?.value;
    if (goal == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: physiqueCard(context, radius: 28),
        child: async.hasError
            ? PhysiqueLoadError(
                onRetry: () => ref.invalidate(physiqueGoalProvider(goalId)),
              )
            : const PhysiqueLoading(),
      );
    }

    final now = ref.watch(clockProvider).now();
    final archived = goal.status == 'archived';
    final bf = ref.watch(physiqueBodyFatReadingProvider(goalId)).percent;
    final fraction = GoalProgress.fraction(
      startBfPercent: goal.startBfPercent,
      currentBfPercent: bf,
      targetBfPercent: goal.targetBfPercent,
    );
    final checkIns =
        ref.watch(physiqueCheckInsProvider(goalId)).asData?.value ?? const [];
    final photos =
        ref.watch(physiquePhotosProvider(goalId)).asData?.value ?? const [];
    final uuid = goal.syncUuid;
    final dream = uuid == null
        ? null
        : ref.watch(physiqueDreamPhotoProvider(uuid)).asData?.value;
    final canPick =
        ref.watch(platformCapabilitiesProvider).hasFileSystem &&
        !archived &&
        uuid != null;

    final end = archived ? (goal.archivedAt ?? now) : now;
    final weeks = end.difference(goal.startedAt).inDays ~/ 7;
    final headline = weeks < 1
        ? 'Just getting started'
        : '$weeks ${weeks == 1 ? 'week' : 'weeks'} in';
    final months = goal.estimatedMonths;
    final eta = months == null
        ? null
        : DateTime(
            goal.startedAt.year,
            goal.startedAt.month + months,
            goal.startedAt.day,
          );
    final verdict = checkIns.isEmpty
        ? null
        : CheckInVerdict.fromWire(checkIns.first.verdict);

    PhysiquePhotoData? photoFor(String role, {int? assessmentId}) {
      PhysiquePhotoData? best;
      for (final p in photos) {
        if (p.role != role) continue;
        if (assessmentId != null && p.assessmentId != assessmentId) continue;
        if (p.pose == 'front') return p;
        best ??= p;
      }
      return best;
    }

    final baseline = photoFor('baseline');
    final latest = checkIns.isEmpty
        ? null
        : photoFor('checkin', assessmentId: checkIns.first.id);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: hx.primary.withValues(alpha: 0.35)),
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.3,
          stops: const [0, 0.65],
          colors: [
            hx.primary.withValues(alpha: 0.32),
            hx.surfaceContainerLowest,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhysiqueRing(
                value: fraction,
                size: 104,
                stroke: 10,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FittedBox(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fraction == null
                              ? '—'
                              : '${(fraction * 100).round()}%',
                          style: physiqueDisplay(
                            30,
                            letterSpacing: -1,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'TO GOAL',
                          style: TextStyle(
                            color: hx.secondary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PhysiqueEyebrow(
                      GoalDisplayCopy.title(
                        goal.targetAestheticStyle,
                      ).toUpperCase(),
                      color: hx.primaryText,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      headline,
                      style: physiqueDisplay(
                        22,
                        letterSpacing: -0.4,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (archived) const HxTextPill(label: 'Archived'),
                        if (verdict == CheckInVerdict.onTrack)
                          PhysiqueTintPill(
                            'On track',
                            color: hx.success,
                            icon: Icons.trending_up_rounded,
                          ),
                        if (verdict == CheckInVerdict.offTrack)
                          PhysiqueTintPill(
                            'Needs attention',
                            color: hx.warning,
                            icon: Icons.trending_flat_rounded,
                          ),
                        if (eta != null)
                          Text(
                            'ETA ${DateFormat('MMM y').format(eta)}',
                            style: TextStyle(
                              color: hx.secondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Frame(
                  label:
                      'START · ${DateFormat('d MMM').format(goal.startedAt).toUpperCase()}',
                  border: hx.outlineVariant,
                  child: baseline == null
                      ? _Empty(icon: Icons.person_outline_rounded)
                      : _Thumb(path: baseline.relativePath),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Frame(
                  label: latest == null
                      ? 'LATEST'
                      : 'WEEK ${checkIns.first.assessedAt.difference(goal.startedAt).inDays ~/ 7}',
                  labelColor: hx.onSurface,
                  border: hx.onSurface,
                  child: latest == null
                      ? _Empty(icon: Icons.photo_camera_outlined)
                      : _Thumb(path: latest.relativePath),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Frame(
                  label: 'GOAL',
                  labelColor: hx.primaryText,
                  border: hx.primary.withValues(alpha: 0.6),
                  onTap: canPick ? () => _pickDream(context, ref, uuid) : null,
                  child: dream == null
                      ? _Empty(
                          icon: Icons.add_photo_alternate_outlined,
                          label: canPick ? 'Add goal photo' : null,
                        )
                      : Image.file(
                          dream,
                          key: ValueKey(dream.lastModifiedSync()),
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.label,
    required this.border,
    required this.child,
    this.labelColor,
    this.onTap,
  });

  final String label;
  final Color border;
  final Color? labelColor;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 118,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: hx.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1.5),
            ),
            child: child,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: labelColor ?? hx.secondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => PhotoThumbnail(
      relativePath: path,
      width: box.maxWidth,
      height: box.maxHeight,
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, this.label});

  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: hx.tertiary),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: hx.secondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
