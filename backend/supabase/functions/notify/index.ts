/**
 * notify — server-side social and summary notifications (ADR-007).
 *
 * Internal endpoint (verify_jwt = false): requires a project secret key in
 * the `apikey` header (legacy projects: the service-role key, also as a
 * bearer token) or INTERNAL_FUNCTION_SECRET (x-internal-secret). Two shapes:
 *
 *   Direct:  { user_id, category, template_key, params?, guild_id?, actor_id?, dedupe_key? }
 *   Database-Webhook-shaped, sent by the …_notify_triggers.sql triggers on
 *   INSERT into reactions, comments and feed_events (challenge milestones):
 *            { type: "INSERT", table, schema, record, old_record }
 *
 * For every recipient, in order: category toggle → guild mute → block list
 * (FR-7) → quiet hours in the recipient's time zone → 7-day re-engagement
 * limit → daily cap (default 5; reminders exempt) → reaction batching →
 * localized template (_shared/i18n/<locale>.json) → FCM HTTP v1.
 * Every decision is logged in public.notification_deliveries.
 * Without FCM credentials: { sent: false, reason: "push_not_configured" }.
 */
import { requireService } from '../_shared/auth.ts';
import { errorResponse, HttpError, json, log, preflight, readJsonObject, requirePost, requireUuid } from '../_shared/http.ts';
import { hasTemplate, type Params, resolveLocale, t } from '../_shared/i18n.ts';
import {
  BATCH_WINDOW_MS,
  CAP_EXEMPT,
  categoryEnabled,
  DEFAULT_DAILY_CAP,
  DEFAULT_QUIET_END,
  DEFAULT_QUIET_START,
  excerpt,
  inQuietHours,
  isNotificationCategory,
  localClock,
  type NotificationCategory,
  RE_ENGAGEMENT_INTERVAL_MS,
} from '../_shared/notification-policy.ts';
import { adminClient } from '../_shared/supabase.ts';
import { sendPush, serviceAccount } from './fcm.ts';

interface NotificationRequest {
  userId: string;
  category: NotificationCategory;
  templateKey: string;
  params: Params;
  guildId: string | null;
  actorId: string | null;
  dedupeKey: string | null;
  data: Record<string, string>;
}

interface DeliveryResult {
  user_id: string;
  sent: boolean;
  reason?: string;
  delivered?: number;
}

