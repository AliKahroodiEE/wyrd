/**
 * generate-chronicle — narrative records grounded in stored facts
 * (requirements H4, ADR-005).
 *
 *   POST { "period": "week" | "month" | "year", "period_start": "YYYY-MM-DD", "force"?: true }
 *     Authorization: Bearer <user access token>      → the caller's chronicle
 *   POST { "user_id", "period", "period_start" }      → internal caller, one user
 *   POST { "mode": "pending", "limit"?: 20 }           → internal caller (pg_cron
 *     via pg_net): drain chronicles enqueued by private.enqueue_weekly_chronicles
 *
 * Internal callers send a project secret key as `apikey` (see _shared/auth.ts);
 * the function is deployed with verify_jwt = false and checks every caller.
 *
 * Facts come from public.chronicle_facts (SQL). Claude may only narrate
 * them (120–220 words, second person, user's AI language); output that is
 * the wrong length or mentions numbers absent from the facts is rejected.
 * Without AI (disabled by the user, not configured, limit reached, refusal,
 * failure) a deterministic template in English or Persian is used. The
 * body and the facts are stored together in public.chronicles for audit.
 */
import { aiConfigured, modelFor, requestStructured } from '../_shared/ai/anthropic.ts';
import {
  buildChronicleUserMessage,
  CHRONICLE_OUTPUT_SCHEMA,
  CHRONICLE_SYSTEM_PROMPT,
  validateChronicle,
} from '../_shared/ai/chronicle.ts';
import { authenticate } from '../_shared/auth.ts';
import { errorResponse, HttpError, json, log, preflight, readJsonObject, requirePost, requireUuid } from '../_shared/http.ts';
import { type ChronicleFacts, type Period, templateChronicle } from '../_shared/chronicle-template.ts';
import { resolveLocale } from '../_shared/i18n.ts';
import { internalHeaders } from '../_shared/keys.ts';
import { adminClient, optionalEnv, rpc, serverKey } from '../_shared/supabase.ts';

const DAILY_AI_CHRONICLES = 20;
const AI_TIMEOUT_MS = 45_000;
const MAX_ATTEMPTS = 5;
const DRAIN_BUDGET_MS = 100_000;

interface ProfileRow {
  locale: string;
  ai_locale: string | null;
  calendar: string;
  time_zone: string;
  ai_chronicles_enabled: boolean;
}

interface ChronicleRow {
  id: string;
  owner_id: string;
  period: Period;
  period_start: string;
  period_end: string;
  locale: string;
  status: string;
  body: string | null;
  facts: ChronicleFacts | null;
  model: string | null;
  source: string | null;
  attempts: number;
}

function parsePeriod(value: unknown): Period {
  if (value === 'week' || value === 'month' || value === 'year') return value;
  throw new HttpError(400, 'invalid_request', 'period must be week, month or year.');
}

function parseIsoDate(value: unknown, field: string): string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(`${value}T00:00:00Z`))) {
    throw new HttpError(400, 'invalid_request', `${field} must be a date (YYYY-MM-DD).`);
  }
  return value;
}

