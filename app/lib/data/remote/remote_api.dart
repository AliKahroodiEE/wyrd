import 'package:supabase_flutter/supabase_flutter.dart';

/// Server operations used by the sync engine; an interface so the engine
/// can be tested without a network.
abstract class RemoteApi {
  /// Applies outbox changes; returns one result per change
  /// (`{id, status: applied|ignored|rejected, retryable?}`).
  Future<List<Map<String, Object?>>> push(List<Map<String, Object?>> changes);

  /// Rows changed after [cursor]: `{cursor, has_more, changes: {table: [rows]}}`.
  /// [maxRows] asks for smaller pages than the server's default.
  Future<Map<String, Object?>> pull(int cursor, {int? maxRows});

  /// Authoritative evaluation: `{status, result, proposal, source, …}`, or
  /// null when the server could not evaluate yet (retried on next sync).
  /// `{status: 'undone'}` is final: the completion was undone on the server
  /// and will never be evaluated. Whether AI is used follows the synced
  /// profile setting.
  Future<Map<String, Object?>?> evaluate(
    String completionId, {
    Map<String, Object?>? clientProposal,
    String? clientModel,
  });

  /// Updates the caller's server profile (language, AI language and
  /// opt-in, time zone, calendar, week start, weekly target, motivation).
  Future<void> updateProfile(Map<String, Object?> fields);

  /// Mirrors the notification switches and quiet hours to the server, which
  /// decides about pushes: `{categories, quiet_hours_start, quiet_hours_end}`.
  Future<void> updateNotificationPrefs(Map<String, Object?> prefs);
}

class SupabaseRemoteApi implements RemoteApi {
  SupabaseRemoteApi(this._client);

  final SupabaseClient _client;

  /// A connection that dies silently never answers, and the sync cycle
  /// waiting for it would hold up every later one until the app restarts.
  /// Generous, for slow links: sending a change again is harmless.
  static const _patience = Duration(seconds: 60);

  @override
  Future<List<Map<String, Object?>>> push(List<Map<String, Object?>> changes) async {
    final res = await _client.rpc<Map<String, dynamic>>('sync_push', params: {'changes': changes}).timeout(_patience);
    return [for (final r in (res['results'] as List? ?? const [])) Map<String, Object?>.from(r as Map)];
  }

  @override
  Future<Map<String, Object?>> pull(int cursor, {int? maxRows}) async {
    final res = await _client
        .rpc<Map<String, dynamic>>('sync_pull', params: {'cursor': cursor, 'max_rows': ?maxRows})
        .timeout(_patience);
    return Map<String, Object?>.from(res);
  }

  @override
  Future<Map<String, Object?>?> evaluate(
    String completionId, {
    Map<String, Object?>? clientProposal,
    String? clientModel,
  }) async {
    final FunctionResponse res;
    try {
      res = await _client.functions
          .invoke(
            'evaluate-completion',
            body: {'completion_id': completionId, 'client_proposal': ?clientProposal, 'client_model': ?clientModel},
          )
          .timeout(_patience);
    } on FunctionException catch (e) {
      // evaluate-completion answers 409 completion_undone for a completion
      // that is no longer active, and no retry changes that. Every other
      // failure, its 409 busy among them, is retried next sync.
      final details = e.details;
      if (e.status == 409 && details is Map && details['error'] == 'completion_undone') return {'status': 'undone'};
      rethrow;
    }
    final data = res.data;
    return data is Map ? Map<String, Object?>.from(data) : null;
  }

  @override
  Future<void> updateProfile(Map<String, Object?> fields) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client.from('profiles').update(fields).eq('id', uid).timeout(_patience);
  }

  @override
  Future<void> updateNotificationPrefs(Map<String, Object?> prefs) =>
      _client.rpc<void>('set_notification_prefs', params: prefs).timeout(_patience);
}
