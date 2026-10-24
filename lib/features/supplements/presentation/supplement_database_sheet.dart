import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/nutrition/domain/nutrient_definitions.dart';
import 'package:herculex/features/supplements/application/supplement_providers.dart';
import 'package:herculex/features/supplements/data/supplement_catalogue_repository.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/presentation/supplement_scan_flow.dart';

const _accent = Color(0xFF9B59B6);

/// Modal bottom sheet allowing the user to search and pick from the
/// supplement database (built-in + locally saved + scanned supplements),
/// or launch the unified barcode → AI scan flow.
class SupplementDatabaseSheet extends ConsumerStatefulWidget {
  const SupplementDatabaseSheet({super.key});

  static Future<SupplementLookupResult?> show(BuildContext context) {
    return showModalBottomSheet<SupplementLookupResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SupplementDatabaseSheet(),
    );
  }

  @override
  ConsumerState<SupplementDatabaseSheet> createState() =>
      _SupplementDatabaseSheetState();
}

class _SupplementDatabaseSheetState
    extends ConsumerState<SupplementDatabaseSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _selectedCategory = 'All';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanFromDatabase() async {
    Haptics.selection();
    final res = await scanAndResolveSupplement(context, ref);
    if (res != null && mounted) {
      Navigator.of(context).pop(res);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final entries = ref
        .watch(supplementCatalogueRepositoryProvider)
        .search(_query, category: _selectedCategory);
    final nutrientDefs = {for (final d in trackedNutrients) d.id: d};

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
        decoration: BoxDecoration(
          color:
              theme.bottomSheetTheme.backgroundColor ??
              theme.colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.library_books_outlined,
                      color: _accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Supplement Database',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Pick from database or scan barcode / AI',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Search bar + Unified Scan button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText:
                            'Search supplements (Creatine, Vitamin D, Mg...)',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _scanFromDatabase,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text('Scan'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Category chips
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: supplementCatalogueCategories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = supplementCatalogueCategories[index];
                  final selected = cat == _selectedCategory;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: selected,
                    onSelected: (_) {
                      Haptics.selection();
                      setState(() => _selectedCategory = cat);
                    },
                    selectedColor: _accent.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: selected ? _accent : AppColors.onSurface,
                    ),
                    side: BorderSide(
                      color: selected
                          ? _accent
                          : AppColors.outlineVariant.withValues(alpha: 0.4),
                    ),
                    shape: const StadiumBorder(),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),

            // Results list
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_outlined,
                              size: 42,
                              color: AppColors.secondary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'No results in database for "$_query".',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Scan the barcode or package and Herculex AI will analyze the supplement and save it to the database.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.secondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _scanFromDatabase,
                              icon: const Icon(Icons.qr_code_scanner, size: 18),
                              label: const Text('Scan barcode / AI analysis'),
                              style: FilledButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.white,
                                shape: const StadiumBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = entries[index];
                        return _CatalogueRow(
                          entry: item,
                          nutrientDefs: nutrientDefs,
                          onSelect: () {
                            Haptics.selection();
                            Navigator.of(context).pop(
                              SupplementLookupResult(
                                supplement: item.toSupplement(),
                                sourceLabel: item.category == 'Saved'
                                    ? 'My Supplement Database'
                                    : 'Herculex Supplement Database',
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogueRow extends StatelessWidget {
  final SupplementCatalogueEntry entry;
  final Map<String, NutrientDefinition> nutrientDefs;
  final VoidCallback onSelect;

  const _CatalogueRow({
    required this.entry,
    required this.nutrientDefs,
    required this.onSelect,
  });

  String? get _doseText {
    if (entry.doseAmount == null || entry.doseUnit == null) return null;
    final a = entry.doseAmount!;
    final fmt = a.truncateToDouble() == a
        ? a.toStringAsFixed(0)
        : a.toStringAsFixed(1);
    return '$fmt ${entry.doseUnit}';
  }

  String? get _scheduleText {
    switch (entry.schedule) {
      case SupplementSchedule.postWorkout:
        return 'Post-workout';
      case SupplementSchedule.time:
        return entry.timeHHMM ?? 'Daily';
      case SupplementSchedule.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dose = _doseText;
    final schedule = _scheduleText;

    final nutrientTags = <String>[];
    entry.nutrients.forEach((id, val) {
      final def = nutrientDefs[id];
      final label = def?.label ?? id;
      final unit = def?.unit ?? '';
      final fmt = val.truncateToDouble() == val
          ? val.toStringAsFixed(0)
          : val.toStringAsFixed(1);
      nutrientTags.add('$label $fmt $unit'.trim());
    });

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.medication_outlined,
                size: 18,
                color: _accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (dose != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            dose,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (entry.brand != null && entry.brand!.isNotEmpty)
                        entry.brand!,
                      entry.category,
                      ?schedule,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                  if (entry.description != null &&
                      entry.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                        fontSize: 11.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (nutrientTags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: nutrientTags.take(4).map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.outlineVariant.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.secondary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.add_circle_outline, size: 20, color: _accent),
          ],
        ),
      ),
    );
  }
}
