part of '../block_builder_view.dart';

Widget _timeSavingOptionsFor({
  required ThemeData theme,
  required TimeSavingTechnique technique,
  required ExperienceLevel experience,
  required int minutes,
  required ValueChanged<TimeSavingTechnique> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preferred time-saving approach',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in TimeSavingTechnique.values)
              ChoiceChip(
                label: Text(option.label),
                selected: technique == option,
                onSelected: (_) => onChanged(option),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          experience == ExperienceLevel.novice
              ? 'While you build experience, keep controlled straight sets and a technique buffer.'
              : minutes > 45 && technique == TimeSavingTechnique.automatic
              ? 'Herculex uses these methods when the planned session exceeds your target time.'
              : 'Selected methods apply to eligible isolation work. A light warm-up is separate from the two working sets. Heavy and technical lifts keep their own progression.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    ),
  );
}
