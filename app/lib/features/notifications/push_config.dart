import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase Cloud Messaging settings passed with `--dart-define`.
///
/// Push is optional. Without these values the app never loads Firebase and
/// the notification switches drive only local reminders. They are public
/// client identifiers (like the Supabase publishable key), not secrets, so
/// they can live in repository variables.
abstract final class PushConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const androidAppId = String.fromEnvironment('FIREBASE_APP_ID_ANDROID');
  static const webAppId = String.fromEnvironment('FIREBASE_APP_ID_WEB');
  static const messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  /// Web Push certificate key (Firebase console, Cloud Messaging, Web configuration).
  static const vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');

  /// The `push_tokens.platform` value for this device, or null where push is
  /// not offered. iPhones use the web app from the Home Screen, not a native
  /// build, so only Android and the web get a Firebase app id.
  static String? get platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.android ? 'android' : null;
  }

  static String get _appId => kIsWeb ? webAppId : androidAppId;

  static bool get isConfigured =>
      platform != null &&
      apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty &&
      (!kIsWeb || vapidKey.isNotEmpty);

  /// Options in code: no google-services.json and no Google Services Gradle plugin.
  static FirebaseOptions get options =>
      FirebaseOptions(apiKey: apiKey, appId: _appId, messagingSenderId: messagingSenderId, projectId: projectId);

  static Future<bool>? _started;

  /// Starts Firebase the first time it is needed and completes with whether
  /// it is running. Push asks for it only once someone is signed in, so
  /// guests never load Firebase. False when push is not configured or
  /// Firebase failed to start; push then stays off for this run.
  static Future<bool> start() => _started ??= isConfigured
      ? Firebase.initializeApp(options: options).then(
          (_) => true,
          onError: (Object error) {
            debugPrint('Push disabled: Firebase failed to start ($error)');
            return false;
          },
        )
      : Future.value(false);
}
