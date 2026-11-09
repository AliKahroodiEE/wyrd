/**
 * evaluate-completion — authoritative progression for one completion
 * (architecture overview §4, ADR-005).
 *
 *   POST { "completion_id": "<uuid>", "client_proposal"?: {...}, "client_model"?: "<name>" }
 *
 * `client_proposal` is a proposal the device obtained from the user's own AI
 * provider (bring your own key); it is validated and bounded server-side.
 *   Authorization: Bearer <user access token>   (or a secret key as `apikey`)
 *
 * 1. Verify the caller and that they own the completion.
 * 2. Load the minimised evaluator inputs (rules §8.2) with the service role.
 * 3. Proposal: 7-day cache → Claude (structured output, 8 s timeout, one
 *    retry) → strict validation; any failure, refusal, opt-out, missing
 *    configuration or the daily limit (120) → deterministic heuristic.
 * 4. Run the TypeScript engine against the user's current day state.
 * 5. Persist atomically with apply_progression (idempotent; retried when
 *    another completion changed the day state in between).
 *
 * Response: { status, result, proposal, source, character?, achievements? }
 */
import {
  type CompletionFacts,
  type DayState,
  dayStateFromJson,
  evaluate,
  evaluateHeuristic,
  type EvaluationProposal,
  parseCategory,
  parseTier,
  type ProposalSource,
  proposalFromJson,
  proposalToJson,
  type QuestCategory,
  resultToJson,
} from '../_shared/engine/index.ts';
import { modelFor, requestStructured } from '../_shared/ai/anthropic.ts';
import {
  buildEvaluationUserMessage,
  cleanText,
  EVALUATION_SYSTEM_PROMPT,
  evaluationCacheMaterial,
  type EvaluationInput,
  PROPOSAL_OUTPUT_SCHEMA,
  validateAiProposal,
  clientModelLabel,
  guardClientProposal,
} from '../_shared/ai/evaluation.ts';
import { aiConfigured } from '../_shared/ai/anthropic.ts';
import { authenticate } from '../_shared/auth.ts';
import { sha256Hex } from '../_shared/crypto.ts';
import {
  errorResponse,
  HttpError,
  json,
  log,
  preflight,
  readJsonObject,
  requirePost,
  requireUuid,
} from '../_shared/http.ts';
import { adminClient, rpc } from '../_shared/supabase.ts';

const DAILY_AI_EVALUATIONS = 120;
const AI_TIMEOUT_MS = 8_000;
const CACHE_DAYS = 7;
const MAX_APPLY_ATTEMPTS = 3;

interface CompletionRow {
  id: string;
  owner_id: string;
  quest_id: string;
  occurrence_day: string | null;
  completed_at: string;
  declared_minutes: number | null;
  tracked_minutes: number | null;
  local_day: string;
  state: string;
  evaluation_status: string;
  result: Record<string, unknown> | null;
}

interface QuestRow {
  id: string;
  parent_id: string | null;
  tier: string;
  title: string;
  notes: string | null;
  category: string | null;
  created_at: string;
  due_at: string | null;
  estimated_minutes: number | null;
  recurrence: unknown;
  intention: string | null;
}

interface ProfileRow {
  locale: string;
  ai_locale: string | null;
  ai_evaluation_enabled: boolean;
}

interface ApplyResponse {
  status: 'applied' | 'already_applied' | 'stale_day_state' | 'undone';
  result?: Record<string, unknown>;
  ledger?: unknown[];
  character?: Record<string, unknown>;
  achievements?: string[];
}

interface ProposalChoice {
  proposal: EvaluationProposal;
  source: ProposalSource;
  model: string | null;
  latencyMs: number | null;
  inputHash: string | null;
  fallbackReason: string | null;
}

async function loadContext(completionId: string) {
  const db = adminClient();
  const { data: completion, error } = await db
    .from('completions')
    .select('id, owner_id, quest_id, occurrence_day, completed_at, declared_minutes, tracked_minutes, local_day, state, evaluation_status, result')
    .eq('id', completionId)
    .maybeSingle<CompletionRow>();
  if (error) throw new Error(`load completion: ${error.message}`);
  if (!completion) throw new HttpError(404, 'completion_not_found', 'Sync the completion before evaluating it.');

  const { data: quest, error: questError } = await db
    .from('quests')
    .select('id, parent_id, tier, title, notes, category, created_at, due_at, estimated_minutes, recurrence, intention')
    .eq('id', completion.quest_id)
    .single<QuestRow>();
  if (questError || !quest) throw new Error(`load quest: ${questError?.message}`);

  let parentTitle: string | null = null;
  if (quest.parent_id) {
    const { data: parent } = await db.from('quests').select('title').eq('id', quest.parent_id).maybeSingle<{ title: string }>();
    parentTitle = parent?.title ?? null;
  }

  const { data: profile, error: profileError } = await db
    .from('profiles')
    .select('locale, ai_locale, ai_evaluation_enabled')
    .eq('id', completion.owner_id)
    .single<ProfileRow>();
  if (profileError || !profile) throw new Error(`load profile: ${profileError?.message}`);

  return { completion, quest, parentTitle, profile };
}

