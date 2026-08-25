import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/tokens/tokens.dart';
import '../../../../ui/ui.dart';
import '../../data/joint_pain_repository.dart';
import '../../domain/joint_model.dart';
import '../recovery_providers.dart';

/// Lets the user flag which joints hurt. Tapping a joint opens a sheet to
/// set severity, add a note, or mark it resolved — writes go straight
/// through [JointPainRepository], so the pill's selected state updates as
/// soon as the write lands.
class JointPainSelector extends ConsumerWidget {
  const JointPainSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final statuses = ref.watch(jointPainStatusesProvider);

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'JOINT PAIN',
            style: theme.textTheme.labelSmall?.copyWith(
              color: hx.secondary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: HxSpace.x1),
          Text(
            'Flag a joint to check whether nearby muscle training or cardio '
            'load has been elevated the last couple of months.',
            style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
          ),
          const SizedBox(height: HxSpace.x3),
          statuses.when(
            data: (map) => Wrap(
              spacing: HxSpace.x2,
              runSpacing: HxSpace.x2,
              children: [
                for (final joint in JointModel.joints)
                  HxTextPill(
                    label: joint,
                    selected: map[joint]?.isFlagged ?? false,
                    accent: hx.danger,
                    onTap: () => _openSheet(context, joint, map[joint]),
                  ),
              ],
            ),
            loading: () => const SizedBox(
              height: 32,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Text('Error: $e', style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  void _openSheet(BuildContext context, String joint, JointPainStatus? current) {
    HxSheet.show(
      context,
      builder: (_) => _JointPainSheet(joint: joint, current: current),
    );
  }
}

class _JointPainSheet extends ConsumerStatefulWidget {
  const _JointPainSheet({required this.joint, required this.current});

  final String joint;
  final JointPainStatus? current;

  @override
  ConsumerState<_JointPainSheet> createState() => _JointPainSheetState();
}

class _JointPainSheetState extends ConsumerState<_JointPainSheet> {
  static const _severityLabels = {1: 'Mild', 2: 'Moderate', 3: 'Severe'};

  late int _severity = widget.current?.severity ?? 0;
  late final _noteController = TextEditingController(text: widget.current?.note);

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final wasFlagged = widget.current?.isFlagged ?? false;

    return HxSheet(
      title: widget.joint,
      subtitle: 'How does it feel?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: HxSpace.x2,
            children: [
              for (final entry in _severityLabels.entries)
                HxTextPill(
                  label: entry.value,
                  selected: _severity == entry.key,
                  accent: hx.danger,
                  onTap: () => setState(() => _severity = entry.key),
                ),
            ],
          ),
          const SizedBox(height: HxSpace.x4),
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Optional note (e.g. sharp on lockout)',
            ),
          ),
          const SizedBox(height: HxSpace.x4),
          Row(
            children: [
              if (wasFlagged) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _save(0),
                    child: const Text('Mark as resolved'),
                  ),
                ),
                const SizedBox(width: HxSpace.x3),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _severity == 0 ? null : () => _save(_severity),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _save(int severity) {
    final note = _noteController.text.trim();
    ref.read(jointPainRepositoryProvider).setStatus(
          joint: widget.joint,
          severity: severity,
          note: note.isEmpty ? null : note,
        );
    Navigator.of(context).pop();
  }
}
