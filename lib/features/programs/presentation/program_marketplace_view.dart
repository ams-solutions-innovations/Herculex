import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/programs/domain/preset_program.dart';
import 'package:herculex/features/programs/presentation/marketplace_providers.dart';
import 'package:herculex/features/programs/presentation/program_preview_view.dart';

const _levelChips = <String>['Beginner', 'Intermediate', 'Advanced'];
const _goalChips = <String>['Strength', 'Hypertrophy', 'General'];

class ProgramMarketplaceView extends ConsumerStatefulWidget {
  const ProgramMarketplaceView({super.key});

  @override
  ConsumerState<ProgramMarketplaceView> createState() =>
      _ProgramMarketplaceViewState();
}

class _ProgramMarketplaceViewState
    extends ConsumerState<ProgramMarketplaceView> {
  String _query = '';
  String? _level;
  String? _goal;
  final _ctrl = TextEditingController();
  Timer? _debounce;

  static const _debounceDelay = Duration(milliseconds: 180);

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.isEmpty) {
      setState(() => _query = '');
      return;
    }
    _debounce = Timer(_debounceDelay, () {
      if (mounted) setState(() => _query = value);
    });
  }

  List<PresetProgramMeta> _filter(List<PresetProgramMeta> programs) {
    final query = _query.trim().toLowerCase();
    return programs.where((p) {
      if (query.isNotEmpty &&
          !p.name.toLowerCase().contains(query) &&
          !p.description.toLowerCase().contains(query)) {
        return false;
      }
      if (_level != null && p.level != _level!.toLowerCase()) return false;
      if (_goal != null && p.goal != _goal!.toLowerCase()) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalogAsync = ref.watch(presetCatalogProvider);

    return HxScreenShell(
      title: 'Search Programs',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: _ctrl,
            onChanged: _onQueryChanged,
            decoration: InputDecoration(
              hintText: 'Search programs…',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: AppColors.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final level in _levelChips)
                _FilterChip(
                  label: level,
                  selected: _level == level,
                  onTap: () =>
                      setState(() => _level = _level == level ? null : level),
                ),
              const SizedBox(width: 8),
              Container(width: 1, color: AppColors.outlineVariant),
              const SizedBox(width: 8),
              for (final goal in _goalChips)
                _FilterChip(
                  label: goal,
                  selected: _goal == goal,
                  onTap: () =>
                      setState(() => _goal = _goal == goal ? null : goal),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        catalogAsync.when(
          data: (programs) {
            final filtered = _filter(programs);
            if (filtered.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No programs match your search.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < filtered.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _ProgramCard(meta: filtered[i]),
                ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.outlineVariant,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  final PresetProgramMeta meta;

  const _ProgramCard({required this.meta});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProgramPreviewView(meta: meta)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              meta.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              meta.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.secondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Text(
              '${meta.weeks} weeks · ${meta.daysPerWeek} days/wk · '
              '${_capitalize(meta.goal)} · ${_capitalize(meta.level)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
