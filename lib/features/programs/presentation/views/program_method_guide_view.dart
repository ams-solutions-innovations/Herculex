import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/programs/domain/periodization.dart';

/// A full-screen explanation that deliberately leaves the builder route on the
/// stack. Back therefore returns to the exact in-progress program draft.
class ProgramMethodGuideView extends StatelessWidget {
  const ProgramMethodGuideView({super.key, required this.model});

  final PeriodizationModel model;

  static Future<void> show(BuildContext context, PeriodizationModel model) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProgramMethodGuideView(model: model),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final guide = ProgramMethodGuide.forModel(model);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${model.label} guide')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              guide.summary,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              guide.introduction,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 24),
            _GuideSection(title: 'Best for', items: guide.bestFor),
            _GuideSection(title: 'How Herculex programs it', items: guide.how),
            _GuideSection(title: 'Exercise rotation', items: guide.rotation),
            const SizedBox(height: 12),
            Text(
              'Example block',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ...guide.weeks.map(
              (week) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: AppColors.surfaceContainerLowest,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: .12),
                    foregroundColor: AppColors.primary,
                    child: Text('${week.number}'),
                  ),
                  title: Text(week.title),
                  subtitle: Text(week.description),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ProgramMethodGuide {
  const ProgramMethodGuide({
    required this.summary,
    required this.introduction,
    required this.bestFor,
    required this.how,
    required this.rotation,
    required this.weeks,
  });

  final String summary;
  final String introduction;
  final List<String> bestFor;
  final List<String> how;
  final List<String> rotation;
  final List<ProgramMethodGuideWeek> weeks;

  static ProgramMethodGuide forModel(
    PeriodizationModel model,
  ) => switch (model) {
    PeriodizationModel.linear => const ProgramMethodGuide(
      summary: 'Build the same lifts patiently, one week at a time.',
      introduction:
          'Linear programming raises the planned load gradually while reducing a little volume. It is the clearest starting point when technique and consistency matter most.',
      bestFor: [
        'Novice lifters and anyone returning after a break.',
        'Strength goals with 2–4 reliable training days each week.',
      ],
      how: [
        'Main lifts use repeatable straight sets or conservative top sets.',
        'Load rises in small steps while a planned deload protects recovery.',
      ],
      rotation: [
        'Main lifts stay stable so progress is easy to measure.',
        'Accessories can rotate only at the interval shown in your review.',
      ],
      weeks: [
        ProgramMethodGuideWeek(
          1,
          'Base',
          'Establish crisp technique and a repeatable working load.',
        ),
        ProgramMethodGuideWeek(
          2,
          'Build',
          'Add a small load or rep improvement while volume stays steady.',
        ),
        ProgramMethodGuideWeek(
          3,
          'Build',
          'Continue the gradual progression if quality remains high.',
        ),
        ProgramMethodGuideWeek(
          4,
          'Deload',
          'Reduce volume and intensity before the next ramp.',
        ),
        ProgramMethodGuideWeek(
          5,
          'Build',
          'Resume progression from the deload with a fresh, modest ramp.',
        ),
        ProgramMethodGuideWeek(
          6,
          'Build',
          'Add another small load or rep increase while form stays crisp.',
        ),
        ProgramMethodGuideWeek(
          7,
          'Build',
          'Keep pushing the ramp while quality and recovery allow it.',
        ),
        ProgramMethodGuideWeek(
          8,
          'Deload',
          'Reduce volume and intensity again before the next block.',
        ),
      ],
    ),
    PeriodizationModel.concurrent => const ProgramMethodGuide(
      summary: 'Train strength, volume and technique in the same week.',
      introduction:
          'Concurrent programming keeps several qualities present at once. Your day roles distribute fatigue instead of forcing every workout to feel equally heavy.',
      bestFor: [
        'Intermediate lifters who recover well from varied sessions.',
        'Powerbuilding and athletic goals with at least 3 training days.',
      ],
      how: [
        'Intensity, volume and mixed days have distinct roles.',
        'The week gently waves stress while every quality remains practiced.',
      ],
      rotation: [
        'The review shows the exact exercise wave for every slot.',
        'Changing a lift can affect this wave, future waves or the full block.',
      ],
      weeks: [
        ProgramMethodGuideWeek(
          1,
          'Establish',
          'Learn the heavy, volume and mixed-day rhythm.',
        ),
        ProgramMethodGuideWeek(
          2,
          'Build',
          'Progress the primary lift while accessories support weak links.',
        ),
        ProgramMethodGuideWeek(
          3,
          'Wave',
          'A slightly different stress emphasis manages fatigue.',
        ),
        ProgramMethodGuideWeek(
          4,
          'Review',
          'Keep, rotate or deload according to performance and recovery.',
        ),
        ProgramMethodGuideWeek(
          5,
          'Establish',
          'Return to the heavy/volume/mixed-day rhythm with lessons from weeks 1-4.',
        ),
        ProgramMethodGuideWeek(
          6,
          'Build',
          'Progress the primary lift again while accessories keep supporting weak links.',
        ),
        ProgramMethodGuideWeek(
          7,
          'Wave',
          'Shift stress emphasis once more to manage accumulated fatigue.',
        ),
        ProgramMethodGuideWeek(
          8,
          'Review',
          "Keep, rotate or deload based on this cycle's performance and recovery.",
        ),
      ],
    ),
    PeriodizationModel.block => const ProgramMethodGuide(
      summary: 'Build volume, convert it to strength, then realize it.',
      introduction:
          'Block programming focuses the block in phases. The exercise pool and loading change on purpose when the phase changes.',
      bestFor: [
        'Intermediate or advanced lifters with a specific performance date.',
        'A goal that benefits from a clear peak rather than flat training.',
      ],
      how: [
        'Accumulation builds work capacity with more volume.',
        'Transmutation shifts toward heavier, more specific work.',
        'Realization keeps the anchor lift and reduces volume to expose performance.',
      ],
      rotation: [
        'Rotation follows phase changes, not a fixed every-two-weeks rule.',
        'The anchor lift stays stable in realization unless you edit it deliberately.',
      ],
      weeks: [
        ProgramMethodGuideWeek(
          1,
          'Accumulation',
          'Higher-volume foundational work.',
        ),
        ProgramMethodGuideWeek(
          2,
          'Accumulation',
          'Add a modest load increase while volume stays high.',
        ),
        ProgramMethodGuideWeek(
          3,
          'Accumulation',
          'Build capacity without chasing max loads.',
        ),
        ProgramMethodGuideWeek(
          4,
          'Accumulation',
          'Hold volume steady as the phase closes out.',
        ),
        ProgramMethodGuideWeek(
          5,
          'Transmutation',
          'Use heavier, more specific work.',
        ),
        ProgramMethodGuideWeek(
          6,
          'Transmutation',
          'Narrow the exercise pool toward the anchor lift.',
        ),
        ProgramMethodGuideWeek(
          7,
          'Transmutation',
          'Sharpen intensity as accumulation-style volume fades.',
        ),
        ProgramMethodGuideWeek(
          8,
          'Realization',
          'Lower volume; sharpen the primary lift.',
        ),
      ],
    ),
    PeriodizationModel.maxEffort => const ProgramMethodGuide(
      summary: 'A conjugate method for experienced strength-focused lifters.',
      introduction:
          'Westside-style programming alternates Max Effort and Dynamic Effort days. It is not the default for beginners because both loading precision and recovery discipline matter.',
      bestFor: [
        'Intermediate or advanced strength/powerbuilding lifters.',
        'Lifters with enough suitable variations and at least 72 hours between matching Max Effort patterns.',
      ],
      how: [
        'Max Effort works up to a controlled heavy 1–3 rep top set.',
        'Dynamic Effort is explicitly labelled speed work, such as 8 × 3 with short rests.',
        'The app validates pool size, weekly Max Effort count and recovery gaps.',
      ],
      rotation: [
        'Main Max Effort variations rotate regularly to manage accommodation.',
        'Dynamic work is method-specific and never silently added to a linear beginner plan.',
      ],
      weeks: [
        ProgramMethodGuideWeek(
          1,
          'Max Effort A',
          'Heavy top set plus controlled supplemental work.',
        ),
        ProgramMethodGuideWeek(
          2,
          'Max Effort B',
          'Rotate the main variation; retain the movement pattern.',
        ),
        ProgramMethodGuideWeek(
          3,
          'Dynamic',
          'Speed-focused work with clearly shown set and rest targets.',
        ),
        ProgramMethodGuideWeek(
          4,
          'Deload',
          'Reduce fatigue before another rotation cycle.',
        ),
        ProgramMethodGuideWeek(
          5,
          'Max Effort A',
          'Heavy top set plus controlled supplemental work, next rotation.',
        ),
        ProgramMethodGuideWeek(
          6,
          'Max Effort B',
          'Rotate the main variation again; retain the movement pattern.',
        ),
        ProgramMethodGuideWeek(
          7,
          'Dynamic',
          'Speed-focused work with clearly shown set and rest targets.',
        ),
        ProgramMethodGuideWeek(
          8,
          'Deload',
          'Reduce fatigue again before the next rotation cycle.',
        ),
      ],
    ),
    PeriodizationModel.none => const ProgramMethodGuide(
      summary: 'Keep loading flat and control changes yourself.',
      introduction:
          'No periodization gives you a stable template without automatic weekly load or volume changes.',
      bestFor: ['Short maintenance blocks or experienced manual programming.'],
      how: ['Herculex keeps the selected exercises and set structure stable.'],
      rotation: [
        'Any rotation shown in review follows your selected interval.',
      ],
      // D-06: `none` has no periodization phases to map onto 8 weeks, so its
      // example stays short by deliberate choice rather than a silent default.
      weeks: [
        ProgramMethodGuideWeek(
          1,
          'Stable',
          'Use the same targets until you choose to progress.',
        ),
        ProgramMethodGuideWeek(
          2,
          'Stable',
          'Review performance and adjust manually if needed.',
        ),
      ],
    ),
  };
}

class ProgramMethodGuideWeek {
  const ProgramMethodGuideWeek(this.number, this.title, this.description);

  final int number;
  final String title;
  final String description;
}
