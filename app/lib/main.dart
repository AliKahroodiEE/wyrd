import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'dart:ui' show PlatformDispatcher;

import 'app/app.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'core/locale/locale_registry.dart';
import 'data/db/database.dart';
import 'data/demo/demo_seed.dart';
import 'data/remote/backend.dart';
import 'data/repositories/settings_repository.dart';
import 'features/auth/handover_host.dart';
import 'features/notifications/push_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  final backendReady = await initBackend();
  final db = AppDatabase();
  // Demo builds (`--dart-define=WYRD_DEMO=true`) start with sample data.
  if (const bool.fromEnvironment('WYRD_DEMO') && !(await SettingsRepository(db).profile()).onboardingComplete) {
    // Seed in the visitor's language unless the build pins one.
    const pinned = String.fromEnvironment('WYRD_DEMO_LOCALE');
    final locale = pinned.isEmpty
        ? LocaleRegistry.resolveAll(PlatformDispatcher.instance.locales)
        : Locale(pinned); // ignore: prefer_const_constructors
    await seedDemo(db, locale: locale, pinLanguage: pinned.isNotEmpty);
  }
  final settings = SettingsRepository(db);
  final profile = await settings.profile();
  final regionalPrefs = await settings.regionalPrefs();
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backendReadyProvider.overrideWithValue(backendReady),
        initialOnboardedProvider.overrideWithValue(profile.onboardingComplete),
        initialThemeProvider.overrideWithValue(profile.theme),
        initialRegionalPrefsProvider.overrideWithValue(regionalPrefs),
      ],
      // Push, when configured (never delays the first frame), and the question
      // a sign-in asks when another account left unsynced work here.
      child: const PushHost(child: HandoverHost(child: WyrdApp())),
    ),
  );
}
