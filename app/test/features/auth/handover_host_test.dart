import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wyrd/app/providers.dart';
import 'package:wyrd/app/router.dart';
import 'package:wyrd/core/locale/regional_settings.dart';
import 'package:wyrd/data/sync/sync_coordinator.dart';
import 'package:wyrd/design/theme.dart';
import 'package:wyrd/design/tokens.dart';
import 'package:wyrd/features/auth/auth_gateway.dart';
import 'package:wyrd/features/auth/handover_host.dart';
import 'package:wyrd/l10n/generated/app_localizations.dart';

import 'fake_auth_gateway.dart';

void main() {
  Future<(FakeAuthGateway, ProviderContainer)> pump(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    final gateway = FakeAuthGateway();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('character page')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routerProvider.overrideWithValue(router),
          authGatewayProvider.overrideWithValue(gateway),
          regionalProvider.overrideWithValue(RegionalPrefs(language: locale.languageCode).resolve(locale)),
        ],
        child: HandoverHost(
          child: MaterialApp.router(
            routerConfig: router,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: buildAppTheme(locale, Palette.dark),
          ),
        ),
      ),
    );
    await settle(tester);
    return (gateway, ProviderScope.containerOf(tester.element(find.byType(HandoverHost))));
  }

  testWidgets('removing the other account\'s changes lets the new account sync', (tester) async {
    final (gateway, container) = await pump(tester);
    final answer = container
        .read(handoverProvider.notifier)
        .ask(Handover(previousEmail: 'arin@example.com', unsynced: 3));
    await settle(tester);
    expect(find.text('Unsaved changes from another account'), findsOneWidget);
    expect(find.textContaining('arin@example.com'), findsOneWidget);
    expect(find.textContaining('3 changes'), findsOneWidget);

    await tester.tap(find.text('Remove them and continue'));
    await settle(tester);
    expect(await answer, isTrue);
    expect(gateway.calls, isEmpty);
    expect(container.read(handoverProvider), isNull);
  });

  testWidgets('keeping them signs the new account out again', (tester) async {
    final (gateway, container) = await pump(tester);
    final answer = container.read(handoverProvider.notifier).ask(Handover(previousEmail: null, unsynced: 1));
    await settle(tester);
    expect(find.textContaining('Another account has 1 change on this device'), findsOneWidget);

    await tester.tap(find.text('Keep them and sign out'));
    await settle(tester);
    expect(await answer, isFalse);
    expect(gateway.calls, ['signOut']);
  });

  testWidgets('Persian: the question reads right to left with the address isolated', (tester) async {
    final (_, container) = await pump(tester, locale: const Locale('fa'));
    final answer = container
        .read(handoverProvider.notifier)
        .ask(Handover(previousEmail: 'arin@example.com', unsynced: 2));
    await settle(tester);
    expect(find.text('تغییرهای ذخیره‌نشده‌ی یک حساب دیگر'), findsOneWidget);
    expect(find.textContaining('\u2068arin@example.com\u2069'), findsOneWidget);
    await tester.tap(find.text('پاکشان کن و ادامه بده'));
    await settle(tester);
    expect(await answer, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a withdrawn question closes without signing anyone out', (tester) async {
    final (gateway, container) = await pump(tester);
    final question = Handover(previousEmail: 'arin@example.com', unsynced: 3);
    final answer = container.read(handoverProvider.notifier).ask(question);
    await settle(tester);
    expect(find.text('Unsaved changes from another account'), findsOneWidget);

    container.read(handoverProvider.notifier).withdraw(question);
    await settle(tester);
    expect(find.text('Unsaved changes from another account'), findsNothing);
    expect(await answer, isFalse);
    expect(question.withdrawn, isTrue);
    expect(gateway.calls, isEmpty);
  });
}
