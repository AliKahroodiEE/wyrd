import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wyrd_engine/wyrd_engine.dart';

import '../data/remote/backend.dart';
import '../design/components/motion.dart';
import '../features/auth/auth_screen.dart';
import '../features/character/character_screen.dart';
import '../features/chronicle/chronicle_screen.dart';
import '../features/chronicle/ledger_screen.dart';
import '../features/guilds/guild_hall_screen.dart';
import '../features/guilds/guilds_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/quests/quest_editor_screen.dart';
import '../features/quests/quests_screen.dart';
import '../features/settings/ai_provider_screen.dart';
import '../features/settings/settings_screen.dart';
import 'providers.dart';
import 'shell.dart';

/// Whether onboarding was complete at launch; overridden in `main()` so
/// the first frame lands on the right screen.
final initialOnboardedProvider = Provider<bool>((ref) => false);

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Whether [location] is what Auth appended to a sign-in link
/// (`#error=access_denied&error_description=…`) rather than a screen.
bool _isSignInLinkFragment(Uri location) =>
    location.pathSegments.length == 1 && isAuthCallbackUri(Uri(query: location.pathSegments.single));

final routerProvider = Provider<GoRouter>((ref) {
  final onboarded = ValueNotifier<bool>(ref.read(initialOnboardedProvider));
  ref.listen(profileProvider, (_, next) {
    final v = next.value?.onboardingComplete;
    if (v != null) onboarded.value = v;
  });

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: onboarded.value ? '/character' : '/onboarding',
    refreshListenable: onboarded,
    redirect: (context, state) {
      // A sign-in that came back with an error also carries it in the URL
      // fragment, which the web app's hash routing reads as a location. Go
      // home instead of "Page Not Found"; the app explains the error there.
      if (_isSignInLinkFragment(state.uri)) return onboarded.value ? '/character' : '/onboarding';
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!onboarded.value && !atOnboarding) return '/onboarding';
      if (onboarded.value && atOnboarding) return '/character';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(
        path: '/quest/new',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, state) => MaterialPage(
          fullscreenDialog: true,
          child: QuestEditorScreen(
            initialTier: QuestTier.parse(state.uri.queryParameters['tier']),
            parentId: state.uri.queryParameters['parent'],
          ),
        ),
      ),
      GoRoute(
        path: '/quest/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => QuestEditorScreen(questId: state.pathParameters['id']),
      ),
      GoRoute(path: '/auth', parentNavigatorKey: _rootKey, builder: (_, _) => const AuthScreen()),
      GoRoute(path: '/settings/ai', parentNavigatorKey: _rootKey, builder: (_, _) => const AiProviderScreen()),
      GoRoute(path: '/settings', parentNavigatorKey: _rootKey, builder: (_, _) => const SettingsScreen()),
      StatefulShellRoute(
        builder: (_, _, shell) => AdaptiveShell(shell: shell),
        // Branches stay alive; the selected one fades in.
        navigatorContainerBuilder: (_, shell, children) =>
            FadeIndexedStack(index: shell.currentIndex, children: children),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/character', builder: (_, _) => const CharacterScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/quests', builder: (_, _) => const QuestsScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/guilds',
                builder: (_, _) => const GuildsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => GuildHallScreen(guildId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chronicle',
                builder: (_, _) => const ChronicleScreen(),
                routes: [GoRoute(path: 'ledger', builder: (_, _) => const LedgerScreen())],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    onboarded.dispose();
  });
  return router;
});
