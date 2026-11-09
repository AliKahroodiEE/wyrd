import 'package:flutter/material.dart';

import '../../app/providers.dart';
import '../../design/components/game.dart';
import '../../design/tokens.dart';
import 'auth_gateway.dart';
import 'auth_widgets.dart';

/// Start: email for a code, a way to passwords, and Google or GitHub.
class EmailStep extends StatelessWidget {
  const EmailStep({
    super.key,
    required this.email,
    required this.busy,
    required this.onContinue,
    required this.onUsePassword,
    this.providers = const [],
    this.onProvider,
  });

  final TextEditingController email;
  final bool busy;
  final VoidCallback onContinue;
  final VoidCallback onUsePassword;

  /// The "Continue with …" buttons to show; none when empty.
  final List<SocialProvider> providers;
  final ValueChanged<SocialProvider>? onProvider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutofillGroup(
          child: EmailField(controller: email, onSubmitted: busy ? null : onContinue),
        ),
        const SizedBox(height: AppSpace.lg),
        GlowButton(
          label: l10n.authContinueEmail,
          icon: Icons.mark_email_unread_outlined,
          onPressed: busy ? null : onContinue,
        ),
        const SizedBox(height: AppSpace.xs),
        TextButton(onPressed: busy ? null : onUsePassword, child: Text(l10n.authUsePassword)),
        if (providers.isNotEmpty && onProvider != null) ...[
          const SizedBox(height: AppSpace.sm),
          const OrDivider(),
          for (final provider in providers) ...[
            const SizedBox(height: AppSpace.md),
            ProviderButton(
              label: switch (provider) {
                SocialProvider.google => l10n.authContinueGoogle,
                SocialProvider.github => l10n.authContinueGithub,
              },
              mark: ProviderLogo(provider),
              onPressed: busy ? null : () => onProvider!(provider),
            ),
          ],
        ],
      ],
    );
  }
}

/// The emailed 6-digit code, with a resend once the cooldown is over.
class CodeStep extends StatelessWidget {
  const CodeStep({
    super.key,
    required this.email,
    required this.code,
    required this.busy,
    required this.resendIn,
    required this.onVerify,
    required this.onResend,
    required this.onChangeEmail,
  });

  final String email;
  final TextEditingController code;
  final bool busy;

  /// Seconds until a new code may be requested, already formatted; null
  /// when it may be requested now.
  final String? resendIn;
  final VoidCallback onVerify;
  final VoidCallback onResend;
  final VoidCallback onChangeEmail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The address is isolated so it reads left to right in Persian.
        Text(
          l10n.authCodeSent('\u2068$email\u2069'),
          style: text.bodyMedium?.copyWith(color: context.palette.inkSoft),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpace.lg),
        CodeField(controller: code, enabled: !busy, onCompleted: busy ? () {} : onVerify),
        const SizedBox(height: AppSpace.lg),
        GlowButton(label: l10n.authVerify, icon: Icons.lock_open_rounded, onPressed: busy ? null : onVerify),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: busy || resendIn != null ? null : onResend,
              child: Text(resendIn == null ? l10n.authResend : l10n.authResendIn(resendIn!)),
            ),
            TextButton(onPressed: busy ? null : onChangeEmail, child: Text(l10n.authChangeEmail)),
          ],
        ),
      ],
    );
  }
}

/// Email and password: sign in, create an account, or recover.
class PasswordStep extends StatelessWidget {
  const PasswordStep({
    super.key,
    required this.email,
    required this.password,
    required this.busy,
    required this.onSignIn,
    required this.onCreateAccount,
    required this.onForgot,
    required this.onUseCode,
  });

  final TextEditingController email;
  final TextEditingController password;
  final bool busy;
  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;
  final VoidCallback onForgot;
  final VoidCallback onUseCode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EmailField(controller: email),
              const SizedBox(height: AppSpace.md),
              PasswordField(
                controller: password,
                label: l10n.authPassword,
                helper: l10n.authPasswordRules,
                onSubmitted: busy ? null : onSignIn,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        GlowButton(label: l10n.signIn, icon: Icons.login_rounded, onPressed: busy ? null : onSignIn),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton(onPressed: busy ? null : onCreateAccount, child: Text(l10n.createAccount)),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(onPressed: busy ? null : onForgot, child: Text(l10n.authForgotPassword)),
            TextButton(onPressed: busy ? null : onUseCode, child: Text(l10n.authUseCode)),
          ],
        ),
      ],
    );
  }
}

/// Asks where to send a password reset code.
class ForgotStep extends StatelessWidget {
  const ForgotStep({super.key, required this.email, required this.busy, required this.onSend, required this.onBack});

  final TextEditingController email;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.authResetBody,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.palette.inkSoft),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpace.lg),
        AutofillGroup(
          child: EmailField(controller: email, autofocus: true, onSubmitted: busy ? null : onSend),
        ),
        const SizedBox(height: AppSpace.lg),
        GlowButton(label: l10n.authSendCode, icon: Icons.send_rounded, onPressed: busy ? null : onSend),
        const SizedBox(height: AppSpace.xs),
        TextButton(onPressed: busy ? null : onBack, child: Text(l10n.actionBack)),
      ],
    );
  }
}

/// After a recovery code: the new password.
class NewPasswordStep extends StatelessWidget {
  const NewPasswordStep({super.key, required this.password, required this.busy, required this.onSave});

  final TextEditingController password;
  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutofillGroup(
          child: PasswordField(
            controller: password,
            label: l10n.authNewPassword,
            helper: l10n.authPasswordRules,
            newPassword: true,
            onSubmitted: busy ? null : onSave,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        GlowButton(label: l10n.authSavePassword, icon: Icons.check_rounded, onPressed: busy ? null : onSave),
      ],
    );
  }
}
