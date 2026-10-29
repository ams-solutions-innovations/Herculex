part of '../full_screen_rest_timer_view.dart';

/// Remaining-time ring: the arc is what is left, so it empties as you rest.
class _RestRing extends StatelessWidget {
  const _RestRing({
    required this.size,
    required this.fraction,
    required this.color,
    required this.label,
    required this.time,
    this.caption,
  });

  final double size;
  final double fraction;
  final Color color;
  final String label;
  final String time;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final stroke = size * 0.05;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: EdgeInsets.all(stroke / 2),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: fraction),
              duration: const Duration(seconds: 1),
              builder: (_, value, _) => SizedBox.square(
                dimension: size - stroke,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: stroke,
                  strokeCap: StrokeCap.round,
                  backgroundColor: hx.outlineVariant.withValues(alpha: 0.55),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: workoutKicker(context, spacing: 1.6)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  time,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: size * 0.3,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    letterSpacing: -3,
                    color: color,
                  ),
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: hx.surfaceContainer.withValues(alpha: 0.9),
                    borderRadius: HxRadius.pillAll,
                  ),
                  child: Text(
                    caption!,
                    style: TextStyle(
                      color: hx.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AdjustButton extends StatelessWidget {
  const _AdjustButton({
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: accent
            ? hx.primary.withValues(alpha: 0.16)
            : hx.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: HxRadius.mdAll,
          side: BorderSide(
            color: accent
                ? hx.primary.withValues(alpha: 0.45)
                : hx.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  Haptics.light();
                  onTap!();
                },
          child: Container(
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: accent ? 20 : 16),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: accent ? hx.primaryText : hx.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The effort of the set the rest follows — logged (tap to edit) or still
/// open (tap to rate).
class _LastEffortRow extends StatelessWidget {
  const _LastEffortRow({
    required this.set,
    required this.exerciseName,
    required this.setLabel,
    required this.onTap,
  });

  final SetEntryData set;
  final String? exerciseName;
  final String? setLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final rpe = set.rpeX10;
    final logged = rpe != null;
    final accent = hx.domainRecovery;
    final which = setLabel ?? 'last set';
    final text = logged
        ? '${exerciseName == null ? '' : '$exerciseName · '}$which · RPE ${_rpe(rpe)}'
        : 'Rate effort for $which';
    return Material(
      color: logged
          ? accent.withValues(alpha: 0.10)
          : hx.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: logged ? accent.withValues(alpha: 0.35) : hx.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                logged ? Icons.check_circle_rounded : Icons.speed_rounded,
                size: 18,
                color: logged ? accent : hx.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: logged
                        ? Color.lerp(accent, Colors.white, 0.45)
                        : hx.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                logged ? 'Edit' : 'Rate',
                style: TextStyle(
                  color: hx.primaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _rpe(int x10) =>
      x10 % 10 == 0 ? '${x10 ~/ 10}' : (x10 / 10).toStringAsFixed(1);
}

class _SupersetTag extends StatelessWidget {
  const _SupersetTag({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: supersetCyan.withValues(alpha: 0.14),
        borderRadius: HxRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_rounded, size: 13, color: supersetCyan),
          const SizedBox(width: 3),
          Text(
            tag,
            style: workoutKicker(
              context,
              color: supersetCyan,
              size: 10.5,
              spacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
