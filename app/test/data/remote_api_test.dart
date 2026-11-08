import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wyrd/data/remote/remote_api.dart';

void main() {
  group('evaluate', () {
    late List<http.Request> requests;

    /// The app's API against an evaluate-completion that answers [status]
    /// with [body], as the Edge Function does (errorResponse in http.ts).
    SupabaseRemoteApi answering(int status, Map<String, Object?> body) {
      requests = [];
      final client = SupabaseClient(
        'http://127.0.0.1:9',
        'sb_publishable_test',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      return SupabaseRemoteApi(client);
    }

    test('a completion undone on the server is a final answer, not a failure', () async {
      final api = answering(409, {'error': 'completion_undone', 'message': 'This completion was undone.'});
      expect(await api.evaluate('018f0000-0000-7000-8000-0000000000c1'), {'status': 'undone'});
      expect(requests.single.url.path, '/functions/v1/evaluate-completion');
    });

    test('a busy server is asked again next time', () async {
      final api = answering(409, {'error': 'busy', 'message': 'The day changed repeatedly; please retry.'});
      await expectLater(
        api.evaluate('018f0000-0000-7000-8000-0000000000c1'),
        throwsA(isA<FunctionException>().having((e) => e.status, 'status', 409)),
      );
    });

    test('other refusals are asked again next time', () async {
      final api = answering(404, {'error': 'completion_not_found', 'message': 'Sync the completion first.'});
      await expectLater(api.evaluate('018f0000-0000-7000-8000-0000000000c1'), throwsA(isA<FunctionException>()));
    });

    test('an evaluation comes back as the function sent it', () async {
      final api = answering(200, {
        'status': 'applied',
        'result': {'totalXp': 7},
        'proposal': {'category': 'work'},
      });
      final res = await api.evaluate('018f0000-0000-7000-8000-0000000000c1');
      expect(res?['status'], 'applied');
      expect(res?['result'], {'totalXp': 7});
    });
  });
}
