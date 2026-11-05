import 'dart:async';
import 'dart:io' show SocketException;

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrd/features/notifications/push_provider.dart';
import 'package:wyrd/features/notifications/push_service.dart';
import 'package:wyrd/features/notifications/push_tile.dart';
import 'package:wyrd/l10n/generated/app_localizations.dart';

/// Firebase stand-in: [answer] is what the user picks at the system prompt.
class FakeMessaging implements PushMessaging {
  bool supported = true;
  PushPermission current = PushPermission.askable;
  PushPermission answer = PushPermission.granted;
  String currentToken = 'token-1';

  /// Thrown by [token], as where no push service answers (Brave with it
  /// switched off, a phone without Google Play services).
  Object? tokenError;

  /// Makes [token] never answer, like a stuck platform call.
  bool tokenHangs = false;

  /// Makes [token] answer only after this long, like a slow platform call.
  Duration? tokenDelay;

  /// Makes [deleteToken] finish only after this long.
  Duration? deleteDelay;

  /// Thrown by [deleteToken], as where FCM cannot be reached (offline).
  Object? deleteError;
  int prompts = 0;

  /// Tokens invalidated: [deleteToken] calls that went through.
  int deletions = 0;

  /// Calls of any kind; the real transport starts Firebase on the first one.
  int calls = 0;
  final refreshes = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  bool get listened => refreshes.hasListener || foreground.hasListener || opened.hasListener;

  @override
  Future<bool> isSupported() async {
    calls++;
    return supported;
  }

  @override
  Future<PushPermission> permission() async {
    calls++;
    return current;
  }

  @override
  Future<PushPermission> requestPermission() async {
    calls++;
    prompts++;
    if (current == PushPermission.askable) current = answer;
    return current;
  }

  @override
  Future<String?> token() async {
    calls++;
    if (tokenHangs) return Completer<String?>().future;
    if (tokenDelay case final delay?) await Future<void>.delayed(delay);
    final error = tokenError;
    if (error != null) throw error;
    return current == PushPermission.granted ? currentToken : null;
  }

  @override
  Future<void> deleteToken() async {
    calls++;
    if (deleteDelay case final delay?) await Future<void>.delayed(delay);
    final error = deleteError;
    if (error != null) throw error;
    deletions++;
    currentToken = 'token-${deletions + 1}'; // FCM issues a fresh one next time.
  }

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<PushMessage> get foregroundMessages => foreground.stream;

  @override
  Stream<PushMessage> get openedMessages => opened.stream;
}

class FakeRegistry implements PushRegistry {
  final registered = <(String, String)>[];
  final unregistered = <String>[];

  /// Makes every call fail, as without a network.
  bool offline = false;

  /// Makes every call wait for good, as on a connection that never answers.
  bool hangs = false;

  Future<void> _reach() async {
    if (hangs) await Completer<void>().future;
    if (offline) throw const SocketException('Failed host lookup');
  }

  @override
  Future<void> register(String token, String platform) async {
    await _reach();
    registered.add((token, platform));
  }

  @override
  Future<void> unregister(String token) async {
    await _reach();
    unregistered.add(token);
  }
}

/// Lives on the device, so it outlasts a [PushService] (see `relaunch`).
class FakeDeviceLog implements PushDeviceLog {
  final asked = <String>{};
  bool retire = false;

  @override
  Future<bool> wasAsked(String userId) async => asked.contains(userId);

  @override
  Future<void> markAsked(String userId) async => asked.add(userId);

  @override
  Future<bool> retirePending() async => retire;

  @override
  Future<void> setRetirePending(bool pending) async => retire = pending;
}

const _both = PushPreferences(guild: true, weekly: true);
const _none = PushPreferences(guild: false, weekly: false);

// What firebase_messaging throws from getToken. On Android the plugin passes
// on the message of FCM's IOException; on the web it maps the Firebase SDK's
// errors and lets the browser's own through.
final _noPlayServices = FirebaseException(
  plugin: 'firebase_messaging',
  message: 'java.io.IOException: MISSING_INSTANCEID_SERVICE',
);
final _offlinePhone = FirebaseException(
  plugin: 'firebase_messaging',
  message: 'java.io.IOException: SERVICE_NOT_AVAILABLE',
);
final _unsupportedBrowser = FirebaseException(
  plugin: 'firebase_messaging',
  code: 'unsupported-browser',
  message: "Messaging: This browser doesn't support the API's required to use the Firebase SDK. ",
);
final _pushServiceError = Exception('AbortError: Registration failed - push service error');

