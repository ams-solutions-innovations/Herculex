import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/workouts/presentation/widgets/set_type_menu.dart';

/// "What is a drop set, a myo-rep set, rest-pause…?" as a screen of its own,
/// reachable from the exercise library, Profile and Settings — not only from
/// the set-type picker in the middle of a workout. Same content as the
/// picker's guide sheet ([SetTypesGuideSheet]); on a wide window the cards sit
/// in two columns.
class SetTypesGuideView extends StatefulWidget {
  const SetTypesGuideView({super.key, this.highlight});

  /// A [SetTypeInfo.id] to put first and outline, from `?type=<id>`.
  final String? highlight;

  @override
  State<SetTypesGuideView> createState() => _SetTypesGuideViewState();
}

class _SetTypesGuideViewState extends State<SetTypesGuideView> {
  final _searchCtrl = TextEditingController();
  SetTypeCategory? _category;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<SetTypeInfo> _filtered() {
    final query = _query.trim().toLowerCase();
    final items = SetTypeInfo.all.where((info) {
      if (_category != null && info.category != _category) return false;
      if (query.isEmpty) return true;
      return info.label.toLowerCase().contains(query) ||
          info.badge.toLowerCase().contains(query) ||
          info.shortDescription.toLowerCase().contains(query) ||
          info.fullExplanation.toLowerCase().contains(query);
    }).toList();
    final highlight = widget.highlight;
    if (highlight != null) {
      // Arriving with ?type=drop: that card leads, so it is never off-screen.
      items.sort((a, b) {
        final aHit = a.id == highlight ? 0 : 1;
        final bHit = b.id == highlight ? 0 : 1;
        return aHit.compareTo(bHit);
      });
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final items = _filtered();

    return HxScreenShell(
      title: 'Training Techniques',
      titleIcon: Icons.menu_book_rounded,
      maxContentWidth: HxBreakpoints.wideMax,
      children: [
        Text(
          'What a drop set, myo reps or rest-pause actually is, how to do it, '
          'and how Herculex counts it towards your volume and recovery.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: hx.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search a technique (drop set, myo reps, AMRAP…)',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CategoryChip(
              label: 'All (${SetTypeInfo.all.length})',
              selected: _category == null,
              onTap: () => setState(() => _category = null),
            ),
            for (final category in SetTypeCategory.values)
              _CategoryChip(
                label: category.title,
                selected: _category == category,
                onTap: () => setState(() => _category = category),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                'No technique matches "${_query.trim()}"',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: hx.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          HxMasonry(
            minColumnWidth: 440,
            maxColumns: 2,
            gap: 16,
            children: [
              for (final info in items)
                SetTypeGuideCard(
                  key: ValueKey(info.id),
                  info: info,
                  isHighlighted: info.id == widget.highlight,
                ),
            ],
          ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : AppColors.secondary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          fontSize: 13,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceContainer,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onSelected: (_) => onTap(),
    );
  }
}
