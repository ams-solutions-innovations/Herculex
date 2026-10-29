import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/utils/auth_validator.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Landing page of the password-reset email on the web.
///
/// The link carries a one-time `code` that supabase_flutter exchanges for a
/// recovery session as the app starts, so by the time this renders the user
/// is signed in and only needs to choose the new password.
class ResetPasswordView extends ConsumerStatefulWidget {
  const ResetPasswordView({super.key});

  @override
  ConsumerState<ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends ConsumerState<ResetPasswordView> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _passwordCtrl.text;
    final error =
        AuthValidator.validatePassword(password, isRegistration: true) ??
        (password == _confirmCtrl.text ? null : 'The passwords don’t match.');
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).updatePassword(password);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e
              .toString()
              .replaceAll('Exception: ', '')
              .replaceAll('AuthException: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(HxSpace.x6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: HxCard(
                padding: const EdgeInsets.all(HxSpace.x6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _done ? 'Password updated' : 'Choose a new password',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: HxSpace.x2),
                    Text(
                      _done
                          ? 'Use it next time you sign in, here or on your phone.'
                          : 'At least ${AuthValidator.minPasswordLength} '
                                'characters.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: HxSpace.x5),
                    if (_done)
                      PremiumButton(
                        text: 'Continue',
                        expand: true,
                        onTap: () => context.go(AppRoutes.app),
                      )
                    else ...[
                      TextField(
                        controller: _passwordCtrl,
                        enabled: !_busy,
                        obscureText: true,
                        maxLength: AuthValidator.maxPasswordLength,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          hintText: 'New password',
                          counterText: '',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: HxSpace.x3),
                      TextField(
                        controller: _confirmCtrl,
                        enabled: !_busy,
                        obscureText: true,
                        maxLength: AuthValidator.maxPasswordLength,
                        onSubmitted: (_) => _save(),
                        decoration: const InputDecoration(
                          hintText: 'Repeat new password',
                          counterText: '',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: HxSpace.x3),
                        Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: hx.danger,
                          ),
                        ),
                      ],
                      const SizedBox(height: HxSpace.x5),
                      _busy
                          ? const Center(child: CircularProgressIndicator())
                          : PremiumButton(
                              text: 'Save password',
                              expand: true,
                              onTap: _save,
                            ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
