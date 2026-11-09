import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wyrd_engine/wyrd_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, RealtimeChannel;

import '../../app/providers.dart';
import '../../core/format/bidi.dart';
import '../../data/remote/backend.dart';
import '../../data/remote/guild_api.dart';
import '../../design/components/progress.dart';
import '../../design/components/states.dart';
import '../../design/sigils.dart';
import '../../design/tokens.dart';
import '../../l10n/content.dart';
import '../../l10n/generated/app_localizations.dart';

/// A guild's hall: activity feed, collective challenges and members.
/// Realtime changes trigger a refetch (never applied directly).
class GuildHallScreen extends ConsumerStatefulWidget {
  const GuildHallScreen({super.key, required this.guildId});
  final String guildId;

  @override
  ConsumerState<GuildHallScreen> createState() => _GuildHallScreenState();
}

class _GuildHallScreenState extends ConsumerState<GuildHallScreen> {
  Guild? _guild;
  List<GuildMember> _members = const [];
  List<FeedEvent> _feed = const [];
  List<Challenge> _challenges = const [];
  bool _loading = true;
  bool _failed = false;
  RealtimeChannel? _channel;
  Timer? _debounce;

  GuildApi? get _api => ref.read(guildApiProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _channel = _api?.watchGuild(widget.guildId, () {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () => unawaited(_load()));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_channel?.unsubscribe());
    super.dispose();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) return;
    try {
      final results = await Future.wait([
        api.guild(widget.guildId),
        api.roster(widget.guildId),
        api.feed(widget.guildId),
        api.challenges(widget.guildId),
      ]);
      if (!mounted) return;
      setState(() {
        _guild = results[0] as Guild;
        _members = results[1] as List<GuildMember>;
        _feed = results[2] as List<FeedEvent>;
        _challenges = results[3] as List<Challenge>;
        _loading = false;
        _failed = false;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  String _name(String? userId) {
    if (userId == null) return context.l10n.formerMember;
    for (final m in _members) {
      if (m.userId == userId) return m.name;
    }
    return context.l10n.formerMember;
  }

  bool get _isOfficer {
    final uid = ref.read(currentUserProvider).value?.id;
    return _members.any((m) => m.userId == uid && m.isOfficer);
  }

  Future<void> _invite() async {
    final l10n = context.l10n;
    try {
      final code = await _api!.createInvite(widget.guildId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l10n.shareInvite),
          content: SelectableText(code, style: Theme.of(c).textTheme.headlineSmall, textDirection: TextDirection.ltr),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (c.mounted) Navigator.pop(c);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.copied)));
                }
              },
              child: Text(l10n.actionCopy),
            ),
            FilledButton(onPressed: () => Navigator.pop(c), child: Text(l10n.actionDone)),
          ],
        ),
      );
    } on Object {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    }
  }

  Future<void> _leave() async {
    await _api?.leave(widget.guildId);
    ref.invalidate(myGuildsProvider);
    if (!mounted) return;
    context.canPop() ? context.pop() : context.go('/guilds');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final f = ref.fmt(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: _guild == null ? null : UserText(_guild!.name, style: Theme.of(context).textTheme.titleLarge),
          actions: [
            IconButton(tooltip: l10n.shareInvite, icon: const Icon(Icons.person_add_alt), onPressed: _invite),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'leave' ? _leave() : null,
              itemBuilder: (_) => [PopupMenuItem(value: 'leave', child: Text(l10n.leaveGuild))],
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.guildFeed),
              Tab(text: l10n.guildChallenges),
              Tab(text: l10n.memberCount(_members.length, f.number(_members.length))),
            ],
          ),
        ),
        floatingActionButton: _isOfficer
            ? FloatingActionButton.extended(
                onPressed: _newChallenge,
                icon: const Icon(Icons.flag_outlined),
                label: Text(l10n.newChallenge),
              )
            : null,
        body: _loading
            ? const LoadingPanels()
            : _failed
            ? Padding(
                padding: const EdgeInsetsDirectional.all(AppSpace.lg),
                child: ErrorState(message: l10n.errorGeneric, retryLabel: l10n.actionRetry, onRetry: _load),
              )
            : TabBarView(children: [_feedView(), _challengesView(), _membersView()]),
      ),
    );
  }

  Widget _centered(Widget child) => Align(
    alignment: AlignmentDirectional.topCenter,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: child),
  );

  Widget _feedView() {
    final l10n = context.l10n;
    if (_feed.isEmpty) {
      return Center(
        child: EmptyState(message: l10n.feedEmpty, icon: Icons.forum_outlined),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _centered(
        ListView.separated(
          padding: const EdgeInsetsDirectional.all(AppSpace.lg),
          itemCount: _feed.length,
          separatorBuilder: (_, _) => const Divider(height: AppSpace.xl),
          itemBuilder: (_, i) => _FeedItem(
            event: _feed[i],
            actor: _name(_feed[i].actorId),
            onReact: (kind, on) async {
              try {
                await _api?.toggleReaction(_feed[i].id, kind, on: on);
              } on Object catch (e) {
                if (mounted) {
                  final message = guildErrorMessage(l10n, e, GuildAction.react);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                }
              }
              await _load();
            },
            onComments: () => _openComments(_feed[i]),
            onReport: () async {
              await _api?.report(_feed[i].id);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.reportSent)));
            },
            onBlock: _feed[i].actorId == null
                ? null
                : () async {
                    await _api?.block(_feed[i].actorId!);
                    await _load();
                  },
          ),
        ),
      ),
    );
  }

  Future<void> _openComments(FeedEvent e) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CommentsSheet(eventId: e.id, nameOf: _name),
    );
    await _load();
  }

  Widget _challengesView() {
    final l10n = context.l10n;
    final f = ref.fmt(context);
    final text = Theme.of(context).textTheme;
    if (_challenges.isEmpty) {
      return Center(
        child: EmptyState(message: l10n.challengesEmpty, icon: Icons.flag_outlined),
      );
    }
    return _centered(
      ListView.separated(
        padding: const EdgeInsetsDirectional.all(AppSpace.lg),
        itemCount: _challenges.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpace.lg),
        itemBuilder: (_, i) {
          final c = _challenges[i];
          final value = c.metric == 'minutes_in_category' ? f.duration(c.progress) : f.number(c.progress);
          final target = c.metric == 'minutes_in_category' ? f.duration(c.target) : f.number(c.target);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UserText(c.title, style: text.titleMedium),
              const SizedBox(height: AppSpace.sm),
              XpBar(fraction: c.fraction, height: 8),
              const SizedBox(height: AppSpace.xs),
              Row(
                children: [
                  Expanded(child: Text(l10n.challengeProgress(value, target), style: text.bodySmall)),
                  Text(f.date(c.endsAt), style: text.bodySmall),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _membersView() {
    final l10n = context.l10n;
    final f = ref.fmt(context);
    String role(String r) => switch (r) {
      'guild_master' => l10n.role_guild_master,
      'officer' => l10n.role_officer,
      _ => l10n.role_member,
    };
    return _centered(
      ListView(
        padding: const EdgeInsetsDirectional.all(AppSpace.lg),
        children: [
          for (final m in _members)
            ListTile(
              contentPadding: EdgeInsetsDirectional.zero,
              leading: CircleAvatar(
                backgroundColor: context.palette.sunken,
                child: Icon(Icons.person_outline, color: context.palette.inkSoft),
              ),
              title: UserText(m.name),
              subtitle: Text(
                [
                  role(m.role),
                  if (m.level != null) l10n.characterLevel(f.number(m.level!)),
                  if (m.title != null) l10n.titleName(m.title!),
                ].join(' · '),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _newChallenge() async {
    final l10n = context.l10n;
    final title = TextEditingController();
    final target = TextEditingController(text: '100');
    final days = TextEditingController(text: '30');
    var metric = 'completions';
    var category = QuestCategory.study;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(l10n.newChallenge),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: InputDecoration(labelText: l10n.challengeTitle),
                ),
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<String>(
                  initialValue: metric,
                  items: [
                    DropdownMenuItem(value: 'completions', child: Text(l10n.challengeMetricCompletions)),
                    DropdownMenuItem(value: 'minutes_in_category', child: Text(l10n.challengeMetricMinutes)),
                  ],
                  onChanged: (v) => setState(() => metric = v ?? 'completions'),
                ),
                if (metric == 'minutes_in_category') ...[
                  const SizedBox(height: AppSpace.md),
                  DropdownButtonFormField<QuestCategory>(
                    initialValue: category,
                    items: [
                      for (final q in QuestCategory.values)
                        DropdownMenuItem(value: q, child: Text(l10n.categoryName(q))),
                    ],
                    onChanged: (v) => setState(() => category = v ?? QuestCategory.study),
                  ),
                ],
                const SizedBox(height: AppSpace.md),
                TextField(
                  controller: target,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.challengeTarget),
                ),
                const SizedBox(height: AppSpace.md),
                TextField(
                  controller: days,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.challengeDays),
                ),
                const SizedBox(height: AppSpace.md),
                Text(l10n.challengeNoPenalty, style: Theme.of(c).textTheme.bodySmall),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.actionCancel)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.newChallenge)),
          ],
        ),
      ),
    );
    final t = int.tryParse(target.text.trim());
    final d = int.tryParse(days.text.trim());
    if (ok != true || title.text.trim().isEmpty || t == null || t <= 0 || d == null || d <= 0) return;
    try {
      await _api?.createChallenge(
        guildId: widget.guildId,
        title: title.text.trim(),
        metric: metric,
        target: t,
        days: d,
        category: metric == 'minutes_in_category' ? category.name : null,
      );
      await _load();
    } on Object {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    }
  }
}

