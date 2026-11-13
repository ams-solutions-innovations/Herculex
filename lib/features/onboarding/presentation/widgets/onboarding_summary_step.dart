import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/profile/domain/profile.dart';

/// Last step: what the answers add up to, plus the setup left for later.
class OnboardingSummaryStep extends StatelessWidget {
  const OnboardingSummaryStep({
    super.key,
    required this.profile,
    required this.onPickProgram,
    required this.onSetPhysique,
  });

  /// The profile as it would be saved right now (defaults already applied).
  final Profile profile;
  final VoidCallback onPickProgram;
  final VoidCallback onSetPhysique;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    final targets = MacroTargets.fromProfile(profile);
    final name = profile.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          name == null ? "You're set" : "You're set, $name",
          style: text.headlineSmall?.copyWith(
            fontFamily: 'SpaceGrotesk',
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: hx.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: _Chip(label: profile.goal.label, color: hx.primaryText),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: hx.surfaceContainerLowest,
            borderRadius: HxRadius.xlAll,
            border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (targets == null)
                Text(
                  'Add your age, weight and height in Profile to get a daily '
                  'calorie and macro target.',
                  style: text.bodyMedium?.copyWith(color: hx.onSurfaceVariant),
                )
              else
                Row(
                  children: [
                    _MacroRing(targets: targets),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          _MacroRow(
                            color: hx.macroProtein,
                            label: 'Protein',
                            grams: targets.proteinG,
                          ),
                          const SizedBox(height: 10),
                          _MacroRow(
                            color: hx.macroCarbs,
                            label: 'Carbs',
                            grams: targets.carbsG,
                          ),
                          const SizedBox(height: 10),
                          _MacroRow(
                            color: hx.macroFat,
                            label: 'Fat',
                            grams: targets.fatG,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              if (profile.activityLevel == ActivityLevel.autocalibrator) ...[
                const SizedBox(height: 16),
                Divider(height: 1, color: hx.outlineVariant),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.autorenew_rounded, size: 20, color: hx.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Auto-calibrator will refine this after about two '
                        'weeks of weight and food logs.',
                        style: text.bodySmall?.copyWith(
                          color: hx.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Finish setting up',
          style: text.labelLarge?.copyWith(
            color: hx.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: hx.surfaceContainerLowest,
            borderRadius: HxRadius.lgAll,
            border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              _TodoRow(
                icon: Icons.event_note_rounded,
                color: hx.domainTraining,
                label: 'Pick a training program',
                onTap: onPickProgram,
              ),
              Divider(height: 1, color: hx.outlineVariant),
              _TodoRow(
                icon: Icons.accessibility_new_rounded,
                color: hx.tertiary,
                label: 'Set your dream physique',
                onTap: onSetPhysique,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.hx.primaryContainer,
        borderRadius: HxRadius.pillAll,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({
    required this.color,
    required this.label,
    required this.grams,
  });

  final Color color;
  final String label;
  final int grams;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: text.bodyMedium?.copyWith(color: hx.onSurfaceVariant),
          ),
        ),
        Text(
          '$grams g',
          style: text.titleSmall?.copyWith(
            fontFamily: 'SpaceGrotesk',
            fontWeight: FontWeight.w700,
            color: hx.onSurface,
          ),
        ),
      ],
    );
  }
}

class _MacroRing extends StatelessWidget {
  const _MacroRing({required this.targets});

  final MacroTargets targets;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 116,
      height: 116,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(116),
            painter: _RingPainter(
              slices: [
                (targets.proteinG * 4.0, hx.macroProtein),
                (targets.carbsG * 4.0, hx.macroCarbs),
                (targets.fatG * 9.0, hx.macroFat),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${targets.kcal}',
                style: text.titleLarge?.copyWith(
                  fontFamily: 'SpaceGrotesk',
                  fontWeight: FontWeight.w700,
                  color: hx.onSurface,
                ),
              ),
              Text(
                'kcal / day',
                style: text.labelSmall?.copyWith(color: hx.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.slices});

  /// (kcal, colour) per slice; angles are proportional to kcal.
  final List<(double, Color)> slices;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 13.0;
    const gap = 0.05;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final total = slices.fold<double>(0, (sum, s) => sum + s.$1);
    if (total <= 0) return;
    var start = -1.5707963; // 12 o'clock
    for (final (kcal, color) in slices) {
      final sweep = kcal / total * 6.2831853;
      canvas.drawArc(
        arc,
        start + gap / 2,
        (sweep - gap).clamp(0.0, 7.0),
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.slices != slices;
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: hx.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: hx.outline),
          ],
        ),
      ),
    );
  }
}
