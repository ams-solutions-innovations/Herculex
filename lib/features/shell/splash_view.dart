import 'package:flutter/material.dart';

import 'package:herculex/design_system/theme/colors.dart';

/// Shown briefly on cold start while the local profile loads.
class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              // The launcher artwork includes a navy background. Use the
              // transparent H/barbell foreground in the UI so it can follow
              // the active app colour without showing the legacy lion mark.
              'assets/images/app_icon_foreground.png',
              width: 120,
              height: 120,
              color: AppColors.primary,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.fitness_center,
                size: 80,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 32),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
