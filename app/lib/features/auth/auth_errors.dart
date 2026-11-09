import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/generated/app_localizations.dart';

/// Auth error codes (https://supabase.com/docs/guides/auth/debugging/error-codes)
/// the sign-in flow explains in its own words.
abstract final class AuthCodes {
  static const invalidCredentials = 'invalid_credentials';
  static const emailNotConfirmed = 'email_not_confirmed';
  static const otpExpired = 'otp_expired';
  static const weakPassword = 'weak_password';
  static const samePassword = 'same_password';
  static const userExists = 'user_already_exists';
  static const emailExists = 'email_exists';
  static const badEmail = {'validation_failed', 'email_address_invalid'};
  static const rateLimits = {'over_email_send_rate_limit', 'over_request_rate_limit', 'over_sms_send_rate_limit'};
  static const timeouts = {'request_timeout'};
  static const unavailable = {
    'provider_disabled',
    'email_provider_disabled',
    // Supabase's built-in mailer only reaches the project's team.
    'email_address_not_authorized',
    'oauth_provider_not_supported',
    'signup_disabled',
    'bad_oauth_state',
    'bad_oauth_callback',
  };

  /// The provider's page was left without signing in.
  static const accessDenied = 'access_denied';

  /// What gotrue reports about the session it keeps itself, rather than
  /// about a sign-in: a stored session that is missing or has expired, and a
  /// refresh token the server refused.
  static const ownSession = {
    'session_missing',
    'session_expired',
    'refresh_token_not_found',
    'refresh_token_already_used',
  };
}

/// Whether [error] is Auth reporting [code].
bool isAuthCode(Object error, String code) => error is AuthException && error.code == code;

/// Whether [error], from Auth's event stream, is a Google or GitHub sign-in
/// that came back refused or broken, which the app reports.
///
/// supabase_flutter puts every AuthException from a sign-in link there: the
/// error the link carries (`?error=server_error&error_code=…`, or the
/// provider's own), or the one that trading its code for a session ran into.
/// gotrue 2.27.3 puts its own errors about the session it keeps there too,
/// and those are not news:
/// - [AuthRetryableFetchException]: offline or a 5xx answer, from a token
///   refresh (`_doRefresh`) or from signing out a stored session that expired
///   (`recoverSession`); Auth tries again later. A code trade that fails this
///   way stays quiet as well.
/// - `session_missing` and `session_expired`: a stored session that cannot be
///   read (`setInitialSession`, `recoverSession`) or that expired with no way
///   to refresh it (`recoverSession`).
/// - The server refusing a refresh token (`refresh_token_not_found`,
///   `refresh_token_already_used`), or no session to refresh
///   ([AuthSessionMissingException]): gotrue 2.27.3 signs out instead of
///   reporting these (before 2.23.0, `recoverSession` reported a refused
///   refresh token here).
///
/// Errors that are not AuthExceptions (stored session data that is not JSON,
/// say) are not news either.
bool isRedirectSignInError(Object error) =>
    error is AuthException &&
    error is! AuthRetryableFetchException &&
    error is! AuthSessionMissingException &&
    !AuthCodes.ownSession.contains(error.code);

/// The most specific code Auth gave for [error]. A sign-in link that comes
/// back with an error carries two, and gotrue files the link's `error`
/// (`access_denied`, `invalid_request`) as [AuthException.code] and Auth's
/// own `error_code` (`bad_oauth_state`), if any, as [AuthException.statusCode].
String? _code(AuthException error) {
  final status = error.statusCode;
  return status != null && status.isNotEmpty && int.tryParse(status) == null ? status : error.code;
}

/// A message for [error] in the reader's language.
String authErrorMessage(AppLocalizations l10n, Object error) {
  // No connection: Auth retries later; database calls fail in the HTTP client.
  if (error is AuthRetryableFetchException || error is ClientException) return l10n.authErrNetwork;
  if (error is AuthWeakPasswordException) return l10n.authErrWeakPassword;
  if (error is AuthException) {
    final code = _code(error);
    if (code == AuthCodes.invalidCredentials) return l10n.authInvalid;
    if (code == AuthCodes.emailNotConfirmed) return l10n.authErrNotConfirmed;
    if (code == AuthCodes.otpExpired) return l10n.authErrCode;
    if (code == AuthCodes.weakPassword) return l10n.authErrWeakPassword;
    if (code == AuthCodes.samePassword) return l10n.authErrSamePassword;
    if (code == AuthCodes.userExists || code == AuthCodes.emailExists) return l10n.authErrAccountExists;
    if (AuthCodes.badEmail.contains(code)) return l10n.authErrEmail;
    if (AuthCodes.rateLimits.contains(code) || error.statusCode == '429') return l10n.authErrRateLimit;
    if (AuthCodes.timeouts.contains(code)) return l10n.authErrNetwork;
    if (AuthCodes.unavailable.contains(code)) return l10n.authErrProvider;
    if (code == AuthCodes.accessDenied) return l10n.authErrCancelled;
  }
  return l10n.errorGeneric;
}
