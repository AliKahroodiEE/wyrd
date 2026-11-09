# Architecture Overview

Status: Accepted for M0–M1 · Decisions are recorded as ADRs in [`adr/`](adr/).

## 1. System context

```
┌──────────────── Flutter client (Android · iOS · Web) ────── ───────────────┐
│  UI (adaptive shells, design system, l10n)                                            │
│  State (Riverpod) ─▶ Repositories ─▶ Local store (Drift / SQLite, offline-first)      │
│                                   └▶ Sync engine (outbox push, cursor pull)            │
│  wyrd_engine (pure Dart): provisional evaluation, curves, streaks, achievements   │
└───────────────┬───────────────────────────────────────────────────────┬───────────────┘
                │ HTTPS (PostgREST / RPC, JWT)                          │ WebSocket (Realtime)
┌───────────────▼───────────────────────────────────────────────────────▼───────────────┐
│ Supabase                                                                              │
│  Auth (email code, password, Google, GitHub)  Postgres 17 + RLS  Realtime  Storage    │
│  Edge Functions (Deno/TS):                                                            │
│    evaluate-completion  → Claude (proposal) → engine.ts (authoritative) → ledger RPC   │
│    generate-chronicle   → facts query → Claude (narrative grounded in facts)          │
│    notify               → FCM / APNs / Web Push fan-out with caps and quiet hours     │
│  pg_cron: weekly chronicles, monthly snapshots/class, condition rollover, retention   │
└───────────────────────────────────────────────────────────────────────────────────────┘
        │                                   │
   Anthropic Messages API             Firebase Cloud Messaging (push transport only)
```

## 2. Key decisions (summary)

| ADR | Decision |
| --- | --- |
| [001](adr/001-flutter-single-codebase.md) | Flutter for all five platforms with adaptive layouts, not stretched mobile UI |
| [002](adr/002-supabase-backend.md) | Supabase (Postgres + RLS, Auth, Realtime, Edge Functions, Storage, pg_cron) |
| [003](adr/003-local-first-sync.md) | Local-first client on Drift/SQLite; outbox push + cursor pull; server-authoritative progression |
| [004](adr/004-dual-engine-conformance.md) | Progression engine in Dart (client) and TypeScript (server) bound by shared conformance vectors |
| [005](adr/005-ai-evaluation.md) | Claude via server-side Edge Functions with structured output; AI proposes, engine decides; heuristic fallback |
| [006](adr/006-client-stack.md) | Riverpod, go_router, gen-l10n (ARB/ICU), bundled Inter + Vazirmatn, fl_chart, shamsi_date |
| [007](adr/007-notifications.md) | Local notifications for reminders; FCM for social push; server-side caps and quiet hours |

## 3. Data model (server)

All tables have RLS enabled. `owner_id`/`user_id` reference `auth.users(id)`.
Timestamps are `timestamptz` (UTC); `local_day` is a `date` computed with the user's time zone.

| Table | Purpose | Key columns |
| --- | --- | --- |
| `profiles` | Account preferences | `id`, `handle`, `display_name`, `locale`, `ai_locale`, `region`, `calendar`, `time_zone`, `week_start`, `weekly_target`, `motivation` jsonb |
| `characters` | Cached character state (rebuildable from ledger) | `id`, `name`, `portrait`, `equipped_title`, `class_id`, `attr_xp` jsonb, `total_xp`, `level`, `condition` |
| `quests` | Daily quests, contracts, objectives | `id`, `owner_id`, `parent_id`, `tier`, `title`, `notes`, `category`, `priority`, `status`, `due_at`, `estimated_minutes`, `recurrence` jsonb, `intention`, `share_level`, `reminder_at`, `updated_at`, `deleted_at` |
| `subtasks` | Checklist items | `id`, `quest_id`, `title`, `done`, `position` |
| `completions` | Append-only completion facts (client UUID = idempotency key) | `id`, `quest_id`, `owner_id`, `occurrence_day`, `completed_at`, `declared_minutes`, `tracked_minutes`, `local_day`, `state` |
| `evaluations` | Evaluator proposals (AI or heuristic) | `completion_id`, `source`, `model`, `proposal` jsonb, `latency_ms` |
| `ledger_entries` | Append-only attribute grants and reversals | `id`, `owner_id`, `completion_id`, `attribute`, `amount`, `raw_amount`, `kind`, `rule_version`, `adjustments` jsonb, `local_day` |
| `achievements` | Unlocked achievements | `owner_id`, `achievement_id`, `unlocked_at` |
| `day_stats` | Per-day rollup for analytics and caps | `owner_id`, `local_day`, `minutes`, `xp` jsonb, `raw_xp` jsonb, `completions`, `trivial_count`, `rest_day` |
| `snapshots` | Monthly character snapshots | `owner_id`, `taken_on`, `data` jsonb |
| `chronicles` | AI chronicles with the facts they were grounded on | `owner_id`, `period`, `period_start`, `locale`, `body`, `facts` jsonb, `model` |
| `guilds` | Guilds | `id`, `name`, `description`, `emblem`, `visibility`, `language_tag`, `owner_id`, `member_limit` |
| `guild_members` | Membership and per-guild prefs | `guild_id`, `user_id`, `role`, `share_level`, `muted` |
| `guild_invites` | Invite codes | `code`, `guild_id`, `expires_at`, `max_uses`, `uses` |
| `feed_events` | Projected, privacy-filtered activity | `id`, `guild_id`, `actor_id`, `kind`, `payload` jsonb |
| `reactions`, `comments` | Social responses | `event_id`, `user_id`, `kind` / `body` |
| `challenges`, `challenge_contributions` | Collective objectives | `metric`, `target`, `starts_at`, `ends_at` / `amount` |
| `blocks`, `reports` | Safety | `blocker_id`, `blocked_id` / `target_type`, `target_id`, `reason`, `status` |
| `notification_prefs`, `push_tokens` | Notifications | categories, quiet hours, daily cap / token, platform |

