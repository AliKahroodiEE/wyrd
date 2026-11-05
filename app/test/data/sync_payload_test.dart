import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrd/data/db/database.dart';
import 'package:wyrd/data/models.dart';
import 'package:wyrd/data/remote/remote_api.dart';
import 'package:wyrd/data/repositories/progression_repository.dart';
import 'package:wyrd/data/repositories/quest_repository.dart';
import 'package:wyrd/data/sync/sync_service.dart';
import 'package:wyrd_engine/wyrd_engine.dart';

/// Takes every change and keeps what went up.
class _Server implements RemoteApi {
  final pushed = <Map<String, Object?>>[];

  @override
  Future<List<Map<String, Object?>>> push(List<Map<String, Object?>> changes) async {
    pushed.addAll(changes);
    return [
      for (final c in changes) {'id': c['id'], 'status': 'applied'},
    ];
  }

  @override
  Future<Map<String, Object?>> pull(int cursor) async => {
    'cursor': cursor,
    'has_more': false,
    'changes': <String, Object?>{},
  };

  @override
  Future<Map<String, Object?>?> evaluate(
    String completionId, {
    Map<String, Object?>? clientProposal,
    String? clientModel,
  }) async => null;

  @override
  Future<void> updateProfile(Map<String, Object?> fields) async {}

  @override
  Future<void> updateNotificationPrefs(Map<String, Object?> prefs) async {}
}

