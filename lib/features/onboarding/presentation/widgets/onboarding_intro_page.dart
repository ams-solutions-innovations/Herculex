import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

/// One of the four pillar pages shown before the setup steps.
class IntroPillar {
  const IntroPillar({
    required this.label,
    required this.headline,
    required this.body,
    required this.icon,
    required this.bullets,
    required this.accent,
  });

  final String label;
  final String headline;
  final String body;
  final IconData icon;
  final List<(IconData, String)> bullets;
  final Color Function(HxColors) accent;
}

final introPillars = <IntroPillar>[
  IntroPillar(
    label: 'Training',
    headline: 'Every set, logged in seconds.',
    body:
        'Run a program or train freely. Herculex tracks loads, PRs and what '
        'to lift next.',
    icon: Icons.fitness_center_rounded,
    accent: (hx) => hx.domainTraining,
    bullets: const [
      (Icons.event_note_rounded, 'Programs from 3-day full body to 6-day PPL'),
      (Icons.trending_up_rounded, 'Progressive-overload targets per lift'),
      (Icons.watch_rounded, 'Log from your wrist'),
    ],
  ),
  IntroPillar(
    label: 'Nutrition',
    headline: 'Hit your macros without the math.',
    body:
        'Scan a barcode, snap a meal or pick from the EU food database. '
        'Targets adapt to your day.',
    icon: Icons.restaurant_rounded,
    accent: (hx) => hx.domainNutrition,
    bullets: const [
      (Icons.qr_code_scanner_rounded, 'Barcode scanning and custom foods'),
      (Icons.donut_large_rounded, 'Macro rings and carb cycling'),
      (Icons.timer_rounded, 'Built-in fasting timer'),
    ],
  ),
  IntroPillar(
    label: 'Recovery',
    headline: 'Know when to push and when to rest.',
    body:
        'A 19-muscle heatmap and CNS fatigue trend show what is ready to '
        'train today.',
    icon: Icons.bedtime_rounded,
    accent: (hx) => hx.domainRecovery,
    bullets: const [
      (Icons.accessibility_new_rounded, 'Muscle recovery heatmap'),
      (Icons.bedtime_rounded, 'Sleep and steps from Health'),
      (Icons.monitor_heart_rounded, 'Fatigue trends before they hurt'),
    ],
  ),
  IntroPillar(
    label: 'Dream Physique',
    headline: 'Pick the body you are building.',
    body:
        'Set a goal, get a phased roadmap, and check in weekly with a '
        'progress photo.',
    icon: Icons.emoji_events_rounded,
    accent: (hx) => hx.tertiary,
    bullets: const [
      (Icons.flag_rounded, 'Phased roadmap with exit criteria'),
      (Icons.photo_camera_rounded, 'Weekly check-ins, max one per 7 days'),
      (Icons.military_tech_rounded, 'Rank and XP as you progress'),
    ],
  ),
];

class OnboardingIntroPage extends StatelessWidget {
  const OnboardingIntroPage({
    super.key,
    required this.index,
    required this.onNext,
    required this.onSkipIntro,
    this.onBack,
  });

  final int index;
  final VoidCallback onNext;
  final VoidCallback onSkipIntro;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    final pillar = introPillars[index];
    final accent = pillar.accent(hx);
    final isLast = index == introPillars.length - 1;
    return OnboardingScaffold(
      onBack: onBack,
      onSkip: isLast ? null : onSkipIntro,
      skipLabel: 'Skip intro',
      topPadding: 4,
      ctaLabel: isLast ? 'Set up my profile' : 'Next',
      onCta: onNext,
      footer: Center(
        child: Semantics(
          label: 'Page ${index + 1} of ${introPillars.length}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < introPillars.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == index ? hx.primary : hx.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 230,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.18),
                  hx.surfaceContainerLowest,
                ],
              ),
            ),
            alignment: Alignment.center,
            child: Icon(pillar.icon, size: 120, color: accent),
          ),
          const SizedBox(height: 20),
          Text(
            pillar.label.toUpperCase(),
            style: text.labelMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            pillar.headline,
            style: text.headlineMedium?.copyWith(
              fontFamily: 'SpaceGrotesk',
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.1,
              color: hx.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            pillar.body,
            style: text.bodyMedium?.copyWith(
              color: hx.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          for (final (icon, label) in pillar.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 20, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: text.bodyMedium?.copyWith(
                        color: hx.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
