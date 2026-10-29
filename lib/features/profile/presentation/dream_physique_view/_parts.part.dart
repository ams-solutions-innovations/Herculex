part of '../dream_physique_view.dart';

/// Space Grotesk, the display face the design uses for titles and numbers.
TextStyle _dpDisplay(
  double size, {
  FontWeight weight = FontWeight.w700,
  double letterSpacing = 0,
  double? height,
  Color? color,
}) => TextStyle(
  fontFamily: AppTheme.fontDisplay,
  fontSize: size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  height: height,
  color: color,
);

/// The small all-caps label above a block ("REALISTIC TIMEFRAME").
class _DpEyebrow extends StatelessWidget {
  const _DpEyebrow(this.text, {this.color, this.icon, this.spacing = 1.2});

  final String text;
  final Color? color;
  final IconData? icon;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.hx.secondary;
    final label = Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: spacing,
        color: c,
      ),
    );
    if (icon == null) return label;
    return Row(
      children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 6),
        Flexible(child: label),
      ],
    );
  }
}

/// The flat card every result block sits in.
BoxDecoration _dpCard(BuildContext context, {double radius = 24}) =>
    BoxDecoration(
      color: context.hx.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: context.hx.outlineVariant),
    );

/// A section title with an optional trailing note ("Where to focus").
class _DpSectionTitle extends StatelessWidget {
  const _DpSectionTitle(this.title, {this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(title, style: _dpDisplay(20))),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.hx.secondary,
            ),
          ),
      ],
    );
  }
}

/// The tall pinned call to action. Disabled, it goes flat and grey; [success]
/// turns it green once the goal is saved.
class _DpPrimaryButton extends StatelessWidget {
  const _DpPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.success = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool success;

  bool get enabled => onPressed != null;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final fill = success ? hx.success : hx.primary;
    final active = enabled || success;
    final foreground = active ? hx.onPrimary : hx.tertiary;
    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedContainer(
        duration: HxMotion.base,
        height: 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: active ? null : hx.surfaceContainer,
          gradient: active
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(fill, Colors.white, 0.14)!, fill],
                )
              : null,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: fill.withValues(alpha: 0.32),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: foreground,
                    ),
                  )
                else
                  Icon(icon, size: 22, color: foreground),
                const SizedBox(width: HxSpace.x2),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: foreground,
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
}

/// A 44 px outlined button ("Camera", "Update nutrition targets").
class _DpSecondaryButton extends StatelessWidget {
  const _DpSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.filled = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Tints border and label; defaults to the neutral outline.
  final Color? color;

  /// Neutral buttons sit on a raised fill; tinted ones are transparent.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final foreground = color ?? hx.onSurfaceVariant;
    return Material(
      color: filled ? hx.surfaceContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: color?.withValues(alpha: 0.45) ?? hx.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill switch from the design: 48 × 28 track, white thumb.
class _DpToggle extends StatelessWidget {
  const _DpToggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: HxMotion.fast,
          width: 48,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? hx.primary : hx.outline,
            borderRadius: BorderRadius.circular(999),
          ),
          child: AnimatedAlign(
            duration: HxMotion.fast,
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small round × over a photo.
class _DpPhotoClose extends StatelessWidget {
  const _DpPhotoClose({required this.onTap, this.size = 24});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Remove photo',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.close_rounded,
            size: size * 0.6,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// A NOW / GOAL tag over a photo.
class _DpPhotoTag extends StatelessWidget {
  const _DpPhotoTag(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Fills its box with [file], or a quiet placeholder when it is missing.
class _DpPhoto extends StatelessWidget {
  const _DpPhoto(this.file, {this.placeholderIcon = Icons.person_rounded});

  final File? file;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final f = file;
    if (f != null && f.existsSync()) {
      return Image.file(
        f,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return ColoredBox(
      color: context.hx.surfaceContainerLowest,
      child: Center(
        child: Icon(placeholderIcon, size: 32, color: context.hx.tertiary),
      ),
    );
  }
}

/// Rounded border that is dashed while a slot is empty and solid once filled.
class _DpSlotBorder extends StatelessWidget {
  const _DpSlotBorder({
    required this.radius,
    required this.color,
    required this.dashed,
    required this.child,
    this.background,
    this.gradient,
  });

  final double radius;
  final Color color;
  final bool dashed;
  final Color? background;
  final Gradient? gradient;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedRRectPainter(
        radius: radius,
        color: color,
        dashed: dashed,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: BoxDecoration(color: background, gradient: gradient),
          child: child,
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.radius,
    required this.color,
    required this.dashed,
  });

  static const _stroke = 1.5;
  static const _dash = 5.0;
  static const _gap = 4.0;

  final double radius;
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    if (!dashed) {
      canvas.drawRRect(rrect, paint);
      return;
    }
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.dashed != dashed || old.radius != radius;
}

class _DpErrorCard extends StatelessWidget {
  const _DpErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hx.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hx.danger.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: hx.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: hx.onSurface,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
