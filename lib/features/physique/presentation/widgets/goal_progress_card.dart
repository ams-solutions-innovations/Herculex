import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/goal_progress.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:image_picker/image_picker.dart';

/// The saved dream physique photo and a bar showing how much of the body-fat
/// distance to the target is already covered.
class GoalProgressCard extends ConsumerWidget {
  const GoalProgressCard({super.key, required this.goalId});

  final int goalId;

  static const double _photoHeight = 220;

  Future<void> _pick(BuildContext context, WidgetRef ref, String uuid) async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not save the photo')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
    if (goal == null) return const SizedBox.shrink();
    final hx = context.hx;
    final uuid = goal.syncUuid;
    final archived = goal.status == 'archived';
    final photo = uuid == null
        ? null
        : ref.watch(physiqueDreamPhotoProvider(uuid)).asData?.value;
    final current = ref.watch(physiqueBodyFatReadingProvider(goalId)).percent;
    final fraction = GoalProgress.fraction(
      startBfPercent: goal.startBfPercent,
      currentBfPercent: current,
      targetBfPercent: goal.targetBfPercent,
    );
    if (photo == null && fraction == null && (archived || uuid == null)) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: HxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(HxRadius.md),
                child: Image.file(
                  photo,
                  key: ValueKey(photo.lastModifiedSync()),
                  height: _photoHeight,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            if (photo == null && !archived && uuid != null)
              TextButton.icon(
                onPressed: () => _pick(context, ref, uuid),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add your dream physique photo'),
              ),
            if (photo != null && !archived && uuid != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _pick(context, ref, uuid),
                  child: const Text('Change photo'),
                ),
              ),
            if (fraction != null) ...[
              const SizedBox(height: HxSpace.x2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Progress to goal',
                      style: PhysiqueText.heading(context, color: hx.onSurface),
                    ),
                  ),
                  Text(
                    '${(fraction * 100).round()}%',
                    style: PhysiqueText.heading(context, color: hx.primary),
                  ),
                ],
              ),
              const SizedBox(height: HxSpace.x2),
              ClipRRect(
                borderRadius: HxRadius.pillAll,
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 12,
                  color: hx.primary,
                  backgroundColor: hx.surfaceVariant,
                ),
              ),
              const SizedBox(height: HxSpace.x1),
              Text(
                '${((1 - fraction) * 100).round()}% to go · '
                '${current!.toStringAsFixed(1)}% → '
                '${goal.targetBfPercent!.toStringAsFixed(1)}% body fat',
                style: PhysiqueText.label(context, color: hx.secondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
