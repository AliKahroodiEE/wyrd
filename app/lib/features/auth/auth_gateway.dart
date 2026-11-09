import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../data/remote/backend.dart';
import 'auth_errors.dart';

/// Why a 6-digit code is sent; decides which Supabase OTP type checks it.
enum CodePurpose { signIn, signUp, recovery }

/// Sign-in with another account, in the order the buttons appear.
enum SocialProvider {
  google(OAuthProvider.google),
  github(OAuthProvider.github);

  const SocialProvider(this.oauth);

  final OAuthProvider oauth;
}

/// Everything the sign-in flow asks of the server. An interface so widget
/// tests run without a network.
abstract interface class AuthGateway {
  /// The "Continue with …" sign-ins this build offers on this platform.
  List<SocialProvider> get socialProviders;

  /// Emails a 6-digit code for [purpose]; also used to resend one.
  Future<void> sendCode(CodePurpose purpose, String email);

  /// Checks [code]; on success the user is signed in.
  Future<void> verifyCode(CodePurpose purpose, String email, String code);

  Future<void> signInWithPassword(String email, String password);

  /// Creates a password account. Returns true when the address still has
  /// to be confirmed with a code (always, with `enable_confirmations`).
  Future<bool> signUp(String email, String password);

  /// Sets a new password for the signed-in user (after a recovery code).
  Future<void> updatePassword(String password);

  /// Opens [provider]'s sign-in page; the session arrives with the redirect
  /// back.
  Future<void> signInWith(SocialProvider provider);

  /// Signs this device out. Succeeds once this device holds no session,
  /// also when the server could not be told (offline).
  Future<void> signOut();

  /// Deletes the account and everything stored with it on the server
  /// (`public.delete_my_account()`).
  Future<void> deleteAccount();
}

/// The gateway for this build, or null when no backend is configured.
final authGatewayProvider = Provider<AuthGateway?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseAuthGateway(client);
});

/// Where the web app sends people to sign in elsewhere and come back:
/// the page it was served from, without query or fragment.
String webRedirectUrl() => '${Uri.base.origin}${Uri.base.path}';

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client, {this.signOutTimeout = const Duration(seconds: 10)});

  final SupabaseClient _client;

  /// How long sign-out waits for the server. Auth forgets the session on
  /// this device first, so a network that drops packets (instead of
  /// refusing them) never holds up signing out.
  final Duration signOutTimeout;

  GoTrueClient get _auth => _client.auth;

  /// Phones return through the `app.wyrd://` link; desktop builds have none.
  static bool get _isPhone =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  List<SocialProvider> get socialProviders => [
    if (kIsWeb || _isPhone) ...[
      if (AuthConfig.googleEnabled) SocialProvider.google,
      if (AuthConfig.githubEnabled) SocialProvider.github,
    ],
  ];

  @override
  Future<void> sendCode(CodePurpose purpose, String email) => switch (purpose) {
    CodePurpose.signIn => _auth.signInWithOtp(email: email),
    CodePurpose.signUp => _auth.resend(type: OtpType.signup, email: email),
    CodePurpose.recovery => _auth.resetPasswordForEmail(email),
  };

  @override
  Future<void> verifyCode(CodePurpose purpose, String email, String code) => _auth.verifyOTP(
    email: email,
    token: code,
    type: switch (purpose) {
      // `email` accepts both the sign-in code and the first code a new
      // address gets (its confirmation).
      CodePurpose.signIn => OtpType.email,
      CodePurpose.signUp => OtpType.signup,
      CodePurpose.recovery => OtpType.recovery,
    },
  );

  @override
  Future<void> signInWithPassword(String email, String password) =>
      _auth.signInWithPassword(email: email, password: password);

  @override
  Future<bool> signUp(String email, String password) async {
    final res = await _auth.signUp(email: email, password: password);
    // With confirmations on, Auth answers an address that already has an
    // account with a stand-in user without identities, and sends nothing.
    if (res.session == null && res.user?.identities?.isEmpty == true) {
      throw const AuthException('User already registered', code: AuthCodes.userExists);
    }
    return res.session == null;
  }

  @override
  Future<void> updatePassword(String password) => _auth.updateUser(UserAttributes(password: password));

  @override
  Future<void> signInWith(SocialProvider provider) async {
    final launched = await _auth.signInWithOAuth(
      provider.oauth,
      redirectTo: kIsWeb ? webRedirectUrl() : AuthConfig.mobileRedirectUrl,
      // Phones open the real browser, where the account may already be
      // signed in (and Google refuses embedded web views); the web app
      // leaves and comes back in the same tab.
      authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      // Google: always let people pick which account to use.
      queryParams: provider == SocialProvider.google ? const {'prompt': 'select_account'} : null,
    );
    if (!launched) throw const AuthException('Could not open the sign-in page', code: 'provider_disabled');
  }

  /// Auth forgets the session on this device first and then revokes it on
  /// the server. Offline that last call fails although this device is
  /// already signed out: it no longer holds the tokens, and the access token
  /// runs out by itself. Only a sign-out that leaves a session here failed.
  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut().timeout(signOutTimeout);
    } on Object catch (error) {
      if (_auth.currentSession != null) rethrow;
      debugPrint('Signed out on this device; the server was not told ($error)');
    }
  }

  @override
  Future<void> deleteAccount() => _client.rpc<void>('delete_my_account');
}
