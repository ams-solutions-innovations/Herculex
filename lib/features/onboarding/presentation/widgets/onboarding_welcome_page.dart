import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

/// "Continue with Apple" / "Continue with Google" pair, shared by the welcome
/// and email sign-up pages.
class OnboardingSocialButtons extends StatelessWidget {
  const OnboardingSocialButtons({
    super.key,
    required this.onApple,
    required this.onGoogle,
    required this.busy,
  });

  final VoidCallback onApple;
  final VoidCallback onGoogle;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SocialButton(
          background: hx.onSurface,
          foreground: hx.background,
          icon: Icons.apple,
          label: 'Continue with Apple',
          onTap: busy ? null : onApple,
        ),
        const SizedBox(height: 10),
        _SocialButton(
          background: hx.surfaceContainerLowest,
          foreground: hx.onSurface,
          border: hx.outlineVariant,
          leading: Text(
            'G',
            style: text.titleMedium?.copyWith(
              color: hx.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          label: 'Continue with Google',
          onTap: busy ? null : onGoogle,
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.background,
    required this.foreground,
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.border,
  });

  final Color background;
  final Color foreground;
  final Color? border;
  final IconData? icon;
  final Widget? leading;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: background,
        shape: StadiumBorder(
          side: border == null ? BorderSide.none : BorderSide(color: border!),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) Icon(icon, color: foreground, size: 20),
                ?leading,
                const SizedBox(width: 10),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Terms / Privacy line used under the auth buttons.
class OnboardingLegalNote extends StatelessWidget {
  const OnboardingLegalNote({super.key});

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final base = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: hx.onSurfaceVariant);
    final link = base?.copyWith(color: hx.primaryText);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'By continuing you agree to the '),
          TextSpan(text: 'Terms', style: link),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Logo + the three ways in. Nothing else: the intro and setup come after.
class OnboardingWelcomePage extends StatelessWidget {
  const OnboardingWelcomePage({
    super.key,
    required this.busy,
    required this.onApple,
    required this.onGoogle,
    required this.onEmail,
    required this.onSignIn,
    this.onContinueWithoutAccount,
  });

  final bool busy;
  final VoidCallback onApple;
  final VoidCallback onGoogle;
  final VoidCallback onEmail;
  final VoidCallback onSignIn;

  /// Offline-first builds let people start without an account; null hides it.
  final VoidCallback? onContinueWithoutAccount;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    return OnboardingScaffold(
      topPadding: 0,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: TextButton(
              onPressed: busy ? null : onSignIn,
              child: Text.rich(
                TextSpan(
                  text: 'Already have an account? ',
                  style: text.bodyMedium?.copyWith(color: hx.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: 'Sign in',
                      style: TextStyle(
                        color: hx.primaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onContinueWithoutAccount != null)
            Center(
              child: TextButton(
                onPressed: busy ? null : onContinueWithoutAccount,
                child: Text(
                  'Continue without an account',
                  style: TextStyle(color: hx.onSurfaceVariant),
                ),
              ),
            ),
          const OnboardingLegalNote(),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 56),
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: hx.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: hx.outlineVariant),
            ),
            alignment: Alignment.center,
            child: Image.asset(
              'assets/images/app_icon_foreground.png',
              width: 110,
              height: 110,
              fit: BoxFit.contain,
              semanticLabel: 'Herculex',
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'HERCULEX',
            style: text.headlineSmall?.copyWith(
              fontFamily: 'SpaceGrotesk',
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
              color: hx.onSurface,
            ),
          ),
          const SizedBox(height: 56),
          OnboardingSocialButtons(
            onApple: onApple,
            onGoogle: onGoogle,
            busy: busy,
          ),
          const SizedBox(height: 10),
          PremiumButton(
            expand: true,
            text: 'Sign up with email',
            onTap: busy ? () {} : onEmail,
          ),
        ],
      ),
    );
  }
}
