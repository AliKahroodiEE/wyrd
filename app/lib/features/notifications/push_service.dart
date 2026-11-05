import 'dart:async';

import 'package:flutter/foundation.dart';

/// Whether this device may show notifications.
enum PushPermission {
  granted,

  /// Not asked yet, or declined in a way that lets the app ask again.
  askable,

  /// Declined for good: only the browser or system settings can change it.
  blocked,
}

/// What the Notifications panel shows for this device.
enum PushStatus {
  /// Push is not offered: not configured, signed out, or both switches off.
  hidden,

  /// This browser cannot receive push (on iPhone: until Wyrd is on the Home
  /// Screen), or this browser or phone can never get a push token
  /// ([isPermanentTokenError]).
  unsupported,

  /// The switches want push, but this device is not registered yet: the
  /// system permission is not granted, or no token came this time (offline,
  /// say). Allow asks, or tries again.
  off,

  /// The system permission was declined for good.
  blocked,

  /// This device is registered for push.
  on,
}

/// A push notification, as the notify function sends it.
@immutable
class PushMessage {
  const PushMessage({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;

  /// String key/values from the notify function: `category`, `template_key`, ids.
  final Map<String, String> data;

  String? get category => data['category'];
}

/// Which pushes the Settings switches allow. Reminders are scheduled on the
/// device itself, so only the guild and weekly switches decide about push.
@immutable
class PushPreferences {
  const PushPreferences({required this.guild, required this.weekly});

  final bool guild;
  final bool weekly;

  bool get any => guild || weekly;

  /// Whether a push of [category] (the notify function's categories) may show.
  bool allows(String? category) => switch (category) {
    'guild_reactions' || 'guild_comments' || 'challenge_milestones' => guild,
    'weekly_summary' || 're_engagement' => weekly,
    _ => any,
  };

  @override
  bool operator ==(Object other) => other is PushPreferences && other.guild == guild && other.weekly == weekly;

  @override
  int get hashCode => Object.hash(guild, weekly);
}

/// The push transport: Firebase Cloud Messaging in the app, a fake in tests.
///
/// Nothing here starts Firebase until it is first used, so [PushService]
/// touches it only once someone is signed in, or to invalidate a token an
/// account left on the device ([PushDeviceLog.retirePending]).
abstract interface class PushMessaging {
  /// Whether this device or browser can receive push at all.
  Future<bool> isSupported();

  /// The current permission. Never prompts.
  Future<PushPermission> permission();

  /// Shows the system prompt where it can still be shown. Browsers allow it
  /// only inside a tap, so callers must not wait on anything slow before it.
  Future<PushPermission> requestPermission();

  /// This device's token, or null when there is none to be had right now.
  /// Throws when the platform could not get one; [isPermanentTokenError]
  /// tells whether it ever will.
  Future<String?> token();

  /// Invalidates the token, so nothing sent to it arrives any more. Throws
  /// when FCM cannot be reached to do so, as offline.
  Future<void> deleteToken();

  /// Tokens issued after the first one.
  Stream<String> get tokenRefreshes;

  /// Pushes that arrive while the app is in the foreground.
  Stream<PushMessage> get foregroundMessages;

  /// Notifications the user tapped, including the one that launched the app.
  Stream<PushMessage> get openedMessages;
}

/// Whether [error], thrown by [PushMessaging.token] or
/// [PushMessaging.deleteToken], means this device or browser can never get a
/// token, rather than not right now. Only these are known to last:
/// - an Android phone without Google Play services: FCM's
///   `MISSING_INSTANCEID_SERVICE`, which firebase_messaging reports as
///   `[firebase_messaging/unknown] java.io.IOException: MISSING_INSTANCEID_SERVICE`;
/// - a browser without what FCM needs: the Firebase SDK's
///   `messaging/unsupported-browser`, or `messaging/indexed-db-unsupported`
///   (a Firefox private window, a Safari iframe), which
///   firebase_messaging_web reports as `[firebase_messaging/unsupported-browser] …`.
///
/// Anything else may pass, so Allow stays to try again, such as
/// `SERVICE_NOT_AVAILABLE` (an Android phone offline), or a browser that is
/// offline at its first registration: its push service refuses the
/// subscription (`AbortError: Registration failed - push service error`) or
/// FCM cannot be reached (`messaging/token-subscribe-failed`).
bool isPermanentTokenError(Object error) => _permanentTokenError.hasMatch('$error');

final _permanentTokenError = RegExp(
  r'\bMISSING_INSTANCEID_SERVICE\b|messaging/(unsupported-browser|indexed-db-unsupported)\b',
);

/// Server-side token storage that the notify function sends to.
abstract interface class PushRegistry {
  Future<void> register(String token, String platform);
  Future<void> unregister(String token);
}

/// What push keeps on this device across restarts.
abstract interface class PushDeviceLog {
  /// Whether [userId] was already asked on this device, so the first Settings
  /// visit prompts once and never again.
  Future<bool> wasAsked(String userId);
  Future<void> markAsked(String userId);

  /// Whether this device's token still has to be invalidated: an account
  /// signed out here or turned push off, and the invalidation has not gone
  /// through yet (FCM out of reach, say, or the app closed first). Until it
  /// does, the token keeps receiving that account's pushes.
  Future<bool> retirePending();
  Future<void> setRetirePending(bool pending);
}

/// Keeps this device's push registration in step with the signed-in account,
/// the Settings switches and the system permission.
///
/// It never prompts by itself at launch. [settingsOpened] asks once per
/// account where the platform allows a prompt outside a tap, and [enable]
/// asks when the user turns a switch on or taps Allow.
///
/// A token it could not invalidate, signing out offline say, is noted in the
/// [PushDeviceLog] and tried again at every launch and every return to the
/// app while signed out, until the invalidation goes through.
class PushService {
  PushService({
    required this._messaging,
    required this._registry,
    required this._log,
    required this._platform,
    this.promptOnSettingsOpen = false,
  });

  final PushMessaging? _messaging;
  final PushRegistry? _registry;
  final PushDeviceLog _log;
  final String? _platform;

  /// Whether the first Settings visit after signing in may show the system
  /// prompt by itself. Browsers allow the prompt only inside a tap, so on the
  /// web the Notifications panel offers an Allow button instead.
  final bool promptOnSettingsOpen;

  final status = ValueNotifier(PushStatus.hidden);
  final _messages = StreamController<PushMessage>.broadcast();
  final _opened = StreamController<PushMessage>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];

  String? _userId;

  /// Whether [setUser] has said who is signed in. Until it has, a device
  /// that seems signed out may be one whose session is still loading, so
  /// nothing is retried on it.
  bool _userKnown = false;
  PushPreferences? _preferences;
  bool? _supported;
  ({String userId, String token})? _registered;
  bool _retired = false;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  /// The step that may change things now, bumped when a step starts. A step
  /// given up after [_stepTimeout] stays current until the next one starts:
  /// nothing can cancel the platform call it waits on, so when that call
  /// answers at last, the step applies its result only if no newer step has
  /// begun since, and otherwise leaves everything to the steps after it.
  int _step = 0;

  bool get isAvailable => _messaging != null && _registry != null && _platform != null;

  /// This device's `push_tokens.platform`: `web`, `android`, or null where
  /// push is not offered.
  String? get platform => _platform;

  /// Foreground pushes for the signed-in account that its switches allow.
  Stream<PushMessage> get messages => _messages.stream;

  /// Notifications the signed-in account tapped to open the app.
  Stream<PushMessage> get opened => _opened.stream;

  /// Completes when every change so far has been applied.
  @visibleForTesting
  Future<void> get settled => _queue;

  /// The signed-in account, or null for guests and after signing out. Call
  /// it once the session is known, not while it loads: the first call counts
  /// too, so a launch signed out retries a token left to invalidate.
  void setUser(String? userId) {
    if (_userKnown && userId == _userId) return;
    final signedOut = _userId != null && userId == null;
    _userKnown = true;
    _userId = userId;
    if (userId != null) _listen();
    unawaited(_sync(signedOut: signedOut));
  }

  /// The app is back in the foreground, where the network may be back too:
  /// a token left to invalidate is tried again while signed out.
  void resumed() {
    if (_userKnown && _userId == null) unawaited(_sync());
  }

  /// The Settings switches; null while the profile is still loading.
  void setPreferences(PushPreferences? preferences) {
    if (preferences == _preferences) return;
    _preferences = preferences;
    unawaited(_sync());
  }

  /// Settings opened. Refreshes the status (the permission may have changed
  /// in the system settings meanwhile) and, the first time an account opens
  /// Settings on this device, shows the system prompt where no tap is needed.
  Future<void> settingsOpened() async {
    await _sync();
    final messaging = _messaging;
    final userId = _userId;
    if (!promptOnSettingsOpen || messaging == null || userId == null || status.value != PushStatus.off) return;
    if (await _log.wasAsked(userId)) return;
    await _log.markAsked(userId);
    await _ask(messaging);
    await _sync();
  }

  /// The user asked for notifications: a switch turned on, or Allow tapped.
  /// Shows the system prompt straight away (browsers allow it only inside
  /// the tap), then registers this device if the answer was yes.
  Future<void> enable() async {
    final messaging = _messaging;
    final userId = _userId;
    if (!isAvailable || messaging == null || userId == null) return;
    // Nothing to ask for where push cannot work (an iPhone browser tab).
    if (_supported != false) {
      await _ask(messaging);
      await _log.markAsked(userId);
    }
    await _sync();
  }

  /// Removes this device's token from the server while the session still
  /// works; the sign-out flow can call it just before signing out. Without
  /// it the token is still invalidated when the sign-out arrives, and the
  /// notify function drops the dead row the next time it sends. Offline,
  /// the invalidation is tried again later ([PushDeviceLog.retirePending]).
  Future<void> beforeSignOut() => _run((step) => _retire(step, server: true));

  void dispose() {
    _disposed = true;
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(_messages.close());
    unawaited(_opened.close());
    status.dispose();
  }

  /// Starts listening (and so starts Firebase) the first time someone signs in.
  void _listen() {
    final messaging = _messaging;
    if (messaging == null || _registry == null || _platform == null || _subscriptions.isNotEmpty) return;
    _subscriptions
      ..add(messaging.tokenRefreshes.listen((_) => unawaited(_sync())))
      ..add(messaging.foregroundMessages.listen(_onForeground))
      ..add(messaging.openedMessages.listen(_onOpened));
  }

  Future<void> _ask(PushMessaging messaging) async {
    try {
      await messaging.requestPermission();
    } on Object catch (error) {
      debugPrint('Push permission request failed: $error');
    }
  }

  Future<void> _sync({bool signedOut = false}) => _run((step) async {
    if (signedOut) {
      await _retire(step, server: false);
    } else if (_userKnown && _userId == null && await _retirePending()) {
      // Signed out, and the token could not be invalidated before: try
      // again. Nothing else touches Firebase while signed out, so a device
      // that never had push never starts it.
      await _retire(step, server: false, pending: true);
    }
    await _reconcile(step);
  });

  /// How long a step may wait on Firebase, the browser or the server before
  /// the steps queued behind it go ahead.
  static const _stepTimeout = Duration(seconds: 45);

  /// Runs [step] after the steps before it, so events never interleave. A
  /// step that is still waiting after [_stepTimeout] (a platform call that
  /// never answers) is given up, so it cannot hold back the rest of the
  /// session, such as retiring the token after signing out. [step] gets its
  /// number, and checks with [_isCurrent] after every wait that it still is
  /// the current step before it changes anything.
  Future<void> _run(Future<void> Function(int step) step) {
    return _queue = _queue.then((_) async {
      if (_disposed) return;
      final current = ++_step;
      try {
        await step(
          current,
        ).timeout(_stepTimeout, onTimeout: () => debugPrint('Push update given up after ${_stepTimeout.inSeconds} s'));
      } on Object catch (error) {
        debugPrint('Push update failed: $error');
      }
    });
  }

  /// Whether [step] may still change things: no step started after it.
  bool _isCurrent(int step) => step == _step;

  Future<void> _reconcile(int step) async {
    if (!_isCurrent(step)) return;
    final messaging = _messaging;
    final registry = _registry;
    final platform = _platform;
    final userId = _userId;
    final preferences = _preferences;
    if (messaging == null || registry == null || platform == null || userId == null) {
      _show(PushStatus.hidden);
      return;
    }
    if (preferences == null) return; // The profile is still loading.
    final supported = _supported ?? await messaging.isSupported();
    if (!_isCurrent(step)) return;
    _supported = supported;
    if (!preferences.any) {
      if (_registered != null) await _retire(step, server: true);
      if (!_isCurrent(step)) return;
      _show(PushStatus.hidden);
      return;
    }
    if (!supported) {
      _show(PushStatus.unsupported);
      return;
    }
    final permission = await messaging.permission();
    if (!_isCurrent(step)) return;
    if (permission != PushPermission.granted) {
      _show(permission == PushPermission.blocked ? PushStatus.blocked : PushStatus.off);
      return;
    }
    final String? token;
    try {
      token = await messaging.token();
    } on Object catch (error) {
      if (!_isCurrent(step)) return;
      if (isPermanentTokenError(error)) {
        // Allow could not get any further here.
        debugPrint('Push token unavailable on this device: $error');
        _show(PushStatus.unsupported);
      } else {
        // Offline, say: Allow tries again.
        debugPrint('Push token unavailable for now: $error');
        _show(PushStatus.off);
      }
      return;
    }
    if (!_isCurrent(step)) return;
    if (token == null) {
      _show(PushStatus.off);
      return;
    }
    _retired = false;
    final registered = _registered;
    if (registered == null || registered.userId != userId || registered.token != token) {
      await registry.register(token, platform);
      if (!_isCurrent(step)) return;
      _registered = (userId: userId, token: token);
    }
    _show(PushStatus.on);
  }

  /// Stops pushes to this device for the account last registered on it.
  /// [server] also deletes the server row, which needs a live session.
  /// [pending]: a token is known to be left to invalidate
  /// ([PushDeviceLog.retirePending]), so this device has one to retire.
  Future<void> _retire(int step, {required bool server, bool pending = false}) async {
    final messaging = _messaging;
    if (messaging == null || _retired || !_isCurrent(step)) return;
    final registered = _registered;
    _registered = null;
    // A token from an earlier session may still be on the server, so retire
    // it whenever this device could have one.
    if (registered == null && !pending) {
      final permission = await messaging.permission();
      if (!_isCurrent(step) || permission != PushPermission.granted) return;
    }
    // Noted first, so that whatever stops the invalidation (FCM out of reach,
    // the app closed while the server is slow) the next launch or return to
    // the app tries again: until then the token keeps receiving the pushes.
    await _setRetirePending(true);
    if (!_isCurrent(step)) return;
    if (server && registered != null) {
      try {
        await _registry?.unregister(registered.token);
      } on Object catch (error) {
        debugPrint('Push token could not be removed from the server: $error');
      }
      if (!_isCurrent(step)) return;
    }
    try {
      await messaging.deleteToken();
    } on Object catch (error) {
      if (!isPermanentTokenError(error)) {
        debugPrint('Push token could not be invalidated, to be tried again: $error');
        return;
      }
      // This device can never get a token, so none is left to invalidate.
      debugPrint('Push token never existed on this device: $error');
    }
    await _setRetirePending(false);
    if (_isCurrent(step)) {
      _retired = true;
    } else {
      // Finished late: a newer step may have registered the very token this
      // just invalidated (FCM hands out its cached token until the delete
      // completes), so the current account fetches and registers a new one.
      unawaited(_sync());
    }
  }

  /// [PushDeviceLog.retirePending], or false when the log cannot be read.
  Future<bool> _retirePending() async {
    try {
      return await _log.retirePending();
    } on Object catch (error) {
      debugPrint('Push device log could not be read: $error');
      return false;
    }
  }

  /// A log that cannot be written never keeps the token from being invalidated.
  Future<void> _setRetirePending(bool pending) async {
    try {
      await _log.setRetirePending(pending);
    } on Object catch (error) {
      debugPrint('Push device log could not be written: $error');
    }
  }

  void _onForeground(PushMessage message) {
    final preferences = _preferences;
    if (_disposed || _userId == null || preferences == null || !preferences.allows(message.category)) return;
    _messages.add(message);
  }

  void _onOpened(PushMessage message) {
    if (!_disposed && _userId != null) _opened.add(message);
  }

  void _show(PushStatus value) {
    if (!_disposed) status.value = value;
  }
}
