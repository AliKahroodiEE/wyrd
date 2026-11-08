import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wyrd/app/providers.dart';
import 'package:wyrd/core/locale/regional_settings.dart';
import 'package:wyrd/data/ai/ai_settings_repository.dart';
import 'package:wyrd/data/db/database.dart';
import 'package:wyrd/data/remote/backend.dart';
import 'package:wyrd/design/theme.dart';
import 'package:wyrd/design/tokens.dart';
import 'package:wyrd/l10n/generated/app_localizations.dart';

AppDatabase memoryDatabase() =>
    AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));

/// Closes [db] at the end of a test that passed. Not in a tear-down: after a
/// failure the widgets stay mounted with queries waiting on a test clock
/// that no longer moves, and closing would wait for them forever.
Future<void> closeDatabase(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(db.close);
}

/// Shows [page] on [db] for a guest, with a `/quests` page to return to.
Future<void> pumpQuestPage(
  WidgetTester tester,
  AppDatabase db,
  Widget page, {
  Locale locale = const Locale('en'),
  Size size = const Size(440, 1400),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/page',
    routes: [
      GoRoute(
        path: '/quests',
        builder: (_, _) => const Scaffold(body: Text('quests page')),
      ),
      GoRoute(path: '/page', builder: (_, _) => page),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        regionalProvider.overrideWithValue(RegionalPrefs(language: locale.languageCode).resolve(locale)),
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        aiSettingsRepositoryProvider.overrideWithValue(AiSettingsRepository(db, MemoryKeyStore())),
        ...overrides,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildAppTheme(locale, Palette.dark),
      ),
    ),
  );
  await settle(tester);
}

/// Lets database calls finish and sheets and sections finish moving.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The form field labelled [label].
Finder field(String label) => find.widgetWithText(TextFormField, label);

/// The text in the form field labelled [label].
String fieldText(WidgetTester tester, String label) => tester.widget<TextFormField>(field(label)).controller!.text;

/// Scrolls [finder] into view and taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}
