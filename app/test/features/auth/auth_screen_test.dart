import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:wyrd/design/tokens.dart';
import 'package:wyrd/features/auth/auth_gateway.dart';
import 'package:wyrd/features/auth/auth_widgets.dart';

import 'fake_auth_gateway.dart';

void main() {
  const email = 'ash@example.com';

  Future<void> openCodeStep(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), email);
    await tester.tap(find.text('Continue with email'));
    await settle(tester);
  }

  Future<void> openPasswordStep(WidgetTester tester) async {
    await tester.tap(find.text('Use a password instead'));
    await settle(tester);
  }

  testWidgets('email: sends a code, takes Persian digits and returns once verified', (tester) async {
    final fake = FakeAuthGateway();
    await pumpAuthScreen(tester, gateway: fake);
    await openCodeStep(tester);

    expect(fake.calls, ['sendCode:signIn:$email']);
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining(email), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
    expect(field.keyboardType, TextInputType.number);

    await tester.enterText(find.byType(TextField), '۱۲۳۴۵۶');
    await settle(tester);
    expect(fake.calls.last, 'verifyCode:signIn:$email:123456');
    expect(find.text('character page'), findsOneWidget);
  });

  testWidgets('code: a wrong code is explained; resend unlocks after 60 s; paste fills the code', (tester) async {
    final fake = FakeAuthGateway();
    await pumpAuthScreen(tester, gateway: fake);
    await openCodeStep(tester);

    fake.failWith = const AuthException('Token has expired or is invalid', statusCode: '403', code: 'otp_expired');
    await tester.enterText(find.byType(TextField), '000000');
    await settle(tester);
    expect(find.text('That code is wrong or has expired. Check it, or ask for a new one.'), findsOneWidget);

    final waiting = find.widgetWithText(TextButton, 'New code in 60s');
    expect(tester.widget<TextButton>(waiting).onPressed, isNull);
    await tester.pump(const Duration(seconds: 60));
    await tester.tap(find.text('Send a new code'));
    await settle(tester);
    expect(fake.calls.where((c) => c == 'sendCode:signIn:$email'), hasLength(2));
    expect(find.text('A new code is on its way.'), findsOneWidget);
    expect(find.text('New code in 60s'), findsOneWidget);

    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': 'Your Wyrd code is 482 913'};
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.byTooltip('Paste code'));
    await settle(tester);
    expect(fake.calls.last, 'verifyCode:signIn:$email:482913');
  });

  testWidgets('code: "Use a different email" goes back to the address', (tester) async {
    await pumpAuthScreen(tester, gateway: FakeAuthGateway());
    await openCodeStep(tester);
    await tester.tap(find.text('Use a different email'));
    await settle(tester);
    expect(find.text('Continue with email'), findsOneWidget);
    expect(find.text(email), findsOneWidget, reason: 'the address is kept for editing');
  });

  testWidgets('password: bad credentials explained, then a new account confirmed by code', (tester) async {
    final fake = FakeAuthGateway();
    await pumpAuthScreen(tester, gateway: fake);
    await openPasswordStep(tester);
    expect(find.text('Forgot password?'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), 'ember2026');
    fake.failWith = const AuthException('Invalid login credentials', statusCode: '400', code: 'invalid_credentials');
    await tester.tap(find.text('Sign in'));
    await settle(tester);
    expect(fake.calls, ['signInWithPassword:$email']);
    expect(find.text("That email and password don't match."), findsOneWidget);

    await tester.tap(find.text('Create account'));
    await settle(tester);
    expect(fake.calls.last, 'signUp:$email');
    expect(find.text('Check your email'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await settle(tester);
    expect(fake.calls.last, 'verifyCode:signUp:$email:123456');
    expect(find.text('character page'), findsOneWidget);
  });

  testWidgets('password: a new password needs a letter and a digit before anything is sent', (tester) async {
    final fake = FakeAuthGateway();
    await pumpAuthScreen(tester, gateway: fake);
    await openPasswordStep(tester);
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), 'emberglowing');
    await tester.tap(find.text('Create account'));
    await settle(tester);
    expect(fake.calls, isEmpty);
    expect(find.textContaining('stronger password'), findsOneWidget);
  });

  testWidgets('password: an existing address is told to sign in', (tester) async {
    final fake = FakeAuthGateway();
    await pumpAuthScreen(tester, gateway: fake);
    await openPasswordStep(tester);
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), 'ember2026');
    fake.failWith = const AuthException('User already registered', code: 'user_already_exists');
    await tester.tap(find.text('Create account'));
    await settle(tester);
    expect(find.text('An account with this email already exists. Sign in instead.'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget, reason: 'still on the password step');
  });

  testWidgets('password: an unconfirmed address gets a fresh code', (tester) async {
    final fake = FakeAuthGateway();
    await pumpAuthScreen(tester, gateway: fake);
    await openPasswordStep(tester);
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), 'ember2026');
    fake.failWith = const AuthException('Email not confirmed', statusCode: '400', code: 'email_not_confirmed');
    await tester.tap(find.text('Sign in'));
    await settle(tester);

    expect(fake.calls, ['signInWithPassword:$email', 'sendCode:signUp:$email']);
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.text("Confirm your email first. We've sent you a new code."), findsOneWidget);
  });

  testWidgets('forgot password: reset code by email, then a new password', (tester) async {
    final fake = FakeAuthGateway();
    await pumpAuthScreen(tester, gateway: fake);
    await openPasswordStep(tester);
    await tester.enterText(find.byType(TextField).first, email);
    await tester.tap(find.text('Forgot password?'));
    await settle(tester);

    expect(find.text('Reset your password'), findsOneWidget);
    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(fake.calls, ['sendCode:recovery:$email']);

    await tester.enterText(find.byType(TextField), '654321');
    await settle(tester);
    expect(fake.calls.last, 'verifyCode:recovery:$email:654321');
    expect(find.text('Choose a new password'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'short');
    await tester.tap(find.text('Save password'));
    await settle(tester);
    expect(find.textContaining('stronger password'), findsOneWidget);
    expect(fake.calls, isNot(contains('updatePassword')));

    await tester.enterText(find.byType(TextField), 'emberglow42');
    await tester.tap(find.text('Save password'));
    await settle(tester);
    expect(fake.calls.last, 'updatePassword');
    expect(find.text('character page'), findsOneWidget);
  });

  testWidgets('Google and GitHub: hidden unless the build enables them', (tester) async {
    await pumpAuthScreen(tester, gateway: FakeAuthGateway());
    expect(find.text('Continue with email'), findsOneWidget);
    expect(find.text('Continue with GitHub'), findsNothing);
    expect(find.text('or'), findsNothing);
    expect(find.textContaining('Google'), findsNothing);
  });

  testWidgets('Google: shown first, with its own mark, and opens Google', (tester) async {
    final fake = FakeAuthGateway(socialProviders: SocialProvider.values);
    await pumpAuthScreen(tester, gateway: fake);
    final google = tester.getTopLeft(find.text('Continue with Google'));
    final github = tester.getTopLeft(find.text('Continue with GitHub'));
    expect(google.dy, lessThan(github.dy));
    expect(find.byType(ProviderLogo), findsNWidgets(2));

    await tester.tap(find.text('Continue with Google'));
    await settle(tester);
    expect(fake.calls, ['google']);
    expect(find.text('character page'), findsNothing);
  });

  testWidgets('GitHub: opens the provider and waits on this screen for the redirect', (tester) async {
    final fake = FakeAuthGateway(socialProviders: const [SocialProvider.github]);
    await pumpAuthScreen(tester, gateway: fake);
    expect(find.text('or'), findsOneWidget);

    await tester.tap(find.text('Continue with GitHub'));
    await settle(tester);
    expect(fake.calls, ['github']);
    expect(find.text('Continue with GitHub'), findsOneWidget);
    expect(find.text('character page'), findsNothing);

    fake.failWith = const AuthException('Unsupported provider', code: 'provider_disabled');
    await tester.tap(find.text('Continue with GitHub'));
    await settle(tester);
    expect(find.text("This sign-in option isn't available right now."), findsOneWidget);
  });

  testWidgets('an invalid email is caught before anything is sent', (tester) async {
    final fake = FakeAuthGateway();
    await pumpAuthScreen(tester, gateway: fake);
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Continue with email'));
    await settle(tester);
    expect(fake.calls, isEmpty);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('without a backend the screen says so', (tester) async {
    await pumpAuthScreen(tester);
    expect(find.text('Online features are not configured in this build.'), findsOneWidget);
    expect(find.text('Continue with email'), findsNothing);
  });

  testWidgets('light theme: the flow takes its colours from the Vellum palette', (tester) async {
    await pumpAuthScreen(
      tester,
      gateway: FakeAuthGateway(socialProviders: SocialProvider.values),
      palette: Palette.light,
    );
    expect(Theme.of(tester.element(find.text('Continue with email'))).brightness, Brightness.light);
    final emblem = tester.widget<Icon>(find.byIcon(Icons.local_fire_department_rounded));
    expect(emblem.color, Palette.light.accent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Persian: the flow reads right to left', (tester) async {
    await pumpAuthScreen(
      tester,
      gateway: FakeAuthGateway(socialProviders: SocialProvider.values),
      locale: const Locale('fa'),
    );
    expect(find.text('ادامه با ایمیل'), findsOneWidget);
    expect(find.text('ادامه با گوگل'), findsOneWidget);
    expect(find.text('ادامه با گیت‌هاب'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('ادامه با ایمیل'))), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });
}
