import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Where the web build sends a route that only works on a phone — health
/// integrations, notifications, Gym Buddy and the like. Deep links and
/// bookmarks can still reach those paths, so they land here instead of on a
/// screen that would fail against a missing plugin.
class NotOnWebView extends StatelessWidget {
  const NotOnWebView({super.key, this.from});

  /// The path that was redirected, used to name the feature.
  final String? from;

  static const _features = <String, (String, IconData)>{
    AppRoutes.health: ('Health integrations', Icons.favorite_rounded),
    AppRoutes.healthSamsung: ('Samsung Health', Icons.favorite_rounded),
    AppRoutes.healthApple: ('Apple Health', Icons.favorite_rounded),
    AppRoutes.healthGoogle: ('Health Connect', Icons.favorite_rounded),
    AppRoutes.steps: ('Steps', Icons.directions_walk_rounded),
    AppRoutes.sleep: ('Sleep', Icons.bedtime_rounded),
    AppRoutes.notifications: ('Notifications', Icons.notifications_rounded),
    AppRoutes.settingsPermissions: ('Permissions', Icons.lock_rounded),
    AppRoutes.gymBuddy: ('Gym Buddy', Icons.group_rounded),
    AppRoutes.buddyJoin: ('Gym Buddy', Icons.group_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final (name, icon) =
        _features[from] ?? ('This feature', Icons.phone_iphone_rounded);

    return HxScreenShell(
      title: name,
      titleIcon: icon,
      children: [
        const SizedBox(height: HxSpace.x6),
        HxCard(
          accent: hx.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(HxSpace.x3),
                decoration: BoxDecoration(
                  color: hx.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.phone_iphone_rounded,
                  color: hx.primaryText,
                  size: 28,
                ),
              ),
              const SizedBox(height: HxSpace.x4),
              Text(
                'Available in the mobile app',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: HxSpace.x2),
              Text(
                '$name needs your phone — its sensors, health store or '
                'notifications. Everything you do there still syncs here.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: HxSpace.x5),
              PremiumButton(
                text: 'Back to Herculex',
                icon: Icons.arrow_back_rounded,
                onTap: () => context.go(AppRoutes.app),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