/** Returns the stored outcome of an already evaluated completion. */
async function storedOutcome(completion: CompletionRow) {
  const { data: evaluation } = await adminClient()
    .from('evaluations')
    .select('proposal, source')
    .eq('completion_id', completion.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle<{ proposal: Record<string, unknown>; source: string }>();
  return {
    status: 'already_applied',
    result: completion.result,
    proposal: evaluation?.proposal ?? null,
    source: evaluation?.source ?? completion.result?.['source'] ?? null,
  };
}

async function cachedAiProposal(ownerId: string, inputHash: string): Promise<EvaluationProposal | null> {
  const since = new Date(Date.now() - CACHE_DAYS * 24 * 3600 * 1000).toISOString();
  const { data } = await adminClient()
    .from('evaluations')
    .select('proposal')
    .eq('owner_id', ownerId)
    .eq('source', 'ai')
    .eq('input_hash', inputHash)
    .gte('created_at', since)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle<{ proposal: Record<string, unknown> }>();
  if (!data) return null;
  try {
    return proposalFromJson(data.proposal);
  } catch {
    return null;
  }
}

async function chooseProposal(
  ownerId: string,
  aiEnabledByUser: boolean,
  input: EvaluationInput,
  heuristic: EvaluationProposal,
  clientProposal: unknown = null,
  clientModel: unknown = null,
): Promise<ProposalChoice> {
  const fallback = (reason: string, extra: Partial<ProposalChoice> = {}): ProposalChoice => ({
    proposal: heuristic,
    source: 'heuristic',
    model: null,
    latencyMs: null,
    inputHash: null,
    fallbackReason: reason,
    ...extra,
  });

  if (!aiEnabledByUser) return fallback('ai_disabled_by_user');

  // Bring-your-own-key: the device already asked the user's AI provider.
  // Used even when this server has no AI key; never costs server quota.
  if (clientProposal !== null && clientProposal !== undefined) {
    const guarded = guardClientProposal(clientProposal, heuristic);
    if (!guarded) return fallback('client_proposal_invalid');
    const model = clientModelLabel(clientModel);
    const inputHash = await sha256Hex(evaluationCacheMaterial(input, model));
    return { proposal: guarded, source: 'ai', model, latencyMs: 0, inputHash, fallbackReason: null };
  }

  if (!aiConfigured()) return fallback('ai_not_configured');

  const model = modelFor('evaluation');
  const inputHash = await sha256Hex(evaluationCacheMaterial(input, model));

  const cached = await cachedAiProposal(ownerId, inputHash);
  if (cached) {
    return { proposal: cached, source: 'ai', model, latencyMs: 0, inputHash, fallbackReason: null };
  }

  const allowed = await rpc<boolean>('consume_ai_quota', {
    user_id: ownerId,
    route: 'evaluation',
    daily_limit: DAILY_AI_EVALUATIONS,
  });
  if (!allowed) return fallback('daily_limit');

  const outcome = await requestStructured({
    route: 'evaluation',
    system: EVALUATION_SYSTEM_PROMPT,
    user: buildEvaluationUserMessage(input),
    schema: PROPOSAL_OUTPUT_SCHEMA,
    effort: 'low',
    maxTokens: 4_096,
    timeoutMs: AI_TIMEOUT_MS,
  });
  if (!outcome.ok) {
    return fallback(outcome.reason, { latencyMs: outcome.latencyMs, model });
  }
  const validation = validateAiProposal(outcome.value);
  if (!validation.ok) {
    log('warn', 'ai_proposal_invalid', { errors: validation.errors.slice(0, 10) });
    return fallback('invalid_output', { latencyMs: outcome.latencyMs, model });
  }
  return {
    proposal: validation.proposal,
    source: 'ai',
    model: outcome.model,
    latencyMs: outcome.latencyMs,
    inputHash,
    fallbackReason: null,
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  const early = preflight(req);
  if (early) return early;
  let completionId: string | undefined;
  try {
    requirePost(req);
    const caller = await authenticate(req, { allowService: true });
    const body = await readJsonObject(req);
    completionId = requireUuid(body['completion_id'], 'completion_id');

    const { completion, quest, parentTitle, profile } = await loadContext(completionId);
    // Owners only; a foreign completion is indistinguishable from a missing one.
    if (caller.kind === 'user' && caller.userId !== completion.owner_id) {
      throw new HttpError(404, 'completion_not_found');
    }
    if (completion.state !== 'active') {
      throw new HttpError(409, 'completion_undone', 'This completion was undone.');
    }
    if (completion.evaluation_status === 'evaluated') {
      return json(await storedOutcome(completion));
    }

    const tier = parseTier(quest.tier);
    const categoryHint: QuestCategory | null = quest.category ? parseCategory(quest.category) : null;
    const heuristic = evaluateHeuristic({
      title: quest.title,
      notes: quest.notes ?? '',
      tier,
      categoryHint,
      declaredMinutes: completion.declared_minutes,
      estimatedMinutes: quest.estimated_minutes,
    });

    const similarCount = await rpc<number>('count_similar_completions', {
      user_id: completion.owner_id,
      quest_id: completion.quest_id,
      similarity_key: heuristic.similarityKey,
      exclude_completion_id: completion.id,
    });

    // Data minimisation (rules §8.2): exactly these fields, nothing else.
    const input: EvaluationInput = {
      title: cleanText(quest.title, 200),
      notes: cleanText(quest.notes, 1_000),
      tier,
      categoryHint,
      declaredMinutes: completion.declared_minutes,
      trackedMinutes: completion.tracked_minutes,
      plannedMinutes: quest.estimated_minutes,
      parentObjectiveTitle: parentTitle ? cleanText(parentTitle, 200) : null,
      similarCompletionsLast7Days: similarCount,
      outputLanguage: profile.ai_locale ?? profile.locale ?? 'en',
    };

    const choice = await chooseProposal(
      completion.owner_id,
      profile.ai_evaluation_enabled,
      input,
      heuristic,
      body['client_proposal'] ?? null,
      body['client_model'] ?? null,
    );

    const facts: CompletionFacts = {
      tier,
      createdAt: new Date(quest.created_at),
      completedAt: new Date(completion.completed_at),
      declaredMinutes: completion.declared_minutes,
      trackedMinutes: completion.tracked_minutes,
      dueAt: quest.due_at ? new Date(quest.due_at) : null,
      isRecurringOccurrence: quest.recurrence !== null || completion.occurrence_day !== null,
      hasImplementationIntention: (quest.intention ?? '').trim() !== '',
    };

    // Engine + atomic persistence, re-read the day state if it moved.
    for (let attempt = 1; attempt <= MAX_APPLY_ATTEMPTS; attempt++) {
      const dayJson = await rpc<Record<string, unknown>>('get_day_state', {
        user_id: completion.owner_id,
        local_day: completion.local_day,
      });
      const day: DayState = dayStateFromJson(dayJson);
      const result = evaluate(choice.proposal, facts, day);
      const applied = await rpc<ApplyResponse>('apply_progression', {
        completion_id: completion.id,
        result: resultToJson(result),
        proposal: proposalToJson(choice.proposal),
        source: choice.source,
        model: choice.model,
        meta: {
          latency_ms: choice.latencyMs,
          input_hash: choice.inputHash,
          fallback_reason: choice.fallbackReason,
          day_change_id: dayJson['changeId'] ?? null,
        },
      });

      if (applied.status === 'stale_day_state') continue;
      if (applied.status === 'undone') throw new HttpError(409, 'completion_undone');
      if (applied.status === 'already_applied') {
        return json({ ...(await storedOutcome(completion)), result: applied.result ?? completion.result });
      }

      log('info', 'completion_evaluated', {
        completion_id: completion.id,
        source: choice.source,
        fallback_reason: choice.fallbackReason,
        latency_ms: choice.latencyMs,
        total_xp: result.grants.reduce((sum, g) => sum + g.amount, 0),
        attempt,
      });
      return json({
        status: 'applied',
        result: resultToJson(result),
        proposal: proposalToJson(choice.proposal),
        source: choice.source,
        character: applied.character,
        achievements: applied.achievements ?? [],
      });
    }
    throw new HttpError(409, 'busy', 'The day changed repeatedly; please retry.');
  } catch (error) {
    return errorResponse(error, { function: 'evaluate-completion', completion_id: completionId });
  }
});
