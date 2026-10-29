import 'package:flutter/material.dart';
import 'package:herculex/features/workouts/domain/workout_action_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/application/exercise_history_providers.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/data/exercise_history_repository.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:intl/intl.dart';

class ExerciseHistoryTransferSheet extends ConsumerStatefulWidget {
  const ExerciseHistoryTransferSheet({super.key, required this.source});
  final ExerciseCatalogData source;
  static Future<void> show(BuildContext context, ExerciseCatalogData source) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ExerciseHistoryTransferSheet(source: source),
      );
  @override
  ConsumerState<ExerciseHistoryTransferSheet> createState() => _TransferState();
}

class _TransferState extends ConsumerState<ExerciseHistoryTransferSheet> {
  List<ExerciseHistoryEntry>? entries;
  final selected = <int>{};
  ExerciseCatalogData? target;
  String? equipment, error;
  String query = '';
  ExerciseHistoryPreview? preview;
  bool busy = false;
  int? transferredId, previousTransfer;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await ref
          .read(exerciseHistoryRepositoryProvider)
          .entries(widget.source.id);
      final previous = await ref
          .read(exerciseHistoryRepositoryProvider)
          .lastTransfer(widget.source.id);
      if (mounted)
        setState(() {
          previousTransfer = previous?.id;
          entries = loaded;
          selected.addAll(loaded.map((e) => e.exercise.id));
        });
    } catch (e) {
      if (mounted) setState(() => error = workoutActionMessage(e));
    }
  }

  Future<void> _review() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await ref
          .read(exerciseHistoryRepositoryProvider)
          .preview(
            sourceId: widget.source.id,
            targetId: target!.id,
            entryIds: selected,
            equipment: equipment,
          );
      if (mounted) setState(() => preview = value);
    } catch (e) {
      if (mounted) setState(() => error = workoutActionMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _transfer() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = await ref
          .read(exerciseHistoryRepositoryProvider)
          .transfer(preview!);
      if (mounted) setState(() => transferredId = id);
    } catch (e) {
      if (mounted)
        setState(() {
          error = workoutActionMessage(e);
          preview = null;
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog =
        ref
            .watch(exerciseCatalogProvider(const ExerciseCatalogFilter()))
            .valueOrNull ??
        [];
    final repo = ref.read(exerciseHistoryRepositoryProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .9,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Transfer history',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (previousTransfer != null && transferredId == null)
              TextButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('Undo last history transfer'),
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await repo.undo(previousTransfer!);
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (mounted)
                            setState(() => error = workoutActionMessage(e));
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (transferredId != null) ...[
              Text(
                '${preview!.setCount} sets moved to ${preview!.target.name}.',
              ),
              const Text(
                'The original exercises and your program are still available.',
              ),
              FilledButton.tonal(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await repo.undo(transferredId!);
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (mounted)
                            setState(() => error = workoutActionMessage(e));
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('Undo transfer'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ] else if (preview != null) ...[
              Text(
                '${preview!.source.name} → ${preview!.target.name}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${preview!.entries.map((e) => e.session.id).toSet().length} workouts · ${preview!.entries.length} entries · ${preview!.setCount} sets',
              ),
              Text(
                'Equipment: ${equipment == null ? 'keep recorded equipment' : equipmentVariantLabel(equipment!)}',
              ),
              const Text(
                'Recorded results keep their values. Equipment changes clear incompatible machine setup notes from the moved entries; the undo record retains them.',
              ),
              for (final e in preview!.entries)
                ListTile(
                  title: Text(e.session.name ?? 'Workout'),
                  subtitle: Text(
                    '${DateFormat.yMMMd().format(e.session.startedAt)} · ${e.setCount} sets',
                  ),
                ),
              FilledButton(
                onPressed: busy ? null : _transfer,
                child: Text(busy ? 'Moving…' : 'Confirm transfer'),
              ),
              TextButton(
                onPressed: busy ? null : () => setState(() => preview = null),
                child: const Text('Back'),
              ),
            ] else ...[
              Text(
                'Move incorrectly recorded entries from ${widget.source.name} to the correct exercise.',
              ),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Find destination exercise',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
              if (target != null)
                ListTile(
                  title: Text(target!.name),
                  leading: const Icon(Icons.check_circle),
                  trailing: IconButton(
                    onPressed: () => setState(() {
                      target = null;
                      equipment = null;
                    }),
                    icon: const Icon(Icons.clear),
                  ),
                ),
              if (target == null) ...[
                for (final e
                    in catalog
                        .where(
                          (e) =>
                              e.id != widget.source.id &&
                              e.name.toLowerCase().contains(
                                query.toLowerCase(),
                              ),
                        )
                        .take(30))
                  ListTile(
                    title: Text(e.name),
                    subtitle: Text(
                      repo.compatible(widget.source, e)
                          ? '${e.primaryMuscle} · ${equipmentVariantLabel(e.modality)}'
                          : 'Incompatible measurements or load accounting',
                    ),
                    enabled: repo.compatible(widget.source, e),
                    onTap: () => setState(() {
                      target = e;
                      equipment = null;
                    }),
                  ),
              ],
              if (target != null)
                DropdownButtonFormField<String>(
                  initialValue: equipment ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Recorded equipment',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Keep recorded equipment'),
                    ),
                    for (final v in equipmentVariantsFor(target!))
                      DropdownMenuItem(
                        value: v,
                        child: Text(equipmentVariantLabel(v)),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => equipment = v == '' ? null : v),
                ),
              const SizedBox(height: 16),
              if (entries == null && error == null)
                const Center(child: CircularProgressIndicator()),
              if (entries?.isEmpty == true)
                const Text('No completed history to transfer.'),
              if (entries?.isNotEmpty == true) ...[
                CheckboxListTile(
                  title: const Text('All history'),
                  value: selected.length == entries!.length,
                  onChanged: (v) => setState(() {
                    selected.clear();
                    if (v == true)
                      selected.addAll(entries!.map((e) => e.exercise.id));
                  }),
                ),
                for (final e in entries!)
                  CheckboxListTile(
                    title: Text(e.session.name ?? 'Workout'),
                    subtitle: Text(
                      '${DateFormat.yMMMd().format(e.session.startedAt)} · entry ${e.exercise.orderIndex + 1} · ${e.setCount} sets · ${equipmentVariantLabel(e.exercise.equipmentVariant ?? widget.source.modality)}',
                    ),
                    value: selected.contains(e.exercise.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        selected.add(e.exercise.id);
                      } else {
                        selected.remove(e.exercise.id);
                      }
                    }),
                  ),
              ],
              FilledButton(
                onPressed: busy || target == null || selected.isEmpty
                    ? null
                    : _review,
                child: Text(busy ? 'Checking…' : 'Review transfer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
