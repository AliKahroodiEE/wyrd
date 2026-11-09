import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../data/remote/backend.dart';
import '../../l10n/generated/app_localizations.dart';
import 'push_config.dart';
import 'push_platform.dart';
import 'push_service.dart';

/// This device's push registration. Inert unless the build is configured for
/// both Supabase and Firebase; Firebase itself starts only once someone signs
/// in, or to invalidate a token an account left on the device.
final pushServiceProvider = Provider<PushService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = PushService(
    messaging: client != null && PushConfig.isConfigured
        ? FirebasePushMessaging(start: PushConfig.start, channel: () => _channelLabels(ref))
        : null,
    registry: client == null ? null : SupabasePushRegistry(client),
    log: PrefsPushDeviceLog(),
    platform: PushConfig.platform,
    promptOnSettingsOpen: !kIsWeb,
  );
  ref.onDispose(service.dispose);
  if (!service.isAvailable) return service;

  final shown = service.messages.listen((message) => _showInApp(ref, message));
  final opened = service.opened.listen((message) => _open(ref, message));
  ref.onDispose(() {
    shown.cancel();
    opened.cancel();
  });
  // Not while the session loads: a signed-in launch would pass for a signed-out one.
  ref.listen(currentUserProvider, (_, user) {
    if (user.hasValue) service.setUser(user.value?.id);
  }, fireImmediately: true);
  ref.listen(
    profileProvider.select(
      (p) => switch (p.value) {
        final profile? => PushPreferences(guild: profile.notifGuild, weekly: profile.notifWeekly),
        null => null,
      },
    ),
    (_, preferences) => service.setPreferences(preferences),
    fireImmediately: true,
  );
  return service;
});

/// Keeps push running for as long as the app runs, so tokens stay
/// registered, refreshed and retired all session, not only while Settings
/// is open, and tells it when the app returns to the foreground, where a
/// token left to invalidate is tried again. `main()` wraps the app in it.
/// Builds without push skip it, and nothing here waits on Firebase, so the
/// first frame is never held up.
class PushHost extends ConsumerStatefulWidget {
  const PushHost({required this.child, this.configured, super.key});

  final Widget child;

  /// Whether this build has push; [PushConfig.isConfigured] when null (tests
  /// set it).
  final bool? configured;

  @override
  ConsumerState<PushHost> createState() => _PushHostState();
}

class _PushHostState extends ConsumerState<PushHost> {
  AppLifecycleListener? _lifecycle;

  bool get _configured => widget.configured ?? PushConfig.isConfigured;

  @override
  void initState() {
    super.initState();
    if (_configured) _lifecycle = AppLifecycleListener(onResume: _resumed);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  void _resumed() {
    try {
      ref.read(pushServiceProvider).resumed();
    } on Object catch (error) {
      debugPrint('Push not started: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_configured) {
      ref.listen(pushServiceProvider, (_, _) {}, onError: (error, _) => debugPrint('Push not started: $error'));
    }
    return widget.child;
  }
}

/// Where a push leads in the app, or null when it has no screen of its own.
String? pushRoute(Map<String, String> data) {
  final guildId = data['guild_id'];
  if (guildId != null && _uuid.hasMatch(guildId)) return '/guilds/$guildId';
  return data['category'] == 'weekly_summary' ? '/chronicle' : null;
}

final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// How a push that arrives while the app is open is shown: the system only
/// draws notifications while the app is in the background. [onOpen] goes to
/// the push's screen, when it has one.
SnackBar pushSnackBar(AppLocalizations l10n, PushMessage message, {VoidCallback? onOpen}) {
  final title = message.title?.trim() ?? '';
  final body = message.body?.trim() ?? '';
  return SnackBar(
    content: title.isEmpty && body.isEmpty
        ? Text(l10n.pushInAppFallback)
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty) Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (body.isNotEmpty) Text(body),
            ],
          ),
    action: onOpen == null ? null : SnackBarAction(label: l10n.pushOpen, onPressed: onOpen),
  );
}

PushChannelLabels _channelLabels(Ref ref) {
  final l10n = lookupAppLocalizations(ref.read(regionalProvider).locale);
  return (name: l10n.pushChannelName, description: l10n.pushChannelDescription);
}

void _showInApp(Ref ref, PushMessage message) {
  final router = ref.read(routerProvider);
  final context = router.routerDelegate.navigatorKey.currentContext;
  final messenger = context == null ? null : ScaffoldMessenger.maybeOf(context);
  if (context == null || messenger == null) return;
  final route = pushRoute(message.data);
  messenger.showSnackBar(
    pushSnackBar(AppLocalizations.of(context), message, onOpen: route == null ? null : () => router.go(route)),
  );
}

/// A tapped notification opens its screen.
void _open(Ref ref, PushMessage message) {
  final route = pushRoute(message.data);
  if (route != null) ref.read(routerProvider).go(route);
}
