import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Client, ClientException;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wyrd/features/auth/auth_gateway.dart';

// Plain `test`s only: `testWidgets` would swap in Flutter's fake HTTP client,
// and these talk to the real Auth client over the real network stack.

/// Nothing listens on the discard port, so every call fails as it does offline.
const _unreachable = 'http://127.0.0.1:9';

/// A session as Auth stores it on the device. Nothing ever checks its token.
String _session(String userId) {
  String part(Map<String, Object> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final expiresAt = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return jsonEncode({
    'access_token': [
      part({'alg': 'HS256', 'typ': 'JWT'}),
      part({'sub': userId, 'role': 'authenticated', 'exp': expiresAt}),
      'signature',
    ].join('.'),
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-$userId',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': '$userId@example.com',
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, Object>{},
      'created_at': '2026-11-01T08:00:00Z',
    },
  });
}

/// A real client, signed in as `u1`, that cannot reach its server. [httpClient]
/// stands in for the network when given.
Future<SupabaseClient> _signedIn({Client? httpClient}) async {
  final client = SupabaseClient(
    _unreachable,
    'sb_publishable_test',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: httpClient,
  );
  addTearDown(client.dispose);
  await client.auth.setInitialSession(_session('u1'));
  expect(client.auth.currentUser?.id, 'u1');
  return client;
}

void main() {
  group('signing out offline', () {
    test('Auth forgets the session here, then fails to tell the server', () async {
      final client = await _signedIn();
      await expectLater(client.auth.signOut(), throwsA(isA<AuthRetryableFetchException>()));
      expect(client.auth.currentSession, isNull);
    });

    test('counts as signed out', () async {
      final client = await _signedIn();
      await SupabaseAuthGateway(client).signOut();
      expect(client.auth.currentSession, isNull);
    });

    test('still fails while a session is left on this device', () async {
      late final SupabaseClient client;
      client = await _signedIn(
        httpClient: MockClient((request) async {
          // Another account lands while the old session is being revoked.
          await client.auth.setInitialSession(_session('u2'));
          throw ClientException('Connection refused', request.url);
        }),
      );
      await expectLater(SupabaseAuthGateway(client).signOut(), throwsA(isA<AuthRetryableFetchException>()));
      expect(client.auth.currentUser?.id, 'u2');
    });

    test('does not wait on a network that never answers', () async {
      final never = Completer<Never>();
      final client = await _signedIn(httpClient: MockClient((_) => never.future));
      await SupabaseAuthGateway(client, signOutTimeout: const Duration(milliseconds: 50)).signOut();
      expect(client.auth.currentSession, isNull);
    });
  });
}
