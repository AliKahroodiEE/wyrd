import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wyrd_engine/wyrd_engine.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../models.dart';

/// Quests, subtasks and the lists built from them.
class QuestRepository {
  QuestRepository(this._db, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  Stream<void> get _changes =>
      _db.tableUpdates(TableUpdateQuery.onAllTables([_db.quests, _db.subtasks, _db.completions]));

  Stream<T> _watch<T>(Future<T> Function() load) async* {
    yield await load();
    await for (final _ in _changes) {
      yield await load();
    }
  }

  // ---------------------------------------------------------------- reads

  Future<Quest?> byId(String id) async {
    final row = await (_db.select(_db.quests)..where((q) => q.id.equals(id))).getSingleOrNull();
    return row == null || row.deletedAt != null ? null : Quest.fromRow(row);
  }

  Stream<Quest?> watchById(String id) => _watch(() => byId(id));

  Future<List<Quest>> _live() async {
    final rows =
        await (_db.select(_db.quests)
              ..where((q) => q.deletedAt.isNull())
              ..orderBy([(q) => OrderingTerm.desc(q.priority), (q) => OrderingTerm.asc(q.createdAt)]))
            .get();
    return rows.map(Quest.fromRow).toList();
  }

  Future<Map<String, String>> _completionsOn(String day) async {
    final rows = await (_db.select(
      _db.completions,
    )..where((c) => c.occurrenceDay.equals(day) & c.state.equals('active'))).get();
    return {for (final r in rows) r.questId: r.id};
  }

  Future<Map<String, (int, int)>> _subtaskCounts() async {
    final rows = await _db
        .customSelect(
          'SELECT quest_id, SUM(done) AS done, COUNT(*) AS total FROM subtasks '
          'WHERE deleted_at IS NULL GROUP BY quest_id',
          readsFrom: {_db.subtasks},
        )
        .get();
    return {for (final r in rows) r.read<String>('quest_id'): (r.read<int>('done'), r.read<int>('total'))};
  }

  /// Quests for today: recurring occurrences, undated daily quests,
  /// anything planned for today or earlier, and today's completions.
  Future<List<QuestView>> today(int firstWeekday) async {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final key = dayKey(now);
    final done = await _completionsOn(key);
    final counts = await _subtaskCounts();
    final out = <QuestView>[];
    for (final q in await _live()) {
      if (q.tier == QuestTier.objective) continue;
      final bool include;
      if (q.isRecurring) {
        include = q.status != QuestStatus.archived && q.occursOn(today, firstWeekday);
      } else if (q.status == QuestStatus.completed) {
        include = done.containsKey(q.id);
      } else if (q.status == QuestStatus.active) {
        include = q.dueAt == null ? q.tier == QuestTier.daily : !q.dueAt!.isAfter(today);
      } else {
        include = false;
      }
      if (!include) continue;
      final c = counts[q.id];
      out.add(
        QuestView(
          quest: q,
          completedToday: done.containsKey(q.id),
          todayCompletionId: done[q.id],
          subtasksDone: c?.$1 ?? 0,
          subtasksTotal: c?.$2 ?? 0,
        ),
      );
    }
    out.sort((a, b) {
      if (a.completedToday != b.completedToday) return a.completedToday ? 1 : -1;
      return b.quest.priority.compareTo(a.quest.priority);
    });
    return out;
  }

  Stream<List<QuestView>> watchToday(int firstWeekday) => _watch(() => today(firstWeekday));

  Future<List<QuestView>> upcoming() async {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = await _subtaskCounts();
    final list =
        (await _live())
            .where(
              (q) =>
                  !q.isRecurring &&
                  q.status == QuestStatus.active &&
                  q.tier != QuestTier.objective &&
                  q.dueAt != null &&
                  q.dueAt!.isAfter(today),
            )
            .toList()
          ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    return [
      for (final q in list)
        QuestView(quest: q, subtasksDone: counts[q.id]?.$1 ?? 0, subtasksTotal: counts[q.id]?.$2 ?? 0),
    ];
  }

  Stream<List<QuestView>> watchUpcoming() => _watch(upcoming);

  /// Active contracts or objectives. Objective progress counts linked
  /// quests and contracts that are completed.
  Future<List<QuestView>> byTier(QuestTier tier) async {
    final all = await _live();
    final counts = await _subtaskCounts();
    final out = <QuestView>[];
    for (final q in all.where((q) => q.tier == tier && q.status == QuestStatus.active)) {
      if (tier == QuestTier.objective) {
        final children = all.where((c) => c.parentId == q.id).toList();
        out.add(
          QuestView(
            quest: q,
            subtasksDone: children.where((c) => c.status == QuestStatus.completed).length,
            subtasksTotal: children.length,
          ),
        );
      } else {
        out.add(QuestView(quest: q, subtasksDone: counts[q.id]?.$1 ?? 0, subtasksTotal: counts[q.id]?.$2 ?? 0));
      }
    }
    return out;
  }

  Stream<List<QuestView>> watchByTier(QuestTier tier) => _watch(() => byTier(tier));

  Future<List<Quest>> objectives() async =>
      (await _live()).where((q) => q.tier == QuestTier.objective && q.status == QuestStatus.active).toList();

  Stream<List<SubtaskRow>> watchSubtasks(String questId) =>
      (_db.select(_db.subtasks)
            ..where((s) => s.questId.equals(questId) & s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.asc(s.position)]))
          .watch();

