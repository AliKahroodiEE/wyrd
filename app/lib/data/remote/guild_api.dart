import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend.dart';

class Guild {
  const Guild({
    required this.id,
    required this.name,
    this.description = '',
    this.visibility = 'private',
    this.languageTag,
  });

  factory Guild.fromRow(Map<String, dynamic> r) => Guild(
    id: r['id'] as String,
    name: r['name'] as String? ?? '',
    description: r['description'] as String? ?? '',
    visibility: r['visibility'] as String? ?? 'private',
    languageTag: r['language_tag'] as String?,
  );

  final String id;
  final String name;
  final String description;
  final String visibility;
  final String? languageTag;
}

class GuildMember {
  const GuildMember({required this.userId, required this.role, required this.name, this.level, this.title});

  factory GuildMember.fromRow(Map<String, dynamic> r) => GuildMember(
    userId: r['user_id'] as String,
    role: r['role'] as String? ?? 'member',
    name: (r['character_name'] as String?)?.trim().isNotEmpty == true
        ? r['character_name'] as String
        : (r['display_name'] as String? ?? ''),
    level: (r['level'] as num?)?.toInt(),
    title: r['equipped_title'] as String?,
  );

  final String userId;
  final String role;
  final String name;
  final int? level;
  final String? title;

  bool get isOfficer => role == 'guild_master' || role == 'officer';
}

class FeedEvent {
  const FeedEvent({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.actorId,
    this.reactions = const {},
    this.myReactions = const {},
    this.comments = 0,
  });

  final String id;
  final String kind;
  final String? actorId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final Map<String, int> reactions;
  final Set<String> myReactions;
  final int comments;
}

class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.metric,
    required this.target,
    required this.progress,
    required this.endsAt,
    required this.status,
  });

  factory Challenge.fromRow(Map<String, dynamic> r) => Challenge(
    id: r['id'] as String,
    title: r['title'] as String? ?? '',
    metric: r['metric'] as String? ?? 'completions',
    target: (r['target'] as num?)?.toInt() ?? 1,
    progress: (r['progress'] as num?)?.toInt() ?? 0,
    endsAt: DateTime.parse(r['ends_at'] as String).toLocal(),
    status: r['status'] as String? ?? 'active',
  );

  final String id;
  final String title;
  final String metric;
  final int target;
  final int progress;
  final DateTime endsAt;
  final String status;

  double get fraction => target <= 0 ? 0 : (progress / target).clamp(0, 1);
}

class GuildComment {
  const GuildComment({required this.id, required this.body, required this.createdAt, this.authorId});
  final String id;
  final String body;
  final String? authorId;
  final DateTime createdAt;
}

/// Guild reads go through row-level security; writes go through the
/// server's SECURITY DEFINER functions so permissions and privacy
/// projection are enforced server-side (FR-6).
class GuildApi {
  GuildApi(this._c);
  final SupabaseClient _c;

  String get _uid => _c.auth.currentUser!.id;

  /// The caller's guilds via `my_guilds()`; members cannot read each
  /// other's membership preferences directly (column-level grants).
  Future<List<Guild>> myGuilds() async {
    final rows = await _c.rpc<List<dynamic>>('my_guilds');
    return [
      for (final r in rows) Guild.fromRow({...Map<String, dynamic>.from(r as Map), 'id': r['guild_id']}),
    ];
  }

  Future<Guild> guild(String id) async => Guild.fromRow(await _c.from('guilds').select().eq('id', id).single());

  Future<Guild> create({required String name, String description = '', String visibility = 'private'}) async =>
      Guild.fromRow(
        await _c.rpc<Map<String, dynamic>>(
          'create_guild',
          params: {'name': name, 'description': description, 'visibility': visibility},
        ),
      );

  Future<Guild> join(String code) async =>
      Guild.fromRow(await _c.rpc<Map<String, dynamic>>('join_guild_by_code', params: {'code': code.trim()}));

  Future<String> createInvite(String guildId) async {
    final r = await _c.rpc<Map<String, dynamic>>('create_invite', params: {'guild_id': guildId});
    return r['code'] as String;
  }

  Future<void> leave(String guildId) => _c.rpc<void>('leave_guild', params: {'guild_id': guildId});