void main() {
  late FakeMessaging messaging;
  late FakeRegistry registry;
  late FakeDeviceLog deviceLog;
  late PushService push;
  final live = <PushService>[];

  PushService keep(PushService service) {
    live.add(service);
    return push = service;
  }

  PushService create({bool promptOnSettingsOpen = false, String platform = 'android'}) => keep(
    PushService(
      messaging: messaging,
      registry: registry,
      log: deviceLog,
      platform: platform,
      promptOnSettingsOpen: promptOnSettingsOpen,
    ),
  );

  /// The app closed and opened again: Firebase and the device log keep what
  /// they had, the service starts from nothing.
  PushService relaunch() {
    live.remove(push);
    push.dispose();
    return create();
  }

  /// Lets stream events reach the service, then waits for its updates.
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await push.settled;
  }

  setUp(() {
    messaging = FakeMessaging();
    registry = FakeRegistry();
    deviceLog = FakeDeviceLog();
  });

  tearDown(() {
    for (final service in live) {
      service.dispose();
    }
    live.clear();
  });

  group('registration', () {
    test('only when signed in, allowed by the switches and granted', () async {
      messaging.current = PushPermission.granted;
      create().setPreferences(_both);
      await settle();
      expect(registry.registered, isEmpty, reason: 'guests never register');
      expect(push.status.value, PushStatus.hidden);

      push.setUser('u1');
      await settle();
      expect(registry.registered, [('token-1', 'android')]);
      expect(push.status.value, PushStatus.on);
    });

    test('not while both switches are off', () async {
      messaging.current = PushPermission.granted;
      create()
        ..setUser('u1')
        ..setPreferences(_none);
      await settle();
      expect(registry.registered, isEmpty);
      expect(push.status.value, PushStatus.hidden);
    });

    test('one switch on is enough', () async {
      messaging.current = PushPermission.granted;
      create()
        ..setUser('u1')
        ..setPreferences(const PushPreferences(guild: false, weekly: true));
      await settle();
      expect(registry.registered, hasLength(1));
    });

    test('waits for the profile before deciding', () async {
      messaging.current = PushPermission.granted;
      create().setUser('u1');
      await settle();
      expect(registry.registered, isEmpty);

      push.setPreferences(_both);
      await settle();
      expect(registry.registered, hasLength(1));
    });

    test('never prompts at launch', () async {
      create(promptOnSettingsOpen: true)
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();
      expect(messaging.prompts, 0);
      expect(registry.registered, isEmpty);
      expect(push.status.value, PushStatus.off);
    });

    test('a blocked permission shows as blocked', () async {
      messaging.current = PushPermission.blocked;
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();
      expect(push.status.value, PushStatus.blocked);
      expect(registry.registered, isEmpty);
    });

    test('a browser without push shows as unsupported', () async {
      messaging
        ..supported = false
        ..current = PushPermission.granted;
      create(platform: 'web')
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();
      expect(push.status.value, PushStatus.unsupported);
      expect(registry.registered, isEmpty);
    });

    test('a token that does not come this time leaves Allow to try again', () async {
      messaging
        ..current = PushPermission.granted
        ..tokenError = _pushServiceError;
      create(platform: 'web')
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();
      expect(push.status.value, PushStatus.off);
      expect(registry.registered, isEmpty);

      messaging.tokenError = null; // A later visit tries again.
      await push.settingsOpened();
      expect(push.status.value, PushStatus.on);
      expect(registry.registered, [('token-1', 'web')]);
    });

    test('a device that can never get a token shows as unsupported', () async {
      for (final (platform, error) in [('android', _noPlayServices), ('web', _unsupportedBrowser)]) {
        messaging = FakeMessaging()
          ..current = PushPermission.granted
          ..tokenError = error;
        create(platform: platform)
          ..setUser('u1')
          ..setPreferences(_both);
        await settle();
        expect(push.status.value, PushStatus.unsupported, reason: platform);
      }
      expect(registry.registered, isEmpty);
    });

    test('builds without Firebase stay inert', () async {
      keep(PushService(messaging: null, registry: registry, log: deviceLog, platform: 'android'))
        ..setUser('u1')
        ..setPreferences(_both);
      await push.enable();
      await settle();
      expect(push.isAvailable, isFalse);
      expect(push.status.value, PushStatus.hidden);
      expect(registry.registered, isEmpty);
    });

    test('guests never start Firebase', () async {
      messaging.current = PushPermission.granted;
      create().setPreferences(_both);
      await push.enable();
      await push.settingsOpened();
      await settle();
      expect(messaging.calls, 0);
      expect(messaging.listened, isFalse);
    });

    test('Firebase starts with the first sign-in', () async {
      create().setPreferences(_both);
      await settle();
      expect(messaging.listened, isFalse);

      push.setUser('u1');
      expect(messaging.listened, isTrue);
    });

    test('the same token is registered once per session', () async {
      messaging.current = PushPermission.granted;
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();
      await push.settingsOpened();
      await push.settingsOpened();
      expect(registry.registered, hasLength(1));
    });
  });

  group('refresh', () {
    test('a new token is registered again', () async {
      messaging.current = PushPermission.granted;
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();

      messaging.currentToken = 'token-9';
      messaging.refreshes.add('token-9');
      await settle();
      expect(registry.registered, [('token-1', 'android'), ('token-9', 'android')]);
    });

    test('a refresh while signed out registers nothing', () async {
      messaging.current = PushPermission.granted;
      create().setPreferences(_both);
      messaging.refreshes.add('token-9');
      await settle();
      expect(registry.registered, isEmpty);
    });
  });

  group('unregister', () {
    Future<void> registered() async {
      messaging.current = PushPermission.granted;
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();
      expect(registry.registered, [('token-1', 'android')]);
    }

    test('both switches off removes the token and invalidates it', () async {
      await registered();
      push.setPreferences(_none);
      await settle();
      expect(registry.unregistered, ['token-1']);
      expect(messaging.deletions, 1);
      expect(push.status.value, PushStatus.hidden);
    });

    test('signing out invalidates the token; the session is gone, so no server call', () async {
      await registered();
      push.setUser(null);
      await settle();
      expect(messaging.deletions, 1);
      expect(registry.unregistered, isEmpty);
      expect(push.status.value, PushStatus.hidden);
    });

    test('beforeSignOut removes the server row while the session works', () async {
      await registered();
      await push.beforeSignOut();
      expect(registry.unregistered, ['token-1']);
      expect(messaging.deletions, 1);

      push.setUser(null);
      await settle();
      expect(messaging.deletions, 1, reason: 'already retired');
    });

    test('the next account on the device gets a fresh token', () async {
      await registered();
      push.setUser(null);
      await settle();
      push.setUser('u2');
      await settle();
      expect(registry.registered.last, ('token-2', 'android'));
    });

    test('signing out retires a token left from an earlier session', () async {
      messaging.current = PushPermission.granted;
      create().setUser('u1'); // The profile never loaded, so nothing registered yet.
      await settle();
      push.setUser(null);
      await settle();
      expect(messaging.deletions, 1);
    });

    test('signing out on a device that never allowed push touches nothing', () async {
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();
      push.setUser(null);
      await settle();
      expect(messaging.deletions, 0);
      expect(registry.unregistered, isEmpty);
    });
  });

  // Widget tests for their fake clock.
  group('a platform call that answers late or never', () {
    testWidgets('holds up the steps behind it for 45 s, not for good', (tester) async {
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await tester.pump();
      expect(push.status.value, PushStatus.off);

      // Allowed in the browser's settings, but the token never comes.
      messaging
        ..current = PushPermission.granted
        ..tokenHangs = true;
      unawaited(push.settingsOpened());
      var retired = false;
      unawaited(push.beforeSignOut().then((_) => retired = true));

      await tester.pump(const Duration(seconds: 44));
      expect(retired, isFalse, reason: 'still waiting on the token');
      expect(messaging.deletions, 0);

      await tester.pump(const Duration(seconds: 2));
      expect(retired, isTrue, reason: 'signing out still retires the token');
      expect(messaging.deletions, 1);
    });

    testWidgets('a step given up on still applies its late answer when nothing replaced it', (tester) async {
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await tester.pump();

      // Allow tapped; the browser takes 50 s to produce the token and nothing
      // else happens meanwhile.
      messaging.tokenDelay = const Duration(seconds: 50);
      unawaited(push.enable());
      await tester.pump(const Duration(seconds: 51));
      await tester.pump();
      expect(registry.registered, isNotEmpty, reason: 'no newer step started, so the late token counts');
      expect(push.status.value, PushStatus.on);
    });

    testWidgets('a step given up on changes nothing when its token comes at last', (tester) async {
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await tester.pump();
      expect(push.status.value, PushStatus.off);

      // Allow tapped, but the token takes 46 s; both switches go off meanwhile.
      messaging.tokenDelay = const Duration(seconds: 46);
      unawaited(push.enable());
      await tester.pump();
      push.setPreferences(_none);

      await tester.pump(const Duration(seconds: 45));
      expect(push.status.value, PushStatus.hidden, reason: 'the switches-off step ran once the first was given up');

      await tester.pump(const Duration(seconds: 1)); // The token arrives.
      await tester.pump();
      expect(push.status.value, PushStatus.hidden, reason: 'as the newer step left it');
      expect(registry.registered, isEmpty);
    });

    testWidgets('a token invalidated late is replaced for the next account', (tester) async {
      messaging.current = PushPermission.granted;
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await tester.pump();
      expect(registry.registered, [('token-1', 'android')]);

      // Signing out invalidates the token, which takes 46 s; u2 signs in meanwhile.
      messaging.deleteDelay = const Duration(seconds: 46);
      push.setUser(null);
      await tester.pump();
      push.setUser('u2');
      await tester.pump(const Duration(seconds: 45));
      expect(push.status.value, PushStatus.on);
      expect(registry.registered, hasLength(2), reason: 'u1, then u2');

      await tester.pump(const Duration(seconds: 1)); // The deletion finishes.
      await tester.pump();
      expect(registry.registered.last, (
        'token-2',
        'android',
      ), reason: 'the late deletion invalidated the token u2 had just registered, so u2 registers the new one');
      expect(push.status.value, PushStatus.on);

      messaging.deleteDelay = null;
      push.setUser(null);
      await tester.pump();
      expect(messaging.deletions, 2, reason: "u2's sign-out invalidates its token too");
    });
  });

  group('a token that could not be invalidated at sign-out', () {
    /// u1 has push on this device and signs out offline: neither the server
    /// row nor the token can be removed, so u1's pushes would keep coming.
    Future<void> signOutOffline(Future<void> Function() settle) async {
      messaging.current = PushPermission.granted;
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();
      expect(registry.registered, [('token-1', 'android')]);

      messaging.deleteError = _offlinePhone;
      registry.offline = true;
      unawaited(push.beforeSignOut());
      push.setUser(null);
      await settle();
      expect(messaging.deletions, 0);
      expect(registry.unregistered, isEmpty);
      expect(deviceLog.retire, isTrue, reason: 'kept to try again');
      expect(push.status.value, PushStatus.hidden);
    }

    void backOnline() {
      messaging.deleteError = null;
      registry.offline = false;
    }

    test('is invalidated once the app is back in the foreground online', () async {
      await signOutOffline(settle);

      push.resumed(); // Still offline.
      await settle();
      expect(messaging.deletions, 0);
      expect(deviceLog.retire, isTrue);

      backOnline();
      push.resumed();
      await settle();
      expect(messaging.deletions, 1);
      expect(deviceLog.retire, isFalse);

      push.resumed();
      await push.settingsOpened();
      await settle();
      expect(messaging.deletions, 1, reason: 'once is enough');
    });

    test('is invalidated at the next launch', () async {
      await signOutOffline(settle);
      backOnline();

      relaunch()
        ..setUser(null)
        ..setPreferences(_both);
      await settle();
      expect(messaging.deletions, 1);
      expect(deviceLog.retire, isFalse);
      expect(push.status.value, PushStatus.hidden);

      relaunch()
        ..setUser(null)
        ..setPreferences(_both);
      await settle();
      expect(messaging.deletions, 1, reason: 'once is enough');
    });

    test('is invalidated even with notifications since turned off for the app', () async {
      await signOutOffline(settle);
      messaging.current = PushPermission.blocked; // The token stays valid all the same.
      backOnline();

      push.resumed();
      await settle();
      expect(messaging.deletions, 1);
      expect(deviceLog.retire, isFalse);
    });

    test('is not tried again on a device that can never have a token', () async {
      messaging.current = PushPermission.granted;
      create().setUser('u1'); // The profile never loaded, so nothing registered.
      await settle();
      messaging.deleteError = _noPlayServices;
      push.setUser(null);
      await settle();
      expect(deviceLog.retire, isFalse, reason: 'no token to invalidate');

      final calls = messaging.calls;
      push.resumed();
      relaunch().setUser(null);
      await settle();
      expect(messaging.calls, calls);
    });

    test('a sign-in before the retry keeps its token', () async {
      await signOutOffline(settle);
      backOnline();

      // Back in the app, where u2 signs in before the retry has run.
      push
        ..resumed()
        ..setUser('u2');
      await settle();
      expect(messaging.deletions, 0);
      expect(registry.registered.last, ('token-1', 'android'), reason: 'the server moves the token to u2');
      expect(push.status.value, PushStatus.on);

      push.resumed();
      await settle();
      expect(messaging.deletions, 0, reason: 'u2 wants push here');

      // The next launch: the profile loads before the session, which is u2's.
      relaunch().setPreferences(_both);
      await settle();
      push.setUser('u2');
      await settle();
      expect(messaging.deletions, 0);
      expect(push.status.value, PushStatus.on);
    });

    test('a guest device that never had push still never starts Firebase', () async {
      create()
        ..setUser(null)
        ..setPreferences(_both);
      push.resumed();
      await push.settingsOpened();
      await settle();
      expect(messaging.calls, 0);
      expect(messaging.listened, isFalse);
    });

    test('once invalidated, later launches signed out leave Firebase alone', () async {
      messaging.current = PushPermission.granted;
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();
      push.setUser(null); // Online: invalidated at once.
      await settle();
      expect(messaging.deletions, 1);
      expect(deviceLog.retire, isFalse);

      final calls = messaging.calls;
      relaunch()
        ..setUser(null)
        ..setPreferences(_both);
      push.resumed();
      await settle();
      expect(messaging.calls, calls);
    });

    // Widget tests for their fake clock.
    testWidgets('a retry that answers late leaves a newer sign-in a working token', (tester) async {
      await signOutOffline(tester.pump);
      backOnline();
      messaging.deleteDelay = const Duration(seconds: 46); // FCM answers, slowly.

      push.resumed();
      await tester.pump();
      push.setUser('u2'); // Signs in while the retry waits.
      await tester.pump(const Duration(seconds: 45));
      expect(registry.registered.last, ('token-1', 'android'), reason: 'the retry was given up on, so u2 went ahead');
      expect(push.status.value, PushStatus.on);

      await tester.pump(const Duration(seconds: 1)); // The invalidation goes through.
      await tester.pump();
      expect(messaging.deletions, 1);
      expect(deviceLog.retire, isFalse);
      expect(registry.registered.last, ('token-2', 'android'), reason: 'u2 registers the token FCM issues next');
      expect(push.status.value, PushStatus.on);
    });

    testWidgets('a launch retries a sign-out the app was closed in the middle of', (tester) async {
      messaging.current = PushPermission.granted;
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await tester.pump();

      registry.hangs = true; // The server never answers.
      unawaited(push.beforeSignOut());
      push.setUser(null); // Signed out on the device after 5 s; then the app is closed.
      await tester.pump(const Duration(seconds: 5));
      expect(messaging.deletions, 0);
      expect(deviceLog.retire, isTrue, reason: 'noted before waiting on the server');

      relaunch()
        ..setUser(null)
        ..setPreferences(_both);
      await tester.pump();
      expect(messaging.deletions, 1);
      expect(deviceLog.retire, isFalse);

      await tester.pump(const Duration(seconds: 45)); // The closed app's step runs out.
    });
  });

  group('asking', () {
    test('the first Settings visit asks once per account where no tap is needed', () async {
      create(promptOnSettingsOpen: true)
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();

      await push.settingsOpened();
      expect(messaging.prompts, 1);
      expect(registry.registered, [('token-1', 'android')]);
      expect(push.status.value, PushStatus.on);

      await push.settingsOpened();
      expect(messaging.prompts, 1);
    });

    test('a declined first prompt is not repeated on later visits', () async {
      messaging.answer = PushPermission.askable;
      create(promptOnSettingsOpen: true)
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();
      await push.settingsOpened();
      await push.settingsOpened();
      expect(messaging.prompts, 1);
      expect(push.status.value, PushStatus.off);
    });

    test('another account on the same device is asked on its own first visit', () async {
      deviceLog.asked.add('u1');
      create(promptOnSettingsOpen: true)
        ..setUser('u2')
        ..setPreferences(_both);
      await settle();
      await push.settingsOpened();
      expect(messaging.prompts, 1);
    });

    test('on the web the first visit offers Allow instead of prompting', () async {
      create(promptOnSettingsOpen: false, platform: 'web')
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();
      await push.settingsOpened();
      expect(messaging.prompts, 0);
      expect(push.status.value, PushStatus.off);

      await push.enable(); // Allow tapped.
      expect(messaging.prompts, 1);
      expect(registry.registered, [('token-1', 'web')]);
    });

    test('turning a switch on asks at once and registers when allowed', () async {
      create()
        ..setUser('u1')
        ..setPreferences(_none);
      await settle();

      final asked = push.enable(); // The switch handler calls this first...
      push.setPreferences(_both); // ...then saves the switch.
      await asked;
      await settle();
      expect(messaging.prompts, 1);
      expect(registry.registered, [('token-1', 'android')]);
    });

    test('guests are never asked', () async {
      create(promptOnSettingsOpen: true).setPreferences(_both);
      await push.enable();
      await push.settingsOpened();
      expect(messaging.prompts, 0);
    });

    test('switches never prompt where push cannot work', () async {
      messaging.supported = false;
      create(platform: 'web')
        ..setUser('u1')
        ..setPreferences(_none);
      await settle();

      final asked = push.enable(); // An iPhone browser tab: a switch turned on.
      push.setPreferences(_both);
      await asked;
      await settle();
      expect(messaging.prompts, 0);
      expect(push.status.value, PushStatus.unsupported);
    });
  });

  group('taps', () {
    test('a tapped notification reaches the signed-in app', () async {
      create()
        ..setUser('u1')
        ..setPreferences(_none); // Taps count even with the switches off now.
      final opened = <PushMessage>[];
      push.opened.listen(opened.add);

      messaging.opened.add(const PushMessage(title: 'Comment', data: {'category': 'guild_comments'}));
      await settle();
      expect(opened.map((m) => m.title), ['Comment']);
    });

    test('nothing opens after signing out', () async {
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await settle();
      push.setUser(null);
      await settle();
      final opened = <PushMessage>[];
      push.opened.listen(opened.add);

      messaging.opened.add(const PushMessage(title: 'Comment'));
      await settle();
      expect(opened, isEmpty);
    });
  });

  group('foreground messages', () {
    test('only what the switches allow reaches the app', () async {
      messaging.current = PushPermission.granted;
      create()
        ..setUser('u1')
        ..setPreferences(const PushPreferences(guild: true, weekly: false));
      await settle();
      final shown = <PushMessage>[];
      push.messages.listen(shown.add);

      messaging.foreground
        ..add(const PushMessage(title: 'Comment', data: {'category': 'guild_comments'}))
        ..add(const PushMessage(title: 'Your week', data: {'category': 'weekly_summary'}));
      await settle();
      expect(shown.map((m) => m.title), ['Comment']);
    });

    test('nothing reaches a signed-out app', () async {
      create().setPreferences(_both);
      final shown = <PushMessage>[];
      push.messages.listen(shown.add);
      messaging.foreground.add(const PushMessage(title: 'Comment', data: {'category': 'guild_comments'}));
      await settle();
      expect(shown, isEmpty);
    });
  });

  test('only token errors known to last count as permanent', () {
    for (final permanent in <Object>[
      _noPlayServices,
      _unsupportedBrowser,
      FirebaseException(
        plugin: 'firebase_messaging',
        code: 'indexed-db-unsupported',
        message: "Messaging: This browser doesn't support indexedDb.open() (ex. Safari iFrame, Firefox Private Browsing, etc)",
      ),
      // As the Firebase SDK words it, should one get through unmapped.
      Exception(
        "FirebaseError: Messaging: This browser doesn't support the API's required to use the Firebase SDK. "
        '(messaging/unsupported-browser).',
      ),
    ]) {
      expect(isPermanentTokenError(permanent), isTrue, reason: '$permanent');
    }
    for (final passing in <Object>[
      _offlinePhone,
      _pushServiceError,
      FirebaseException(
        plugin: 'firebase_messaging',
        code: 'token-subscribe-failed',
        message: 'Messaging: A problem occurred while subscribing the user to FCM: TypeError: Failed to fetch',
      ),
      FirebaseException(plugin: 'firebase_messaging', message: 'java.io.IOException: TIMEOUT'),
      StateError('no answer'),
    ]) {
      expect(isPermanentTokenError(passing), isFalse, reason: '$passing');
    }
  });

  test('push routes lead to the guild hall or the chronicle', () {
    const guild = '6f1c2b9e-8a4d-4c1e-9b7a-2d5e8f0a1b3c';
    expect(pushRoute({'category': 'guild_comments', 'guild_id': guild}), '/guilds/$guild');
    expect(pushRoute({'category': 'weekly_summary'}), '/chronicle');
    expect(pushRoute({'category': 'guild_comments', 'guild_id': '../settings'}), isNull);
    expect(pushRoute({'category': 'briefing'}), isNull);
  });

  group('settings row', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    Future<void> pumpRow(WidgetTester tester, {bool fromHomeScreen = false}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [pushServiceProvider.overrideWithValue(push)],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: PushDeviceTile(runsFromHomeScreen: fromHomeScreen)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('offers Allow and turns on when allowed', (tester) async {
      create(platform: 'web')
        ..setUser('u1')
        ..setPreferences(_both);
      await pumpRow(tester);
      expect(find.text(l10n.pushDeviceOff), findsOneWidget);

      await tester.tap(find.text(l10n.pushAllow));
      await tester.pump();
      expect(messaging.prompts, 1);
      expect(find.text(l10n.pushDeviceOn), findsOneWidget);
    });

    testWidgets('stops offering Allow once allowed in a browser that can never get a token', (tester) async {
      messaging.tokenError = _unsupportedBrowser;
      create(platform: 'web')
        ..setUser('u1')
        ..setPreferences(_both);
      await pumpRow(tester);
      expect(find.text(l10n.pushDeviceOff), findsOneWidget);

      await tester.tap(find.text(l10n.pushAllow));
      await tester.pump();
      expect(messaging.prompts, 1);
      expect(find.text(l10n.pushAllow), findsNothing);
      expect(find.text(l10n.pushUnsupported), findsOneWidget);
    });

    testWidgets('keeps offering Allow while the token may still come', (tester) async {
      messaging.tokenError = _pushServiceError; // Offline at the first registration, say.
      create(platform: 'web')
        ..setUser('u1')
        ..setPreferences(_both);
      await pumpRow(tester);

      await tester.tap(find.text(l10n.pushAllow));
      await tester.pump();
      expect(messaging.prompts, 1);
      expect(find.text(l10n.pushDeviceOff), findsOneWidget);

      messaging.tokenError = null; // Back online: Allow tries again.
      await tester.tap(find.text(l10n.pushAllow));
      await tester.pump();
      expect(find.text(l10n.pushDeviceOn), findsOneWidget);
      expect(registry.registered, [('token-1', 'web')]);
    });

    testWidgets('points to the settings once blocked, without an Allow button', (tester) async {
      messaging.current = PushPermission.blocked;
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await pumpRow(tester);
      expect(find.text(l10n.pushDeviceBlocked), findsOneWidget);
      expect(find.text(l10n.pushAllow), findsNothing);
    });

    testWidgets('says so where push cannot work', (tester) async {
      messaging.supported = false;
      create(platform: 'web')
        ..setUser('u1')
        ..setPreferences(_both);
      await pumpRow(tester);
      expect(find.text(l10n.pushUnsupported), findsOneWidget);
      expect(find.text(l10n.pushAllow), findsNothing);
    });

    testWidgets('in the Android app without Google Play services, speaks of the device', (tester) async {
      messaging
        ..current = PushPermission.granted
        ..tokenError = _noPlayServices;
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await pumpRow(tester);
      expect(find.text(l10n.pushUnsupportedDevice), findsOneWidget);
      expect(find.text(l10n.pushAllow), findsNothing);
    });

    testWidgets('in the Android app offline, keeps Allow to try again', (tester) async {
      messaging
        ..current = PushPermission.granted
        ..tokenError = _offlinePhone;
      create()
        ..setUser('u1')
        ..setPreferences(_both);
      await pumpRow(tester);
      expect(find.text(l10n.pushDeviceOff), findsOneWidget);
      expect(find.text(l10n.pushUnsupportedDevice), findsNothing);

      messaging.tokenError = null; // Back online.
      await tester.tap(find.text(l10n.pushAllow));
      await tester.pump();
      expect(find.text(l10n.pushDeviceOn), findsOneWidget);
      expect(registry.registered, [('token-1', 'android')]);
    });

    testWidgets('in an iPhone browser, points to the Home Screen', (tester) async {
      messaging.supported = false;
      create(platform: 'web')
        ..setUser('u1')
        ..setPreferences(_both);
      await pumpRow(tester);
      expect(find.text(l10n.pushInstallHint), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('opened from the iPhone Home Screen, does not point there again', (tester) async {
      messaging.supported = false; // An iOS version without web push, say.
      create(platform: 'web')
        ..setUser('u1')
        ..setPreferences(_both);
      await pumpRow(tester, fromHomeScreen: true);
      expect(find.text(l10n.pushInstallHint), findsNothing);
      expect(find.text(l10n.pushUnsupportedDevice), findsOneWidget);
      expect(find.text(l10n.pushAllow), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('stays hidden when push is not offered', (tester) async {
      create(); // Signed out.
      await pumpRow(tester);
      expect(find.byType(ListTile), findsNothing);
    });
  });

  group('in-app snack bar', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    Future<void> show(WidgetTester tester, SnackBar snackBar) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(snackBar),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Slide in.
    }

    testWidgets('shows the push with an Open action for its screen', (tester) async {
      var opened = 0;
      const message = PushMessage(title: 'Mira commented', body: 'Well fought.');
      await show(tester, pushSnackBar(l10n, message, onOpen: () => opened++));
      expect(find.text('Mira commented'), findsOneWidget);
      expect(find.text('Well fought.'), findsOneWidget);

      await tester.tap(find.text(l10n.pushOpen));
      expect(opened, 1);
    });

    testWidgets('falls back to a localized line and no action', (tester) async {
      await show(tester, pushSnackBar(l10n, const PushMessage(title: ' ')));
      expect(find.text(l10n.pushInAppFallback), findsOneWidget);
      expect(find.byType(SnackBarAction), findsNothing);
    });
  });

  testWidgets('PushHost renders the app untouched in builds without push', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PushHost(
          child: Directionality(textDirection: TextDirection.ltr, child: Text('app')),
        ),
      ),
    );
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('PushHost tells push when the app is back in the foreground', (tester) async {
    messaging.current = PushPermission.granted;
    create()
      ..setUser('u1')
      ..setPreferences(_both);
    await tester.pump();
    messaging.deleteError = _offlinePhone;
    push.setUser(null); // Signed out offline.
    await tester.pump();
    expect(deviceLog.retire, isTrue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [pushServiceProvider.overrideWithValue(push)],
        child: const PushHost(configured: true, child: SizedBox()),
      ),
    );
    messaging.deleteError = null;
    // Away from the app while the network comes back, then back in it.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(messaging.deletions, 0, reason: 'not back yet');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(messaging.deletions, 1);
    expect(deviceLog.retire, isFalse);
  });
}
