import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/gamification/application/gamification_providers.dart';
import 'package:herculex/features/health/application/health_providers.dart';
import 'package:herculex/features/programs/domain/session_completion.dart';
import 'package:herculex/features/programs/presentation/widgets/session_tile.dart';
import 'package:herculex/features/workout_report/application/workout_report_providers.dart';
import 'package:herculex/features/workout_report/presentation/workout_report_card.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/circuit_stats.dart';
import 'package:herculex/features/workouts/domain/session_summary.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

part 'workout_finish_view/_cards.part.dart';
part 'workout_finish_view/_photo.part.dart';
part 'workout_finish_view/_summary.part.dart';

/// Background options for the shareable card (§2).
enum ShareCardBackground {
  dark('Dark'),
  light('Light'),
  transparent('Transparent');

  const ShareCardBackground(this.label);
  final String label;
}

/// Celebratory end-of-workout screen. Everything is centred on the vertical
/// axis; the stats stagger in behind a check-mark burst, and the card can be
/// exported as an image to share.
class WorkoutFinishView extends ConsumerStatefulWidget {
  final int sessionId;
  const WorkoutFinishView({super.key, required this.sessionId});

  /// Pushes the finish screen over the current route. Awaits so callers can
  /// pop back to the workouts landing afterwards.
  static Future<void> show(BuildContext context, int sessionId) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) => WorkoutFinishView(sessionId: sessionId),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  ConsumerState<WorkoutFinishView> createState() => _WorkoutFinishViewState();
}

