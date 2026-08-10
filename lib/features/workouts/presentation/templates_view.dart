import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import 'template_builder_view.dart';
import 'workouts_providers.dart';

class TemplatesView extends ConsumerWidget {
  const TemplatesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final foldersAsync = ref.watch(workoutFoldersProvider);
    final unfiledAsync = ref.watch(workoutTemplatesProvider(null));

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _IconPill(
              icon: Icons.create_new_folder_outlined,
              label: 'Folder',
              onTap: () => _createFolder(context, ref),
            ),
            const SizedBox(width: 10),
            _IconPill(
              icon: Icons.add,
              label: 'Template',
              onTap: () => TemplateBuilderView.show(context),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Folders
        foldersAsync.when(
          data: (folders) => folders.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FOLDERS',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: AppColors.secondary, letterSpacing: 1.2)),
                    const SizedBox(height: 10),
                    for (final f in folders)
                      _FolderTile(folder: f),
                    const SizedBox(height: 24),
                  ],
                ),
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
        ),

        // Unfiled templates
        unfiledAsync.when(
          data: (templates) {
            if (templates.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NO FOLDER',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.secondary, letterSpacing: 1.2)),
                const SizedBox(height: 10),
                for (final t in templates)
                  _TemplateTile(template: t),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
        ),

        // Empty state
        if (foldersAsync.asData?.value.isEmpty == true &&
            unfiledAsync.asData?.value.isEmpty == true)
          _EmptyState(onCreateTemplate: () => TemplateBuilderView.show(context)),
      ],
    );
  }

  void _createFolder(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateFolderSheet(ref: ref),
    );
  }
}

// ── Folder tile ──────────────────────────────────────────────────────────────

class _FolderTile extends ConsumerWidget {
  final WorkoutFolderData folder;
  const _FolderTile({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(workoutTemplatesProvider(folder.id));
    final count = templatesAsync.asData?.value.length ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => _FolderDetailView(folder: folder)),
        ),
        onLongPress: () => _showFolderMenu(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(folder.emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(folder.name,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      count == 1 ? '1 template' : '$count templates',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.secondary),
            ],
          ),
        ),
      ),
    );
  }

  void _showFolderMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FolderMenuSheet(folder: folder, ref: ref),
    );
  }
}

// ── Template tile ────────────────────────────────────────────────────────────

class _TemplateTile extends ConsumerWidget {
  final WorkoutTemplateData template;
  const _TemplateTile({required this.template});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final exercisesAsync = ref.watch(templateExercisesProvider(template.id));
    final count = exercisesAsync.asData?.value.length ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _startOrEdit(context, ref),
        onLongPress: () => _showMenu(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.fitness_center, size: 22, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.name,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      count == 1 ? '1 exercise' : '$count exercises',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Start',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startOrEdit(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TemplateActionSheet(template: template, ref: ref),
    );
  }

  void _showMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TemplateMenuSheet(template: template, ref: ref),
    );
  }
}

// ── Folder detail view ───────────────────────────────────────────────────────

class _FolderDetailView extends ConsumerWidget {
  final WorkoutFolderData folder;
  const _FolderDetailView({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(workoutTemplatesProvider(folder.id));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Text(folder.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(folder.name,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add_circle, color: AppColors.primary),
            onPressed: () => TemplateBuilderView.show(context, initialFolderId: folder.id),
          ),
        ],
      ),
      body: templatesAsync.when(
        data: (templates) => templates.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open, size: 48, color: AppColors.primary),
                    const SizedBox(height: 12),
                    Text('No templates yet',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Tap + to add a template to this folder',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
                itemCount: templates.length,
                itemBuilder: (_, i) => _TemplateTile(template: templates[i]),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

// ── Action / menu sheets ─────────────────────────────────────────────────────

class _TemplateActionSheet extends StatelessWidget {
  final WorkoutTemplateData template;
  final WidgetRef ref;
  const _TemplateActionSheet({required this.template, required this.ref});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.bottomSheetTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(template.name,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _SheetAction(
            icon: Icons.play_arrow_rounded,
            label: 'Start Workout',
            color: AppColors.primary,
            onTap: () async {
              Navigator.pop(context);
              final repo = ref.read(templatesRepositoryProvider);
              await repo.startSessionFromTemplate(template.id);
            },
          ),
          const SizedBox(height: 8),
          _SheetAction(
            icon: Icons.edit_outlined,
            label: 'Edit Template',
            onTap: () {
              Navigator.pop(context);
              TemplateBuilderView.show(context, existing: template);
            },
          ),
        ],
      ),
    );
  }
}

class _TemplateMenuSheet extends StatelessWidget {
  final WorkoutTemplateData template;
  final WidgetRef ref;
  const _TemplateMenuSheet({required this.template, required this.ref});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.bottomSheetTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          _SheetAction(
            icon: Icons.edit_outlined,
            label: 'Edit',
            onTap: () {
              Navigator.pop(context);
              TemplateBuilderView.show(context, existing: template);
            },
          ),
          const SizedBox(height: 8),
          _SheetAction(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: Colors.redAccent,
            onTap: () async {
              Navigator.pop(context);
              await ref.read(templatesRepositoryProvider).deleteTemplate(template.id);
            },
          ),
        ],
      ),
    );
  }
}

class _FolderMenuSheet extends StatelessWidget {
  final WorkoutFolderData folder;
  final WidgetRef ref;
  const _FolderMenuSheet({required this.folder, required this.ref});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.bottomSheetTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text('${folder.emoji} ${folder.name}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _SheetAction(
            icon: Icons.delete_outline,
            label: 'Delete folder',
            color: Colors.redAccent,
            onTap: () async {
              Navigator.pop(context);
              await ref.read(templatesRepositoryProvider).deleteFolder(folder.id);
            },
          ),
        ],
      ),
    );
  }
}

class _CreateFolderSheet extends StatefulWidget {
  final WidgetRef ref;
  const _CreateFolderSheet({required this.ref});

  @override
  State<_CreateFolderSheet> createState() => _CreateFolderSheetState();
}

class _CreateFolderSheetState extends State<_CreateFolderSheet> {
  final _name = TextEditingController();
  String _emoji = '💪';
  static const _emojis = ['💪', '🏋️', '🔥', '⚡', '🦵', '🏃', '🧘', '🎯', '🥇', '📋'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('New Folder', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: _emojis.map((e) => GestureDetector(
                onTap: () => setState(() => _emoji = e),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _emoji == e ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _emoji == e ? AppColors.primary : Colors.transparent,
                    ),
                  ),
                  child: Center(child: Text(e, style: const TextStyle(fontSize: 20))),
                ),
              )).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Folder name',
                filled: true,
                fillColor: AppColors.surfaceContainer,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  final name = _name.text.trim();
                  if (name.isEmpty) return;
                  await widget.ref.read(templatesRepositoryProvider).createFolder(name: name, emoji: _emoji);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Create Folder', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTemplate;
  const _EmptyState({required this.onCreateTemplate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(Icons.folder_copy_outlined, size: 48, color: AppColors.primary),
            const SizedBox(height: 16),
            Text('No templates yet',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Save your go-to workouts as templates and organise them into folders.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create first template'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: onCreateTemplate,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ───────────────────────────────────────────────────────────

class _IconPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _IconPill({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _SheetAction({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(label, style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
