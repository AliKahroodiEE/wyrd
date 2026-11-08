import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrd/data/db/database.dart';
import 'package:wyrd/data/models.dart';
import 'package:wyrd/data/repositories/character_repository.dart';
import 'package:wyrd/data/repositories/progression_repository.dart';
import 'package:wyrd/data/repositories/quest_repository.dart';
import 'package:wyrd/data/repositories/settings_repository.dart';
import 'package:wyrd_engine/wyrd_engine.dart';

void main() {
  late AppDatabase db;
  late DateTime now;
  late QuestRepository quests;
  late ProgressionRepository progression;
  late CharacterRepository character;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    now = DateTime(2026, 11, 4, 8);
    DateTime clock() => now;
    quests = QuestRepository(db, clock: clock);
    progression = ProgressionRepository(db, clock: clock);
    settings = SettingsRepository(db);
    character = CharacterRepository(db, progression, settings, clock: clock);
  });

  tearDown(() => db.close());

  test('creating and completing a quest records growth and an achievement', () async {
    final q = await quests.create(const QuestDraft(title: 'Study electronics for 90 minutes'));
    now = now.add(const Duration(hours: 11));

    final outcome = await progression.complete(q, declaredMinutes: 90);
    expect(outcome, isNotNull);
    expect(outcome!.result.amountFor(Attribute.intelligence), greaterThan(0));
    expect(outcome.newAchievements.map((a) => a.id), contains('first_oath'));
    expect(outcome.levelBefore.step, 1);

    final totals = await progression.attributeTotals();
    expect(totals.values.fold(0, (a, b) => a + b), outcome.result.totalXp);
    expect((await quests.byId(q.id))!.status, QuestStatus.completed);

    final today = await quests.today(DateTime.monday);
    expect(today.single.completedToday, isTrue);
  });

  test('a quest cannot be completed twice for the same occurrence', () async {
    final q = await quests.create(const QuestDraft(title: 'Read 10 pages'));
    expect(await progression.complete(q), isNotNull);
    expect(await progression.complete(q), isNull);
  });

  test('undo reverses rewards within 24 hours and reopens the quest', () async {
    final q = await quests.create(const QuestDraft(title: 'Go to the gym 60m'));
    final outcome = await progression.complete(q);
    expect(await progression.undo(outcome!.completionId), isTrue);
    final totals = await progression.attributeTotals();
    expect(totals.values.every((v) => v == 0), isTrue);
    expect((await quests.byId(q.id))!.status, QuestStatus.active);
    // Repeating after undo is allowed again.
    expect(await progression.complete(q), isNotNull);
  });

  test('undo is refused after 24 hours', () async {
    final q = await quests.create(const QuestDraft(title: 'Call mom'));
    final outcome = await progression.complete(q);
    now = now.add(const Duration(hours: 25));
    expect(await progression.undo(outcome!.completionId), isFalse);
  });

  test('recurring quests recur daily and earn the follow-through bonus', () async {
    final q = await quests.create(const QuestDraft(title: 'Meditation 10 min', recurrence: Recurrence.daily));
    final first = await progression.complete(q);
    expect(first!.result.hasAdjustment(AdjustmentCode.followThrough), isTrue);
    now = now.add(const Duration(days: 1));
    expect((await quests.today(DateTime.monday)).single.completedToday, isFalse);
    expect(await progression.complete(q), isNotNull);
  });

  test('repetition within a day decays rewards', () async {
    final a = await quests.create(const QuestDraft(title: 'Study electronics 60m'));
    final b = await quests.create(const QuestDraft(title: 'Study electronics 60m'));
    final first = await progression.complete(a);
    final second = await progression.complete(b);
    expect(second!.result.totalXp, lessThan(first!.result.totalXp));
    expect(second.result.hasAdjustment(AdjustmentCode.repetition), isTrue);
  });

  test('an evaluation that arrives after an undo leaves it undone', () async {
    final q = await quests.create(const QuestDraft(title: 'Write report 45m'));
    final outcome = await progression.complete(q, provisional: true);
    expect(await progression.undo(outcome!.completionId), isTrue);
    final undone = await progression.attributeTotals();
    const server = RewardResult(
      grants: [Grant(Attribute.discipline, 7, 7)],
      effectiveMinutes: 45,
      trivial: false,
      similarityKey: 'work.report',
      adjustments: [],
      ruleVersion: rulesVersion,
      source: ProposalSource.ai,
    );
    await progression.reconcile(outcome.completionId, outcome.proposal, server);
    expect(await progression.attributeTotals(), undone, reason: 'the XP stays taken back');
  });

  test('server reconciliation supersedes provisional rows', () async {
    final q = await quests.create(const QuestDraft(title: 'Write report 45m'));
    final outcome = await progression.complete(q, provisional: true);
    const server = RewardResult(
      grants: [Grant(Attribute.discipline, 7, 7)],
      effectiveMinutes: 45,
      trivial: false,
      similarityKey: 'work.report',
      adjustments: [],
      ruleVersion: rulesVersion,
      source: ProposalSource.ai,
    );
    await progression.reconcile(outcome!.completionId, outcome.proposal, server);
    final totals = await progression.attributeTotals();
    expect(totals, {Attribute.discipline: 7});
  });

  test('character state derives level, today XP and consistency', () async {
    await settings.saveProfile(const UserProfile(characterName: 'Arin', weeklyTarget: 1));
    final q = await quests.create(const QuestDraft(title: 'Run 5k 30m'));
    final outcome = await progression.complete(q);
    final state = await character.load(DateTime.monday);
    expect(state.profile.characterName, 'Arin');
    expect(state.totalXp, outcome!.result.totalXp);
    expect(state.todayXp.values.fold(0, (a, b) => a + b), outcome.result.totalXp);
    expect(state.weekly.keptThisWeek, isTrue);
    expect(state.condition, 100);
    expect(state.recent.single.questTitle, 'Run 5k 30m');
    expect(state.achievements.map((a) => a.id), contains('first_oath'));
  });

  test('period stats aggregate minutes, categories and XP by day', () async {
    final q = await quests.create(const QuestDraft(title: 'Study 40m'));
    await progression.complete(q);
    final stats = await character.period(DateTime(2026, 11, 2), DateTime(2026, 11, 9));
    expect(stats.completions, 1);
    expect(stats.minutes, 40);
    expect(stats.minutesByCategory[QuestCategory.study], 40);
    expect(stats.activeDays, {'2026-11-04'});
    expect(stats.xpByDay['2026-11-04'], isNotEmpty);
    expect(stats.strongest, Attribute.intelligence);
  });

  test('objectives report progress from linked quests', () async {
    final goal = await quests.create(const QuestDraft(title: 'Learn Python', tier: QuestTier.objective));
    final step = await quests.create(QuestDraft(title: 'Python exercise 30m', parentId: goal.id));
    await quests.create(QuestDraft(title: 'Build a small project', parentId: goal.id, tier: QuestTier.contract));
    await progression.complete(step);
    final view = (await quests.byTier(QuestTier.objective)).single;
    expect(view.subtasksDone, 1);
    expect(view.subtasksTotal, 2);
  });

  test('profile and regional settings round-trip', () async {
    await settings.updateProfile((p) => p.copyWith(tone: 'gentle', drivers: ['progress']));
    final p = await settings.profile();
    expect(p.tone, 'gentle');
    expect(p.drivers, ['progress']);
  });
}
