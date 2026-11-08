import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_config.dart';
import 'push_service.dart';

/// Android channel that server pushes land in; the manifest names it as the
/// default, so the notify function needs no channel id.
const pushChannelId = 'guild_and_chronicle';

/// User-visible name and description of [pushChannelId], in the app language.
typedef PushChannelLabels = ({String name, String description});

/// [PushMessaging] on Firebase Cloud Messaging.
///
/// [start] runs on first use, so Firebase loads only once push is needed.
///
/// The notify function sends to FCM registration tokens (HTTP v1
/// `message.token`), so this uses the token API. firebase_messaging 17 marks
/// it deprecated in favour of Firebase Installation IDs (`register()`), which
/// would need the backend to send to FIDs first.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging({required this._start, required this._channel});

  final Future<bool> Function() _start;
  final PushChannelLabels Function() _channel;
  bool _channelReady = false;

  Future<FirebaseMessaging?> get _messaging async => await _start() ? FirebaseMessaging.instance : null;

  @override
  Future<bool> isSupported() async {
    try {
      final messaging = await _messaging;
      return messaging != null && await messaging.isSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<PushPermission> permission() async {
    try {
      final messaging = await _messaging;
      return messaging == null ? PushPermission.blocked : _permission(await messaging.getNotificationSettings());
    } on Object {
      return PushPermission.blocked;
    }
  }

  @override
  Future<PushPermission> requestPermission() async {
    try {
      final messaging = await _messaging;
      return messaging == null ? PushPermission.blocked : _permission(await messaging.requestPermission());
    } on Object {
      return PushPermission.blocked;
    }
  }

  @override
  Future<String?> token() async {
    final messaging = await _messaging;
    if (messaging == null) return null;
    if (!kIsWeb) await _createChannel();
    // No custom service worker path: the Firebase SDK then registers
    // /firebase-messaging-sw.js under its own scope
    // (/firebase-cloud-messaging-push-scope), clear of Flutter's worker.
    // ignore: deprecated_member_use
    return messaging.getToken(vapidKey: kIsWeb ? PushConfig.vapidKey : null);
  }

  @override
  Future<void> deleteToken() async {
    // ignore: deprecated_member_use
    await (await _messaging)?.deleteToken();
  }

  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenRefreshes => _whenReady((m) => m.onTokenRefresh);

  @override
  Stream<PushMessage> get foregroundMessages => _whenReady((_) => FirebaseMessaging.onMessage.map(_message));

  @override
  Stream<PushMessage> get openedMessages => _whenReady((m) async* {
    final initial = await m.getInitialMessage();
    if (initial != null) yield _message(initial);
    yield* FirebaseMessaging.onMessageOpenedApp.map(_message);
  });

  Stream<T> _whenReady<T>(Stream<T> Function(FirebaseMessaging messaging) stream) =>
      Stream.fromFuture(_messaging).asyncExpand((m) => m == null ? Stream<T>.empty() : stream(m));

  static PushPermission _permission(NotificationSettings settings) => switch (settings.authorizationStatus) {
    AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermission.granted,
    AuthorizationStatus.notDetermined => PushPermission.askable,
    // A browser that was told no never asks again; Android may ask once more.
    AuthorizationStatus.denied => kIsWeb ? PushPermission.blocked : PushPermission.askable,
    AuthorizationStatus.deniedPermanently => PushPermission.blocked,
  };

  static PushMessage _message(RemoteMessage message) {
    final data = {for (final e in message.data.entries) e.key: '${e.value}'};
    return PushMessage(
      title: message.notification?.title ?? data['title'],
      body: message.notification?.body ?? data['body'],
      data: data,
    );
  }

  Future<void> _createChannel() async {
    if (_channelReady) return;
    final labels = _channel();
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          AndroidNotificationChannel(pushChannelId, labels.name, description: labels.description),
        );
    _channelReady = true;
  }
}

/// [PushRegistry] on Supabase.
class SupabasePushRegistry implements PushRegistry {
  SupabasePushRegistry(this._client);

  final SupabaseClient _client;

  /// `public.register_push_token(token text, platform text)`: moves the token
  /// to this account and refreshes its `last_seen_at`.
  @override
  Future<void> register(String token, String platform) =>
      _client.rpc<void>('register_push_token', params: {'token': token, 'platform': platform});

  /// `public.unregister_push_token(token text)`: deletes the token if it
  /// belongs to this account, and does nothing otherwise. Device tokens are
  /// push credentials, so the app cannot read or delete `push_tokens` rows
  /// itself.
  @override
  Future<void> unregister(String token) => _client.rpc<void>('unregister_push_token', params: {'token': token});
}

/// [PushDeviceLog] in this device's preferences.
class PrefsPushDeviceLog implements PushDeviceLog {
  // Created on first use: only builds with push ever touch the preferences.
  late final _prefs = SharedPreferencesAsync();

  static String _askedKey(String userId) => 'push.asked.$userId';
  static const _retireKey = 'push.retirePending';
  static const _holdsKey = 'push.holdsToken';

  @override
  Future<bool> wasAsked(String userId) async => await _prefs.getBool(_askedKey(userId)) ?? false;

  @override
  Future<void> markAsked(String userId) => _prefs.setBool(_askedKey(userId), true);

  @override
  Future<bool> retirePending() async => await _prefs.getBool(_retireKey) ?? false;

  @override
  Future<void> setRetirePending(bool pending) => pending ? _prefs.setBool(_retireKey, true) : _prefs.remove(_retireKey);

  @override
  Future<bool> holdsToken() async => await _prefs.getBool(_holdsKey) ?? false;

  @override
  Future<void> setHoldsToken(bool holds) => holds ? _prefs.setBool(_holdsKey, true) : _prefs.remove(_holdsKey);
}
