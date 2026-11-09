import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wyrd_engine/wyrd_engine.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../models.dart';

/// What happened when a quest was completed, for the reward card.
class CompletionOutcome {
  const CompletionOutcome({
    required this.completionId,
    required this.result,
    required this.proposal,
    required this.provisional,
    required this.levelBefore,
    required this.levelAfter,
    required this.rankUps,
    required this.newAchievements,
  });

  final String completionId;
  final RewardResult result;
  final EvaluationProposal proposal;
  final bool provisional;
  final CurveProgress levelBefore;
  final CurveProgress levelAfter;

  /// Attributes whose rank increased, with the new rank.
  final Map<Attribute, int> rankUps;
  final List<AchievementDef> newAchievements;

  bool get leveledUp => levelAfter.step > levelBefore.step;
}

/// Records completions and turns them into ledger entries through the
/// deterministic engine. Locally the heuristic evaluator proposes; when a
/// backend is connected the server's authoritative result supersedes the
/// provisional one via [reconcile] (ADR-003).
class ProgressionRepository {
  ProgressionRepository(this._db, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  // ------------------------------------------------------------- queries

  /// Lifetime XP per attribute (superseded rows excluded; reversals net out).
  Future<Map<Attribute, int>> attributeTotals({String? fromDay, String? toDayExclusive}) async {
    final where = StringBuffer('superseded = 0');
    final vars = <Variable<Object>>[];
    if (fromDay != null) {
      where.write(' AND local_day >= ?');
      vars.add(Variable(fromDay));
    }
    if (toDayExclusive != null) {
      where.write(' AND local_day < ?');
      vars.add(Variable(toDayExclusive));
    }
    final rows = await _db
        .customSelect(
          'SELECT attribute, SUM(amount) AS total FROM ledger_entries WHERE $where GROUP BY attribute',
          variables: vars,
          readsFrom: {_db.ledgerEntries},
        )
        .get();
    final totals = <Attribute, int>{};
    for (final r in rows) {
      final a = Attribute.tryParse(r.read<String>('attribute'));
      if (a != null) totals[a] = r.read<int>('total');
    }
    return totals;
  }

  /// Engine day state rebuilt from today's active evaluations.
  Future<DayState> dayState(String day) async {
    final rows = await _db
        .customSelect(
          'SELECT e.result_json FROM evaluations e JOIN completions c ON c.id = e.completion_id '
          "WHERE e.local_day = ? AND c.state = 'active'",
          variables: [Variable(day)],
          readsFrom: {_db.evaluations, _db.completions},
        )
        .get();
    var state = DayState.empty;
    for (final r in rows) {
      state = decodeResult(r.read<String>('result_json')).applyTo(state);
    }
    return state;
  }

  /// Local days with at least one non-trivial active completion.
  Future<Set<DateTime>> activeDays() async {
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT e.local_day FROM evaluations e JOIN completions c ON c.id = e.completion_id '
          "WHERE c.state = 'active' AND e.trivial = 0",
          readsFrom: {_db.evaluations, _db.completions},
        )
        .get();
    return {for (final r in rows) parseDayKey(r.read<String>('local_day'))};
  }

