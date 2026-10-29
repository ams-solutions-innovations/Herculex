part of '../workout_finish_view.dart';

/// Preview of the shareable card with its style picker. The card is only
/// rendered here, so the share action rasterises this sheet's boundary.
/// Pops with the chosen style so the next preview opens on it.
class _SharePreviewSheet extends StatefulWidget {
  const _SharePreviewSheet({
    required this.summary,
    required this.initial,
    required this.weightFormat,
    required this.onShare,
  });

  final SessionSummary summary;
  final ShareCardBackground initial;
  final WeightFormat weightFormat;
  final Future<void> Function(GlobalKey cardKey) onShare;

  @override
  State<_SharePreviewSheet> createState() => _SharePreviewSheetState();
}

class _SharePreviewSheetState extends State<_SharePreviewSheet> {
  final _cardKey = GlobalKey();
  late ShareCardBackground _background = widget.initial;
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final transparent = _background == ShareCardBackground.transparent;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HxTopTabs(
              labels: [for (final bg in ShareCardBackground.values) bg.label],
              index: ShareCardBackground.values.indexOf(_background),
              onChanged: (i) =>
                  setState(() => _background = ShareCardBackground.values[i]),
            ),
            const SizedBox(height: 14),
            // The stage stands in for wherever the image ends up; only the
            // card inside the boundary is exported.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: HxRadius.xlAll,
                color: transparent ? null : const Color(0xFF0B1220),
                gradient: transparent
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF6B7A8C),
                          Color(0xFF33435A),
                          Color(0xFF151C28),
                        ],
                      )
                    : null,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  RepaintBoundary(
                    key: _cardKey,
                    child: _ShareCard(
                      summary: widget.summary,
                      background: _background,
                      weightFormat: widget.weightFormat,
                    ),
                  ),
                  if (transparent)
                    const Positioned(
                      left: 0,
                      bottom: -11,
                      child: Text(
                        'your photo / story background',
                        style: TextStyle(
                          color: Color(0x73FFFFFF),
                          fontSize: 9.5,
                          letterSpacing: 0.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: hx.primary,
                  foregroundColor: hx.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: HxRadius.lgAll),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: _sharing
                    ? null
                    : () async {
                        setState(() => _sharing = true);
                        await widget.onShare(_cardKey);
                        if (!context.mounted) return;
                        Navigator.of(context).pop(_background);
                      },
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share image'),
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

  static const _brand = Color(0xFF0A84FF);
  static const _gold = Color(0xFFFFD60A);

  bool get _onDark => background != ShareCardBackground.light;
  bool get _transparent => background == ShareCardBackground.transparent;

  Color get _fg => _onDark ? Colors.white : const Color(0xFF0B1220);
  Color get _muted => switch (background) {
    ShareCardBackground.dark => Colors.white.withValues(alpha: 0.6),
    ShareCardBackground.light => const Color(0xFF64748B),
    ShareCardBackground.transparent => Colors.white.withValues(alpha: 0.82),
  };

  /// Keeps white text legible over whatever photo it lands on.
  List<Shadow>? get _shadow => _transparent
      ? [Shadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 14)]
      : null;

  TextStyle _display(double size, {Color? color}) => TextStyle(
    fontFamily: AppTheme.fontDisplay,
    color: color ?? _fg,
    fontSize: size,
    fontWeight: FontWeight.w600,
    shadows: _shadow,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  TextStyle _label(double size) => TextStyle(
    fontFamily: AppTheme.fontBody,
    color: _muted,
    fontSize: size,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.4,
    shadows: _shadow,
  );

  @override
  Widget build(BuildContext context) {
    final photo = summary.photoPath == null
        ? null
        : LocalPhotoStore.resolveSync(summary.photoPath!);
    final records = summary.achievements;
    final hero =
        records.firstWhereOrNull((a) => a.type == AchievementType.weightPr) ??
        records.firstOrNull;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: switch (background) {
          ShareCardBackground.dark => null,
          ShareCardBackground.light => Colors.white,
          ShareCardBackground.transparent => Colors.transparent,
        },
        gradient: background == ShareCardBackground.dark
            ? RadialGradient(
                center: Alignment.topCenter,
                radius: 1.2,
                stops: const [0, 0.6],
                colors: [
                  Color.lerp(const Color(0xFF0D1B2A), _brand, 0.35)!,
                  const Color(0xFF0D1B2A),
                ],
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'HERCULEX',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              color: _brand,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            summary.name,
            textAlign: TextAlign.center,
            style: _display(22).copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            DateFormat('EEEE, d MMM').format(summary.startedAt),
            style: _label(
              11.5,
            ).copyWith(fontWeight: FontWeight.w600, letterSpacing: 0),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    summary.tonnageKg.isFinite
                        ? NumberFormat.decimalPattern().format(
                            weightFormat.toDisplay(summary.tonnageKg).round(),
                          )
                        : '0',
                    style: _display(52).copyWith(letterSpacing: -2, height: 1),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(weightFormat.suffix, style: _display(18, color: _muted)),
            ],
          ),
          const SizedBox(height: 2),
          Text('VOLUME', style: _label(9.5)),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat(WorkoutElapsedText.format(summary.duration), 'TIME'),
              _stat('${summary.totalSets}', 'SETS'),
              _stat('${summary.totalReps}', 'REPS'),
            ],
          ),
          if (photo != null && photo.existsSync()) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                photo,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (hero != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: switch (background) {
                  ShareCardBackground.dark => const Color(
                    0xFF132238,
                  ).withValues(alpha: 0.85),
                  ShareCardBackground.light => const Color(0xFFF1F5F9),
                  ShareCardBackground.transparent => Colors.white.withValues(
                    alpha: 0.12,
                  ),
                },
                border: Border.all(
                  color: switch (background) {
                    ShareCardBackground.dark => _gold.withValues(alpha: 0.4),
                    ShareCardBackground.light => const Color(
                      0xFFD97706,
                    ).withValues(alpha: 0.35),
                    ShareCardBackground.transparent => Colors.white.withValues(
                      alpha: 0.28,
                    ),
                  },
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.emoji_events_rounded,
                    size: 18,
                    color: _gold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      records.length == 1
                          ? '1 new PR'
                          : '${records.length} new PRs',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        color: _fg,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        shadows: _shadow,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${hero.title} ${hero.value}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        color: background == ShareCardBackground.light
                            ? const Color(0xFFB45309)
                            : _gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        shadows: _shadow,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: _display(19)),
        ),
        Text(label, style: _label(9).copyWith(letterSpacing: 1.2)),
      ],
    ),
  );
}
