import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/colors.dart';

/// Modal dialog allowing the user to manually set or edit a workout's total duration in minutes.
class DurationPickerDialog extends StatefulWidget {
  final int initialMinutes;

  const DurationPickerDialog({
    super.key,
    required this.initialMinutes,
  });

  static Future<int?> show(BuildContext context, {int initialMinutes = 45}) {
    return showDialog<int>(
      context: context,
      builder: (_) => DurationPickerDialog(initialMinutes: initialMinutes),
    );
  }

  @override
  State<DurationPickerDialog> createState() => _DurationPickerDialogState();
}

class _DurationPickerDialogState extends State<DurationPickerDialog> {
  late final TextEditingController _controller;
  int? _selectedMinutes;

  static const _presetOptions = [20, 30, 45, 60, 75, 90, 120];

  @override
  void initState() {
    super.initState();
    _selectedMinutes = widget.initialMinutes > 0 ? widget.initialMinutes : 45;
    _controller = TextEditingController(text: '$_selectedMinutes');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectPreset(int minutes) {
    setState(() {
      _selectedMinutes = minutes;
      _controller.text = '$minutes';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Set Workout Duration'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter total duration trained in minutes:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              autofocus: false,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Duration',
                suffixText: 'min',
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (val) {
                final parsed = int.tryParse(val.trim());
                setState(() => _selectedMinutes = parsed);
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Quick Select:',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _presetOptions.map((m) {
                final isSelected = _selectedMinutes == m;
                return ChoiceChip(
                  label: Text('${m}m'),
                  selected: isSelected,
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.primary : AppColors.onSurface,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (_) => _selectPreset(m),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final parsed = int.tryParse(_controller.text.trim());
            if (parsed != null && parsed > 0) {
              Navigator.pop(context, parsed);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
