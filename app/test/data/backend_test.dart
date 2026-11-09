import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wyrd/data/remote/backend.dart';

void main() {
  group('authErrorsProvider', () {
    test('passes on what Auth reports as errors, also from before anyone listened', () async {
      final client = SupabaseClient(
        'http://127.0.0.1:9',
        'sb_publishable_test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final container = ProviderContainer.test(overrides: [supabaseClientProvider.overrideWithValue(client)]);

      // A stored session that cannot be read: Auth signs out (an event) and
      // reports why (an error) while nothing listens yet, as it does with the
      // link that reopened the web app.
      await expectLater(client.auth.recoverSession('{}'), throwsA(isA<AuthException>()));
      final errors = <Object>[];
      final subscription = container.read(authErrorsProvider).listen(errors.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(errors, [isA<AuthException>().having((e) => e.code, 'code', 'session_missing')]);

      await expectLater(client.auth.setInitialSession('{}'), throwsA(isA<AuthException>()));
      await pumpEventQueue();
      expect(errors, hasLength(2));
    });

    test('is empty without a backend', () async {
      final container = ProviderContainer.test();
      expect(await container.read(authErrorsProvider).isEmpty, isTrue);
    });
  });
}
