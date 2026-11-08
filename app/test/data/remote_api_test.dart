import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wyrd/data/remote/remote_api.dart';

void main() {
  group('a request that never answers', () {
    /// Starts [call] against a server that stays silent, and reports whether
    /// it gave up within a few minutes.
    void givesUp(Future<void> Function(SupabaseRemoteApi api) call) => fakeAsync((time) {
      final client = SupabaseClient(
        'http://127.0.0.1:9',
        'sb_publishable_test',
        httpClient: MockClient((_) => Completer<http.Response>().future),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      Object? failure;
      unawaited(call(SupabaseRemoteApi(client)).then<void>((_) {}, onError: (Object e) => failure = e));
      time.elapse(const Duration(minutes: 3));
      expect(failure, isA<TimeoutException>(), reason: 'or sync would wait for it until the app restarts');
      unawaited(client.dispose());
      time.flushMicrotasks();
    });

    test('ends a push', () => givesUp((api) => api.push(const [])));
    test('ends a pull', () => givesUp((api) => api.pull(0)));
    test('ends an evaluation', () => givesUp((api) => api.evaluate('018f0000-0000-7000-8000-0000000000c1')));
    test('ends a notification settings update', () => givesUp((api) => api.updateNotificationPrefs(const {})));
  });

  test('a pull asks for the server\'s page size unless told another', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'http://127.0.0.1:9',
      'sb_publishable_test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{"cursor":7,"has_more":false,"changes":{}}',
          200,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    final api = SupabaseRemoteApi(client);

    await api.pull(7);
    expect(requests.last.url.path, '/rest/v1/rpc/sync_pull');
    expect(jsonDecode(requests.last.body), {'cursor': 7});
    await api.pull(7, maxRows: 250);
    expect(jsonDecode(requests.last.body), {'cursor': 7, 'max_rows': 250});
  });

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