  Future<AchievementStats> achievementStats({
    bool returnedAfterLongGap = false,
    int weeklyTarget = 4,
    int firstWeekday = DateTime.monday,
  }) async {
    final counts = await _db
        .customSelect(
          "SELECT q.tier AS tier, COUNT(*) AS n FROM completions c JOIN quests q ON q.id = c.quest_id "
          "WHERE c.state = 'active' GROUP BY q.tier",
          readsFrom: {_db.completions, _db.quests},
        )
        .get();
    final byTier = {for (final r in counts) r.read<String>('tier'): r.read<int>('n')};
    final minutes = await _db
        .customSelect(
          'SELECT COALESCE(SUM(e.effective_minutes), 0) AS m FROM evaluations e '
          "JOIN completions c ON c.id = e.completion_id WHERE c.state = 'active'",
          readsFrom: {_db.evaluations, _db.completions},
        )
        .getSingle();
    final totals = await attributeTotals();
    final total = totals.values.fold(0, (a, b) => a + b);
    final weekly = Consistency.weekly(
      activeDays: await activeDays(),
      today: _now(),
      target: weeklyTarget,
      firstWeekday: firstWeekday,
    );
    return AchievementStats(
      totalCompletions: byTier.values.fold(0, (a, b) => a + b),
      contractsCompleted: byTier[QuestTier.contract.name] ?? 0,
      objectivesCompleted: byTier[QuestTier.objective.name] ?? 0,
      level: Curves.level(total).step,
      ranks: {for (final a in Attribute.values) a: Curves.rank(totals[a] ?? 0).step},
      bestWeekStreak: weekly.bestStreak,
      totalCreditedMinutes: minutes.read<int>('m'),
      returnedAfterLongGap: returnedAfterLongGap,
    );
  }

  Future<Set<String>> unlockedAchievementIds() async =>
      (await _db.select(_db.unlockedAchievements).get()).map((r) => r.id).toSet();

  // ------------------------------------------------------------- commands

  /// Completes [quest] now. Idempotent per occurrence: completing a quest
  /// already completed today returns null.
  Future<CompletionOutcome?> complete(
    Quest quest, {
    int? declaredMinutes,
    int? trackedMinutes,
    bool provisional = false,
    int weeklyTarget = 4,
    int firstWeekday = DateTime.monday,
    EvaluationProposal? aiProposal,
  }) async {
    final now = _now();
    final day = dayKey(now);
    final existing =
        await (_db.select(_db.completions)
              ..where((c) => c.questId.equals(quest.id) & c.occurrenceDay.equals(day) & c.state.equals('active')))
            .getSingleOrNull();
    if (existing != null) return null;

    // A proposal from the user's own AI provider, when available;
    // otherwise the built-in heuristic. The engine decides either way.
    final proposal =
        aiProposal ??
        HeuristicEvaluator.evaluate(
          HeuristicInput(
            title: quest.title,
            notes: quest.notes,
            tier: quest.tier,
            categoryHint: quest.category,
            declaredMinutes: declaredMinutes,
            estimatedMinutes: quest.estimatedMinutes,
          ),
        );
    final facts = CompletionFacts(
      tier: quest.tier,
      createdAt: quest.createdAt,
      completedAt: now,
      declaredMinutes: declaredMinutes,
      trackedMinutes: trackedMinutes,
      dueAt: quest.isRecurring ? null : quest.dueInstant,
      isRecurringOccurrence: quest.isRecurring,
      hasImplementationIntention: quest.hasIntention,
    );
    final result = ProgressionEngine.evaluate(proposal: proposal, facts: facts, day: await dayState(day));

    final totalsBefore = await attributeTotals();
    final away = Consistency.daysAway(await activeDays(), now);
    final completionId = _uuid.v7();

    await _db.transaction(() async {
      await _db
          .into(_db.completions)
          .insert(
            CompletionsCompanion.insert(
              id: completionId,
              questId: quest.id,
              occurrenceDay: day,
              localDay: day,
              completedAt: now,
              declaredMinutes: Value(declaredMinutes),
              trackedMinutes: Value(trackedMinutes),
              createdAt: now,
            ),
          );
      await _writeEvaluation(completionId, day, proposal, result, provisional: provisional);
      await _writeGrants(completionId, day, result, provisional: provisional);
      if (!quest.isRecurring) {
        await (_db.update(_db.quests)..where((q) => q.id.equals(quest.id))).write(
          QuestsCompanion(status: const Value('completed'), updatedAt: Value(now)),
        );
      }
      await _enqueue('completion', completionId);
      // After the completion. Without it the server would keep the quest
      // open, and every other device would list it as still to do.
      if (!quest.isRecurring) await _enqueue('quest', quest.id, fields: const ['status']);
    });

    final totalsAfter = await attributeTotals();
    final newAchievements = await _unlockAchievements(
      returnedAfterLongGap: !result.trivial && away != null && away >= 7,
      weeklyTarget: weeklyTarget,
      firstWeekday: firstWeekday,
    );
    int sum(Map<Attribute, int> m) => m.values.fold(0, (a, b) => a + b);
    final rankUps = <Attribute, int>{
      for (final a in Attribute.values)
        if (Curves.rank(totalsAfter[a] ?? 0).step > Curves.rank(totalsBefore[a] ?? 0).step)
          a: Curves.rank(totalsAfter[a] ?? 0).step,
    };
    return CompletionOutcome(
      completionId: completionId,
      result: result,
      proposal: proposal,
      provisional: provisional,
      levelBefore: Curves.level(sum(totalsBefore)),
      levelAfter: Curves.level(sum(totalsAfter)),
      rankUps: rankUps,
      newAchievements: newAchievements,
    );
  }