class _WorkoutFinishViewState extends ConsumerState<WorkoutFinishView>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  // A light card is the calm default and matches what is most useful in a
  // social share. The other treatments are offered in the share preview.
  ShareCardBackground _background = ShareCardBackground.light;
  bool _sharing = false;
  bool _syncingHealth = false;
  bool? _healthSyncSuccess;

  @override
  void initState() {
    super.initState();
    Haptics.success();
    // The finish screen is mounted after `endSession` commits, so this is the
    // safe point to award the idempotent workout XP event. It also covers both
    // classic and dynamic workout flows without touching a disposed editor.
    WidgetsBinding.instance.addPostFrameCallback((_) => _awardWorkoutXp());
  }

  Future<void> _awardWorkoutXp() async {
    try {
      final session = await ref.read(
        workoutSessionProvider(widget.sessionId).future,
      );
      if (!mounted) return;
      final db = ref.read(appDatabaseProvider);
      final completed = await (db.select(
        db.workoutSessions,
      )..where((row) => row.endedAt.isNotNull())).get();
      if (!mounted) return;
      await ref
          .read(gamificationServiceProvider)
          .onWorkoutFinished(
            sessionId: session.id,
            workoutName: session.name ?? 'Workout',
            startedAt: session.startedAt,
            endedAt: session.endedAt ?? session.startedAt,
            totalCompletedWorkouts: completed
                .where((row) => row.deletedAt == null)
                .length,
          );
    } catch (_) {
      // XP is a non-critical local enhancement; the finish screen remains
      // usable if a database or preference read cannot complete.
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Fades and slides one block in, [order] steps after the burst.
  Widget _staggered(int order, Widget child) {
    final start = (0.25 + order * 0.11).clamp(0.0, 0.9);
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(
        start,
        (start + 0.35).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - anim.value)),
          child: c,
        ),
      ),
      child: child,
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      await ref
          .read(pendingAiScanServiceProvider)
          .setPendingContext(
            PendingAiScanContext(
              type: AiScanContextType.workoutPhoto,
              extra: {'sessionId': widget.sessionId},
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
      Haptics.selection();
      await ref
          .read(workoutsRepositoryProvider)
          .updateSessionPhoto(widget.sessionId, image.path);
      ref.invalidate(sessionSummaryProvider(widget.sessionId));
      ref.invalidate(workoutSessionProvider(widget.sessionId));
    } catch (e) {
      if (mounted) {
        AppNotice.show(
          context,
          'Error selecting image: $e',
          kind: AppNoticeKind.error,
        );
      }
    }
  }

  Future<void> _openSharePreview(SessionSummary s) async {
    final picked = await showModalBottomSheet<ShareCardBackground>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SharePreviewSheet(
        summary: s,
        initial: _background,
        weightFormat: ref.read(weightFormatProvider),
        onShare: (key) => _share(s, key),
      ),
    );
    if (picked != null && mounted) setState(() => _background = picked);
  }

  Future<void> _removePhoto() async {
    Haptics.selection();
    await ref
        .read(workoutsRepositoryProvider)
        .updateSessionPhoto(widget.sessionId, null);
    ref.invalidate(sessionSummaryProvider(widget.sessionId));
    ref.invalidate(workoutSessionProvider(widget.sessionId));
  }

  Future<void> _syncToHealth(SessionSummary s) async {
    setState(() => _syncingHealth = true);
    Haptics.selection();
    try {
      final success = await ref
          .read(healthServiceProvider)
          .writeWorkoutToHealth(
            workoutSessionId: s.sessionId,
            activityName: s.name,
            startTime: s.startedAt,
            endTime: s.startedAt.add(s.duration),
            totalCaloriesBurned: s.caloriesBurned,
          );
      if (mounted) {
        setState(() {
          _syncingHealth = false;
          _healthSyncSuccess = success;
        });
        AppNotice.showWith(
          ref,
          success ? 'Synced to Health Connect' : 'Sync failed',
          title: success
              ? 'Workout saved'
              : 'Check Health Connect permissions in settings',
          kind: success ? AppNoticeKind.success : AppNoticeKind.error,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _syncingHealth = false;
          _healthSyncSuccess = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summaryAsync = ref.watch(sessionSummaryProvider(widget.sessionId));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: summaryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (s) => Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _staggered(0, _finishHeader(s, theme)),
                          const SizedBox(height: 20),
                          _staggered(
                            1,
                            _FinishStats(
                              summary: s,
                              sessionId: widget.sessionId,
                              weightFormat: ref.watch(weightFormatProvider),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _staggered(
                            2,
                            WorkoutReportCard(sessionId: widget.sessionId),
                          ),
                          const SizedBox(height: 16),
                          _staggered(3, _detailsSection(s, theme)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _staggered(
                4,
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            onPressed: _sharing
                                ? null
                                : () => _openSharePreview(s),
                            icon: const Icon(Icons.ios_share_rounded),
                            label: const Text('Share'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _finishHeader(SessionSummary summary, ThemeData theme) => Column(
    children: [
      _Burst(controller: _intro),
      const SizedBox(height: 8),
      Text(
        'Workout Complete',
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '${summary.name} · ${DateFormat('d MMMM').format(summary.startedAt)}',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
      ),
    ],
  );

  Widget _detailsSection(SessionSummary summary, ThemeData theme) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: AppColors.outlineVariant.withValues(alpha: 0.32),
      ),
    ),
    child: ExpansionTile(
      key: const PageStorageKey('workout-finish-more-details'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      shape: const RoundedRectangleBorder(),
      collapsedShape: const RoundedRectangleBorder(),
      leading: Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
      title: Text(
        'More details',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        'Photo, health sync and circuits',
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
      ),
      children: [
        _PhotoSection(
          summary: summary,
          onPick: _pickPhoto,
          onRemove: _removePhoto,
        ),
        const SizedBox(height: 12),
        _healthSyncCard(summary, theme),
        _circuitsSummarySection(widget.sessionId, theme),
      ],
    ),
  );

  Widget _circuitsSummarySection(int sessionId, ThemeData theme) {
    final exercisesAsync = ref.watch(sessionExercisesProvider(sessionId));
    return exercisesAsync.when(
      data: (exercises) {
        final groups = <int, List<WorkoutExerciseData>>{};
        for (final ex in exercises) {
          if (ex.supersetGroup != null) {
            groups.putIfAbsent(ex.supersetGroup!, () => []).add(ex);
          }
        }
        final circuitGroups = groups.values
            .where((g) => g.length >= 2)
            .toList();
        if (circuitGroups.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _CircuitsSummaryCard(
            sessionId: sessionId,
            circuitGroups: circuitGroups,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
    );
  }

  Widget _healthSyncCard(SessionSummary s, ThemeData theme) {
    final isSynced = _healthSyncSuccess == true;

    return Container(
      width: 320,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSynced
              ? const Color(0xFF30D158).withValues(alpha: 0.4)
              : AppColors.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  (isSynced ? const Color(0xFF30D158) : const Color(0xFF4285F4))
                      .withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSynced ? Icons.check_circle_rounded : Icons.favorite_rounded,
              color: isSynced
                  ? const Color(0xFF30D158)
                  : const Color(0xFF4285F4),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Health Connect / Samsung Health',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isSynced
                      ? 'Synced (${s.caloriesBurned} kcal)'
                      : '${s.caloriesBurned} kcal · ${s.durationLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isSynced
                        ? const Color(0xFF30D158)
                        : AppColors.secondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _syncingHealth ? null : () => _syncToHealth(s),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            child: _syncingHealth
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    isSynced ? 'Retry' : 'Sync',
                    style: TextStyle(
                      color: isSynced ? AppColors.secondary : AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Rasterises the card and hands it to the OS share sheet. Transparent
  /// backgrounds stay transparent because PNG carries the alpha channel.
  Future<void> _share(SessionSummary s, GlobalKey cardKey) async {
    setState(() => _sharing = true);
    try {
      final boundary =
          cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = await File(
        '${dir.path}/herculex_workout_${s.sessionId}.png',
      ).writeAsBytes(bytes);

      final files = [XFile(file.path, mimeType: 'image/png')];
      if (s.photoPath != null && File(s.photoPath!).existsSync()) {
        files.add(XFile(s.photoPath!));
      }

      await Share.shareXFiles(
        files,
        text:
            '${s.name} — ${s.totalSets} sets, '
            '${ref.read(weightFormatProvider).formatTonnage(s.tonnageKg)} moved, '
            '${s.caloriesBurned} kcal in ${s.durationLabel}. #Herculex',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
