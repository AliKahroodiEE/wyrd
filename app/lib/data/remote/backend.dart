import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';

/// Initializes Supabase when this build is configured for a backend.
/// Returns false in guest-only builds; nothing else then touches the
/// network (ADR-003).
Future<bool> initBackend() async {
  if (!BackendConfig.isConfigured) return false;
  await Supabase.initialize(
    url: BackendConfig.url,
    publishableKey: BackendConfig.publishableKey,
    // OAuth returns with a PKCE `?code=`. supabase_flutter watches incoming
    // links (app_links on Android/iOS, the page URL on the web) and trades
    // the code for a session.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      detectSessionInUriPredicate: isAuthCallbackUri,
    ),
  );
  return true;
}

/// Whether an incoming link is a sign-in callback. Phones only accept
/// `app.wyrd://auth-callback`, so other app links that happen to carry a
/// `code` (guild invites, say) are never mistaken for one.
bool isAuthCallbackUri(Uri uri) {
  if (uri.scheme == AuthConfig.mobileScheme) return uri.host == AuthConfig.mobileCallbackHost;
  final fragment = Uri.splitQueryString(uri.fragment);
  return const [
    'code',
    'access_token',
    'error',
    'error_code',
    'error_description',
  ].any((k) => uri.queryParameters.containsKey(k) || fragment.containsKey(k));
}

/// Whether [initBackend] succeeded; overridden in `main()`.
final backendReadyProvider = Provider<bool>((ref) => false);

SupabaseClient? _client(Ref ref) => ref.watch(backendReadyProvider) ? Supabase.instance.client : null;

final supabaseClientProvider = Provider<SupabaseClient?>(_client);

/// The signed-in user, or null for guests and unconfigured builds.
final currentUserProvider = StreamProvider<User?>((ref) async* {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    yield null;
    return;
  }
  yield client.auth.currentUser;
  // A token refresh while offline or an OAuth callback that returns an
  // error arrives as a stream error; the session is unchanged by it, and
  // letting it through would end this stream for good. [authErrorsProvider]
  // passes those errors on.
  await for (final state in client.auth.onAuthStateChange.handleError((Object _) {})) {
    yield state.session?.user;
  }
});

/// The errors Auth reports on its event stream, as they come: a Google or
/// GitHub sign-in that came back refused or broken (supabase_flutter reports
/// what the link brought), but also token refreshes that failed offline and
/// a stored session that is missing or expired (`isRedirectSignInError` in
/// features/auth tells them apart). Earlier errors are replayed to a new
/// listener, so one from the link that reopened the web app reaches the app
/// once it is up.
final authErrorsProvider = Provider<Stream<Object>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream.empty();
  return client.auth.onAuthStateChange.transform(
    StreamTransformer<AuthState, Object>.fromHandlers(
      handleData: (_, _) {},
      handleError: (error, _, sink) => sink.add(error),
    ),
  );
});
