import 'dart:async';
import 'dart:ui' show Locale;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
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

/// Asks to retry every change later, as the server does for a completion
/// whose quest it never got.
class _RetryLater extends Fake implements RemoteApi {
  /// The ids each push carried.
  final pushes = <List<Object?>>[];

  @override
  Future<List<Map<String, Object?>>> push(List<Map<String, Object?>> changes) async {
    pushes.add([for (final c in changes) c['id']]);
    return [
      for (final c in changes) {'id': c['id'], 'status': 'rejected', 'reason': 'missing_reference', 'retryable': true},
    ];
  }

  @override
  Future<Map<String, Object?>> pull(int cursor) async => {
    'cursor': cursor,
    'has_more': false,
    'changes': const <String, Object?>{},
  };

  @override
  Future<void> updateProfile(Map<String, Object?> fields) async {}

  @override
  Future<void> updateNotificationPrefs(Map<String, Object?> prefs) async {}
}

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
  // Plain tests only in this file: with a Flutter binding, each cycle's
  // time zone lookup would wait on the platform, which fake time never
  // answers. Without one it fails at once and is left out.
  test(
    'a change the server keeps asking to retry waits for the next cycle; a new one goes up 2 s after it is made',
    () {
      fakeAsync((time) {
        final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
        final server = _RetryLater();
        final users = StreamController<User?>();
        final container = ProviderContainer.test(
          overrides: [
            databaseProvider.overrideWithValue(db),
            syncApiProvider.overrideWithValue(server),
            aiSettingsRepositoryProvider.overrideWithValue(AiSettingsRepository(db, MemoryKeyStore())),
            currentUserProvider.overrideWith((ref) => users.stream),
            regionalProvider.overrideWithValue(_english),
          ],
        );
        try {
          container.listen(syncCoordinatorProvider, (_, _) {});
          final quests = QuestRepository(db);
          late Quest refused, later;
          unawaited(quests.create(const QuestDraft(title: 'Refused for now')).then((q) => refused = q));
          time.flushMicrotasks();

          users.add(_userA);
          time.elapse(const Duration(seconds: 10));
          // Counting the refusal is not a local change: no new cycle for it.
          expect(server.pushes, [
            [refused.id],
          ]);

          unawaited(quests.create(const QuestDraft(title: 'Made later')).then((q) => later = q));
          time.elapse(const Duration(milliseconds: 1900));
          expect(server.pushes, hasLength(1));
          time.elapse(const Duration(milliseconds: 200));
          expect(server.pushes, hasLength(2));
          expect(server.pushes.last, [refused.id, later.id]);
        } finally {
          container.dispose();
          unawaited(users.close());
          unawaited(db.close());
          time.flushMicrotasks();
        }
      });
    },
  );

  group('signing in where another account left its data', () {
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

    /// Signs A in while a request of the account before is still out, and
    /// out again before that request ends.
    Future<void> signInAndOutWhileTheOneBeforeSyncs() async {
      final before = Completer<void>();
      container.read(syncControlProvider).track(before.future);
      users.add(_userA);
      await pumpEventQueue(); // A's first cycle waits for it
      users.add(null);
      before.complete();
      await pumpEventQueue();
    }

    test('the question is withdrawn when its sign-in ends, and nothing is removed', () async {
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

    test('the question is withdrawn once another tab has claimed the device for this account', () async {
      await leaveUnsynced();
      users.add(_userA);
      final question = await _asked(container);

      // Other writes leave it open.
      await ai.save(const AiProviderConfig(kind: AiProviderKind.openai, model: 'gpt-5'));
      await pumpEventQueue();
      expect(question.withdrawn, isFalse);

      // The web app's tabs share this database: Remove was chosen in another.
      await SyncService(db, _NoServer(), ProgressionRepository(db)).claimFor(_userA.id, email: _userA.email);
      await pumpEventQueue();
      expect(question.withdrawn, isTrue);
      expect(await question.answer, isFalse);
      expect(container.read(handoverProvider), isNull);
    });

    test('a sign-in that ends while the account before still syncs asks nothing', () async {
      await leaveUnsynced();
      final asked = <Handover>[];
      container.listen<Handover?>(handoverProvider, (_, next) {
        if (next != null) asked.add(next);
      });
      await signInAndOutWhileTheOneBeforeSyncs();
      expect(asked, isEmpty);
      await expectKept(unsynced: 1);
    });

    test('a sign-in that ends while the account before still syncs clears nothing', () async {
      // Nothing unsynced: there is no question, the AI key would go next.
      await signInAndOutWhileTheOneBeforeSyncs();
      await expectKept(unsynced: 0);
    });
  });
}