  Future<List<GuildMember>> roster(String guildId) async {
    final rows = await _c.rpc<List<dynamic>>('guild_roster', params: {'guild_id': guildId});
    return [for (final r in rows) GuildMember.fromRow(Map<String, dynamic>.from(r as Map))];
  }

  Future<List<FeedEvent>> feed(String guildId) async {
    final events = await _c
        .from('feed_events')
        .select()
        .eq('guild_id', guildId)
        .isFilter('hidden_at', null)
        .order('created_at', ascending: false)
        .limit(50);
    final ids = [for (final e in events) e['id'] as String];
    if (ids.isEmpty) return const [];
    final reactions = await _c.from('reactions').select('event_id,user_id,kind').inFilter('event_id', ids);
    final comments = await _c
        .from('comments')
        .select('event_id')
        .inFilter('event_id', ids)
        .isFilter('deleted_at', null);
    return [
      for (final e in events)
        FeedEvent(
          id: e['id'] as String,
          kind: e['kind'] as String,
          actorId: e['actor_id'] as String?,
          payload: Map<String, dynamic>.from((e['payload'] as Map?) ?? const {}),
          createdAt: DateTime.parse(e['created_at'] as String).toLocal(),
          reactions: {
            for (final kind in const ['honour', 'steel', 'flame', 'laurel'])
              kind: reactions.where((r) => r['event_id'] == e['id'] && r['kind'] == kind).length,
          },
          myReactions: {
            for (final r in reactions)
              if (r['event_id'] == e['id'] && r['user_id'] == _uid) r['kind'] as String,
          },
          comments: comments.where((c) => c['event_id'] == e['id']).length,
        ),
    ];
  }

  Future<void> toggleReaction(String eventId, String kind, {required bool on}) =>
      _c.rpc<void>(on ? 'react' : 'unreact', params: {'event_id': eventId, 'kind': kind});

  Future<List<GuildComment>> comments(String eventId) async {
    final rows = await _c
        .from('comments')
        .select()
        .eq('event_id', eventId)
        .isFilter('deleted_at', null)
        .order('created_at');
    return [
      for (final r in rows)
        GuildComment(
          id: r['id'] as String,
          body: r['body'] as String? ?? '',
          authorId: r['author_id'] as String?,
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        ),
    ];
  }

  Future<void> addComment(String eventId, String body) =>
      _c.rpc<void>('add_comment', params: {'event_id': eventId, 'body': body.trim()});

  Future<List<Challenge>> challenges(String guildId) async {
    final rows = await _c.from('challenges').select().eq('guild_id', guildId).order('created_at', ascending: false);
    return [for (final r in rows) Challenge.fromRow(r)];
  }

  Future<void> createChallenge({
    required String guildId,
    required String title,
    required String metric,
    required int target,
    required int days,
    String? category,
  }) => _c.rpc<void>(
    'create_challenge',
    params: {
      'guild_id': guildId,
      'title': title,
      'metric': metric,
      'target': target,
      'ends_at': DateTime.now().add(Duration(days: days)).toUtc().toIso8601String(),
      'metric_category': ?category,
    },
  );

  Future<void> report(String eventId) =>
      _c.rpc<void>('report_content', params: {'target_type': 'feed_event', 'target_id': eventId, 'reason': 'other'});

  Future<void> block(String userId) => _c.rpc<void>('block_user', params: {'user_id': userId});

  /// Live "something changed" signal for a guild's hall (ADR-003: realtime
  /// triggers a refetch, it is never applied directly). Reactions, and
  /// comments being deleted or hidden, cannot signal by themselves (Realtime
  /// hides deletions from no one and updates a member can no longer see from
  /// everyone): each touches its feed event, which arrives here as an update.
  RealtimeChannel watchGuild(String guildId, void Function() onChange) {
    final channel = _c.channel('guild:$guildId');
    for (final table in const ['feed_events', 'comments', 'challenges']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'guild_id', value: guildId),
        callback: (_) => onChange(),
      );
    }
    return channel..subscribe();
  }
}

final guildApiProvider = Provider<GuildApi?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final user = ref.watch(currentUserProvider).value;
  return client == null || user == null ? null : GuildApi(client);
});

final myGuildsProvider = FutureProvider<List<Guild>>((ref) async {
  final api = ref.watch(guildApiProvider);
  return api == null ? const [] : api.myGuilds();
});