interface FeedEventRow {
  id: string;
  guild_id: string;
  actor_id: string | null;
  kind: string;
  payload: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Request parsing
// ---------------------------------------------------------------------------

function parseParams(value: unknown): Params {
  if (value === undefined || value === null) return {};
  if (typeof value !== 'object' || Array.isArray(value)) {
    throw new HttpError(400, 'invalid_request', 'params must be an object.');
  }
  const params: Params = {};
  for (const [key, v] of Object.entries(value as Record<string, unknown>)) {
    if (typeof v === 'string') params[key] = v.slice(0, 200);
    else if (typeof v === 'number' && Number.isFinite(v)) params[key] = v;
  }
  return params;
}

function fromDirect(body: Record<string, unknown>): NotificationRequest {
  const category = body['category'];
  if (!isNotificationCategory(category)) throw new HttpError(400, 'invalid_request', 'Unknown category.');
  const templateKey = body['template_key'];
  if (typeof templateKey !== 'string' || !/^[a-z0-9_]{1,64}$/.test(templateKey)
      || !hasTemplate('en', `notifications.${templateKey}.title`)) {
    throw new HttpError(400, 'invalid_request', 'Unknown template_key.');
  }
  const guildId = body['guild_id'] === undefined || body['guild_id'] === null ? null : requireUuid(body['guild_id'], 'guild_id');
  const actorId = body['actor_id'] === undefined || body['actor_id'] === null ? null : requireUuid(body['actor_id'], 'actor_id');
  const dedupeKey = typeof body['dedupe_key'] === 'string' ? body['dedupe_key'].slice(0, 200) : null;
  return {
    userId: requireUuid(body['user_id'], 'user_id'),
    category,
    templateKey,
    params: parseParams(body['params']),
    guildId,
    actorId,
    dedupeKey,
    data: guildId ? { guild_id: guildId } : {},
  };
}

async function displayName(userId: string | null): Promise<string> {
  if (!userId) return '';
  const db = adminClient();
  const [{ data: profile }, { data: character }] = await Promise.all([
    db.from('profiles').select('display_name, handle').eq('id', userId).maybeSingle<{ display_name: string; handle: string | null }>(),
    db.from('characters').select('name').eq('owner_id', userId).maybeSingle<{ name: string }>(),
  ]);
  return (profile?.display_name || character?.name || profile?.handle || '').trim();
}

async function guildName(guildId: string): Promise<string> {
  const { data } = await adminClient().from('guilds').select('name').eq('id', guildId).maybeSingle<{ name: string }>();
  return data?.name ?? '';
}

async function loadEvent(eventId: unknown): Promise<FeedEventRow | null> {
  if (typeof eventId !== 'string') return null;
  const { data } = await adminClient()
    .from('feed_events')
    .select('id, guild_id, actor_id, kind, payload')
    .eq('id', eventId)
    .maybeSingle<FeedEventRow>();
  return data;
}

/** Maps a Database Webhook payload to zero or more notifications. */
async function fromWebhook(body: Record<string, unknown>): Promise<NotificationRequest[]> {
  if (body['type'] !== 'INSERT' || typeof body['record'] !== 'object' || body['record'] === null) return [];
  const record = body['record'] as Record<string, unknown>;
  const db = adminClient();

  switch (body['table']) {
    case 'reactions': {
      const event = await loadEvent(record['event_id']);
      const reactor = typeof record['user_id'] === 'string' ? record['user_id'] : null;
      if (!event || !event.actor_id || !reactor || event.actor_id === reactor) return [];
      const { data: reactors } = await db.from('reactions').select('user_id').eq('event_id', event.id);
      const others = new Set((reactors ?? []).map((r: { user_id: string }) => r.user_id).filter((id: string) => id !== event.actor_id));
      const extra = Math.max(others.size - 1, 0);
      const kind = typeof record['kind'] === 'string' ? record['kind'] : 'honour';
      return [{
        userId: event.actor_id,
        category: 'guild_reactions',
        templateKey: extra > 0 ? 'reaction_batched' : `reaction_${kind}`,
        params: { actor: await displayName(reactor), guild: await guildName(event.guild_id), ...(extra > 0 ? { count: extra } : {}) },
        guildId: event.guild_id,
        actorId: reactor,
        dedupeKey: `reaction:${event.id}`,
        data: { guild_id: event.guild_id, event_id: event.id },
      }];
    }
    case 'comments': {
      const event = await loadEvent(record['event_id']);
      const author = typeof record['author_id'] === 'string' ? record['author_id'] : null;
      if (!event || !event.actor_id || !author || event.actor_id === author) return [];
      return [{
        userId: event.actor_id,
        category: 'guild_comments',
        templateKey: 'comment',
        params: {
          actor: await displayName(author),
          guild: await guildName(event.guild_id),
          excerpt: excerpt(typeof record['body'] === 'string' ? record['body'] : ''),
        },
        guildId: event.guild_id,
        actorId: author,
        dedupeKey: typeof record['id'] === 'string' ? `comment:${record['id']}` : null,
        data: { guild_id: event.guild_id, event_id: event.id },
      }];
    }
    case 'feed_events': {
      if (record['kind'] !== 'challenge_milestone' || typeof record['guild_id'] !== 'string') return [];
      const payload = (record['payload'] ?? {}) as Record<string, unknown>;
      const milestone = Number(payload['milestone'] ?? 0);
      const guildId = record['guild_id'];
      const { data: members } = await db.from('guild_members').select('user_id').eq('guild_id', guildId);
      const name = await guildName(guildId);
      return (members ?? []).map((m: { user_id: string }): NotificationRequest => ({
        userId: m.user_id,
        category: 'challenge_milestones',
        templateKey: milestone >= 100 ? 'challenge_complete' : 'challenge_milestone',
        params: { challenge: String(payload['title'] ?? ''), percent: milestone, guild: name },
        guildId,
        actorId: null,
        dedupeKey: `milestone:${String(payload['challenge_id'] ?? '')}:${milestone}`,
        data: { guild_id: guildId, challenge_id: String(payload['challenge_id'] ?? '') },
      }));
    }
    default:
      return [];
  }
}

// ---------------------------------------------------------------------------
// Delivery
// ---------------------------------------------------------------------------

async function deliver(request: NotificationRequest): Promise<DeliveryResult> {
  const db = adminClient();
  const [{ data: profile }, { data: prefs }] = await Promise.all([
    db.from('profiles').select('locale, time_zone').eq('id', request.userId)
      .maybeSingle<{ locale: string; time_zone: string }>(),
    db.from('notification_prefs').select('categories, quiet_hours_start, quiet_hours_end, daily_cap')
      .eq('user_id', request.userId)
      .maybeSingle<{ categories: Record<string, unknown>; quiet_hours_start: string; quiet_hours_end: string; daily_cap: number }>(),
  ]);
  if (!profile) return { user_id: request.userId, sent: false, reason: 'unknown_user' };

  const locale = resolveLocale(profile.locale);
  const clock = localClock(profile.time_zone, new Date());

  const record = async (status: 'sent' | 'suppressed' | 'failed', reason: string | null) => {
    const { error } = await db.from('notification_deliveries').insert({
      user_id: request.userId,
      category: request.category,
      template_key: request.templateKey,
      guild_id: request.guildId,
      dedupe_key: request.dedupeKey,
      local_day: clock.localDay,
      status,
      reason,
    });
    if (error) log('warn', 'notification_log_failed', { error: error.message });
  };
  const suppress = async (reason: string): Promise<DeliveryResult> => {
    await record('suppressed', reason);
    return { user_id: request.userId, sent: false, reason };
  };

  if (!categoryEnabled(prefs?.categories, request.category)) return suppress('category_disabled');

  if (request.guildId) {
    const { data: membership } = await db.from('guild_members').select('muted')
      .eq('guild_id', request.guildId).eq('user_id', request.userId).maybeSingle<{ muted: boolean }>();
    if (!membership) return suppress('not_member');
    if (membership.muted) return suppress('guild_muted');
  }

  if (request.actorId) {
    const { data: block } = await db.from('blocks').select('blocker_id')
      .eq('blocker_id', request.userId).eq('blocked_id', request.actorId).maybeSingle();
    if (block) return suppress('blocked');
  }

  if (inQuietHours(prefs?.quiet_hours_start ?? DEFAULT_QUIET_START, prefs?.quiet_hours_end ?? DEFAULT_QUIET_END, clock.minutes)) {
    return suppress('quiet_hours');
  }

  if (request.category === 're_engagement') {
    const since = new Date(Date.now() - RE_ENGAGEMENT_INTERVAL_MS).toISOString();
    const { count } = await db.from('notification_deliveries').select('id', { count: 'exact', head: true })
      .eq('user_id', request.userId).eq('category', 're_engagement').eq('status', 'sent').gte('created_at', since);
    if ((count ?? 0) > 0) return suppress('re_engagement_limit');
  }

  if (!CAP_EXEMPT.has(request.category)) {
    const { count } = await db.from('notification_deliveries').select('id', { count: 'exact', head: true })
      .eq('user_id', request.userId).eq('local_day', clock.localDay).eq('status', 'sent').neq('category', 'reminders');
    if ((count ?? 0) >= (prefs?.daily_cap ?? DEFAULT_DAILY_CAP)) return suppress('daily_cap');
  }

  if (request.dedupeKey) {
    const since = new Date(Date.now() - BATCH_WINDOW_MS).toISOString();
    const { count } = await db.from('notification_deliveries').select('id', { count: 'exact', head: true })
      .eq('user_id', request.userId).eq('dedupe_key', request.dedupeKey).eq('status', 'sent').gte('created_at', since);
    if ((count ?? 0) > 0) return suppress('batched');
  }

  const params: Params = { ...request.params };
  if (params['actor'] === '') params['actor'] = t(locale, 'common.someone');
  if (params['guild'] === '') params['guild'] = t(locale, 'common.guild');
  const title = t(locale, `notifications.${request.templateKey}.title`, params);
  const body = t(locale, `notifications.${request.templateKey}.body`, params);

  const account = serviceAccount();
  if (!account) {
    log('info', 'push_not_configured', { category: request.category, template_key: request.templateKey });
    await record('suppressed', 'push_not_configured');
    return { user_id: request.userId, sent: false, reason: 'push_not_configured' };
  }

  const { data: tokens } = await db.from('push_tokens').select('id, token').eq('user_id', request.userId);
  if (!tokens || tokens.length === 0) return suppress('no_device');

  let delivered = 0;
  for (const device of tokens as Array<{ id: string; token: string }>) {
    try {
      const outcome = await sendPush(account, {
        token: device.token,
        title,
        body,
        thread: request.category,
        data: { category: request.category, template_key: request.templateKey, ...request.data },
      });
      if (outcome === 'sent') delivered++;
      else if (outcome === 'unregistered') await db.from('push_tokens').delete().eq('id', device.id);
    } catch (error) {
      log('warn', 'push_send_error', { error: error instanceof Error ? error.message : String(error) });
    }
  }
  if (delivered === 0) {
    await record('failed', 'transport');
    return { user_id: request.userId, sent: false, reason: 'transport_failed' };
  }
  await record('sent', null);
  return { user_id: request.userId, sent: true, delivered };
}

Deno.serve(async (req: Request): Promise<Response> => {
  const early = preflight(req);
  if (early) return early;
  try {
    requirePost(req);
    requireService(req);
    const body = await readJsonObject(req, 65_536);
    const isWebhook = typeof body['type'] === 'string' && typeof body['table'] === 'string';
    const requests = isWebhook ? await fromWebhook(body) : [fromDirect(body)];
    if (requests.length === 0) return json({ sent: false, reason: 'ignored' });

    const results: DeliveryResult[] = [];
    for (const request of requests) results.push(await deliver(request));
    return json(requests.length === 1 && !isWebhook ? results[0] : { results });
  } catch (error) {
    return errorResponse(error, { function: 'notify' });
  }
});
