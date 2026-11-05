import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart' show Characters;
import 'package:wyrd_engine/wyrd_engine.dart';

import '../db/database.dart';
import '../models.dart';
import '../remote/remote_api.dart';
import '../repositories/data_repository.dart';
import '../repositories/progression_repository.dart';

class SyncReport {
  const SyncReport({this.pushed = 0, this.rejected = 0, this.evaluated = 0, this.pulled = 0, this.settingsFailed = 0});
  final int pushed;
  final int rejected;
  final int evaluated;
  final int pulled;

  /// Settings groups that could not be sent this cycle (retried next time).
  final int settingsFailed;

  @override
  String toString() =>
      'SyncReport(pushed: $pushed, rejected: $rejected, evaluated: $evaluated, pulled: $pulled, '
      'settingsFailed: $settingsFailed)';
}

/// Ends a cycle whose sync was stopped (sign-out, another account, the
/// device being cleared): nothing more is written.
class SyncStopped implements Exception {
  const SyncStopped();

  @override
  String toString() => 'SyncStopped';
}

/// A group of account settings that syncs as a whole, in the form this
/// device sends ([current], sent with [send]).
///
/// With [table], [fromServer] and [apply], changes made on other devices are
/// taken over too. Pulled rows of [table] are turned into the same form and
/// merged key by key against what this device last sent or took over: keys
/// only the server changed are adopted, keys changed here stay and go up. A
/// device that never synced the group (new, or cleared) takes the server's
/// values as they are, so a new device does not overwrite an account's
/// settings with its defaults.
class SyncedSettings {
  const SyncedSettings({
    required this.key,
    required this.current,
    required this.send,
    this.table,
    this.fromServer,
    this.apply,
  });

  /// Where the value last sent or taken over is kept on this device.
  final String key;
  final Future<Map<String, Object?>> Function() current;
  final Future<void> Function(Map<String, Object?> value) send;

  /// The pulled entity that carries these settings, such as `profiles`.
  final String? table;

  /// The settings in a pulled row, or null when it holds nothing to take
  /// over (a profile no client has changed since sign-up).
  final Map<String, Object?>? Function(Map<String, Object?> row)? fromServer;

  /// Makes [value] (in the form of [current]) this device's settings.
  final Future<void> Function(Map<String, Object?> value)? apply;
}

/// Outbox push, authoritative evaluation and cursor pull (ADR-003).
///
/// Local rows stay the UI's source of truth. Pushes carry a fixed-width
/// hybrid logical clock derived from the mutation time so the server can
/// merge fields last-writer-wins; completions are insert-only; the
/// server's evaluation supersedes the provisional local one.
class SyncService {
  SyncService(this._db, this._api, this._progression, {Future<String?> Function()? clientModel})
    : _clientModel = clientModel; // ignore: prefer_initializing_formals

  /// Model name of the user's own AI provider, sent with proposals made
  /// on this device so the server can record it.
  final Future<String?> Function()? _clientModel;

  final AppDatabase _db;
  final RemoteApi _api;
  final ProgressionRepository _progression;
  static const _cursorKey = 'sync_cursor';
  static const _nodeKey = 'sync_node';
  static const _pendingEvalKey = 'sync_pending_evaluations';
  static const _droppedKey = 'sync_dropped';
  static const _ownerKey = 'sync_owner';
  static const _ownerEmailKey = 'sync_owner_email';

  bool _stopped = false;

  /// Ends this account's sync on this device: a cycle in progress stops at
  /// its next write and nothing is written afterwards, so a device being
  /// cleared or handed to another account is never refilled.
  void stop() => _stopped = true;

  bool get isStopped => _stopped;

  /// The account this device's data belongs to, or null (guest data only).
  Future<String?> owner() async => await _read(_ownerKey) as String?;

  /// That account's email, when it was known at sign-in.
  Future<String?> ownerEmail() async => await _read(_ownerEmailKey) as String?;