### Privacy projection
Feed events are written by a `SECURITY DEFINER` function that reads the quest's effective
share level and writes only the permitted fields into `payload`. Clients never write
`feed_events` directly, so a client bug cannot leak a private title.

## 4. Completion flow

```
Client (online or offline)
 1. INSERT completion (client UUID) locally + outbox row
 2. engine.evaluate(heuristicProposal, facts, localDayState) → provisional result (shown at once)
Sync
 3. push completion → RPC sync_push (idempotent upsert)
 4. client calls evaluate-completion(completion_id)
Edge function
 5. load completion + quest + day_stats (service role)
 6. Claude → proposal (JSON schema); on failure/timeout (8 s) → heuristic proposal
 7. engine.ts evaluate(proposal, facts, dayState) → result
 8. RPC apply_progression(result) — one transaction: ledger rows, day_stats, character
    cache, achievements, challenge contributions, feed event (projected)
 9. return result
Client
10. mark provisional ledger rows superseded; store authoritative rows; UI animates delta
Other devices
11. next sync cycle (after a local change, on sign-in, every 2 minutes) → pull → UI updates
```

Idempotency: `apply_progression` is a no-op if confirmed ledger rows already exist for the
completion. Retries are safe at every step.

## 5. Sync protocol (client)

- **Outbox:** every local mutation appends `(entity, id, op, payload, hlc)`; a single worker
  pushes in order with exponential backoff; rows are deleted on acknowledgement.
- **Pull:** `sync_pull(cursor)` returns rows changed since the cursor per table (server
  `updated_at` + monotonic `change_id`). Personal data is pulled on a schedule (sign-in,
  shortly after each local change, every two minutes), never pushed by Realtime: Realtime
  carries only the guild hall's change signals (feed events, comments, challenges), which
  trigger a refetch and are never applied directly, keeping one code path.
- **One account per device:** the local data and sync state belong to the account that
  signed in (guest data joins the first one). Another account signing in on the same device
  starts from a wiped database, so two accounts never mix.
- **Account settings:** name, weekly target, motivation, AI opt-in and notification
  switches are taken over from the server when another device changed them (merged key by
  key against what this device last sent); language, calendar, time zone and week start
  are per device and only sent.
- **Conflicts:** quests and subtasks use field-level last-writer-wins by hybrid logical clock;
  completions and ledger entries are append-only (no conflicts); deletes are tombstones.
- **Guest mode:** identical local schema; on sign-up the outbox is replayed against the new
  account.

## 6. Security

- RLS on every table; owners read/write their rows; guild data readable by members; public
  guild metadata readable by authenticated users; `ledger_entries`, `characters`,
  `feed_events`, `challenge_contributions` writable only through `SECURITY DEFINER` RPCs or
  the service role.
- Service-role and Anthropic keys exist only in Edge Function secrets.
- Rate limits: evaluate-completion ≤ 120 calls/user/day; comment/post limits per guild;
  invite code entropy ≥ 40 bits.
- Abuse: report queue, automatic hide at N reports in public guilds, keyword filter, slow mode.
- Data export: `export_my_data()` returns all user-owned rows as JSON; deletion cascades and
  anonymises authored guild content to "Former member".

## 7. Observability

Sentry for client and function errors (PII scrubbing on), structured function logs with
completion IDs, evaluation latency and fallback-rate metrics, AI cost per user per day,
and a reward-distribution dashboard used to tune rules between versions.

## 8. Environments

`local` (Supabase CLI + Docker) · `staging` · `production`. Client flavours are selected with
`--dart-define=WYRD_ENV=…`; without backend configuration the app runs in local-only
mode with the heuristic evaluator, which is also the demo environment.
