import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import '../../../widgets/premium_button.dart';
import '../domain/preset_program.dart';
import '../domain/program_csv.dart';
import '../domain/periodization.dart';
import 'marketplace_providers.dart';
import 'programs_providers.dart';

class ProgramPreviewView extends ConsumerStatefulWidget {
  final PresetProgramMeta meta;

  const ProgramPreviewView({super.key, required this.meta});

  @override
  ConsumerState<ProgramPreviewView> createState() => _ProgramPreviewViewState();
}

class _ProgramPreviewViewState extends ConsumerState<ProgramPreviewView> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final docAsync = ref.watch(presetProgramDocumentProvider(widget.meta));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.meta.name, style: theme.textTheme.titleMedium),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: docAsync.when(
          data: (doc) => _buildBody(theme, doc),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ProgramCsvDocument doc) {
    final model = PeriodizationModel.fromId(doc.periodizationModel);
    final weekIndices = doc.rows.map((r) => r.weekIndex).toSet().toList()..sort();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Text(widget.meta.description, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.secondary)),
              const SizedBox(height: 8),
              Text(
                '${doc.weeks} weeks · ${model.label} periodization',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              for (final weekIndex in weekIndices) _buildWeekSection(theme, doc, weekIndex),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: PremiumButton(
            text: _importing ? 'Adding…' : 'Add to my blocks',
            icon: Icons.add_circle_outline_rounded,
            onTap: _importing ? () {} : () => _onAddToMyBlocks(context, doc),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekSection(ThemeData theme, ProgramCsvDocument doc, int weekIndex) {
    final weekRows = doc.rows.where((r) => r.weekIndex == weekIndex).toList();
    final dayKeys = <(int, String)>[];
    for (final row in weekRows) {
      final key = (row.dayOfWeek, row.dayName);
      if (!dayKeys.contains(key)) dayKeys.add(key);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Week ${weekIndex + 1}', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          for (final dayKey in dayKeys) _buildDay(theme, weekRows, dayKey),
        ],
      ),
    );
  }

  Widget _buildDay(ThemeData theme, List<ProgramCsvRow> weekRows, (int, String) dayKey) {
    final rows = weekRows.where((r) => (r.dayOfWeek, r.dayName) == dayKey).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dayKey.$2, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text(
                '${row.exerciseName} · ${row.sets}×${_repsLabel(row)}'
                '${row.rpe != null ? ' @ RPE ${row.rpe}' : ''}'
                '${row.percentOf1Rm != null ? ' @ ${row.percentOf1Rm!.toStringAsFixed(0)}% 1RM' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
              ),
            ),
        ],
      ),
    );
  }

  String _repsLabel(ProgramCsvRow row) {
    if (row.repsMin == null && row.repsMax == null) return '?';
    if (row.repsMin == row.repsMax || row.repsMax == null) return '${row.repsMin}';
    return '${row.repsMin}-${row.repsMax}';
  }

  Future<void> _onAddToMyBlocks(BuildContext context, ProgramCsvDocument doc) async {
    final programsRepo = ref.read(programsRepositoryProvider);
    final existing = await programsRepo.getActivePrograms();
    final duplicate = existing.any((p) => p.name == doc.name);

    if (!context.mounted) return;
    if (duplicate) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('You already have this program'),
          content: const Text('Import it again? This will create a second copy.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import again')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (!context.mounted) return;
    final now = DateTime.now();
    final nextMonday = now.add(Duration(days: (8 - now.weekday) % 7 == 0 ? 7 : (8 - now.weekday) % 7));
    final startDate = await showDatePicker(
      context: context,
      initialDate: nextMonday,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (startDate == null) return;

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add to my blocks?'),
        content: const Text(
          'This will replace your currently planned schedule with this program, starting on the date you picked.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _importing = true);
    try {
      final csv = await ref.read(presetCatalogRepositoryProvider).loadCsv(widget.meta);
      final programId = await ref.read(programCsvIoProvider).importProgram(
            csv,
            createdByUser: false,
            description: widget.meta.description,
          );
      // Activate before materializing so the Blocks tab lands on the block the
      // user just imported rather than an empty state.
      await programsRepo.setActiveProgram(programId);
      await programsRepo.materializeProgram(programId, startDate);
      ref.invalidate(activeProgramsProvider);

      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.meta.name} added to your training blocks'),
          backgroundColor: AppColors.primary,
        ),
      );
    } on ProgramCsvFormatException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}
