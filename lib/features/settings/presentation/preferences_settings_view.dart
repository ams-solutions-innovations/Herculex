import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/data/speech_to_text_service.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/settings/presentation/widgets/stt_language_picker.dart';
import 'package:herculex/features/workouts/application/workout_bubble_controller.dart';
import 'package:herculex/services/platform/workout_bubble_service.dart';
import 'package:permission_handler/permission_handler.dart';

/// Behaviour switches: calorie accounting, coach tone, voice language, goals
/// and the floating workout bubble.
///
/// `countBurnedCalories` and `herculTone` live on [Profile]. This screen writes
/// them straight to the repository; `ProfileView` reads them back from the
/// stream instead of keeping its own copy, so it cannot overwrite them.
class PreferencesSettingsView extends ConsumerWidget {
  const PreferencesSettingsView({super.key});

  Future<void> _setBurnedCalories(WidgetRef ref, Profile profile, bool value) {
    return ref
        .read(localProfileRepositoryProvider)
        .save(profile.copyWith(countBurnedCalories: value));
  }

  Future<void> _setHonestHercul(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
    bool enabled,
  ) async {
    if (enabled) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Enable Honest Hercul?'),
          content: const Text(
            'Honest Hercul uses blunt, unfiltered language about '
            'training and consistency. It may contain profanity. '
            'Are you 18 or older?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Yes, I am 18+'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    await ref
        .read(localProfileRepositoryProvider)
        .save(profile.copyWith(herculTone: enabled ? 'honest' : 'normal'));
  }

  /// Turning the Workout Bubble on needs "Display over other apps", which is a
  /// settings-screen grant rather than a dialog: `request()` opens the system
  /// page and returns when the user comes back, so the real answer has to be
  /// re-read afterwards. The switch only goes on if the permission actually
  /// landed — otherwise the setting would claim a bubble the OS will never draw.
  Future<void> _onWorkoutBubbleToggled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final notifier = ref.read(workoutBubbleEnabledProvider.notifier);
    if (!enabled) {
      await notifier.set(false);
      return;
    }

    if (await WorkoutBubbleService.instance.hasPermission()) {
      await notifier.set(true);
      return;
    }

    await Permission.systemAlertWindow.request();
    final granted = await WorkoutBubbleService.instance.hasPermission();
    await notifier.set(granted);
    if (granted || !context.mounted) return;

    AppNotice.show(
      context,
      'Herculex needs "Display over other apps" to float the workout '
      'bubble. You can grant it any time in system settings.',
      kind: AppNoticeKind.info,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final stt = ref.watch(speechToTextServiceProvider);

    return HxScreenShell(
      title: 'Preferences',
      titleIcon: Icons.tune_rounded,
      children: [
        const HxSectionHeader('Tracking'),
        const SizedBox(height: 10),
        HxSettingsCard(
          children: [
            HxSettingsTile(
              icon: Icons.local_fire_department,
              label: 'Include Burned Calories',
              subtitle: 'Add workout calories to your daily budget',
              trailing: Switch(
                value: profile?.countBurnedCalories ?? false,
                onChanged: profile == null
                    ? null
                    : (v) => _setBurnedCalories(ref, profile, v),
              ),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.track_changes_rounded,
              label: 'Goals & Targets',
              chevron: true,
              onTap: () => context.push(AppRoutes.goals),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const HxSectionHeader('Coach & voice'),
        const SizedBox(height: 10),
        HxSettingsCard(
          children: [
            HxSettingsTile(
              icon: Icons.psychology_outlined,
              label: 'Honest Hercul (18+)',
              subtitle: 'Blunt, unfiltered coaching tone',
              trailing: Switch(
                value: profile?.herculTone == 'honest',
                onChanged: profile == null
                    ? null
                    : (v) => _setHonestHercul(context, ref, profile, v),
              ),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.mic_rounded,
              label: 'Voice / Rambler Language',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${stt.selectedLanguageOption.flag} ${stt.selectedLanguageOption.name}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.hx.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    color: context.hx.onSurfaceVariant,
                    size: 18,
                  ),
                ],
              ),
              onTap: () => showSttLanguagePicker(context, ref),
            ),
          ],
        ),
        // Android-only: iOS has no system overlay windows, so the section is
        // hidden rather than shown disabled — a permanently dead switch reads
        // as a bug.
        if (WorkoutBubbleService.instance.isSupported) ...[
          const SizedBox(height: 24),
          const HxSectionHeader('Workout'),
          const SizedBox(height: 10),
          HxSettingsCard(
            children: [
              HxSettingsTile(
                icon: Icons.bubble_chart_rounded,
                label: 'Workout Bubble',
                subtitle: 'Floating shortcut while a workout is running',
                trailing: Switch(
                  value: ref.watch(workoutBubbleEnabledProvider),
                  onChanged: (v) => _onWorkoutBubbleToggled(context, ref, v),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
