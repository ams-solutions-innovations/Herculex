import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/toast/hx_toast_controller.dart';
import 'package:herculex/core/notifications/toast/hx_toast_model.dart';
import 'package:herculex/core/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/health/presentation/health_providers.dart';
import 'package:herculex/features/workouts/domain/circuit_stats.dart';
import 'package:herculex/features/workouts/domain/session_summary.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';
import 'package:herculex/services/pending_ai_scan_service.dart';
import 'package:herculex/theme/colors.dart';
import 'package:herculex/theme/haptics.dart';
import 'package:herculex/widgets/premium_button.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

  final _shareCardKey = GlobalKey();
  ShareCardBackground _background = ShareCardBackground.dark;
  bool _sharing = false;
  bool _syncingHealth = false;
  bool? _healthSyncSuccess;

  @override
  void initState() {
    super.initState();
    Haptics.success();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error selecting image: $e')));
      }
    }
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
        ref
            .read(hxToastControllerProvider.notifier)
            .show(
              success
                  ? HxToastItem.workoutSynced()
                  : HxToastItem.workoutSyncFailed(),
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
          data: (s) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Burst(controller: _intro),
                const SizedBox(height: 20),
                _staggered(
                  0,
                  Text(
                    'Workout Complete',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _staggered(
                  1,
                  Text(
                    s.name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _staggered(
                  2,
                  RepaintBoundary(
                    key: _shareCardKey,
                    child: _ShareCard(
                      summary: s,
                      background: _background,
                      weightFormat: ref.watch(weightFormatProvider),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _staggered(3, _circuitsSummarySection(widget.sessionId, theme)),
                const SizedBox(height: 16),
                _staggered(4, _photoSection(s, theme)),
                const SizedBox(height: 16),
                _staggered(5, _healthSyncCard(s, theme)),
                const SizedBox(height: 20),
                _staggered(6, _backgroundPicker(theme)),
                const SizedBox(height: 24),
                _staggered(
                  7,
                  SizedBox(
                    width: 240,
                    child: PremiumButton(
                      text: _sharing ? 'Preparing…' : 'Share',
                      icon: Icons.ios_share,
                      onTap: () {
                        if (_sharing) return;
                        _share(s);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _staggered(
                  7,
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Done',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

        return _CircuitsSummaryCard(
          sessionId: sessionId,
          circuitGroups: circuitGroups,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
    );
  }

  Widget _photoSection(SessionSummary s, ThemeData theme) {
    final photo = s.photoPath;
    final hasPhoto = photo != null && File(photo).existsSync();

    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'WORKOUT PHOTO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              if (hasPhoto)
                InkWell(
                  onTap: _removePhoto,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      'Remove',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.redAccent,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasPhoto) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(photo),
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded, size: 16),
                    label: const Text('Camera', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded, size: 16),
                    label: const Text(
                      'Gallery',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded, size: 16),
                    label: const Text('Take photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.15,
                      ),
                      foregroundColor: AppColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded, size: 16),
                    label: const Text('Choose from gallery'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceVariant,
                      foregroundColor: theme.colorScheme.onSurface,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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

  Widget _backgroundPicker(ThemeData theme) {
    return Column(
      children: [
        Text(
          'CARD BACKGROUND',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.secondary,
            letterSpacing: 1.2,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            for (final bg in ShareCardBackground.values)
              ChoiceChip(
                label: Text(bg.label),
                selected: _background == bg,
                onSelected: (_) {
                  Haptics.selection();
                  setState(() => _background = bg);
                },
                selectedColor: AppColors.primary.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: _background == bg
                      ? AppColors.primary
                      : AppColors.secondary,
                  fontWeight: _background == bg
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                side: BorderSide(
                  color: _background == bg
                      ? AppColors.primary
                      : AppColors.outlineVariant.withValues(alpha: 0.4),
                ),
                shape: const StadiumBorder(),
              ),
          ],
        ),
      ],
    );
  }

  /// Rasterises the card and hands it to the OS share sheet. Transparent
  /// backgrounds stay transparent because PNG carries the alpha channel.
  Future<void> _share(SessionSummary s) async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _shareCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
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

/// Expanding ring + check mark that plays once when the screen opens.
class _Burst extends StatelessWidget {
  final AnimationController controller;
  const _Burst({required this.controller});

  @override
  Widget build(BuildContext context) {
    final pop = CurvedAnimation(
      parent: controller,
      curve: const Interval(0, 0.45, curve: Curves.elasticOut),
    );
    final ripple = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.05, 0.65, curve: Curves.easeOutCubic),
    );

    return SizedBox(
      width: 140,
      height: 140,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            for (final delay in const [0.0, 0.15])
              Opacity(
                opacity:
                    (1 - ((ripple.value - delay).clamp(0.0, 1.0))).clamp(
                      0.0,
                      1.0,
                    ) *
                    0.35,
                child: Container(
                  width: 80 + 60 * (ripple.value - delay).clamp(0.0, 1.0),
                  height: 80 + 60 * (ripple.value - delay).clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
            Transform.scale(
              scale: pop.value.clamp(0.0, 1.4),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, const Color(0xFF30D158)],
                  ),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The exported card. Kept free of theme lookups so the chosen [background]
/// fully determines how it renders, whatever the app theme is.
class _ShareCard extends StatelessWidget {
  final SessionSummary summary;
  final ShareCardBackground background;
  final WeightFormat weightFormat;

  const _ShareCard({
    required this.summary,
    required this.background,
    required this.weightFormat,
  });

  bool get _onDark => background != ShareCardBackground.light;

  Color get _fg => _onDark ? Colors.white : const Color(0xFF0B1220);
  Color get _muted =>
      _onDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: switch (background) {
          ShareCardBackground.dark => const Color(0xFF0D1B2A),
          ShareCardBackground.light => Colors.white,
          ShareCardBackground.transparent => Colors.transparent,
        },
        border: background == ShareCardBackground.transparent
            ? Border.all(color: _fg.withValues(alpha: 0.25), width: 1.5)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'HERCULEX',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            summary.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _fg,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE, d MMM').format(summary.startedAt),
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat(summary.durationLabel, 'TIME'),
              _divider(),
              _stat('${summary.caloriesBurned}', 'KCAL'),
              _divider(),
              _stat(weightFormat.formatTonnage(summary.tonnageKg), 'VOLUME'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('${summary.totalSets}', 'SETS'),
              _divider(),
              _stat('${summary.totalReps}', 'REPS'),
              _divider(),
              _stat('${summary.exerciseCount}', 'EXERCISES'),
            ],
          ),
          if (summary.photoPath != null &&
              File(summary.photoPath!).existsSync()) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(summary.photoPath!),
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (summary.muscleGroups.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in summary.muscleGroups)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      m,
                      style: TextStyle(
                        color: _onDark ? Colors.white : AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (summary.achievements.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: _onDark
                    ? const Color(0xFF132238).withValues(alpha: 0.85)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(
                    0xFFFFD700,
                  ).withValues(alpha: _onDark ? 0.35 : 0.45),
                  width: 1.0,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.emoji_events_rounded,
                        color: Color(0xFFFFD700),
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'NEW RECORDS & ACHIEVEMENTS',
                        style: TextStyle(
                          color: _onDark
                              ? const Color(0xFFFFD700)
                              : const Color(0xFFB45309),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final ach in summary.achievements.take(3)) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: Row(
                        children: [
                          Icon(ach.icon, size: 14, color: ach.primaryColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              ach.title,
                              style: TextStyle(
                                color: _fg,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            ach.valueText,
                            style: TextStyle(
                              color: _onDark
                                  ? ach.primaryColor
                                  : const Color(0xFF0F172A),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: TextStyle(color: _fg, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: TextStyle(
          color: _muted,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
        ),
      ),
    ],
  );

  Widget _divider() =>
      Container(width: 1, height: 30, color: _fg.withValues(alpha: 0.12));
}

// ── Circuit Summary Section ────────────────────────────────────────────────

class _CircuitsSummaryCard extends StatelessWidget {
  final int sessionId;
  final List<List<WorkoutExerciseData>> circuitGroups;

  const _CircuitsSummaryCard({
    required this.sessionId,
    required this.circuitGroups,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.repeat_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'CIRCUITS PERFORMANCE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < circuitGroups.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _CircuitSummaryTile(index: i + 1, exercises: circuitGroups[i]),
          ],
        ],
      ),
    );
  }
}

class _CircuitSummaryTile extends ConsumerWidget {
  final int index;
  final List<WorkoutExerciseData> exercises;

  const _CircuitSummaryTile({required this.index, required this.exercises});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortedExercises = List<WorkoutExerciseData>.from(exercises)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    final setsByEx = <int, List<SetEntryData>>{};
    for (final ex in sortedExercises) {
      final setsAsync = ref.watch(workoutExerciseSetsProvider(ex.id));
      setsByEx[ex.id] = setsAsync.asData?.value ?? [];
    }

    final stats = calculateCircuitStats(
      exercises: sortedExercises,
      setsByExerciseId: setsByEx,
    );

    final isCircuit = sortedExercises.length >= 3;
    final label = isCircuit ? 'Circuit $index' : 'Superset $index';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${sortedExercises.length} exercises',
                style: TextStyle(color: AppColors.secondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COMPLETED ROUNDS',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${stats.completedRounds} / ${stats.totalPlannedRounds}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 24, color: AppColors.outlineVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AVG REST BETWEEN',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stats.formattedAvgRest,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
