import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../workouts/presentation/exercise_picker_sheet.dart';
import '../../../app/providers.dart';
import 'programs_providers.dart';

/// Create or edit a rotation pool. Pass [existing] to edit.
class RotationPoolSheet extends ConsumerStatefulWidget {
  final ExerciseRotationData? existing;

  const RotationPoolSheet({super.key, this.existing});

  static Future<void> show(BuildContext context, {ExerciseRotationData? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RotationPoolSheet(existing: existing),
    );
  }

  @override
  ConsumerState<RotationPoolSheet> createState() => _RotationPoolSheetState();
}

class _RotationPoolSheetState extends ConsumerState<RotationPoolSheet> {
  late final TextEditingController _name;
  int _rotateEveryWeeks = 2;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    if (widget.existing != null) {
      _rotateEveryWeeks = widget.existing!.rotateEveryWeeks;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Haptics.medium();
    setState(() => _saving = true);
    final repo = ref.read(rotationsRepositoryProvider);
    if (widget.existing == null) {
      await repo.createRotation(
        name: name,
        rotateEveryWeeks: _rotateEveryWeeks,
        exerciseIds: const [],
      );
    } else {
      await repo.updateRotation(
        widget.existing!.id,
        name: name,
        rotateEveryWeeks: _rotateEveryWeeks,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = widget.existing != null
        ? ref.watch(rotationMembersProvider(widget.existing!.id))
        : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.existing == null ? 'New Rotation Pool' : 'Edit Pool',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('Group exercises that rotate each block week.',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
            const SizedBox(height: 24),
            _label(theme, 'NAME'),
            const SizedBox(height: 6),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                hintText: 'e.g. Max-Effort Squat',
                filled: true,
                fillColor: AppColors.surfaceContainer,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _label(theme, 'ROTATE EVERY N WEEKS'),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final n in [1, 2, 3, 4])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () {
                          Haptics.selection();
                          setState(() => _rotateEveryWeeks = n);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _rotateEveryWeeks == n
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : AppColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _rotateEveryWeeks == n
                                  ? AppColors.primary
                                  : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            '$n',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _rotateEveryWeeks == n
                                  ? AppColors.primary
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (members != null) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _label(theme, 'EXERCISES IN POOL')),
                  TextButton.icon(
                    onPressed: () async {
                      final results = await ExercisePickerSheet.show(context);
                      if (results != null && results.isNotEmpty) {
                        for (final ex in results) {
                          await ref
                              .read(rotationsRepositoryProvider)
                              .addMember(widget.existing!.id, ex.exercise.id);
                        }
                      }
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              members.when(
                data: (rows) => rows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('No exercises yet.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.secondary)),
                      )
                    : Column(
                        children: rows
                            .map((m) => _MemberTile(
                                  member: m,
                                  onRemove: () => ref
                                      .read(rotationsRepositoryProvider)
                                      .removeMember(m.id),
                                ))
                            .toList(),
                      ),
                loading: () => const SizedBox(height: 40, child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Text('Error: $e'),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String text) => Text(
        text,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: AppColors.secondary, letterSpacing: 0.8, fontWeight: FontWeight.w600),
      );
}

class _MemberTile extends ConsumerWidget {
  final RotationMemberData member;
  final VoidCallback onRemove;
  const _MemberTile({required this.member, required this.onRemove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.watch(appDatabaseProvider);

    return FutureBuilder<ExerciseCatalogData?>(
      future: (db.select(db.exerciseCatalog)
            ..where((t) => t.id.equals(member.exerciseId)))
          .getSingleOrNull(),
      builder: (context, snap) {
        final name = snap.data?.name ?? '…';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(name, style: theme.textTheme.bodyMedium),
          trailing: IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
            onPressed: onRemove,
          ),
        );
      },
    );
  }
}
