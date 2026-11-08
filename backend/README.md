# Wyrd backend

Supabase project for Wyrd: Postgres schema with row-level security, the
sync and progression RPCs, the TypeScript twin of the progression engine and
three Edge Functions (AI evaluation, chronicles, push notifications).

Design background: [architecture overview](../docs/architecture/overview.md),
[ADR-002](../docs/architecture/adr/002-supabase-backend.md) (Supabase),
[ADR-003](../docs/architecture/adr/003-local-first-sync.md) (sync),
[ADR-004](../docs/architecture/adr/004-dual-engine-conformance.md) (two engines),
[ADR-005](../docs/architecture/adr/005-ai-evaluation.md) (AI),
[ADR-007](../docs/architecture/adr/007-notifications.md) (notifications) and the
[progression rules](../docs/product/progression-rules.md).
Running it for real users: [Production](#production) and [Backups](#backups).

```
backend/
├── package.json                 Node tooling only (tests, SQL validation)
├── scripts/
│   ├── validate-sql.mjs         Applies all migrations to PGlite: grants, smoke checks
│   └── data-api-surface.mjs     Finds every .from() / .rpc() / Realtime call to check grants
└── supabase/
    ├── config.toml              CLI v3 config: the local stack, and what the deploy pushes
    ├── migrations/              Ordered SQL migrations (see below)
    └── functions/               Deno Edge Functions
        ├── deno.json / deno.lock
        ├── .env.example         Local secrets template
        ├── _shared/
        │   ├── engine/          TypeScript progression engine (+ conformance tests)
        │   ├── ai/              Claude client, prompts, schemas, output validation
        │   ├── i18n/            en.json, fa.json — server-rendered text
        │   ├── keys.ts          API keys and caller checks (+ keys.test.ts)
        │   └── …                auth, http/CORS, Supabase admin client, policy helpers
        ├── evaluate-completion/
        ├── generate-chronicle/
        └── notify/
```

## Prerequisites

| Tool | Version | Used for |
| --- | --- | --- |
| [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) | 3.x (`npx supabase@3` works without installing) | local stack, migrations, deploys |
| Docker | current | `supabase start` |
| Node.js | ≥ 23.6 (26 recommended) | engine tests, SQL validation (native TypeScript type stripping) |
| Deno | 2.x (optional) | type-checking functions; `npx deno@2` works without installing |
| [age](https://github.com/FiloSottile/age) | 1.x | reading [backups](#backups) |

## Local development

All Supabase CLI commands run from `backend/` (the CLI looks for `./supabase`).

```bash
cd backend
supabase start                      # Postgres 17, Auth, Realtime, Storage, Studio, local mail
supabase status                     # API URL, publishable and secret keys
supabase db reset                   # re-applies every migration from scratch

cp supabase/functions/.env.example supabase/functions/.env   # then fill in
supabase functions serve --env-file supabase/functions/.env
```

The `[auth]` sections of `config.toml` read some values with `env(...)`
(site URL, SMTP, sign-in providers); the CLI takes them from the shell or
`backend/supabase/.env` (git-ignored), and refuses to load the file while a
number or `true`/`false` value is unresolved.

Local URLs: API `http://127.0.0.1:54321`, Studio `http://127.0.0.1:54323`,
local mail (sign-in codes, confirmations) `http://127.0.0.1:54324`.

Like a new hosted project, the local stack exposes nothing in `public`
without a GRANT (`[api] auto_expose_new_tables = false`), so a missing grant
shows up locally first.

Without `ANTHROPIC_API_KEY` everything still works: evaluations use the
deterministic heuristic and chronicles the localized template. Without
`FCM_SERVICE_ACCOUNT`, `notify` answers `{"sent": false, "reason": "push_not_configured"}`.
pg_cron's chronicle dispatch and the notification triggers stay silent until
the database knows where to call; to try them locally, store the API URL as
the database container reaches it and the local secret key from
`supabase status`:

```sql
select private.set_function_credentials('http://host.docker.internal:54321', 'sb_secret_…');
```

### Secrets (Edge Functions)

| Name | Required | Purpose |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | for AI | Claude API key (function secret only, never in the client) |
| `AI_EVALUATION_MODEL` | no | model for evaluate-completion, default `claude-opus-5-5` |
| `AI_CHRONICLE_MODEL` | no | model for generate-chronicle, default `claude-opus-5-5` |
| `AI_SERVER_FALLBACKS` | no | `off` disables the server-side refusal fallback (`fallbacks: "default"`) |
| `FCM_SERVICE_ACCOUNT` | for push | Firebase service-account JSON (raw or base64) with FCM permission |
| `INTERNAL_FUNCTION_SECRET` | no | extra shared secret internal callers may send as `x-internal-secret` |

Supabase injects `SUPABASE_URL` and the project's keys: `SUPABASE_SECRET_KEYS`,
`SUPABASE_PUBLISHABLE_KEYS` and `SUPABASE_JWKS` with the new API keys,
`SUPABASE_SERVICE_ROLE_KEY` on older projects; never set `SUPABASE_*`
yourself. On the hosted project the deploy workflow sets `ANTHROPIC_API_KEY`
and `FCM_SERVICE_ACCOUNT` from GitHub secrets; by hand:

```bash
supabase secrets set --yes ANTHROPIC_API_KEY=…
supabase secrets set --yes FCM_SERVICE_ACCOUNT="$(base64 < firebase-service-account.json)"
```

### API keys and callers

New Supabase projects have no `anon` / `service_role` JWT keys:

* The app ships the **publishable key** (`sb_publishable_…`); RLS and the
  RPCs enforce everything. Signed-in calls carry the user's access token.
* The **secret keys** (`sb_secret_…`) act as the `service_role` Postgres role
  and never leave the server. The Edge Functions' admin client uses the
  `default` entry of `SUPABASE_SECRET_KEYS` (the legacy
  `SUPABASE_SERVICE_ROLE_KEY` on older projects; see `_shared/keys.ts`).
* **User tokens** are verified in every function with `auth.getClaims`:
  locally against `SUPABASE_JWKS` (the JWKS endpoint after a key rotation,
  the Auth server on legacy HS256 projects). No JWT secret is configured
  anywhere.
* **Internal callers** (pg_cron and the notification triggers through
  pg_net, function to function) send a project secret key in the `apikey`
  header, never as `Authorization: Bearer`; any of the project's secret keys
  is accepted, so one can be rotated without downtime. A legacy service-role
  JWT is accepted as `apikey` or bearer token, and `INTERNAL_FUNCTION_SECRET`
  as `x-internal-secret`.
* `verify_jwt` (`[functions.*]` in `config.toml`): on for the user-facing
  `evaluate-completion`; off for `generate-chronicle` and `notify`, which
  internal callers reach with a secret key (not a JWT). Every function checks
  its callers itself either way.

### Scheduled jobs

`…_cron.sql` installs pg_cron jobs when the extension is available (it is on
hosted Supabase; the migration skips scheduling elsewhere):

| Job | Schedule (UTC) | Function |
| --- | --- | --- |
| `wyrd-monthly` | 05:00 on the 1st | `private.take_monthly_snapshots()`, `private.recompute_classes()` |
| `wyrd-chronicles` | 03:15 daily | `private.enqueue_weekly_chronicles()` (idempotent per user/week) |
| `wyrd-dispatch` | every 15 min | `private.dispatch_pending_chronicles()` → `generate-chronicle {mode:"pending"}` |
| `wyrd-hourly` | :07 hourly | `private.refresh_conditions()`, `private.end_challenges()` |
| `wyrd-retention` | 04:30 daily | `private.retention_cleanup()` |

The dispatch job (and the notification triggers below) calls the functions
through pg_net with two Vault secrets, `wyrd_project_url` and
`wyrd_secret_key` (`…_cron_secret_key.sql`; the old `wyrd_service_role_key`
still works as a fallback). The deploy workflow stores both on every run;
by hand, as `postgres` (SQL editor or `supabase db query --remote --yes`):

```sql
select private.set_function_credentials('https://<project-ref>.supabase.co', 'sb_secret_…');
```

Without pg_net or the secrets every internal call is a no-op.

### Notifications

`…_notify_triggers.sql` posts every new reaction, comment and challenge
milestone to `notify` through pg_net (after commit, with the secret key as
`apikey`), in the Database Webhook shape `{ type, table, schema, record,
old_record }`. No dashboard webhooks are needed. Earlier instructions had
owners create three (INSERT on these tables → `/functions/v1/notify`);
`…_drop_notify_webhooks.sql` removes them so pushes are not sent twice: only
webhooks whose URL (the first `http_request` argument) has the path
`/functions/v1/notify` right after a non-empty host, optionally followed by
`/`, `?` or `#`. The URL is read as pg_net's libcurl reads it: the scheme in
any case (`HTTPS://`) and one to three slashes after it (`https:///…`, which
the dashboard accepts). Webhooks to other functions such as
`notify-moderators`, and to other URLs, stay. Do not create new ones: the
migration runs only once. A failing pg_net never fails the user's write.
Other senders POST `{ user_id, category, template_key, params, guild_id? }`
directly.

## Flutter configuration

The app reads the backend location from compile-time defines; with none it
runs in local-only (guest/demo) mode.

```bash
flutter run \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key from `supabase status`>
```

Android emulators reach the host at `http://10.0.2.2:54321`. Only the
publishable key ever ships in the client.

## Tests and verification

```bash
cd backend
npm install                  # PGlite (dev only)
npm test                     # engine conformance vectors + heuristic + keys + shared modules (Node)
npm run validate:sql         # all migrations on PGlite: grants, RLS/sync/progression smoke checks, internal calls
npm run check:functions      # deno check of every function and test (strict)
npm run lint:functions       # deno lint
npm run verify               # test + validate:sql + check:functions
```

The engine conformance test can also be run on its own from the repo root:

```bash
node --test backend/supabase/functions/_shared/engine/engine.test.ts
```

It loads `packages/wyrd_engine/test/vectors/reward_cases.json` and
`curves.json` — the same files the Dart engine tests use (ADR-004). Any rule
change must update both engines, bump `RULES_VERSION` and regenerate the
vectors (`dart run tool/generate_vectors.dart` in the Dart package).

`validate-sql.mjs` stubs only what Supabase provides (`auth.users`,
`auth.uid()` from the `request.jwt.claim.sub` GUC, the anon / authenticated /
service_role roles, the empty `supabase_realtime` publication and a new
project's default privileges, which expose nothing) and drives
`apply_progression` with the real TypeScript engine. It also:

* checks the grants against every `.from()`, `.rpc()` and Realtime call in
  `app/lib` (role `authenticated`) and `supabase/functions` (role
  `service_role`): a call without its grant, a grant nothing uses, anything
  for `anon` and any function `PUBLIC` can execute fail the run, and so does
  a Realtime publication that holds anything but the watched tables;
* requires UPDATE on every profile field the app syncs (the map
  `_serverProfile` in `sync_coordinator.dart` returns, conditional and
  null-aware entries included); an entry it cannot read fails the run;
* applies the migrations a second time with the old platform defaults
  (everything granted to all three roles) and requires identical privileges;
* exercises pg_cron's dispatch and the notification triggers against
  stand-ins for pg_net and Vault (URL, headers, payload, failure isolation),
  and checks that old dashboard webhooks to `notify` are dropped (also with
  an uppercase scheme or one or three slashes) while the triggers stay and
  webhooks to other URLs (`notify-moderators`, `notify` named only in a later
  argument, an empty host) and triggers without arguments survive (a
  `supabase_functions` stand-in);
* checks that reaction changes and deleted or hidden comments touch their
  feed event (`hall_changed_at`), and that `account_set_at` moves only when
  the account's own settings change;
* pulls, in small pages, a history whose quests were edited after they were
  done, and applies each page as the app does: every row arrives, each
  page's `cursor` and `has_more` come from its own rows, and no subtask or
  completion arrives without its quest, nor a completion without its
  evaluation.

It does not exercise real pg_cron, pg_net, Vault, Realtime or Storage.

## Database

### Migrations

Applied in filename order; each file is self-contained so it can be reviewed
and committed separately.

| File | Contents |
| --- | --- |
| `20261104000100_core_schema.sql` | enums, sync sequence/trigger, profiles, characters, quests, subtasks, completions, evaluations, ledger_entries, achievements, day_stats, snapshots, chronicles, ai_usage; signup trigger |
| `20261104000200_social_schema.sql` | guilds, guild_members, guild_invites, feed_events, reactions, comments, challenges, challenge_contributions, blocks, reports, notification_prefs, push_tokens, notification_deliveries |
| `20261104000300_rls.sql` | RLS on every table, policies, membership/block helpers, Realtime publication |
| `20261104000400_rpc_sync.sql` | `sync_push`, `sync_pull` |
| `20261104000500_rpc_progression.sql` | curves, condition, `apply_progression`, `undo_completion`, day-state/quota/facts helpers |
| `20261104000600_rpc_social.sql` | guild, invite, role, reaction, comment, challenge, safety, export and deletion RPCs |
| `20261104000700_cron.sql` | job functions and pg_cron schedules |
| `20261104000900_data_api_grants.sql` | the complete Data API surface: exactly what the app and the functions use |
| `20261104000910_cron_secret_key.sql` | internal Edge Function calls with a secret key from Vault, `set_function_credentials` |
| `20261104000920_notify_triggers.sql` | pg_net triggers on reactions, comments and milestones → `notify` |
| `20261104001000_push_token_unregister.sql` | `unregister_push_token`: sign-out removes this device's token from the account |
| `20261104001010_notification_prefs_rpc.sql` | `set_notification_prefs`: the app's notification switches and quiet hours |
| `20261104001020_reaction_signals.sql` | reactions and the personal tables leave the Realtime publication (`feed_events`, `comments`, `challenges` stay); each reaction change and each comment deletion or moderation hide touches its feed event (`feed_events.hall_changed_at`) |
| `20261104001030_reaction_rate_limit.sql` | `react` / `unreact`: at most 60 reaction changes per user per minute |
| `20261104001040_drop_notify_webhooks.sql` | drops dashboard webhooks whose URL is the `notify` function (they would double every push); others stay |
| `20261104001050_profile_account_set_at.sql` | `profiles.account_set_at`: when the name, weekly target, motivation or AI opt-in were last chosen, so a new device knows whether to take them over |
| `20261104001060_sync_pull_self_contained_pages.sql` | `sync_pull`: each page also brings the quests of its subtasks and completions and the evaluations of its completions when they lie in another page, so a new device gets the whole history |
| `20261104001070_sync_quest_patch.sql` | `sync_push` op `patch`: an edit of a quest, which merges its fields but can never create the quest |

New migrations: create with `supabase migration new <name>`. Never edit an
applied one. Every new table needs `enable row level security`, and every
table, column or function the app or a function reaches needs an explicit
GRANT to the role that uses it (new projects grant nothing by default);
revoke new functions from `public` and `anon`. `npm run validate:sql` fails
until the grants match the code.

### Access model

| Role | Gets |
| --- | --- |
| `anon` | nothing: guests never reach the server (ADR-003) |
| `authenticated` (the app) | SELECT on `guilds`, `feed_events`, `reactions`, `comments`, `challenges` (guild hall and its Realtime feed); SELECT(id) and UPDATE of the settings columns on `profiles`; EXECUTE on the user RPCs below |
| `service_role` (secret keys, the functions) | SELECT on the tables the functions read; INSERT on `notification_deliveries`; INSERT/UPDATE on `chronicles`; DELETE on `push_tokens`; EXECUTE on the service RPCs |

* Personal data reaches the app only through `sync_pull`; every client write
  goes through a SECURITY DEFINER RPC that checks the caller.
* Device tokens are credentials for the push service: clients never read
  `push_tokens` and change it only through `register_push_token` and
  `unregister_push_token`; `export_my_data` lists devices without tokens.
* Realtime publishes only what the guild hall watches: `feed_events`,
  `comments` and `challenges`. Reactions, and comments that are deleted or
  hidden, signal through their feed event; personal tables are not published
  at all. A feed event hidden by moderation sends no signal and stays in open
  halls until their next refetch.
* RLS still guards the rows: guild data is visible to members, public guild
  metadata to signed-in users. Feed events, reactions and comments from users
  the viewer blocked are filtered out (FR-7); the blocked party cannot see
  the block.
* Feed payloads are projected at write time from the effective share level
  (quest override → member's per-guild level → guild default):
  `full` → title, total XP, attribute deltas · `title_only` → title ·
  `completion_only` → tier and category · `private` → no event.
  Trivial completions are not posted.

### Sync protocol (client ↔ server)

`sync_push(changes jsonb)` — up to 500 outbox entries, applied in order:

```json
[{ "entity": "quest", "op": "upsert", "id": "<uuid>",
   "hlc": "2026-11-04T08:00:00.000Z-0000-<node>",
   "payload": { "title": "…", "tier": "daily", "created_at": "…" } },
 { "entity": "completion", "op": "insert", "id": "<uuid>",
   "payload": { "quest_id": "<uuid>", "completed_at": "…", "declared_minutes": 90,
                "tracked_minutes": null, "occurrence_day": null } },
 { "entity": "completion", "op": "undo", "id": "<uuid>", "payload": { "undone_at": "…" } }]
```

Entities: `quest` (`upsert`, `patch` = an edit carrying only the fields it changed,
which can never create the row, `delete` = tombstone), `subtask` (`upsert` / `delete`), `completion`
(`insert`, `undo`), `provisional_ledger` (offline engine grants, kept for audit
and marked `superseded`). Quests and subtasks merge field by field: a field
changes only when the change's HLC is strictly newer than that field's
(`field_hlc`). HLC strings are compared byte-wise, so they must be fixed-width
and lexicographically ordered. The response lists each change as `applied`,
`ignored` (replay / older clock) or `rejected` with `reason`
(`forbidden`, `missing_reference` + `retryable: true`, `conflict`, `invalid`).
`completions.local_day` is always recomputed from `profiles.time_zone`.

`sync_pull(cursor bigint default 0, max_rows int default 1000)` returns the
caller's rows with a `change_id` above `cursor`, oldest first and at most
`max_rows` across all tables, as `{ cursor, has_more, server_time, changes:
{ profiles, characters, quests, subtasks, completions, evaluations,
ledger_entries, achievements, day_stats, chronicles, notification_prefs } }`.
Loop while `has_more`, passing the returned `cursor`. Each page can be applied
on its own: it also brings the quest of every subtask and completion in it
whose own `change_id` comes in a later page (an edit moves a quest behind its
older completions), and the evaluation of every completion in it that lies
in another page. These extra rows never move `cursor` or `has_more`; each is
also sent in its own page.

### RPC reference (callable by signed-in users)

| Function | Notes |
| --- | --- |
| `undo_completion(completion_id)` | within 24 h; appends reversal entries, rolls back caches, removes the feed event |
| `set_rest_day(local_day, rest = true)` | ±7 days of today; returns the new condition |
| `update_character(name?, portrait?, equipped_title?, clear_title = false)` | title must be unlocked |
| `create_guild(name, description = '', visibility = 'private', language_tag?, emblem?, default_share_level = 'completion_only')` | caller becomes guild master |
| `create_invite(guild_id, expires_in_hours = 168, max_uses = 10)` / `revoke_invite(code)` | officers; codes are 12 Crockford base32 chars (60 bits) |
| `join_guild_by_code(code, share_level?)` | tolerant of case, spaces, O/0 and I/L/1 |
| `leave_guild(guild_id)` | a leaving master hands over; an empty guild is dissolved |
| `set_member_role(guild_id, user_id, role)` | guild master only; promoting to master transfers mastery |
| `remove_member(guild_id, user_id)` | master: anyone but self; officer: members |
| `guild_roster(guild_id)` | display data of co-members |
| `my_guilds()` | the caller's guilds with their own sharing / mute preferences (co-members cannot read these) |
| `react(event_id, kind)` / `unreact(event_id, kind)` | kinds: `honour`, `steel`, `flame`, `laurel`; 60 changes per minute per user (calls that change nothing are free) |
| `add_comment(event_id, body)` / `delete_comment(comment_id)` | 1–1000 chars; 30 per hour per guild; slow mode |
| `create_challenge(guild_id, title, metric, target, ends_at, starts_at = now(), description = '', metric_category?, metric_attribute?)` | officers; ≤ 5 active |
| `block_user(user_id)` / `unblock_user(user_id)` | |
| `report_content(target_type, target_id, reason, details?)` | public guilds auto-hide at 3 reporters |
| `register_push_token(token, platform)` | moves a device token to the current user |
| `unregister_push_token(token)` | deletes the token if it is the caller's (sign-out); silent otherwise |
| `set_notification_prefs(categories, quiet_hours_start?, quiet_hours_end?)` | merges known category switches (true/false) and sets quiet hours for the caller; the app mirrors its Notifications settings with it |
| `export_my_data()` | all user-owned rows as JSON |
| `delete_my_account()` | anonymises authored guild content ("Former member"), then deletes the user |

Errors use SQLSTATE `42501` (forbidden), `22023` (invalid), `P0002` (not
found), `54000` (limit) with a machine code in the error `hint`.

Service role only: `apply_progression`, `get_day_state`, `consume_ai_quota`,
`count_similar_completions`, `chronicle_facts`. The XP curve functions
(`level_for_xp` and friends) are internal: no Data API role may call them.

## Edge Functions

### `evaluate-completion`

`POST { "completion_id": "<uuid>", "client_proposal"?: {…}, "client_model"?: "<name>" }`
with the user's access token. `client_proposal` is a proposal the app obtained from the
user's own AI provider (bring your own key; the server never sees that key). It is validated
like model output and bounded by the server heuristic (difficulty ±1, estimate ≤ 2× the
heuristic's, min 15 min); it needs no server AI key and uses no server quota.
Returns `{ status, result, proposal, source, character, achievements }`
(`result` is the engine's RewardResult JSON, identical in shape to the Dart
engine's). Steps: ownership check → minimised inputs (title, notes ≤ 1 000
chars, tier, category hint, minutes, parent title, AI language, similar count)
→ 7-day proposal cache → Claude with structured output (`output_config.format`,
effort `low`, cached system prompt, 8 s timeout, one SDK retry, server-side
refusal fallback) → strict schema validation → TypeScript engine →
`apply_progression` (idempotent; recomputed if the day state changed
concurrently). Any AI failure, refusal, invalid output, user opt-out
(`profiles.ai_evaluation_enabled = false`) or the 120/day limit uses the
heuristic evaluator, recorded in `evaluations.fallback_reason`.
404 `completion_not_found` means "push the completion first".

### `generate-chronicle`

`POST { "period": "week" | "month" | "year", "period_start": "YYYY-MM-DD", "force"?: true }`
with the user's token, or `{ "mode": "pending" }` from an internal caller
(pg_cron, secret key as `apikey`). Facts come from `chronicle_facts` (SQL);
Claude (effort `medium`) may only narrate them in the user's AI language
(120–220 words, second person, no judgement or generic motivation). Text with
numbers that are not in the facts or of the wrong length is rejected in favour
of the deterministic English / Persian template. Body and facts are stored in
`chronicles`.

### `notify`

Internal only (a project secret key as `apikey`, or `INTERNAL_FUNCTION_SECRET`).
Enforces category toggles, per-guild mute, blocks, quiet hours in the user's
time zone (default 22:00–08:00), the daily cap (default 5, reminders exempt),
reaction batching (30 min) and at most one re-engagement message per 7 days;
renders `_shared/i18n/<locale>.json`; sends through FCM HTTP v1; logs every
decision in `notification_deliveries`.

## Production

The backend runs on a **Supabase Free project** created after 2026-05-30 (new
API keys, nothing exposed by default). No step needs a credit card. Two
workflows do everything; nothing is configured by hand in the dashboard:

| Workflow | When | What |
| --- | --- | --- |
| [`deploy-backend.yml`](../.github/workflows/deploy-backend.yml) | push to `main` touching `backend/**`, or by hand | `npm run verify`, then migrations, project config (auth, SMTP, API), Edge Functions, function secrets, Vault |
| [`backup.yml`](../.github/workflows/backup.yml) | daily 03:23 UTC, or by hand | encrypted dumps kept 14 days ([Backups](#backups)) |

Both skip with a notice until their secrets exist.

### One-time setup

1. Create the project at <https://supabase.com/dashboard/new> (Free plan; a
   long generated database password; the region closest to your users). The
   **project ref** is the id in the dashboard URL.
2. **API keys** (Project Settings → API Keys): copy the publishable key for
   the app builds. Under **Secret keys** create one for internal calls (for
   example `internal`) and copy it once: it becomes `SUPABASE_SECRET_KEY`. A
   separate key can be rotated without touching the functions' own `default`
   key.
3. A **personal access token** for the CLI:
   <https://supabase.com/dashboard/account/tokens>.
4. Store everything in GitHub (Settings → Secrets and variables → Actions,
   or `tool/setup_production.sh`):

| Name | Kind | Required | Used for |
| --- | --- | --- | --- |
| `SUPABASE_PROJECT_ID` | secret | yes | project ref (20 letters) |
| `SUPABASE_ACCESS_TOKEN` | secret | yes | CLI: link, config, functions, secrets, Vault, backups |
| `SUPABASE_DB_PASSWORD` | secret | yes | migrations and backups (through the session pooler) |
| `SUPABASE_SECRET_KEY` | secret | for cron and push | stored in Vault for pg_cron and the notification triggers |
| `WYRD_SITE_URL` | variable | recommended | the web app's origin: Auth site URL and redirects (default `https://wyrd-app.pages.dev`) |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_ADMIN_EMAIL`, `SMTP_SENDER_NAME` | secrets | for real users | custom SMTP (Brevo free or a Gmail app password now, Resend later); without it Supabase only mails your own team, 2 an hour |
| `WYRD_GOOGLE_CLIENT_ID` / `WYRD_GOOGLE_CLIENT_SECRET` | variable / secret | for Google sign-in | Google Cloud Web OAuth client (redirect URI `https://<ref>.supabase.co/auth/v1/callback`) |
| `WYRD_AUTH_GOOGLE` | variable | for Google sign-in | `true` turns the provider on (needs both values above) |
| `WYRD_GITHUB_CLIENT_ID` / `WYRD_GITHUB_CLIENT_SECRET` | variable / secret | for GitHub sign-in | GitHub OAuth app (GitHub reserves the `GITHUB_` prefix, hence `WYRD_`) |
| `WYRD_AUTH_GITHUB` | variable | for GitHub sign-in | `true` turns the provider on (needs both values above) |
| `ANTHROPIC_API_KEY` | secret | no | server-side AI evaluation and chronicles |
| `FCM_SERVICE_ACCOUNT` | secret | for push | Firebase service-account JSON for `notify` |
| `BACKUP_AGE_RECIPIENT` | variable | for backups | age public key(s) the dumps are encrypted to |

5. Run **Actions → Deploy backend (Supabase) → Run workflow**
   (`gh workflow run deploy-backend.yml`). The run summary lists what was
   configured; the Vault step prints the secret names and the pg_cron jobs.

### What a deploy does

1. `npm run verify` (tests, migrations and grants on PGlite, `deno check`).
2. `supabase link`, which also saves the session pooler URL: GitHub runners
   have no IPv6 and the direct database host is IPv6-only.
3. `supabase db push --remote --yes`: new migrations only.
4. `supabase config push --yes`: what `config.toml` declares (auth, SMTP,
   redirect URLs, API schemas). Keys it leaves out stay as they are.
5. `supabase functions deploy --use-api --yes`, with `verify_jwt` from
   `[functions.*]`. Functions are never deleted.
6. `supabase secrets set` for `ANTHROPIC_API_KEY` and `FCM_SERVICE_ACCOUNT`,
   only when present.
7. `private.set_function_credentials()` through `supabase db query --remote`:
   the project URL and `SUPABASE_SECRET_KEY` into Vault (idempotent).

The same by hand, from `backend/` with `SUPABASE_ACCESS_TOKEN`,
`SUPABASE_DB_PASSWORD` and the `env(...)` values of `config.toml` exported:

```bash
supabase link --project-ref <ref>
supabase db push --remote --yes
supabase config push --yes
supabase functions deploy --use-api --yes
```

### Changing things later

* **Domain**: set `WYRD_SITE_URL` to the new origin and re-run this workflow
  and the web deploy; nothing else holds the address.
* **Rotate the internal secret key**: create a new secret key, update
  `SUPABASE_SECRET_KEY`, re-run the deploy (Vault is updated), then delete the
  old key in the dashboard. The functions accept every current secret key.
* **Database password**: reset it in the dashboard, then update
  `SUPABASE_DB_PASSWORD`.
* A **new table, column use or RPC** needs its GRANT in a new migration; see
  [Migrations](#migrations).

### Free plan

* The project **pauses after about 7 idle days**; the daily backup counts as
  activity. A paused project is restored from the dashboard.
* **No automatic backups**: see below.
* The built-in mailer only reaches the project's team; real users need custom
  SMTP, which the Free plan allows.
* Edge Function invocations are counted per month; the notification triggers
  fire only for reactions, comments and challenge milestones.

## Backups

`backup.yml` takes the three dumps Supabase documents for a full restore,
through the Supavisor session pooler (IPv4, port 5432, address from the
Management API):

* `roles.sql.gz.age`: `supabase db dump --role-only` (no passwords)
* `schema.sql.gz.age`: `supabase db dump`
* `data.sql.gz.age`: `supabase db dump --data-only --use-copy`

Each is gzipped and encrypted with [age](https://github.com/FiloSottile/age)
to `BACKUP_AGE_RECIPIENT`, then uploaded as the artifact
`wyrd-db-backup-<date>` with a checksum manifest and kept 14 days. The
artifact is useless without the private key, so it may live in a public
repository. Download older copies before they expire if you need longer
retention.

**Key**: `age-keygen -o ~/.config/wyrd/wyrd-backup-key.txt` prints the public
key (`age1…`) for `BACKUP_AGE_RECIPIENT`; several keys separated by spaces all
can decrypt. Keep the key file offline (password manager); never in GitHub.

**Caveats**

* Vault secrets are stored encrypted with the project's root key, which is
  not exported. Restored into another project they cannot be decrypted:
  re-run the deploy there to store new ones.
* GitHub turns off scheduled workflows in a public repository after 60 days
  without commits; re-enable it in the Actions tab.

**Restore** into an empty project (needs `psql`, e.g. `brew install libpq` or
`apt install postgresql-client`):

```bash
# The artifact from Actions → Back up database → <run> → Artifacts, unzipped.
for part in roles schema data; do
  age --decrypt -i ~/.config/wyrd/wyrd-backup-key.txt "$part.sql.gz.age" | gunzip > "$part.sql"
done
# The target's session pooler URL: dashboard → Connect → Session pooler.
psql --single-transaction --variable ON_ERROR_STOP=1 \
  --file roles.sql --file schema.sql \
  --command 'SET session_replication_role = replica' \
  --file data.sql \
  --dbname 'postgresql://postgres.<ref>:<password>@<pooler-host>:5432/postgres'
```

Then point the GitHub secrets at the new project and run the deploy. If
`supabase migration list --remote` shows the restored migrations as not
applied, mark them first so `db push` does not run them again:
`supabase migration repair --remote --status applied <version>…`.