  // --------------------------------------------------------------- writes

  Future<Quest> create(QuestDraft d) async {
    final now = _now();
    final id = _uuid.v7();
    await _db.transaction(() async {
      await _db
          .into(_db.quests)
          .insert(
            QuestsCompanion.insert(
              id: id,
              parentId: Value(d.parentId),
              tier: d.tier.name,
              title: d.title.trim(),
              notes: Value(d.notes.trim()),
              category: Value(d.category?.name),
              priority: Value(d.priority),
              dueAt: Value(_dateOnly(d.dueAt)),
              estimatedMinutes: Value(d.estimatedMinutes),
              recurrence: Value(d.recurrence.name),
              intention: Value(_blankToNull(d.intention)),
              shareLevel: Value(d.shareLevel.name),
              remindAt: Value(d.remindAt),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _enqueue('quest', id);
    });
    return (await byId(id))!;
  }

  Future<void> update(String id, QuestDraft d) => _db.transaction(() async {
    final q = await (_db.select(_db.quests)..where((q) => q.id.equals(id))).getSingleOrNull();
    if (q == null) return;
    final dueAt = _dateOnly(d.dueAt);
    final dueChanged = q.dueAt?.millisecondsSinceEpoch != dueAt?.millisecondsSinceEpoch;
    // The server's names for what this save changes (see _enqueue).
    final fields = <String>[
      if (q.parentId != d.parentId) 'parent_id',
      if (q.tier != d.tier.name) 'tier',
      if (q.title != d.title.trim()) 'title',
      if (q.notes != d.notes.trim()) 'notes',
      if (q.category != d.category?.name) 'category',
      if (q.priority != d.priority) 'priority',
      if (dueChanged) 'due_at',
      if (q.estimatedMinutes != d.estimatedMinutes) 'estimated_minutes',
      if (q.recurrence != d.recurrence.name) 'recurrence',
      if (q.intention != _blankToNull(d.intention)) 'intention',
      if (q.shareLevel != d.shareLevel.name) 'share_level',
      // A reminder falls on the due date, so it moves with it.
      if (q.remindAt != d.remindAt || (dueChanged && d.remindAt != null)) 'reminder_at',
    ];
    if (fields.isEmpty) return;
    await (_db.update(_db.quests)..where((q) => q.id.equals(id))).write(
      QuestsCompanion(
        parentId: Value(d.parentId),
        tier: Value(d.tier.name),
        title: Value(d.title.trim()),
        notes: Value(d.notes.trim()),
        category: Value(d.category?.name),
        priority: Value(d.priority),
        dueAt: Value(dueAt),
        estimatedMinutes: Value(d.estimatedMinutes),
        recurrence: Value(d.recurrence.name),
        intention: Value(_blankToNull(d.intention)),
        shareLevel: Value(d.shareLevel.name),
        remindAt: Value(d.remindAt),
        updatedAt: Value(_now()),
      ),
    );
    await _enqueue('quest', id, fields: fields);
  });

  /// Soft delete. Rewards already earned remain in the ledger.
  Future<void> delete(String id) => _db.transaction(() async {
    final now = _now();
    await (_db.update(
      _db.quests,
    )..where((q) => q.id.equals(id))).write(QuestsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    final children = await (_db.select(_db.quests)..where((q) => q.parentId.equals(id))).get();
    await (_db.update(
      _db.quests,
    )..where((q) => q.parentId.equals(id))).write(QuestsCompanion(parentId: const Value(null), updatedAt: Value(now)));
    await _enqueue('quest', id, fields: const ['deleted_at']);
    for (final child in children) {
      await _enqueue('quest', child.id, fields: const ['parent_id']);
    }
  });

  Future<void> addSubtask(String questId, String title) => _db.transaction(() async {
    final count = await (_db.select(_db.subtasks)..where((s) => s.questId.equals(questId))).get();
    final id = _uuid.v7();
    await _db
        .into(_db.subtasks)
        .insert(
          SubtasksCompanion.insert(
            id: id,
            questId: questId,
            title: title.trim(),
            position: Value(count.length),
            updatedAt: _now(),
          ),
        );
    await _enqueue('subtask', id);
  });

  Future<void> setSubtaskDone(String id, bool done) => _db.transaction(() async {
    await (_db.update(
      _db.subtasks,
    )..where((s) => s.id.equals(id))).write(SubtasksCompanion(done: Value(done), updatedAt: Value(_now())));
    await _enqueue('subtask', id, fields: const ['done']);
  });

  Future<void> deleteSubtask(String id) => _db.transaction(() async {
    final now = _now();
    await (_db.update(
      _db.subtasks,
    )..where((s) => s.id.equals(id))).write(SubtasksCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    await _enqueue('subtask', id, fields: const ['deleted_at']);
  });

  /// Queues a change for sync. [fields] are the server's names for what it
  /// changed; without them (a new row) the whole row goes up.
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

  static DateTime? _dateOnly(DateTime? d) => d == null ? null : DateTime(d.year, d.month, d.day);
  static String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}
