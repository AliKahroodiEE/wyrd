import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wyrd/features/notifications/push_platform.dart';

void main() {
  group('SupabasePushRegistry', () {
    late List<http.Request> requests;
    late SupabaseClient client;

    setUp(() {
      requests = [];
      client = SupabaseClient(
        'https://abcdefghijklmnopqrst.supabase.co',
        'sb_publishable_test',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('', 204, request: request);
        }),
      );
    });

    tearDown(() => client.dispose());

    test('register sends the token and platform to register_push_token', () async {
      await SupabasePushRegistry(client).register('token-1', 'android');

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/rest/v1/rpc/register_push_token');
      expect(jsonDecode(requests.single.body), {'token': 'token-1', 'platform': 'android'});
    });

    test('unregister goes through unregister_push_token, never the table', () async {
      await SupabasePushRegistry(client).unregister('token-1');

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/rest/v1/rpc/unregister_push_token');
      expect(jsonDecode(requests.single.body), {'token': 'token-1'});
    });
  });
}
