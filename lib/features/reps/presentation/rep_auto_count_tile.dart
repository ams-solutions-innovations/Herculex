import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/colors.dart';
import 'rep_tracking_providers.dart';

/// The single global switch for assisted rep counting, shown in the workout
/// settings sheet.
///
/// ## Why one switch replaced per-exercise opt-in
///
/// Whether an exercise can be counted is a fact about where the sensors sit,
/// not a preference: a bench press rotates the wrist through a large arc, a
/// pull-up leaves the wrist nearly still while the body travels past it, and a
/// seated leg curl moves neither the wrist nor the thigh at all. The app now
/// knows that for every catalogue row. Asking the user to opt in exercise by
/// exercise was asking them to re-derive it — and to keep re-deriving it for
/// every exercise they ever add.
///
/// So this turns the feature on, the capability profiles decide where it can
/// apply, and the per-exercise control in the exercise options menu is
/// demoted to an override for the cases where the user disagrees.
///
/// ## Consent stays a separate door
///
/// This switch is disabled until the consent screen has been completed, and
/// tapping it in that state routes there rather than granting inline. Consent
/// is a decision about data handling; this is a decision about a feature. The
/// repository refuses the write too, so the gate does not depend on this
/// widget getting it right.
class RepAutoCountTile extends ConsumerWidget {
  const RepAutoCountTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(repTrackingSettingsProvider);
    final settings = settingsAsync.asData?.value;
    final consented = settings?.consentGrantedAt != null;
    final enabled = settings?.autoCountEnabled ?? false;

    if (!consented) {
      return ListTile(
        leading: Icon(Icons.sensors_outlined, color: AppColors.primary),
        title: const Text('Assisted rep counting'),
        subtitle: const Text('Review how motion data is used to turn this on'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/rep-tracking-consent'),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          secondary: Icon(Icons.sensors_outlined, color: AppColors.primary),
          title: const Text('Assisted rep counting'),
          subtitle: const Text(
            'Count reps automatically where the sensors can see them',
          ),
          value: enabled,
          activeThumbColor: AppColors.primary,
          onChanged: (value) async {
            await ref
                .read(repTrackingRepositoryProvider)
                .setAutoCountEnabled(value);
            ref.invalidate(repTrackingSettingsProvider);
            ref.invalidate(repAutoCountEnabledProvider);
          },
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: Text(
              // Stated up front rather than discovered mid-set. For a pull-up
              // or a dip the hands are locked to a bar and the watch travels
              // barely at all — there is no threshold that recovers the rep
              // from the wrist, so the user has to know where to put the
              // phone before the set, not after it produced nothing.
              'Most exercises are counted from your watch. Pull-ups, dips, '
              'push-ups and other hands-fixed moves need your phone in a '
              'pocket — your hands barely move, so the watch cannot see them.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
            ),
          ),
      ],
    );
  }
}
