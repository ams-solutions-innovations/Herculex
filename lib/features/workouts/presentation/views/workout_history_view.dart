import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/health/application/health_providers.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/set_metric_format.dart';
import 'package:herculex/features/workouts/presentation/dialogs/duration_picker_dialog.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class WorkoutHistoryView extends ConsumerWidget {
  final int sessionId;
  const WorkoutHistoryView({super.key, required this.sessionId});

  Future<void> _pickPhoto(
    BuildContext context,
    WidgetRef ref,
    int sessionId,
    ImageSource source,
  ) async {
    await ref
        .read(pendingAiScanServiceProvider)
        .setPendingContext(
          PendingAiScanContext(
            type: AiScanContextType.workoutPhoto,
            extra: {'sessionId': sessionId},
          ),
        );
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    await ref.read(pendingAiScanServiceProvider).clearPendingContext();
    if (image == null) return;
    await ref
        .read(workoutsRepositoryProvider)
        .updateSessionPhoto(sessionId, image.path);
    ref.invalidate(workoutSessionProvider(sessionId));
    ref.invalidate(sessionSummaryProvider(sessionId));
  }

  Future<void> _syncToHealth(
    BuildContext context,
    WidgetRef ref,
    WorkoutSessionData session,
  ) async {
    final end = session.endedAt ?? DateTime.now();
    final dur = end.difference(session.startedAt);
    final profile = ref.read(profileProvider).valueOrNull;
    final weight = (profile?.weightKg != null && profile!.weightKg! > 20)
        ? profile.weightKg!
        : 75.0;
    final minutes = dur.inMinutes > 0 ? dur.inMinutes : 1;
    final kcal =
        session.caloriesBurned ??
        (5.0 * weight * (minutes / 60.0)).round().clamp(10, 3000);

    final success = await ref
        .read(healthServiceProvider)
        .writeWorkoutToHealth(
          activityName: _titleFor(session),
          startTime: session.startedAt,
          endTime: end,
          totalCaloriesBurned: kcal,
        );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Workout "${_titleFor(session)}" ($kcal kcal) sent to Health Connect / Samsung Health!'
                : 'Sync failed. Please check Health Connect permissions in settings.',
          ),
          backgroundColor: success ? const Color(0xFF30D158) : Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final exercises = ref.watch(sessionExercisesProvider(sessionId));
    final catalog = ref.watch(
      exerciseCatalogProvider(const ExerciseCatalogFilter()),
    );
    final sessionAsync = ref.watch(workoutSessionProvider(sessionId));

    return HxScreenShell(
      title: _titleFor(sessionAsync.asData?.value),
      actions: [
        IconButton(
          icon: const Icon(Icons.sync_rounded),
          tooltip: 'Sync with Health Connect',
          onPressed: () {
            final session = sessionAsync.asData?.value;
            if (session != null) _syncToHealth(context, ref, session);
          },
        ),
        IconButton(
          icon: const Icon(Icons.edit),
          tooltip: 'Edit Workout',
          onPressed: () async {
            final session = sessionAsync.asData?.value;
            final originalEndedAt = session?.endedAt;
            if (originalEndedAt != null) {
              ref
                  .read(editingSessionOriginalEndedAtProvider.notifier)
                  .update((state) => {...state, sessionId: originalEndedAt});
            }
            // Resume workout by clearing endedAt
            final stmt =
                ref
                    .read(appDatabaseProvider)
                    .update(ref.read(appDatabaseProvider).workoutSessions)
                  ..where((t) => t.id.equals(sessionId));
            await stmt.write(
              const WorkoutSessionsCompanion(endedAt: drift.Value(null)),
            );
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          tooltip: 'Delete Workout',
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete workout?'),
                content: const Text(
                  'This permanently deletes this workout and all logged sets.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'Delete',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            );
            if (confirmed == true && context.mounted) {
              await ref
                  .read(workoutsRepositoryProvider)
                  .deleteSession(sessionId);
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            }
          },
        ),
      ],
      children: [
        exercises.when(
          data: (rows) {
            if (rows.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No exercises recorded for this session.'),
                ),
              );
            }
            final session = sessionAsync.asData?.value;
            final duration = session?.endedAt != null
                ? session!.endedAt!.difference(session.startedAt)
                : null;
            final durationStr = duration == null
                ? ''
                : duration.inHours > 0
                ? '${duration.inHours}h ${duration.inMinutes.remainder(60)}m'
                : '${duration.inMinutes}m';

            final profile = ref.watch(profileProvider).valueOrNull;
            final weight =
                (profile?.weightKg != null && profile!.weightKg! > 20)
                ? profile.weightKg!
                : 75.0;
            final minutes = duration?.inMinutes ?? 45;
            final calories =
                session?.caloriesBurned ??
                (5.0 * weight * (minutes / 60.0)).round().clamp(10, 3000);

            final photo = session?.photoPath;
            final hasPhoto = photo != null && File(photo).existsSync();

            return Column(
              children: [
                if (session != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat(
                                'EEEE, MMM d, yyyy · HH:mm',
                              ).format(session.startedAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.secondary,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$calories kcal',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () async {
                                    final currentDur =
                                        session.endedAt?.difference(
                                          session.startedAt,
                                        ) ??
                                        const Duration(minutes: 45);
                                    final newMins =
                                        await DurationPickerDialog.show(
                                          context,
                                          initialMinutes:
                                              currentDur.inMinutes > 0
                                              ? currentDur.inMinutes
                                              : 45,
                                        );
                                    if (newMins != null && newMins > 0) {
                                      final newEndedAt = session.startedAt.add(
                                        Duration(minutes: newMins),
                                      );
                                      await ref
                                          .read(workoutsRepositoryProvider)
                                          .endSession(
                                            session.id,
                                            endedAt: newEndedAt,
                                          );
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          durationStr.isNotEmpty
                                              ? durationStr
                                              : 'Set duration',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 12,
                                          color: AppColors.primary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (hasPhoto) ...[
                          const SizedBox(height: 10),
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(photo),
                                  height: 130,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: Colors.black54,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(
                                          Icons.camera_alt_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                        onPressed: () => _pickPhoto(
                                          context,
                                          ref,
                                          session.id,
                                          ImageSource.camera,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: Colors.black54,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 14,
                                          color: Colors.redAccent,
                                        ),
                                        onPressed: () async {
                                          await ref
                                              .read(workoutsRepositoryProvider)
                                              .updateSessionPhoto(
                                                session.id,
                                                null,
                                              );
                                          ref.invalidate(
                                            workoutSessionProvider(session.id),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              InkWell(
                                onTap: () => _pickPhoto(
                                  context,
                                  ref,
                                  session.id,
                                  ImageSource.gallery,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.add_a_photo_outlined,
                                        size: 13,
                                        color: AppColors.secondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Add photo',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: AppColors.secondary,
                                              fontSize: 11,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final we = rows[i];
                      final exercise = catalog.asData?.value.firstWhere(
                        (e) => e.id == we.exerciseId,
                        orElse: () => _placeholder(we.exerciseId),
                      );
                      final isWeightedBw =
                          (we.equipmentVariant ?? exercise?.modality) ==
                          'weighted';
                      return _ExerciseBlock(
                        workoutExercise: we,
                        exerciseName: exercise?.name ?? '',
                        metric: exercise != null
                            ? effectiveLoggingMetric(
                                exercise: exercise,
                                equipmentVariant: we.equipmentVariant,
                              )
                            : LoggingMetric.weightReps,
                        isWeightedBodyweight: isWeightedBw,
                      );
                    },
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }

  /// The session's own name, falling back to its date when unnamed.
  String _titleFor(WorkoutSessionData? session) {
    if (session == null) return 'Workout';
    final name = session.name?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return DateFormat('EEE, MMM d').format(session.startedAt);
  }

  ExerciseCatalogData _placeholder(int id) => ExerciseCatalogData(
    id: id,
    name: 'Unknown',
    primaryMuscle: '',
    equipment: '',
    mechanics: '',
    force: '',
    plane: '',
    defaultRestSeconds: 120,
    isCustom: false,
    category: 'strength',
    modality: 'barbell',
    cnsScore: 3,
    recoveryImpact: 3,
    loggingMetric: 'weight_reps',
    supportsWeightedBodyweight: false,
    isReviewed: false,
  );
}

class _ExerciseBlock extends ConsumerWidget {
  final WorkoutExerciseData workoutExercise;
  final String exerciseName;

  /// What this exercise is measured in — a logged plank reads as `2:00` here,
  /// not as `0 kg × 0` (EXR-05).
  final LoggingMetric metric;
  final bool isWeightedBodyweight;

  const _ExerciseBlock({
    required this.workoutExercise,
    required this.exerciseName,
    required this.metric,
    this.isWeightedBodyweight = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sets = ref.watch(setsForWorkoutExerciseProvider(workoutExercise.id));

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exerciseName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          sets.when(
            data: (rows) => Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            rows[i].isWarmup ? 'W' : '${i + 1}',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          SetMetricFormat.summariseSet(
                            rows[i],
                            metric: metric,
                            weight: ref.watch(weightFormatProvider),
                            distance: ref.watch(distanceFormatProvider),
                            isWeightedBodyweight: isWeightedBodyweight,
                          ),
                        ),
                        if (rows[i].rpeX10 != null) ...[
                          const SizedBox(width: 12),
                          Text(
                            '@${(rows[i].rpeX10! / 10).toStringAsFixed(1)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                        if (rows[i].completedAt != null) ...[
                          const Spacer(),
                          Text(
                            DateFormat('HH:mm').format(rows[i].completedAt!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
