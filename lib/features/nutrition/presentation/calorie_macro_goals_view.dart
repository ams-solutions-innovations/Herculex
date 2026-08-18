import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import '../../../theme/system_ui.dart';
import 'nutrition_providers.dart';
import 'nutrition_targets_view.dart';

class CalorieMacroGoalsView extends ConsumerWidget {
  const CalorieMacroGoalsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(baselineTargetsProvider);
    final customTargets = ref.watch(nutritionTargetsProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Text(
          'Calorie & Macro Goals',
          style: TextStyle(
            color: AppColors.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              size: 20, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        systemOverlayStyle: overlayStyleFor(context),
      ),
      body: ListView(
        children: [
          // ── Default Goal section ─────────────────────────────────────────
          const _SectionHeader('Default Goal'),
          const _Divider(),

          if (targets != null) ...[
            _CalorieRow(kcal: targets.kcal),
            const _Divider(),
            _MacroRow(
              label: 'Net Carbs',
              grams: targets.carbsG,
              pct: _pct(targets.carbsG * 4, targets.kcal),
            ),
            const _Divider(),
            _MacroRow(
              label: 'Protein',
              grams: targets.proteinG,
              pct: _pct(targets.proteinG * 4, targets.kcal),
            ),
            const _Divider(),
            _MacroRow(
              label: 'Fat',
              grams: targets.fatG,
              pct: _pct(targets.fatG * 9, targets.kcal),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Text(
                'Complete your profile (weight, height, age) to see '
                'calculated goals.',
                style: TextStyle(
                  color: AppColors.secondary,
                  fontSize: 14,
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // ── Set Daily Goals section ──────────────────────────────────────
          const _SectionHeader('Set Daily Goals'),
          const _Divider(),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Create custom goals for different days of the week',
              style: TextStyle(color: AppColors.secondary, fontSize: 14),
            ),
          ),

          // Custom target rows
          customTargets.when(
            data: (rows) => rows.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      for (final t in rows) ...[
                        _CustomTargetRow(
                          label: t.label,
                          kcal: t.kcal,
                          onDelete: () => ref
                              .read(nutritionRepositoryProvider)
                              .deleteTarget(t.id),
                        ),
                        const _Divider(),
                      ],
                    ],
                  ),
            loading: () => const SizedBox.shrink(),
            error: (e, st) => const SizedBox.shrink(),
          ),

          // Add Daily Goal
          InkWell(
            onTap: () => _showAddTargetSheet(context, ref),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Text(
                'Add Daily Goal',
                style: TextStyle(color: AppColors.primary, fontSize: 16),
              ),
            ),
          ),

          const _Divider(),

          // How we make recommendations
          GestureDetector(
            onTap: () => _showRecommendationsInfo(context),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: AppColors.secondary, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'How we make recommendations',
                    style: TextStyle(color: AppColors.secondary, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  static int _pct(int numeratorKcal, int totalKcal) {
    if (totalKcal == 0) return 0;
    return (numeratorKcal / totalKcal * 100).round();
  }

  /// The target editor is a full screen now (§5), not a bottom sheet.
  Future<void> _showAddTargetSheet(BuildContext context, WidgetRef ref) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TargetEditorView()),
    );
  }

  void _showRecommendationsInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'How we calculate goals',
          style: TextStyle(
              color: AppColors.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Calorie targets are calculated using the Mifflin-St Jeor BMR formula '
          'adjusted for your activity level and fitness goal.\n\n'
          'Protein: 1.8 g/kg bodyweight\n'
          'Fat: 27.5% of total calories\n'
          'Carbs: remaining calories',
          style: TextStyle(color: AppColors.secondary, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Got it',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

// ── Row widgets ───────────────────────────────────────────────────────────────

class _CalorieRow extends StatelessWidget {
  final int kcal;
  const _CalorieRow({required this.kcal});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Calories',
              style: TextStyle(color: AppColors.onSurface, fontSize: 16),
            ),
          ),
          Text(
            _fmtKcal(kcal),
            style: TextStyle(color: AppColors.primary, fontSize: 16),
          ),
        ],
      ),
    );
  }

  static String _fmtKcal(int v) => v
      .toString()
      .replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
}

class _MacroRow extends StatelessWidget {
  final String label;
  final int grams;
  final int pct;

  const _MacroRow({
    required this.label,
    required this.grams,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: AppColors.onSurface, fontSize: 16),
          ),
          const SizedBox(width: 6),
          Text(
            '${grams}g',
            style: TextStyle(color: AppColors.secondary, fontSize: 16),
          ),
          const Spacer(),
          Text(
            '$pct%',
            style: TextStyle(color: AppColors.primary, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _CustomTargetRow extends StatelessWidget {
  final String label;
  final int kcal;
  final VoidCallback onDelete;

  const _CustomTargetRow({
    required this.label,
    required this.kcal,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: AppColors.onSurface, fontSize: 16),
                ),
                Text(
                  '$kcal kcal',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: AppColors.secondary, size: 20),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0,
      thickness: 0.5,
      color: AppColors.outlineVariant,
    );
  }
}