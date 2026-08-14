import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import 'rep_tracking_providers.dart';

/// The dedicated consent/onboarding screen for assisted rep tracking.
///
/// **This is the only place in the app that calls `grantConsent()`**
/// (REP-01/T-10-20) — the per-exercise toggle elsewhere in the app never
/// grants consent itself, it only links back here.
class RepTrackingConsentView extends ConsumerWidget {
  const RepTrackingConsentView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final form = ref.watch(repConsentFormProvider);
    final formNotifier = ref.read(repConsentFormProvider.notifier);
    final settingsAsync = ref.watch(repTrackingSettingsProvider);
    final alreadyGranted =
        settingsAsync.asData?.value?.consentGrantedAt != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'ASSISTED REP TRACKING',
          style: theme.textTheme.titleMedium?.copyWith(
            letterSpacing: 2.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
        children: [
          _explainerCard(theme),
          const SizedBox(height: 32),
          Text(
            'SENSOR SOURCE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SourceChip(
                  label: 'Wrist (watch)',
                  selected: form.source == 'wrist',
                  onTap: () => formNotifier.selectSource('wrist'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SourceChip(
                  label: 'Phone',
                  selected: form.source == 'phone',
                  onTap: () => formNotifier.selectSource('phone'),
                ),
              ),
            ],
          ),
          if (form.source == 'phone') ...[
            const SizedBox(height: 20),
            Text(
              'PHONE PLACEMENT (REQUIRED)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Never assumed — pick where the phone sits during the set.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SourceChip(
                    label: 'Front pocket',
                    selected: form.placement == 'pocket_front',
                    onTap: () => formNotifier.selectPlacement('pocket_front'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceChip(
                    label: 'Armband',
                    selected: form.placement == 'armband',
                    onTap: () => formNotifier.selectPlacement('armband'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: form.canSubmit ? () => _grant(context, ref) : null,
              child: Text(
                alreadyGranted
                    ? 'Update sensor preferences'
                    : 'Enable assisted rep tracking',
              ),
            ),
          ),
          if (alreadyGranted) ...[
            const SizedBox(height: 12),
            Text(
              'Turn tracking on for an individual exercise from that '
              "exercise's options during a workout.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _confirmRevoke(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                ),
                child: const Text('Revoke consent & delete data'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _explainerCard(ThemeData theme) {
    Widget row(IconData icon, String title, String body) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(
            Icons.sensors,
            'What is measured',
            'Accelerometer motion during a set you explicitly start — '
                'nothing runs in the background.',
          ),
          row(
            Icons.phonelink_lock_outlined,
            'Where it is processed',
            'On your watch and phone only. Raw motion never leaves your '
                'devices and is discarded the moment the set ends.',
          ),
          row(
            Icons.save_outlined,
            'What is kept',
            'A summary of each confirmed set — cadence, consistency, and '
                'your confirmed reps and RPE.',
          ),
          row(
            Icons.block,
            'What it will never do',
            'Complete, save or change a set on its own. Every value is '
                'yours to review and edit before it is saved.',
          ),
          row(
            Icons.info_outline,
            'Not a medical device',
            'This is a training aid, not a medical or safety device.',
          ),
        ],
      ),
    );
  }

  Future<void> _grant(BuildContext context, WidgetRef ref) async {
    final form = ref.read(repConsentFormProvider);
    final repo = ref.read(repTrackingRepositoryProvider);
    await repo.grantConsent(version: 1);
    await repo.updateSensorPreferences(
      source: form.source,
      placement: form.source == 'phone' ? form.placement : null,
    );
    ref.invalidate(repTrackingSettingsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Rep tracking enabled. Turn it on per exercise from that '
          "exercise's options.",
        ),
      ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke consent?'),
        content: const Text(
          'This permanently deletes every stored calibration profile, '
          'per-exercise preference and confirmed-set observation on this '
          'device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Revoke & delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(repTrackingRepositoryProvider).revokeConsent();
    ref.invalidate(repTrackingSettingsProvider);
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outlineVariant,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.onSurfaceVariant,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
