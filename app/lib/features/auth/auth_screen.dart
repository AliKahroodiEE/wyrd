import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../app/providers.dart';
import '../../data/remote/backend.dart';
import '../../design/components/background.dart';
import '../../design/components/motion.dart';
import '../../design/components/panel.dart';
import '../../design/components/states.dart';
import '../../design/tokens.dart';
import '../settings/legal_links.dart';
import 'auth_errors.dart';
import 'auth_gateway.dart';
import 'auth_steps.dart';
import 'auth_widgets.dart';
import 'sign_out.dart';

/// Where the sign-in flow is.
enum AuthStep { email, code, password, forgot, newPassword }

/// Sign-in: an emailed 6-digit code first, passwords (confirmed and reset by
/// code) second, Google and GitHub when this build enables them. Upgrading from guest
/// keeps all local data; the sync engine uploads it to the account (A2).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  /// Seconds before another code may be requested (`auth.email.max_frequency`).
  static const resendCooldown = 60;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _newPassword = TextEditingController();

  AuthStep _step = AuthStep.email;
  CodePurpose _purpose = CodePurpose.signIn;
  bool _busy = false;
  String? _message;
  bool _messageIsError = true;
  Timer? _cooldown;
  int _resendLeft = 0;

  /// An OAuth page is open; its session arrives as an auth state change.
  bool _awaitingRedirect = false;
  bool _left = false;

  @override
  void dispose() {
    _cooldown?.cancel();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  AuthGateway? get _gateway => ref.read(authGatewayProvider);

  String get _address => _email.text.trim();

  void _go(AuthStep step, {String? message, bool isError = true}) => setState(() {
    _step = step;
    _message = message;
    _messageIsError = isError;
  });

  void _say(String? message, {bool isError = true}) => setState(() {
    _message = message;
    _messageIsError = isError;
  });

  /// Back to wherever the sign-in was opened from.
  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    context.canPop() ? context.pop() : context.go('/character');
  }

  void _startCooldown() {
    _cooldown?.cancel();
    setState(() => _resendLeft = AuthScreen.resendCooldown);
    _cooldown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() => _resendLeft--);
      if (!mounted || _resendLeft <= 0) t.cancel();
    });
  }

  /// Runs [action] with the form locked; failures become a message.
  Future<void> _run(Future<void> Function(AuthGateway gateway) action) async {
    final gateway = _gateway;
    if (gateway == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _awaitingRedirect = false;
    });
    try {
      await action(gateway);
    } on Object catch (e) {
      if (mounted) _say(authErrorMessage(context.l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _checkEmail() {
    if (isValidEmail(_address)) return true;
    _say(context.l10n.authErrEmail);
    return false;
  }

  Future<void> _sendCode(CodePurpose purpose) async {
    if (!_checkEmail()) return;
    await _run((g) async {
      await g.sendCode(purpose, _address);
      if (!mounted) return;
      _code.clear();
      _purpose = purpose;
      _go(AuthStep.code);
      _startCooldown();
    });
  }

  Future<void> _resend() => _run((g) async {
    await g.sendCode(_purpose, _address);
    if (!mounted) return;
    _code.clear();
    _say(context.l10n.authCodeResent, isError: false);
    _startCooldown();
  });

  Future<void> _verify() async {
    final code = _code.text;
    if (code.length != codeLength) {
      _say(context.l10n.authErrCodeLength);
      return;
    }
    await _run((g) async {
      await g.verifyCode(_purpose, _address, code);
      if (!mounted) return;
      if (_purpose == CodePurpose.recovery) {
        _newPassword.clear();
        _go(AuthStep.newPassword);
      } else {
        _leave();
      }
    });
  }

  Future<void> _signIn() async {
    if (!_checkEmail()) return;
    await _run((g) async {
      try {
        await g.signInWithPassword(_address, _password.text);
      } on Object catch (e) {
        if (!isAuthCode(e, AuthCodes.emailNotConfirmed)) rethrow;
        // Never confirmed: send a fresh code and let them finish here.
        try {
          await g.sendCode(CodePurpose.signUp, _address);
        } on Object {
          // Rate limited; the last code may still be valid.
        }
        if (!mounted) return;
        _code.clear();
        _purpose = CodePurpose.signUp;
        _go(AuthStep.code, message: context.l10n.authErrNotConfirmed, isError: false);
        _startCooldown();
        return;
      }
      _leave();
    });
  }

  Future<void> _createAccount() async {
    if (!_checkEmail()) return;
    if (!isAcceptablePassword(_password.text)) {
      _say(context.l10n.authErrWeakPassword);
      return;
    }
    await _run((g) async {
      final needsCode = await g.signUp(_address, _password.text);
      if (!mounted) return;
      if (!needsCode) {
        _leave();
        return;
      }
      _code.clear();
      _purpose = CodePurpose.signUp;
      _go(AuthStep.code);
      _startCooldown();
    });
  }

  Future<void> _savePassword() async {
    if (!isAcceptablePassword(_newPassword.text)) {
      _say(context.l10n.authErrWeakPassword);
      return;
    }
    await _run((g) async {
      await g.updatePassword(_newPassword.text);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.l10n.authPasswordSaved)));
      _leave();
    });
  }

  Future<void> _signOut(AuthGateway gateway) => signOutDevice(ref, gateway);

  Future<void> _social(SocialProvider provider) => _run((g) async {
    await g.signInWith(provider);
    _awaitingRedirect = true;
  });

  void _back() {
    switch (_step) {
      case AuthStep.email:
      case AuthStep.newPassword:
        _leave();
      case AuthStep.password:
        _go(AuthStep.email);
      case AuthStep.forgot:
        _go(AuthStep.password);
      case AuthStep.code:
        _cooldown?.cancel();
        _go(switch (_purpose) {
          CodePurpose.signIn => AuthStep.email,
          CodePurpose.signUp => AuthStep.password,
          CodePurpose.recovery => AuthStep.forgot,
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gateway = ref.watch(authGatewayProvider);
    final user = ref.watch(currentUserProvider).value;
    // Phones come back from Google or GitHub in the browser through the app.wyrd://
    // link; leave as soon as that session lands.
    ref.listen(currentUserProvider, (prev, next) {
      if (_awaitingRedirect && prev?.value == null && next.value != null) _leave();
    });
    final signedInUser = _step == AuthStep.newPassword ? null : user;

    return PopScope(
      canPop: signedInUser != null || _step == AuthStep.email,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _back();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.authTitle)),
        body: AppBackground(
          child: SafeArea(
            top: false,
            child: Align(
              alignment: AlignmentDirectional.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.xl, AppSpace.lg, AppSpace.xxl),
                  children: [
                    if (gateway == null)
                      ErrorState(message: l10n.authBackendMissing)
                    else if (signedInUser != null)
                      _SignedIn(user: signedInUser, busy: _busy, onSignOut: () => _run(_signOut))
                    else ...[
                      _header(context),
                      const SizedBox(height: AppSpace.xl),
                      Panel(
                        accent: context.palette.accent,
                        padding: const EdgeInsetsDirectional.all(AppSpace.xl),
                        child: AnimatedSwitcher(
                          duration: motion(context, AppMotion.base),
                          switchInCurve: AppMotion.standard,
                          child: KeyedSubtree(key: ValueKey(_step), child: _form(gateway)),
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      const LegalLinks(),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: AppSpace.lg),
                      AuthMessage(message: _message!, isError: _messageIsError),
                    ],
                    if (_busy) ...[
                      const SizedBox(height: AppSpace.lg),
                      const Center(
                        child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
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

  Widget _header(BuildContext context) {
    final l10n = context.l10n;
    return switch (_step) {
      AuthStep.email || AuthStep.password => AuthHeader(title: l10n.authHeadline, body: l10n.authIntro),
      AuthStep.code => AuthHeader(title: l10n.authCodeTitle, icon: Icons.mark_email_unread_outlined),
      AuthStep.forgot => AuthHeader(title: l10n.authResetTitle, icon: Icons.key_outlined),
      AuthStep.newPassword => AuthHeader(title: l10n.authNewPasswordTitle, icon: Icons.key_outlined),
    };
  }

  Widget _form(AuthGateway gateway) => switch (_step) {
    AuthStep.email => EmailStep(
      email: _email,
      busy: _busy,
      onContinue: () => _sendCode(CodePurpose.signIn),
      onUsePassword: () => _go(AuthStep.password),
      providers: gateway.socialProviders,
      onProvider: _social,
    ),
    AuthStep.code => CodeStep(
      email: _address,
      code: _code,
      busy: _busy,
      resendIn: _resendLeft > 0 ? ref.fmt(context).number(_resendLeft) : null,
      onVerify: _verify,
      onResend: _resend,
      onChangeEmail: _back,
    ),
    AuthStep.password => PasswordStep(
      email: _email,
      password: _password,
      busy: _busy,
      onSignIn: _signIn,
      onCreateAccount: _createAccount,
      onForgot: () => _go(AuthStep.forgot),
      onUseCode: () => _go(AuthStep.email),
    ),
    AuthStep.forgot => ForgotStep(
      email: _email,
      busy: _busy,
      onSend: () => _sendCode(CodePurpose.recovery),
      onBack: _back,
    ),
    AuthStep.newPassword => NewPasswordStep(password: _newPassword, busy: _busy, onSave: _savePassword),
  };
}

class _SignedIn extends StatelessWidget {
  const _SignedIn({required this.user, required this.busy, required this.onSignOut});

  final User user;
  final bool busy;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.signedInAs(user.email ?? ''), style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: AppSpace.lg),
          OutlinedButton(onPressed: busy ? null : onSignOut, child: Text(l10n.signOut)),
        ],
      ),
    );
  }
}