function daysBetween(start: string, end: string): number {
  return Math.round((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86_400_000);
}

function todayIn(timeZone: string): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

async function loadProfile(userId: string): Promise<ProfileRow> {
  const { data, error } = await adminClient()
    .from('profiles')
    .select('locale, ai_locale, calendar, time_zone, ai_chronicles_enabled')
    .eq('id', userId)
    .maybeSingle<ProfileRow>();
  if (error) throw new Error(`load profile: ${error.message}`);
  if (!data) throw new HttpError(404, 'profile_not_found');
  return data;
}

async function generate(
  userId: string,
  period: Period,
  periodStart: string,
  options: { force: boolean; userRequested: boolean },
): Promise<ChronicleRow> {
  const db = adminClient();
  const profile = await loadProfile(userId);

  if (periodStart > todayIn(profile.time_zone)) {
    throw new HttpError(400, 'invalid_request', 'The period has not started yet.');
  }

  const { data: existing } = await db
    .from('chronicles')
    .select('*')
    .eq('owner_id', userId)
    .eq('period', period)
    .eq('period_start', periodStart)
    .maybeSingle<ChronicleRow>();
  if (existing && existing.status === 'ready' && !options.force) return existing;

  const facts = await rpc<ChronicleFacts>('chronicle_facts', {
    user_id: userId,
    period,
    period_start: periodStart,
  });
  facts.days = daysBetween(facts.periodStart, facts.periodEnd);

  const aiLocale = profile.ai_locale ?? profile.locale ?? 'en';
  let body: string | null = null;
  let source: 'ai' | 'template' = 'template';
  let model: string | null = null;
  let locale = resolveLocale(aiLocale);
  let fallbackReason: string | null = null;

  if (!profile.ai_chronicles_enabled) {
    fallbackReason = 'ai_disabled_by_user';
  } else if (!aiConfigured()) {
    fallbackReason = 'ai_not_configured';
  } else if (facts.totals.completions === 0) {
    fallbackReason = 'no_activity';            // nothing to narrate; no model call needed
  } else if (
    options.userRequested &&
    !(await rpc<boolean>('consume_ai_quota', { user_id: userId, route: 'chronicle', daily_limit: DAILY_AI_CHRONICLES }))
  ) {
    fallbackReason = 'daily_limit';
  } else {
    const outcome = await requestStructured({
      route: 'chronicle',
      system: CHRONICLE_SYSTEM_PROMPT,
      user: buildChronicleUserMessage(facts, aiLocale),
      schema: CHRONICLE_OUTPUT_SCHEMA,
      effort: 'medium',
      maxTokens: 8_000,
      timeoutMs: AI_TIMEOUT_MS,
    });
    if (outcome.ok) {
      const validation = validateChronicle(outcome.value, facts);
      if (validation.ok) {
        body = validation.body;
        source = 'ai';
        model = outcome.model;
        locale = aiLocale;                     // the model writes any language
      } else {
        fallbackReason = 'invalid_output';
        log('warn', 'chronicle_rejected', { user_id: userId, errors: validation.errors.slice(0, 10) });
      }
    } else {
      fallbackReason = outcome.reason;
    }
  }

  if (body === null) {
    body = templateChronicle(facts, aiLocale, profile.calendar);
    model = null;
  }

  const row = {
    owner_id: userId,
    period,
    period_start: periodStart,
    period_end: facts.periodEnd,
    locale,
    status: 'ready',
    body,
    facts,
    model,
    source,
    attempts: (existing?.attempts ?? 0) + 1,
    error: null,
  };
  const { data: saved, error } = await db
    .from('chronicles')
    .upsert(row, { onConflict: 'owner_id,period,period_start' })
    .select('*')
    .single<ChronicleRow>();
  if (error || !saved) throw new Error(`save chronicle: ${error?.message}`);

  log('info', 'chronicle_generated', {
    chronicle_id: saved.id,
    period,
    source,
    fallback_reason: fallbackReason,
    model: source === 'ai' ? modelFor('chronicle') : null,
  });
  return saved;
}

/** Best-effort push that a weekly chronicle is ready (respects all notify rules). */
async function announce(userId: string): Promise<void> {
  const url = optionalEnv('SUPABASE_URL');
  const key = serverKey();
  if (!url || !key) return;
  try {
    await fetch(`${url.replace(/\/$/, '')}/functions/v1/notify`, {
      method: 'POST',
      headers: internalHeaders(key, (name) => Deno.env.get(name)),
      body: JSON.stringify({ user_id: userId, category: 'weekly_summary', template_key: 'weekly_chronicle', params: {} }),
      signal: AbortSignal.timeout(5_000),
    });
  } catch (error) {
    log('warn', 'chronicle_announce_failed', { user_id: userId, error: String(error) });
  }
}

async function drainPending(limit: number) {
  const started = Date.now();
  const { data: pending, error } = await adminClient()
    .from('chronicles')
    .select('id, owner_id, period, period_start, attempts')
    .eq('status', 'pending')
    .lt('attempts', MAX_ATTEMPTS)
    .order('created_at', { ascending: true })
    .limit(limit);
  if (error) throw new Error(`load pending chronicles: ${error.message}`);

  let ready = 0;
  let failed = 0;
  for (const item of (pending ?? []) as Array<Pick<ChronicleRow, 'id' | 'owner_id' | 'period' | 'period_start' | 'attempts'>>) {
    if (Date.now() - started > DRAIN_BUDGET_MS) break;
    try {
      await generate(item.owner_id, item.period, item.period_start, { force: true, userRequested: false });
      ready++;
      if (item.period === 'week') await announce(item.owner_id);
    } catch (err) {
      failed++;
      const attempts = item.attempts + 1;
      await adminClient()
        .from('chronicles')
        .update({
          attempts,
          status: attempts >= MAX_ATTEMPTS ? 'failed' : 'pending',
          error: err instanceof Error ? err.message.slice(0, 500) : 'unknown error',
        })
        .eq('id', item.id);
      log('warn', 'chronicle_failed', { chronicle_id: item.id, attempts });
    }
  }
  return { processed: ready + failed, ready, failed };
}

Deno.serve(async (req: Request): Promise<Response> => {
  const early = preflight(req);
  if (early) return early;
  try {
    requirePost(req);
    const caller = await authenticate(req, { allowService: true });
    const body = await readJsonObject(req);

    if (body['mode'] === 'pending') {
      if (caller.kind !== 'service') throw new HttpError(403, 'forbidden');
      const limit = Math.min(Math.max(Number(body['limit'] ?? 20) || 20, 1), 50);
      return json(await drainPending(limit));
    }

    const userId = caller.kind === 'user' ? caller.userId : requireUuid(body['user_id'], 'user_id');
    const period = parsePeriod(body['period']);
    const periodStart = parseIsoDate(body['period_start'], 'period_start');
    const chronicle = await generate(userId, period, periodStart, {
      force: body['force'] === true,
      userRequested: caller.kind === 'user',
    });
    return json({
      id: chronicle.id,
      period: chronicle.period,
      period_start: chronicle.period_start,
      period_end: chronicle.period_end,
      locale: chronicle.locale,
      body: chronicle.body,
      facts: chronicle.facts,
      source: chronicle.source,
      model: chronicle.model,
    });
  } catch (error) {
    return errorResponse(error, { function: 'generate-chronicle' });
  }
});
