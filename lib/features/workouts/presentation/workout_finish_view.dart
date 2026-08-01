import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/units.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../widgets/premium_button.dart';
import '../domain/session_summary.dart';
import 'workouts_providers.dart';

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
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
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
      curve: Interval(start, (start + 0.35).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
            offset: Offset(0, 18 * (1 - anim.value)), child: c),
      ),
      child: child,
    );
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
                  Text('Workout Complete',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 6),
                _staggered(
                  1,
                  Text(s.name,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: AppColors.secondary)),
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
                const SizedBox(height: 24),
                _staggered(3, _backgroundPicker(theme)),
                const SizedBox(height: 24),
                _staggered(
                  4,
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
                  5,
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Done',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: AppColors.secondary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _backgroundPicker(ThemeData theme) {
    return Column(
      children: [
        Text('CARD BACKGROUND',
            style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary, letterSpacing: 1.2, fontSize: 10)),
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
                  fontWeight:
                      _background == bg ? FontWeight.bold : FontWeight.normal,
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
      final boundary = _shareCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = await File('${dir.path}/herculex_workout_${s.sessionId}.png')
          .writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: '${s.name} — ${s.totalSets} sets, '
            '${ref.read(weightFormatProvider).formatTonnage(s.tonnageKg)} moved '
            'in ${s.durationLabel}. #Herculex',
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
        curve: const Interval(0, 0.45, curve: Curves.elasticOut));
    final ripple = CurvedAnimation(
        parent: controller,
        curve: const Interval(0.05, 0.65, curve: Curves.easeOutCubic));

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
                opacity: (1 - ((ripple.value - delay).clamp(0.0, 1.0)))
                    .clamp(0.0, 1.0) *
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
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 44),
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
          Text('HERCULEX',
              style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3)),
          const SizedBox(height: 14),
          Text(summary.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _fg, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(DateFormat('EEEE, d MMM').format(summary.startedAt),
              style: TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat(summary.durationLabel, 'TIME'),
              _divider(),
              _stat(weightFormat.formatTonnage(summary.tonnageKg), 'VOLUME'),
              _divider(),
              _stat('${summary.totalSets}', 'SETS'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('${summary.exerciseCount}', 'EXERCISES'),
              _divider(),
              _stat('${summary.totalReps}', 'REPS'),
            ],
          ),
          if (summary.muscleGroups.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in summary.muscleGroups)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(m,
                        style: TextStyle(
                            color: _onDark ? Colors.white : AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: _fg, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1)),
        ],
      );

  Widget _divider() => Container(
        width: 1,
        height: 30,
        color: _fg.withValues(alpha: 0.12),
      );
}