  /// Undoes a completion within 24 hours by appending reversing entries.
  /// Returns false when the window has passed.
  Future<bool> undo(String completionId) async {
    final c = await (_db.select(_db.completions)..where((c) => c.id.equals(completionId))).getSingleOrNull();
    if (c == null || c.state != 'active') return false;
    if (_now().difference(c.completedAt) > const Duration(hours: 24)) return false;
    await _db.transaction(() async {
      final grants = await (_db.select(
        _db.ledgerEntries,
      )..where((l) => l.completionId.equals(completionId) & l.superseded.equals(false) & l.kind.equals('grant'))).get();
      for (final g in grants) {
        await _db
            .into(_db.ledgerEntries)
            .insert(
              LedgerEntriesCompanion.insert(
                id: _uuid.v7(),
                completionId: Value(completionId),
                attribute: g.attribute,
                amount: -g.amount,
                rawAmount: -g.rawAmount,
                kind: 'reversal',
                ruleVersion: g.ruleVersion,
                localDay: g.localDay,
                provisional: Value(g.provisional),
                createdAt: _now(),
              ),
            );
      }
      await (_db.update(
        _db.completions,
      )..where((x) => x.id.equals(completionId))).write(const CompletionsCompanion(state: Value('undone')));
      final reopened =
          await (_db.update(_db.quests)..where((q) => q.id.equals(c.questId) & q.status.equals('completed'))).write(
            QuestsCompanion(status: const Value('active'), updatedAt: Value(_now())),
          );
      await _enqueue('completion_undo', completionId);
      if (reopened > 0) await _enqueue('quest', c.questId, fields: const ['status']);
    });
    return true;
  }

  /// Replaces a provisional local result with the server's authoritative
  /// one. Both stay in the ledger; the provisional rows are superseded.
  Future<void> reconcile(String completionId, EvaluationProposal proposal, RewardResult result) => _db.transaction(
    () async {
      // Undone while the evaluation was on its way: the reversals stand.
      final completion = await (_db.select(_db.completions)..where((c) => c.id.equals(completionId))).getSingleOrNull();
      if (completion == null || completion.state == 'undone') return;
      final eval = await (_db.select(
        _db.evaluations,
      )..where((e) => e.completionId.equals(completionId))).getSingleOrNull();
      if (eval == null) return;
      await (_db.update(_db.ledgerEntries)..where((l) => l.completionId.equals(completionId))).write(
        const LedgerEntriesCompanion(superseded: Value(true)),
      );
      await _writeEvaluation(completionId, eval.localDay, proposal, result, provisional: false);
      await _writeGrants(completionId, eval.localDay, result, provisional: false);
    },
  );