  /// Local work the server does not have yet: changes still to send, and
  /// completions still waiting for their authoritative evaluation (only the
  /// device that sent a completion asks for it).
  Future<int> unsyncedChanges() async =>
      (await _db.select(_db.outboxEntries).get()).length + (await _pendingEvaluations()).length;

  /// Ties this device's data and sync state to [userId] before it syncs.
  /// Data made as a guest (no owner yet) joins the account that signs in
  /// (A2); data another account left on the device is wiped first, so two
  /// accounts never mix on a shared device. Returns whether it wiped.
  Future<bool> claimFor(String userId, {String? email}) => _guarded(() async {
    final owner = await _read(_ownerKey);
    final other = owner != null && owner != userId;
    if (other) await DataRepository(_db).wipe();
    if (owner != userId) await _write(_ownerKey, userId);
    if (email != null && email.isNotEmpty) await _write(_ownerEmailKey, email);
    return other;
  });

  /// One full cycle. Local changes go up first, so a pull never meets a row
  /// this device still has to send. Then the pull takes over settings
  /// changed on other devices, before this device sends those groups, and
  /// last come the authoritative evaluations (after the AI opt-in is on the
  /// server). Settings groups that only go up ([SyncedSettings.table] null,
  /// such as language and time zone) are sent before everything else.
  /// Settings are best-effort: a group that fails is retried next cycle and
  /// never holds up the outbox.
  ///
  /// A pull that stopped early (see [_pull]) has not seen every setting yet,
  /// so the groups taken over from the server wait for a complete one; and
  /// evaluations wait until those groups, the AI opt-in among them, are on
  /// the server.
  Future<SyncReport> syncOnce({List<SyncedSettings> settings = const []}) async {
    var settingsFailed = 0;
    for (final s in settings.where((s) => s.table == null)) {
      if (!await _pushSettings(s)) settingsFailed++;
    }
    final push = await _push();
    final (pulled, complete) = await _pull(settings);
    var settled = complete;
    if (complete) {
      for (final s in settings.where((s) => s.table != null)) {
        if (!await _pushSettings(s)) {
          settingsFailed++;
          settled = false;
        }
      }
    }
    final evaluated = settled ? await _evaluatePending() : 0;
    return SyncReport(
      pushed: push.$1,
      rejected: push.$2,
      evaluated: evaluated,
      pulled: pulled,
      settingsFailed: settingsFailed,
    );
  }

  /// Ends a stopped cycle before its next network call.
  void _checkStopped() {
    if (_stopped) throw const SyncStopped();
  }

  // ----------------------------------------------------------------- push

  Future<(int, int)> _push() async {
    var pushed = 0;
    var rejected = 0;
    final node = await _nodeId();
    // Entries the server asked to retry stay for the next cycle; the rest of
    // the outbox still goes up now.
    final waiting = <int>{};
    while (true) {
      final batch =
          await (_db.select(_db.outboxEntries)
                ..where((o) => o.id.isNotIn(waiting))
                ..orderBy([(o) => OrderingTerm.asc(o.id)])
                ..limit(100))
              .get();
      if (batch.isEmpty) break;
      final changes = <Map<String, Object?>>[];
      final rows = <OutboxRow>[];
      for (final o in batch) {
        final change = await _envelope(o, node);
        if (change == null) {
          await _guarded(() async {
            await (_db.delete(_db.outboxEntries)..where((x) => x.id.equals(o.id))).go();
            await _settleDropped(o, taken: false);
          });
          continue;
        }
        changes.add(change);
        rows.add(o);
      }
      if (changes.isEmpty) continue;
      _checkStopped();
      final results = await _api.push(changes);
      // The server applies each change on its own, so every result counts:
      // only the ones it asked to retry stay in the outbox.
      await _guarded(() async {
        final completionIds = <String>[];
        for (var i = 0; i < changes.length; i++) {
          final c = changes[i];
          final o = rows[i];
          final r = i < results.length ? results[i] : const <String, Object?>{};
          final status = r['status'];
          if (status == 'applied' || status == 'ignored') {
            pushed++;
            await (_db.delete(_db.outboxEntries)..where((x) => x.id.equals(o.id))).go();
            await _settleDropped(o, taken: status == 'applied');
            if (c['entity'] == 'completion' && c['op'] == 'insert') completionIds.add(c['id']! as String);
          } else if (r['retryable'] == true || status == null) {
            await (_db.update(
              _db.outboxEntries,
            )..where((x) => x.id.equals(o.id))).write(OutboxEntriesCompanion(attempts: Value(o.attempts + 1)));
            waiting.add(o.id);
          } else {
            rejected++;
            await (_db.delete(_db.outboxEntries)..where((x) => x.id.equals(o.id))).go();
            await _settleDropped(o, taken: false);
          }
        }
        await _addPendingEvaluations(completionIds);
      });
    }
    return (pushed, rejected);
  }

