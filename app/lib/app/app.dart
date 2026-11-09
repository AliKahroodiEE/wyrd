import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/remote/backend.dart';
import '../data/sync/sync_coordinator.dart';
import '../data/repositories/settings_repository.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../features/auth/auth_errors.dart';
import '../features/auth/sign_in_link.dart';
import '../features/reminders/reminder_coordinator.dart';
import '../l10n/generated/app_localizations.dart';
import 'providers.dart';
import 'router.dart';

class WyrdApp extends ConsumerStatefulWidget {
  const WyrdApp({super.key});

  @override
  ConsumerState<WyrdApp> createState() => _WyrdAppState();
}

class _WyrdAppState extends ConsumerState<WyrdApp> {
  /// Shows messages that belong to no one screen.
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<Object>? _authErrors;

  @override
  void initState() {
    super.initState();
    // A Google or GitHub sign-in that came back refused or broken. The web
    // app reloads on the way back, so no sign-in screen is open to say so.
    ref.listenManual(authErrorsProvider, (_, errors) {
      unawaited(_authErrors?.cancel());
      _authErrors = errors.where(isRedirectSignInError).listen(_showAuthError);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    unawaited(_authErrors?.cancel());
    super.dispose();
  }

  void _showAuthError(Object error) {
    final messenger = _messenger.currentState;
    if (messenger == null) return;
    // The messenger sits above the app's localizations; the snack bar's
    // content is built inside a screen, which has them.
    messenger.showSnackBar(
      SnackBar(content: Builder(builder: (context) => Text(authErrorMessage(context.l10n, error)))),
    );
    // Said once: reloading the web app must not bring it back from the address.
    forgetSignInError();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(reminderCoordinatorProvider);
    ref.watch(syncCoordinatorProvider);
    final regional = ref.watch(regionalProvider);
    final reducedMotion = ref.watch(profileProvider.select((p) => p.value?.reducedMotion ?? false));
    final theme =
        ref.watch(profileProvider.select((p) => p.value?.theme)) ?? ref.watch<ThemePreference>(initialThemeProvider);
    return MaterialApp.router(
      scaffoldMessengerKey: _messenger,
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (c) => AppLocalizations.of(c).appName,
      routerConfig: ref.watch(routerProvider),
      locale: regional.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: buildAppTheme(regional.locale, Palette.light),
      darkTheme: buildAppTheme(regional.locale, Palette.dark),
      themeMode: switch (theme) {
        ThemePreference.system => ThemeMode.system,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      },
      themeAnimationDuration: AppMotion.settle,
      themeAnimationCurve: AppMotion.standard,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(disableAnimations: mq.disableAnimations || reducedMotion),
          child: child!,
        );
      },
    );
  }
}