  /// Records a server-confirmed result for a completion that arrived from
  /// another device (no local evaluation exists yet).
  Future<void> importConfirmed(CompletionRow completion, EvaluationProposal proposal, RewardResult result) =>
      _db.transaction(() async {
        await _writeEvaluation(completion.id, completion.localDay, proposal, result, provisional: false);
        await _writeGrants(completion.id, completion.localDay, result, provisional: false);
      });

  /// Active completions with [similarityKey] since [since] (AI context).
  Future<int> similarCountSince(String similarityKey, DateTime since) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM evaluations e JOIN completions c ON c.id = e.completion_id '
          "WHERE c.state = 'active' AND e.similarity_key = ? AND e.local_day >= ?",
          variables: [Variable(similarityKey), Variable(dayKey(since))],
          readsFrom: {_db.evaluations, _db.completions},
        )
        .getSingle();
    return row.read<int>('n');
  }

  Future<void> setRestDay(String day, bool rest) =>
      _db.into(_db.dayMarks).insertOnConflictUpdate(DayMarksCompanion.insert(localDay: day, rest: Value(rest)));

  Future<void> markPausedDays(Iterable<String> days) => _db.batch((b) {
    for (final d in days) {
      b.insert(
        _db.dayMarks,
        DayMarksCompanion.insert(localDay: d, paused: const Value(true)),
        onConflict: DoUpdate((_) => const DayMarksCompanion(paused: Value(true))),
      );
    }
  });

  // ------------------------------------------------------------- helpers

  Future<void> _writeEvaluation(
    String completionId,
    String day,
    EvaluationProposal proposal,
    RewardResult result, {
    required bool provisional,
  }) => _db
      .into(_db.evaluations)
      .insertOnConflictUpdate(
        EvaluationsCompanion.insert(
          completionId: completionId,
          localDay: day,
          category: proposal.category.name,
          similarityKey: result.similarityKey,
          effectiveMinutes: result.effectiveMinutes,
          totalXp: result.totalXp,
          trivial: result.trivial,
          source: result.source.name,
          proposalJson: jsonEncode(proposal.toJson()),
          resultJson: jsonEncode(result.toJson()),
          provisional: Value(provisional),
          createdAt: _now(),
        ),
      );

  Future<void> _writeGrants(String completionId, String day, RewardResult result, {required bool provisional}) async {
    for (final g in result.grants) {
      await _db
          .into(_db.ledgerEntries)
          .insert(
            LedgerEntriesCompanion.insert(
              id: _uuid.v7(),
              completionId: Value(completionId),
              attribute: g.attribute.name,
              amount: g.amount,
              rawAmount: g.rawAmount,
              kind: 'grant',
              ruleVersion: result.ruleVersion,
              localDay: day,
              provisional: Value(provisional),
              createdAt: _now(),
            ),
          );
    }
  }

  Future<List<AchievementDef>> _unlockAchievements({
    required bool returnedAfterLongGap,
    required int weeklyTarget,
    required int firstWeekday,
  }) async {
    final stats = await achievementStats(
      returnedAfterLongGap: returnedAfterLongGap,
      weeklyTarget: weeklyTarget,
      firstWeekday: firstWeekday,
    );
    final fresh = Achievements.newlyUnlocked(stats, await unlockedAchievementIds());
    if (fresh.isEmpty) return fresh;
    await _db.batch((b) {
      for (final a in fresh) {
        b.insert(
          _db.unlockedAchievements,
          UnlockedAchievementsCompanion.insert(id: a.id, unlockedAt: _now()),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
    return fresh;
  }

  /// Queues a change for sync; [fields] are the server's names for what it
  /// changed, and only those go up.
  Future<void> _enqueue(String entity, String id, {List<String>? fields}) => _db
      .into(_db.outboxEntries)
      .insert(
        OutboxEntriesCompanion.insert(
          entity: entity,
          entityId: id,
          op: 'upsert',
          payload: jsonEncode({'id': id, 'fields': ?fields}),
          createdAt: _now(),
        ),
      );
}