/// Every value goes up within the checks of public.quests, public.subtasks
/// and public.completions (…_core_schema.sql), so the server never refuses
/// for good a change this device accepted.
void main() {
  late AppDatabase db;
  late QuestRepository quests;
  late ProgressionRepository progression;
  late _Server server;
  late SyncService sync;

  setUp(() {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    quests = QuestRepository(db);
    progression = ProgressionRepository(db);
    server = _Server();
    sync = SyncService(db, server, progression);
  });
  tearDown(() => db.close());

  /// The payload that went up last for the row [id].
  Map<String, Object?> sent(String id) =>
      server.pushed.lastWhere((c) => c['id'] == id)['payload']! as Map<String, Object?>;

  /// Stores [values] in a row as they are, past the app's own checks, as an
  /// older version or another path may have.
  Future<void> store(String table, String id, Map<String, Object?> values) => db.customStatement(
    'UPDATE $table SET ${values.keys.map((k) => '$k = ?').join(', ')} WHERE id = ?',
    [...values.values, id],
  );

  group('quests', () {
    test('an estimate outside 1 to 1440 minutes goes up as none', () async {
      final ids = <int?, String>{};
      for (final minutes in [null, -5, 0, 1, 90, 1440, 1441, 2000, 90120, 1 << 40]) {
        ids[minutes] = (await quests.create(QuestDraft(title: 'Estimate $minutes', estimatedMinutes: minutes))).id;
      }
      await sync.syncOnce();
      expect(
        {for (final e in ids.entries) e.key: sent(e.value)['estimated_minutes']},
        {
          null: null,
          -5: null,
          0: null,
          1: 1,
          90: 90,
          1440: 1440,
          1441: null,
          2000: null,
          90120: null, // "90-120" typed as an estimate
          1 << 40: null,
        },
      );
    });

    test('priority stays within 0 to 3', () async {
      final ids = <int, String>{};
      for (final priority in [-1, 0, 1, 2, 3, 7]) {
        ids[priority] = (await quests.create(QuestDraft(title: 'Priority $priority', priority: priority))).id;
      }
      await sync.syncOnce();
      expect({for (final e in ids.entries) e.key: sent(e.value)['priority']}, {-1: 0, 0: 0, 1: 1, 2: 2, 3: 3, 7: 3});
    });

    test('title, notes and intention are cut to the server\'s length, between characters', () async {
      final q = await quests.create(const QuestDraft(title: 'Long'));
      await store('quests', q.id, {
        // 199 letters, then a thumbs-up with a skin tone: 201 code points.
        'title': '${'a' * 199}👍🏽',
        // 3998 letters, then beh with kasra and shadda: one character, three code points.
        'notes': '${'ا' * 3998}ب\u0650\u0651',
        // 279 letters, then a flag of two regional indicators.
        'intention': '${'x' * 279}🇮🇷',
      });
      await sync.syncOnce();
      final payload = sent(q.id);
      expect(payload['title'], 'a' * 199);
      expect(payload['notes'], 'ا' * 3998);
      expect(payload['intention'], 'x' * 279);
    });

    test('texts within the server\'s length go up unchanged', () async {
      final title = '${'a' * 198}e\u0301'; // exactly 200 code points, the last two one character
      const notes = 'یادداشت\nبا خط تازه';
      final q = await quests.create(QuestDraft(title: title, notes: notes, intention: 'Pomodoro 👨‍👩‍👧‍👦'));
      await sync.syncOnce();
      final payload = sent(q.id);
      expect(payload['title'], title);
      expect(payload['notes'], notes);
      expect(payload['intention'], 'Pomodoro 👨‍👩‍👧‍👦');
    });

    test('a single character longer than the limit is cut inside rather than sent empty', () async {
      final q = await quests.create(const QuestDraft(title: 'Marks'));
      await store('quests', q.id, {'title': 'z${'\u0301' * 300}'});
      await sync.syncOnce();
      final title = sent(q.id)['title']! as String;
      expect(title.runes.length, 200);
      expect(title, startsWith('z'));
    });

    test('NUL, which no jsonb value holds, is left out', () async {
      final q = await quests.create(const QuestDraft(title: 'Pasted'));
      await store('quests', q.id, {'title': 'Pas\u0000ted', 'notes': '\u0000', 'intention': 'At\u0000 9'});
      await sync.syncOnce();
      final payload = sent(q.id);
      expect(payload['title'], 'Pasted');
      expect(payload['notes'], '');
      expect(payload['intention'], 'At 9');
    });

    test('tier, category and status go up as values the server knows', () async {
      final odd = await quests.create(const QuestDraft(title: 'From a newer version'));
      await store('quests', odd.id, {'tier': 'epic', 'category': 'gardening', 'status': 'snoozed'});
      final paused = await quests.create(const QuestDraft(title: 'Paused elsewhere'));
      await store('quests', paused.id, {'status': 'paused'});
      await sync.syncOnce();
      expect(sent(odd.id)['tier'], 'daily');
      expect(sent(odd.id)['category'], isNull);
      expect(sent(odd.id)['status'], 'active');
      expect(sent(paused.id)['status'], 'paused');
    });

    test('every tier, category and status of the app goes up unchanged', () async {
      final tiers = {for (final t in QuestTier.values) t: (await quests.create(QuestDraft(title: t.name, tier: t))).id};
      final categories = {
        for (final c in QuestCategory.values) c: (await quests.create(QuestDraft(title: c.name, category: c))).id,
      };
      final statuses = <QuestStatus, String>{};
      for (final s in QuestStatus.values) {
        final q = await quests.create(QuestDraft(title: s.name));
        await store('quests', q.id, {'status': s.name});
        statuses[s] = q.id;
      }
      await sync.syncOnce();
      for (final e in tiers.entries) {
        expect(sent(e.value)['tier'], e.key.name);
      }
      for (final e in categories.entries) {
        expect(sent(e.value)['category'], e.key.name);
      }
      for (final e in statuses.entries) {
        expect(sent(e.value)['status'], e.key.name);
      }
    });

    test('a quest is never sent as its own parent', () async {
      // An objective turned into a contract can pick itself in the editor.
      final q = await quests.create(const QuestDraft(title: 'Learn Persian', tier: QuestTier.objective));
      await quests.update(q.id, QuestDraft(title: 'Learn Persian', tier: QuestTier.contract, parentId: q.id));
      final objective = await quests.create(const QuestDraft(title: 'Become fluent', tier: QuestTier.objective));
      final child = await quests.create(QuestDraft(title: 'Lesson 1', parentId: objective.id));
      await sync.syncOnce();
      expect(sent(q.id)['parent_id'], isNull);
      expect(sent(child.id)['parent_id'], objective.id);
    });
  });

  test('a subtask title is cut to the server\'s length, between characters', () async {
    final q = await quests.create(const QuestDraft(title: 'With steps'));
    await quests.addSubtask(q.id, 'Step');
    final s = await db.select(db.subtasks).getSingle();
    // 195 letters, then a family of four: seven code points joined by ZWJ.
    await store('subtasks', s.id, {'title': '${'b' * 195}👨‍👩‍👧‍👦'});
    await sync.syncOnce();
    expect(sent(s.id)['title'], 'b' * 195);
  });

  test('a completion\'s minutes stay within a day', () async {
    final shift = await quests.create(const QuestDraft(title: 'Night shift'));
    final long = await progression.complete(shift, declaredMinutes: 1500, trackedMinutes: 2000);
    final walk = await quests.create(const QuestDraft(title: 'Walk'));
    final short = await progression.complete(walk, declaredMinutes: 30);
    final odd = await quests.create(const QuestDraft(title: 'Odd'));
    final negative = await progression.complete(odd, declaredMinutes: 10);
    await store('completions', negative!.completionId, {'declared_minutes': -3});
    await sync.syncOnce();
    expect(
      sent(long!.completionId),
      allOf(containsPair('declared_minutes', 1440), containsPair('tracked_minutes', 1440)),
    );
    expect(
      sent(short!.completionId),
      allOf(containsPair('declared_minutes', 30), containsPair('tracked_minutes', null)),
    );
    expect(sent(negative.completionId)['declared_minutes'], 0);
  });
}
