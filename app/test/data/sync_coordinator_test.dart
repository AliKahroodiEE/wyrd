import 'dart:async';
import 'dart:ui' show Locale;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthClientOptions, SupabaseClient, User;
import 'package:wyrd/app/providers.dart';
import 'package:wyrd/core/locale/regional_settings.dart';
import 'package:wyrd/data/ai/ai_client.dart';
import 'package:wyrd/data/ai/ai_settings_repository.dart';
import 'package:wyrd/data/db/database.dart';
import 'package:wyrd/data/models.dart';
import 'package:wyrd/data/remote/backend.dart';
import 'package:wyrd/data/remote/remote_api.dart';
import 'package:wyrd/data/repositories/progression_repository.dart';
import 'package:wyrd/data/repositories/quest_repository.dart';
import 'package:wyrd/data/sync/sync_coordinator.dart';
import 'package:wyrd/data/sync/sync_service.dart';

/// Never called: claiming the device needs no server.
class _NoServer extends Fake implements RemoteApi {}

const _userA = User(
  id: '00000000-0000-4000-8000-00000000000a',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  email: 'a@example.test',
  createdAt: '2026-11-04T00:00:00Z',
);

final _english = const RegionalPrefs(language: 'en').resolve(const Locale('en'));

/// The next question sync asks.
Future<Handover> _asked(ProviderContainer container) {
  final asked = Completer<Handover>();
  final sub = container.listen<Handover?>(handoverProvider, (_, next) {
    if (next != null && !asked.isCompleted) asked.complete(next);
  }, fireImmediately: true);
  return asked.future.timeout(const Duration(seconds: 5)).whenComplete(sub.close);
}

void main() {
  group('the question about another account\'s unsynced work', () {
    late AppDatabase db;
    late MemoryKeyStore keys;
    late AiSettingsRepository ai;
    late SyncService device;
    late StreamController<User?> users;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
      addTearDown(db.close);
      // The device belongs to owner-c, whose AI provider and key are here.
      keys = MemoryKeyStore()..value = 'sk-c';
      ai = AiSettingsRepository(db, keys);
      await ai.save(const AiProviderConfig(kind: AiProviderKind.anthropic, model: 'claude-opus-5-5'));
      device = SyncService(db, _NoServer(), ProgressionRepository(db));
      await device.claimFor('owner-c', email: 'c@example.test');

      final client = SupabaseClient(
        'http://127.0.0.1:9',
        'sb_publishable_test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      // Synchronous, so a sign-in ends exactly where a test says.
      users = StreamController<User?>(sync: true);
      addTearDown(() => unawaited(users.close()));
      container = ProviderContainer.test(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiSettingsRepositoryProvider.overrideWithValue(ai),
          supabaseClientProvider.overrideWithValue(client),
          currentUserProvider.overrideWith((ref) => users.stream),
          regionalProvider.overrideWithValue(_english),
        ],
      );
      container.listen(syncCoordinatorProvider, (_, _) {});
    });

    Future<void> leaveUnsynced() => QuestRepository(db).create(const QuestDraft(title: 'Not synced yet'));

    /// Nothing of owner-c's was removed.
    Future<void> expectKept({required int unsynced}) async {
      expect(await device.owner(), 'owner-c');
      expect(await device.unsyncedChanges(), unsynced);
      expect(await ai.config(), isNotNull);
      expect(keys.value, 'sk-c');
    }

    test('is withdrawn when its sign-in ends, and nothing is removed', () async {
      await leaveUnsynced();
      users.add(_userA);
      final question = await _asked(container);
      expect(question.previousEmail, 'c@example.test');
      expect(question.unsynced, 1);

      users.add(null);
      await pumpEventQueue();
      expect(container.read(handoverProvider), isNull);
      expect(question.withdrawn, isTrue);
      expect(await question.answer, isFalse);
      await expectKept(unsynced: 1);
    });

    test('Remove that comes after its sign-in ended removes nothing', () async {
      await leaveUnsynced();
      users.add(_userA);
      final question = await _asked(container);

      users.add(null); // sync stops now; the question is withdrawn just after
      question.decide(remove: true); // but Remove came first
      await pumpEventQueue();
      expect(await question.answer, isTrue);
      await expectKept(unsynced: 1);
    });
  });
}
