import 'package:flutter/material.dart';
import 'package:herculex/core/utils/auth_validator.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/onboarding/presentation/widgets/onboarding_controls.dart';
import 'package:herculex/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:herculex/features/onboarding/presentation/widgets/onboarding_welcome_page.dart';

/// Email + password sign-up / sign-in, with the social buttons repeated above.
class OnboardingEmailPage extends StatefulWidget {
  const OnboardingEmailPage({
    super.key,
    required this.register,
    required this.busy,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.onBack,
    required this.onSubmit,
    required this.onToggleMode,
    required this.onForgotPassword,
    required this.onApple,
    required this.onGoogle,
  });

  final bool register;
  final bool busy;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final VoidCallback onBack;
  final VoidCallback onSubmit;
  final VoidCallback onToggleMode;
  final VoidCallback onForgotPassword;
  final VoidCallback onApple;
  final VoidCallback onGoogle;

  @override
  State<OnboardingEmailPage> createState() => _OnboardingEmailPageState();
}

class _OnboardingEmailPageState extends State<OnboardingEmailPage> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    final register = widget.register;
    return OnboardingScaffold(
      onBack: widget.onBack,
      ctaLabel: widget.busy
          ? 'Please wait...'
          : (register ? 'Create account' : 'Sign in'),
      onCta: widget.busy ? null : widget.onSubmit,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: TextButton(
              onPressed: widget.busy ? null : widget.onToggleMode,
              child: Text.rich(
                TextSpan(
                  text: register
                      ? 'Already have an account? '
                      : 'Need an account? ',
                  style: text.bodyMedium?.copyWith(color: hx.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: register ? 'Sign in' : 'Register',
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
          const OnboardingLegalNote(),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnboardingHeading(
            title: register ? 'Create your account' : 'Welcome back',
            subtitle: register
                ? 'Your profile, programs and logs stay with you across '
                      'devices and your watch.'
                : 'Sign in to pick up where you left off.',
          ),
          const SizedBox(height: 20),
          OnboardingSocialButtons(
            onApple: widget.onApple,
            onGoogle: widget.onGoogle,
            busy: widget.busy,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Divider(color: hx.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or with email',
                  style: text.bodySmall?.copyWith(color: hx.onSurfaceVariant),
                ),
              ),
              Expanded(child: Divider(color: hx.outlineVariant)),
            ],
          ),
          const SizedBox(height: 20),
          OnboardingField(
            label: 'Email',
            hint: 'you@example.com',
            controller: widget.emailCtrl,
            keyboardType: TextInputType.emailAddress,
            maxLength: AuthValidator.maxEmailLength,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: 16),
          OnboardingField(
            label: 'Password',
            hint: 'At least 8 characters',
            controller: widget.passwordCtrl,
            keyboardType: TextInputType.visiblePassword,
            obscureText: _obscure,
            maxLength: AuthValidator.maxPasswordLength,
            autofillHints: [
              register ? AutofillHints.newPassword : AutofillHints.password,
            ],
            suffix: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: hx.onSurfaceVariant,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          if (!register)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.busy ? null : widget.onForgotPassword,
                child: Text(
                  'Reset password',
                  style: TextStyle(color: hx.primaryText),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