class _FeedItem extends ConsumerWidget {
  const _FeedItem({
    required this.event,
    required this.actor,
    required this.onReact,
    required this.onComments,
    required this.onReport,
    required this.onBlock,
  });

  final FeedEvent event;
  final String actor;
  final Future<void> Function(String kind, bool on) onReact;
  final VoidCallback onComments;
  final VoidCallback onReport;
  final VoidCallback? onBlock;

  String _sentence(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final f = ref.fmt(context);
    final p = event.payload;
    switch (event.kind) {
      case 'completion':
        final title = p['title'] as String?;
        final xp = (p['total_xp'] as num?)?.toInt();
        if (title != null && xp != null) return l10n.feedCompletedFull(actor, title, f.number(xp));
        if (title != null) return l10n.feedCompletedTitle(actor, title);
        return l10n.feedCompletedOnly(actor, l10n.tierName(QuestTier.parse(p['tier'])));
      case 'challenge_milestone':
        return l10n.feedMilestone(
          f.percent(((p['milestone'] as num?)?.toDouble() ?? 0) / 100),
          p['challenge_title'] as String? ?? p['title'] as String? ?? '',
        );
      case 'challenge_created':
        return l10n.feedChallengeCreated(actor, p['challenge_title'] as String? ?? p['title'] as String? ?? '');
      case 'member_joined':
        return l10n.feedMemberJoined(actor);
    }
    return actor;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final f = ref.fmt(context);
    final text = Theme.of(context).textTheme;
    final attrs = event.payload['attributes'];
    const kinds = ['honour', 'steel', 'flame', 'laurel'];
    String label(String k) => switch (k) {
      'honour' => l10n.react_honour,
      'steel' => l10n.react_steel,
      'flame' => l10n.react_flame,
      _ => l10n.react_laurel,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: context.palette.sunken,
              child: Icon(Icons.shield_outlined, size: 16, color: context.palette.inkSoft),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_sentence(context, ref), style: text.bodyLarge),
                  Text(
                    '${f.relativeDay(event.createdAt, DateTime.now())} · ${f.time(event.createdAt)}',
                    style: text.bodySmall,
                  ),
                  if (attrs is Map && attrs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: AppSpace.xs),
                      child: Wrap(
                        spacing: AppSpace.sm,
                        children: [
                          for (final e in attrs.entries)
                            if (Attribute.tryParse(e.key) case final a? when (e.value as num? ?? 0) > 0)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AttributeSigil(a, size: 12),
                                  const SizedBox(width: 3),
                                  Text(f.signedNumber(e.value as num), style: text.bodySmall),
                                ],
                              ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              iconSize: 18,
              onSelected: (v) => v == 'report' ? onReport() : onBlock?.call(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'report', child: Text(l10n.reportContent)),
                if (onBlock != null) PopupMenuItem(value: 'block', child: Text(l10n.blockUser)),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            for (final k in kinds)
              FilterChip(
                label: Text((event.reactions[k] ?? 0) > 0 ? '${label(k)} ${f.number(event.reactions[k]!)}' : label(k)),
                selected: event.myReactions.contains(k),
                onSelected: (on) => onReact(k, on),
              ),
            ActionChip(
              avatar: const Icon(Icons.mode_comment_outlined, size: 16),
              label: Text(l10n.commentsCount(event.comments, f.number(event.comments))),
              onPressed: onComments,
            ),
          ],
        ),
      ],
    );
  }
}

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.eventId, required this.nameOf});
  final String eventId;
  final String Function(String?) nameOf;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _input = TextEditingController();
  List<GuildComment> _comments = const [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await ref.read(guildApiProvider)?.comments(widget.eventId) ?? const [];
    if (mounted) setState(() => _comments = list);
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(guildApiProvider)?.addComment(widget.eventId, body);
      _input.clear();
      await _load();
    } on Object catch (e) {
      if (mounted) {
        final message = guildErrorMessage(context.l10n, e, GuildAction.comment);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final f = ref.fmt(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: AppSpace.lg,
        end: AppSpace.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in _comments)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: AppSpace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.nameOf(c.authorId)} · ${f.relativeDay(c.createdAt, DateTime.now())}',
                          style: text.bodySmall,
                        ),
                        UserText(c.body, style: text.bodyMedium),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 500,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(hintText: l10n.commentHint, counterText: ''),
                ),
              ),
              IconButton(tooltip: l10n.actionSave, icon: const Icon(Icons.send), onPressed: _sending ? null : _send),
            ],
          ),
        ],
      ),
    );
  }
}

/// The guild actions the server rate-limits, each with a limit of its own.
enum GuildAction {
  /// react and unreact: 60 changes per member per minute, across all guilds
  /// (…_reaction_rate_limit.sql).
  react,

  /// add_comment: 30 comments per member in one guild within the last hour,
  /// a rolling hour (…_rpc_social.sql).
  comment,
}

/// A refused guild [action] in words. When a rate limit refused it (hint
/// rate_limited), reactions ask for a minute's patience and comments, whose
/// limit counts the last hour, to come back later. Anything else gets the
/// general message.
String guildErrorMessage(AppLocalizations l10n, Object error, GuildAction action) {
  if (error is! PostgrestException || error.hint != 'rate_limited') return l10n.errorGeneric;
  return switch (action) {
    GuildAction.react => l10n.actionRateLimited,
    GuildAction.comment => l10n.commentRateLimited,
  };
}