  /// A change of this device for a row that a pull dropped (see [_pull]) is
  /// done with. If the server took it ([taken]), the row has a new change_id
  /// and comes down with the next pull. If the server kept its own version
  /// ('ignored', or a refusal that is final), that version gets no new
  /// change_id, so once nothing else waits to go up for the row the cursor
  /// goes back to just before it and the next pull fetches it again.
  Future<void> _settleDropped(OutboxRow o, {required bool taken}) async {
    final dropped = await _droppedRows();
    final key = '${o.entity}:${o.entityId}';
    final changeId = dropped.remove(key);
    if (changeId == null) return;
    if (!taken) {
      if (await _pendingAttempts(o.entity, o.entityId) != null) return; // the last one to settle decides
      final cursor = (await _read(_cursorKey) as num?)?.toInt() ?? 0;
      if (changeId - 1 < cursor) await _write(_cursorKey, changeId - 1);
    }
    await _write(_droppedKey, dropped);
  }

  /// Rows a pull dropped while their change waited to go up:
  /// `{'quest:<id>': lowest change_id dropped}`.
  Future<Map<String, int>> _droppedRows() async {
    final v = await _read(_droppedKey);
    return {
      if (v is Map)
        for (final e in v.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
    };
  }

  Future<Map<String, Object?>?> _envelope(OutboxRow o, String node) async {
    final hlc = hlcFor(o.createdAt, o.id, node);
    switch (o.entity) {
      case 'quest':
        final q = await (_db.select(_db.quests)..where((x) => x.id.equals(o.entityId))).getSingleOrNull();
        if (q == null) return null;
        return {'entity': 'quest', 'op': 'upsert', 'id': q.id, 'hlc': hlc, 'payload': questPayload(q)};
      case 'subtask':
        final s = await (_db.select(_db.subtasks)..where((x) => x.id.equals(o.entityId))).getSingleOrNull();
        if (s == null) return null;
        return {
          'entity': 'subtask',
          'op': 'upsert',
          'id': s.id,
          'hlc': hlc,
          'payload': {
            'quest_id': s.questId,
            'title': _fitText(s.title, 200),
            'done': s.done,
            'position': s.position,
            'deleted_at': s.deletedAt?.toUtc().toIso8601String(),
          },
        };
      case 'completion':
        final c = await (_db.select(_db.completions)..where((x) => x.id.equals(o.entityId))).getSingleOrNull();
        if (c == null) return null;
        return {
          'entity': 'completion',
          'op': 'insert',
          'id': c.id,
          'hlc': hlc,
          'payload': {
            'quest_id': c.questId,
            'occurrence_day': c.occurrenceDay,
            'completed_at': c.completedAt.toUtc().toIso8601String(),
            // At most a day each (completions_declared_minutes and
            // completions_tracked_minutes); a timer left running is longer.
            'declared_minutes': c.declaredMinutes?.clamp(0, 1440),
            'tracked_minutes': c.trackedMinutes?.clamp(0, 1440),
          },
        };
      case 'completion_undo':
        return {
          'entity': 'completion',
          'op': 'undo',
          'id': o.entityId,
          'hlc': hlc,
          'payload': {'undone_at': o.createdAt.toUtc().toIso8601String()},
        };
    }
    return null;
  }

  /// Server representation of a local quest row, within the checks of
  /// public.quests (…_core_schema.sql): a value outside them would be
  /// refused for good, and the quest, its subtasks and completions would
  /// never reach the server. Texts are cut to the server's length, an
  /// estimate outside 1 to 1440 minutes goes up as none, priority stays
  /// within 0 to 3, tier, category and status are ones the server knows,
  /// and a quest is never its own parent.
  static Map<String, Object?> questPayload(QuestRow q) {
    final anchor = q.dueAt ?? q.createdAt;
    final reminder = q.remindAt == null
        ? null
        : DateTime(anchor.year, anchor.month, anchor.day, q.remindAt! ~/ 60, q.remindAt! % 60);
    final estimate = q.estimatedMinutes;
    final intention = q.intention;
    return {
      'parent_id': q.parentId == q.id ? null : q.parentId,
      'tier': _tiers.contains(q.tier) ? q.tier : 'daily',
      'title': _fitText(q.title, 200),
      'notes': _fitText(q.notes, 4000),
      'category': _categories.contains(q.category) ? q.category : null,
      'priority': q.priority.clamp(0, 3),
      'status': _statuses.contains(q.status) ? q.status : 'active',
      'due_at': q.dueAt?.toUtc().toIso8601String(),
      'estimated_minutes': estimate != null && estimate >= 1 && estimate <= 1440 ? estimate : null,
      'recurrence': q.recurrence == 'none' ? null : {'kind': q.recurrence},
      'intention': intention == null ? null : _fitText(intention, 280),
      'share_level': _shareToServer[q.shareLevel] ?? 'private',
      'reminder_at': reminder?.toUtc().toIso8601String(),
      'deleted_at': q.deletedAt?.toUtc().toIso8601String(),
      'created_at': q.createdAt.toUtc().toIso8601String(),
    };
  }

  static const _shareToServer = {
    'full': 'full',
    'titleOnly': 'title_only',
    'completionOnly': 'completion_only',
    'private': 'private',
  };

  // What public.quests takes: the quest_tier and quest_category types and
  // the quests_status check.
  static const _tiers = {'daily', 'contract', 'objective'};
  static const _categories = {
    'study',
    'work',
    'fitness',
    'health',
    'creative',
    'social',
    'chores',
    'admin',
    'mindfulness',
    'reading',
    'other',
  };
  static const _statuses = {'active', 'completed', 'paused', 'archived'};

  /// [text] as a server text column of at most [max] characters takes it.
  /// The server counts code points (char_length); the cut falls between
  /// characters as people see them, never inside an emoji or between a
  /// letter and its marks. Only a first character longer than [max] on its
  /// own (a letter under hundreds of marks) is cut inside, rather than
  /// leaving nothing. NUL is left out: no jsonb value can hold it, so it
  /// would fail the whole push.
  static String _fitText(String text, int max) {
    final clean = text.contains('\u0000') ? text.replaceAll('\u0000', '') : text;
    if (clean.runes.length <= max) return clean;
    var points = 0;
    var end = 0;
    for (final c in Characters(clean)) {
      final n = c.runes.length;
      if (points + n > max) break;
      points += n;
      end += c.length;
    }
    return end == 0 ? String.fromCharCodes(clean.runes.take(max)) : clean.substring(0, end);
  }

  /// Fixed-width, lexicographically ordered HLC:
  /// `<ISO-8601 UTC millis>-<4 hex counter>-<node>`.
  static String hlcFor(DateTime at, int counter, String node) {
    final iso = DateTime.fromMillisecondsSinceEpoch(at.millisecondsSinceEpoch, isUtc: true).toIso8601String();
    return '$iso-${(counter & 0xffff).toRadixString(16).padLeft(4, '0')}-$node';
  }

  // ------------------------------------------------------------- settings

  /// Sends [s] when it differs from what this device last sent or took
  /// over. Returns false when that failed; it is retried next cycle.
  Future<bool> _pushSettings(SyncedSettings s) async {
    try {
      _checkStopped();
      final value = await s.current();
      if (_canon(await _read(s.key)) == _canon(value)) return true;
      _checkStopped();
      await s.send(value);
      await _guarded(() => _write(s.key, value));
      return true;
    } on Object {
      // Whatever failed, a stopped cycle ends here rather than carrying on.
      _checkStopped();
      return false;
    }
  }

  /// Takes over what another device changed in [s] (see [SyncedSettings]).
  /// Runs inside the pull's transaction.
  Future<void> _adopt(SyncedSettings s, Map<String, Object?> row) async {
    final fromServer = s.fromServer;
    final apply = s.apply;
    if (fromServer == null || apply == null) return;
    final server = fromServer(row);
    if (server == null) return;
    final base = await _read(s.key);
    if (base is Map && _canon(base) == _canon(server)) return; // what this device sent or took over
    final local = await s.current();
    final merged = {...local};
    for (final k in server.keys) {
      final changedThere = base is! Map || _canon(server[k]) != _canon(base[k]);
      final changedHere = base is Map && _canon(local[k]) != _canon(base[k]);
      if (changedThere && !changedHere) merged[k] = server[k];
    }
    if (_canon(merged) != _canon(local)) await apply(merged);
    await _write(s.key, server);
  }

  /// JSON with map keys sorted, so equal settings compare equal whatever
  /// order their keys arrived in.
  static String _canon(Object? value) => jsonEncode(_sorted(value));

  static Object? _sorted(Object? value) => switch (value) {
    final Map<Object?, Object?> map => {for (final k in map.keys.map((k) => '$k').toList()..sort()) k: _sorted(map[k])},
    final List<Object?> list => [for (final e in list) _sorted(e)],
    _ => value,
  };

  // ------------------------------------------------------------- evaluate

  /// Asks the server to evaluate the completions this device sent. A
  /// completion that was undone (here, or on another device: the pull
  /// before this has applied that) or that is gone needs no evaluation and
  /// leaves the list without asking; so does one the server reports undone.
  /// Anything else that fails is asked again next cycle.
  Future<int> _evaluatePending() async {
    final pending = await _pendingEvaluations();
    var done = 0;
    final remaining = <String>[];
    for (final id in pending) {
      _checkStopped();
      try {
        final completion = await (_db.select(_db.completions)..where((c) => c.id.equals(id))).getSingleOrNull();
        if (completion == null || completion.state == 'undone') continue;
        // Proposals made with the user's own AI travel with the request;
        // the server validates and bounds them (it never sees the key).
        final local = await (_db.select(_db.evaluations)..where((e) => e.completionId.equals(id))).getSingleOrNull();
        Map<String, Object?>? clientProposal;
        if (local != null && local.source == 'ai') {
          clientProposal = Map<String, Object?>.from(jsonDecode(local.proposalJson) as Map)..remove('source');
        }
        final res = await _api.evaluate(
          id,
          clientProposal: clientProposal,
          clientModel: clientProposal == null ? null : await _clientModel?.call(),
        );
        if (res?['status'] == 'undone') continue; // the next pull brings the undo, if it has not yet
        final result = res?['result'];
        final proposal = res?['proposal'];
        if (result is Map && proposal is Map) {
          await _guarded(
            () => _progression.reconcile(
              id,
              EvaluationProposal.fromJson(Map<String, Object?>.from(proposal)),
              decodeResult(jsonEncode(result)),
            ),
          );
          done++;
        } else {
          remaining.add(id);
        }
      } on SyncStopped {
        rethrow;
      } on Object {
        remaining.add(id);
      }
    }
    await _guarded(() => _write(_pendingEvalKey, remaining));
    return done;
  }

  Future<List<String>> _pendingEvaluations() async {
    final v = await _read(_pendingEvalKey);
    return v is List ? v.whereType<String>().toList() : <String>[];
  }

  Future<void> _addPendingEvaluations(List<String> ids) async {
    if (ids.isEmpty) return;
    await _write(_pendingEvalKey, {...await _pendingEvaluations(), ...ids}.toList());
  }

  // ----------------------------------------------------------------- pull

  /// Applies the server's changes page by page; each page and its cursor
  /// land in one transaction. Returns how many rows were applied, and
  /// whether the pull reached the end.
  ///
  /// A row skipped because this device still has a change to send for it
  /// (the server asked to retry it) holds the cursor just before it, and the
  /// pull ends there: the next cycle sends the change first and then gets
  /// the row again, so the server's winning version is never lost. A change
  /// the server has refused [_holdAttempts] times no longer holds anything
  /// up: its row is dropped and the cursor moves on, but the row is noted
  /// in the same transaction, so it is fetched again if that change ends
  /// without the server taking it ([_settleDropped]).
  Future<(int, bool)> _pull(List<SyncedSettings> settings) async {
    var cursor = (await _read(_cursorKey) as num?)?.toInt() ?? 0;
    var applied = 0;
    while (true) {
      _checkStopped();
      final res = await _api.pull(cursor);
      var next = (res['cursor'] as num?)?.toInt() ?? cursor;
      var held = false;
      applied += await _guarded(() async {
        final changes = (res['changes'] as Map?) ?? const {};
        final left = _Left();
        var n = await _applyQuests((changes['quests'] as List?) ?? const [], left);
        n += await _applySubtasks((changes['subtasks'] as List?) ?? const [], left);
        final proposals = <String, Map<String, Object?>>{
          for (final e in ((changes['evaluations'] as List?) ?? const []).whereType<Map<Object?, Object?>>())
            if (e['completion_id'] is String && e['proposal'] is Map)
              e['completion_id']! as String: Map<String, Object?>.from(e['proposal']! as Map),
        };
        n += await _applyCompletions((changes['completions'] as List?) ?? const [], proposals);
        for (final s in settings) {
          final table = s.table;
          if (table == null) continue;
          for (final row in ((changes[table] as List?) ?? const []).whereType<Map<Object?, Object?>>()) {
            await _adopt(s, Map<String, Object?>.from(row));
          }
        }
        if (left.held.isNotEmpty) {
          final hold = left.held.reduce(min) - 1;
          if (hold < next) {
            next = hold < cursor ? cursor : hold;
            held = true;
          }
        }
        if (left.dropped.isNotEmpty) await _noteDropped(left.dropped);
        await _write(_cursorKey, next);
        return n;
      });
      cursor = next;
      if (held) return (applied, false);
      if (res['has_more'] != true) break;
    }
    return (applied, true);
  }

  /// Retries after which a waiting change stops holding the pull cursor.
  static const _holdAttempts = 3;

  Future<int> _applyQuests(List<Object?> rows, _Left left) async {
    var n = 0;
    for (final raw in rows.whereType<Map<Object?, Object?>>()) {
      final r = Map<String, Object?>.from(raw);
      final id = r['id'] as String?;
      if (id == null) continue;
      final attempts = await _pendingAttempts('quest', id);
      if (attempts != null) {
        _leave('quest', id, r, attempts, left);
        continue;
      }
      DateTime? ts(String k) => r[k] is String ? DateTime.parse(r[k]! as String).toLocal() : null;
      final due = ts('due_at');
      final reminder = ts('reminder_at');
      final recurrence = r['recurrence'] is Map ? (r['recurrence']! as Map)['kind'] as String? : null;
      await _db
          .into(_db.quests)
          .insertOnConflictUpdate(
            QuestsCompanion.insert(
              id: id,
              parentId: Value(r['parent_id'] as String?),
              tier: r['tier'] as String? ?? 'daily',
              title: r['title'] as String? ?? '',
              notes: Value(r['notes'] as String? ?? ''),
              category: Value(r['category'] as String?),
              priority: Value((r['priority'] as num?)?.toInt() ?? 1),
              status: Value(r['status'] as String? ?? 'active'),
              dueAt: Value(due == null ? null : DateTime(due.year, due.month, due.day)),
              estimatedMinutes: Value((r['estimated_minutes'] as num?)?.toInt()),
              recurrence: Value(recurrence ?? 'none'),
              intention: Value(r['intention'] as String?),
              shareLevel: Value(_shareFromServer[r['share_level']] ?? 'private'),
              remindAt: Value(reminder == null ? null : reminder.hour * 60 + reminder.minute),
              createdAt: ts('created_at') ?? DateTime.now(),
              updatedAt: ts('updated_at') ?? DateTime.now(),
              deletedAt: Value(ts('deleted_at')),
            ),
          );
      n++;
    }
    return n;
  }

  static const _shareFromServer = {
    'full': 'full',
    'title_only': 'titleOnly',
    'completion_only': 'completionOnly',
    'private': 'private',
  };

  Future<int> _applySubtasks(List<Object?> rows, _Left left) async {
    var n = 0;
    for (final raw in rows.whereType<Map<Object?, Object?>>()) {
      final r = Map<String, Object?>.from(raw);
      final id = r['id'] as String?;
      final questId = r['quest_id'] as String?;
      if (id == null || questId == null) continue;
      final attempts = await _pendingAttempts('subtask', id);
      if (attempts != null) {
        _leave('subtask', id, r, attempts, left);
        continue;
      }
      final quest = await (_db.select(_db.quests)..where((q) => q.id.equals(questId))).getSingleOrNull();
      if (quest == null) continue;
      await _db
          .into(_db.subtasks)
          .insertOnConflictUpdate(
            SubtasksCompanion.insert(
              id: id,
              questId: questId,
              title: r['title'] as String? ?? '',
              done: Value(r['done'] == true),
              position: Value((r['position'] as num?)?.toInt() ?? 0),
              updatedAt: DateTime.tryParse(r['updated_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
              deletedAt: Value(DateTime.tryParse(r['deleted_at'] as String? ?? '')?.toLocal()),
            ),
          );
      n++;
    }
    return n;
  }

  Future<int> _applyCompletions(List<Object?> rows, Map<String, Map<String, Object?>> proposals) async {
    var n = 0;
    for (final raw in rows.whereType<Map<Object?, Object?>>()) {
      final r = Map<String, Object?>.from(raw);
      final id = r['id'] as String?;
      final questId = r['quest_id'] as String?;
      if (id == null || questId == null) continue;
      final quest = await (_db.select(_db.quests)..where((q) => q.id.equals(questId))).getSingleOrNull();
      if (quest == null) continue;
      final undone = r['undone_at'] != null || r['state'] == 'undone';
      final completedAt = DateTime.tryParse(r['completed_at'] as String? ?? '')?.toLocal() ?? DateTime.now();
      final existing = await (_db.select(_db.completions)..where((c) => c.id.equals(id))).getSingleOrNull();
      if (existing == null) {
        final occurrence = r['occurrence_day'] as String? ?? dayKey(completedAt);
        await _db
            .into(_db.completions)
            .insert(
              CompletionsCompanion.insert(
                id: id,
                questId: questId,
                occurrenceDay: occurrence,
                localDay: r['local_day'] as String? ?? occurrence,
                completedAt: completedAt,
                declaredMinutes: Value((r['declared_minutes'] as num?)?.toInt()),
                trackedMinutes: Value((r['tracked_minutes'] as num?)?.toInt()),
                state: Value(undone ? 'undone' : 'active'),
                createdAt: completedAt,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        n++;
      } else if (undone && existing.state != 'undone') {
        await (_db.update(
          _db.completions,
        )..where((c) => c.id.equals(id))).write(const CompletionsCompanion(state: Value('undone')));
        await (_db.update(
          _db.ledgerEntries,
        )..where((l) => l.completionId.equals(id))).write(const LedgerEntriesCompanion(superseded: Value(true)));
        n++;
      }
      if (!undone && r['result'] is Map) {
        if (await _applyResult(id, Map<String, Object?>.from(r['result']! as Map), proposals[id], r)) n++;
      }
    }
    return n;
  }

  /// Applies a server-confirmed result: supersedes a provisional local one,
  /// or records it for a completion made on another device.
  Future<bool> _applyResult(
    String completionId,
    Map<String, Object?> result,
    Map<String, Object?>? proposal,
    Map<String, Object?> completionRow,
  ) async {
    final completion = await (_db.select(_db.completions)..where((c) => c.id.equals(completionId))).getSingleOrNull();
    if (completion == null || completion.state == 'undone') return false;
    final local = await (_db.select(
      _db.evaluations,
    )..where((e) => e.completionId.equals(completionId))).getSingleOrNull();
    if (local != null && !local.provisional) return false;
    final parsedResult = decodeResult(jsonEncode(result));
    final parsedProposal = proposal != null
        ? EvaluationProposal.fromJson(proposal)
        : EvaluationProposal(
            category: QuestCategory.parse(completionRow['category']),
            similarityKey: parsedResult.similarityKey,
            difficulty: 3,
            estimatedMinutes: parsedResult.effectiveMinutes.clamp(1, 600),
            attributes: const [],
            source: parsedResult.source,
          );
    if (local == null) {
      await _progression.importConfirmed(completion, parsedProposal, parsedResult);
    } else {
      await _progression.reconcile(completionId, parsedProposal, parsedResult);
    }
    return true;
  }

  /// Leaves a pulled row alone while a change of this device for it waits
  /// to go up: the row holds the cursor, or after [_holdAttempts] refusals
  /// it is dropped and noted (see [_pull]). Rows without a change_id can do
  /// neither.
  static void _leave(String entity, String id, Map<String, Object?> row, int attempts, _Left left) {
    final changeId = row['change_id'];
    if (changeId is! num) return;
    if (attempts < _holdAttempts) {
      left.held.add(changeId.toInt());
    } else {
      final known = left.dropped['$entity:$id'];
      left.dropped['$entity:$id'] = known == null ? changeId.toInt() : min(known, changeId.toInt());
    }
  }

  /// Notes rows a pull dropped, keeping the lowest change_id of each.
  Future<void> _noteDropped(Map<String, int> rows) async {
    final dropped = await _droppedRows();
    for (final MapEntry(:key, :value) in rows.entries) {
      final known = dropped[key];
      dropped[key] = known == null ? value : min(known, value);
    }
    await _write(_droppedKey, dropped);
  }

  /// How often the server already asked to retry this device's waiting
  /// change for a row, or null when there is none.
  Future<int?> _pendingAttempts(String entity, String id) async {
    final waiting = await (_db.select(
      _db.outboxEntries,
    )..where((o) => o.entity.equals(entity) & o.entityId.equals(id))).get();
    return waiting.isEmpty ? null : waiting.map((o) => o.attempts).reduce(min);
  }

  // ------------------------------------------------------------ key-value

  Future<String> _nodeId() async {
    final v = await _read(_nodeKey);
    if (v is String && v.length == 8) return v;
    final r = Random.secure();
    final node = List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
    await _guarded(() => _write(_nodeKey, node));
    return node;
  }

  /// Runs [writes] in one transaction unless sync was stopped. Transactions
  /// run one at a time, so a device being cleared waits for one already
  /// running, and every later one sees the stop.
  Future<T> _guarded<T>(Future<T> Function() writes) {
    if (_stopped) return Future<T>.error(const SyncStopped());
    return _db.transaction(() async {
      if (_stopped) throw const SyncStopped();
      return writes();
    });
  }

  Future<Object?> _read(String key) async {
    final row = await (_db.select(_db.keyValues)..where((k) => k.key.equals(key))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.value);
  }

  Future<void> _write(String key, Object? value) =>
      _db.into(_db.keyValues).insertOnConflictUpdate(KeyValuesCompanion.insert(key: key, value: jsonEncode(value)));
}

/// Pulled rows a page leaves alone because this device still has a change
/// to send for them (see [SyncService._pull]).
class _Left {
  /// change_ids of the rows that hold the cursor.
  final held = <int>[];

  /// Rows dropped after [SyncService._holdAttempts] refusals, by
  /// `entity:id`, with the change_id they came with.
  final dropped = <String, int>{};
}
