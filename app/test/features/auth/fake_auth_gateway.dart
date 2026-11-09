import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wyrd/app/providers.dart';
import 'package:wyrd/core/locale/regional_settings.dart';
import 'package:wyrd/design/theme.dart';
import 'package:wyrd/design/tokens.dart';
import 'package:wyrd/features/auth/auth_gateway.dart';
import 'package:wyrd/features/auth/auth_screen.dart';
import 'package:wyrd/l10n/generated/app_localizations.dart';

/// Records calls instead of talking to Supabase.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({this.socialProviders = const []});

  @override
  final List<SocialProvider> socialProviders;

  final calls = <String>[];

  /// Thrown by the next call, then cleared.
  Object? failWith;
  bool signUpNeedsCode = true;

  Future<void> _record(String call) async {
    calls.add(call);
    final error = failWith;
    if (error != null) {
      failWith = null;
      throw error;
    }
  }

  @override
  Future<void> sendCode(CodePurpose purpose, String email) => _record('sendCode:${purpose.name}:$email');

  @override
  Future<void> verifyCode(CodePurpose purpose, String email, String code) =>
      _record('verifyCode:${purpose.name}:$email:$code');

  @override
  Future<void> signInWithPassword(String email, String password) => _record('signInWithPassword:$email');

  @override
  Future<bool> signUp(String email, String password) async {
    await _record('signUp:$email');
    return signUpNeedsCode;
  }

  @override
  Future<void> updatePassword(String password) => _record('updatePassword');

  @override
  Future<void> signInWith(SocialProvider provider) => _record(provider.name);

  @override
  Future<void> signOut() => _record('signOut');

  @override
  Future<void> deleteAccount() => _record('deleteAccount');
}

/// Shows [page] at `/start`, with `/character` and `/onboarding` pages to
/// move on to, in [locale] and the [palette] theme.
Future<void> pumpPage(
  WidgetTester tester,
  Widget page, {
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
  Palette palette = Palette.dark,
}) async {
  tester.view.physicalSize = const Size(440, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/character',
        builder: (_, _) => const Scaffold(body: Text('character page')),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const Scaffold(body: Text('onboarding page')),
      ),
      GoRoute(path: '/start', builder: (_, _) => page),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        regionalProvider.overrideWithValue(RegionalPrefs(language: locale.languageCode).resolve(locale)),
        ...overrides,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildAppTheme(locale, palette),
      ),
    ),
  );
  await settle(tester);
}

/// The sign-in screen; a null [gateway] leaves the build without a backend.
Future<void> pumpAuthScreen(
  WidgetTester tester, {
  AuthGateway? gateway,
  Locale locale = const Locale('en'),
  Palette palette = Palette.dark,
}) => pumpPage(
  tester,
  const AuthScreen(),
  overrides: [authGatewayProvider.overrideWithValue(gateway)],
  locale: locale,
  palette: palette,
);

/// Lets fake calls complete and step transitions finish.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
