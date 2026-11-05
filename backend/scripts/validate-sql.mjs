#!/usr/bin/env node
/**
 * Offline validation of the Supabase migrations with PGlite (Postgres 17 in
 * WebAssembly). No Docker or Supabase CLI required:
 *
 *   cd backend && npm install && npm run validate:sql
 *
 * 1. Creates a stub of what the Supabase platform provides: `auth.users`,
 *    `auth.uid()` reading the `request.jwt.claim.sub` GUC, the roles anon /
 *    authenticated / service_role (BYPASSRLS), the empty supabase_realtime
 *    publication and the default privileges of a project created after
 *    2026-05-30, which expose nothing in `public` to the Data API without an
 *    explicit GRANT.
 * 2. Applies every file in supabase/migrations/ in order. pg_cron / pg_net
 *    do not exist in PGlite; the cron migration skips scheduling itself.
 * 3. Checks the Data API grants (…_data_api_grants.sql) against the calls in
 *    app/lib and supabase/functions (scripts/data-api-surface.mjs): every
 *    table, column, RPC and Realtime table they use is granted to the role
 *    that uses it (authenticated for the app, service_role for the
 *    functions), nothing else is, anon gets nothing, no function is
 *    executable by PUBLIC and Realtime publishes exactly the watched tables.
 *    Every profile field the app syncs (_serverProfile's map, conditional
 *    entries included) must be updatable by authenticated.
 *    A second database with the old platform defaults (everything granted
 *    to all three roles, no publication) must end with the same privileges.
 * 4. Runs smoke checks as the real roles: RLS isolation, sync_push LWW and
 *    idempotency, sync_pull cursors, apply_progression driven by the real
 *    TypeScript engine (idempotency, stale-day protection, privacy
 *    projection, challenges), undo, social RPCs, device tokens,
 *    export/deletion, cron jobs, and the guild hall's Realtime signals:
 *    reaction changes and deleted or hidden comments touch their feed event.
 * 5. Exercises the internal Edge Function calls (pg_cron's chronicle dispatch,
 *    the notification triggers) against stand-ins for pg_net and Vault: no-op
 *    without them, then request URL, headers and payload, idempotent Vault
 *    credentials, the legacy-key fallback and a failing pg_net. Old
 *    dashboard webhooks to notify (a supabase_functions stand-in) are
 *    dropped, however libcurl lets their URL be spelled (scheme case, one
 *    to three slashes); the notification triggers and webhooks to other
 *    URLs, such as notify-moderators, are not.
 *
 * Exit code 0 means every migration applied and every check passed.
 */
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';

import * as engine from '../supabase/functions/_shared/engine/index.ts';
import { listSources, returnedMapKeys, returnedMapKeysIn, scanDataApi } from './data-api-surface.mjs';

const MIGRATIONS = fileURLToPath(new URL('../supabase/migrations/', import.meta.url));
const DROP_NOTIFY_WEBHOOKS = '20261104001040_drop_notify_webhooks.sql';
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const APP_LIB = fileURLToPath(new URL('../../app/lib/', import.meta.url));
const FUNCTIONS = fileURLToPath(new URL('../supabase/functions/', import.meta.url));
const APP_PROFILE_FIELDS = fileURLToPath(new URL('../../app/lib/data/sync/sync_coordinator.dart', import.meta.url));
const CURVES = JSON.parse(
  readFileSync(
    new URL('../../packages/wyrd_engine/test/vectors/curves.json', import.meta.url),
    'utf8',
  ),
);

const SUPABASE_STUB = /* sql */ `
  create role anon nologin noinherit;
  create role authenticated nologin noinherit;
  create role service_role nologin noinherit bypassrls;

  create schema auth;
  create table auth.users (
    id uuid primary key,
    email text,
    raw_user_meta_data jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
  );
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
  grant usage on schema auth to anon, authenticated, service_role;
  grant execute on all functions in schema auth to anon, authenticated, service_role;
  grant usage on schema public to anon, authenticated, service_role;
`;

// Default privileges of a project created since 2026-05-30 ("Automatically
// expose new tables" off): the Data API privileges are gone, these remain,
// and Postgres still lets PUBLIC execute every new function.
const NEW_PROJECT_DEFAULTS = /* sql */ `
  alter default privileges in schema public
    grant truncate, references, trigger, maintain on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant update on sequences to anon, authenticated, service_role;
`;

// Supabase creates this publication empty; Realtime streams the tables in
// it. The old-project database below has none, so the migrations' paths for
// a missing publication are applied as well.
const REALTIME_PUBLICATION = /* sql */ `
  create publication supabase_realtime;
`;

// Older projects (and a local stack without auto_expose_new_tables = false).
const OLD_PROJECT_DEFAULTS = /* sql */ `
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
  alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
`;

// ---------------------------------------------------------------------------
// Tiny test harness
// ---------------------------------------------------------------------------

const results = [];

function check(name, ok, detail = '') {
  results.push({ name, ok: Boolean(ok), detail });
  console.log(`${ok ? '  ok  ' : '  FAIL'} ${name}${detail ? ` — ${detail}` : ''}`);
}

/** Runs `fn(tx)` in a transaction as `role`, with auth.uid() = `uid`. */
function as(db, role, uid, fn) {
  return db.transaction(async (tx) => {
    await tx.exec(`set local role ${role};`);
    await tx.query(`select set_config('request.jwt.claim.sub', $1, true)`, [uid ?? '']);
    return fn(tx);
  });
}

async function one(db, role, uid, sql, params = []) {
  const res = await as(db, role, uid, (tx) => tx.query(sql, params));
  return res.rows[0];
}

async function rows(db, role, uid, sql, params = []) {
  const res = await as(db, role, uid, (tx) => tx.query(sql, params));
  return res.rows;
}

async function expectError(name, promise, pattern) {
  try {
    await promise;
    check(name, false, 'expected an error but the statement succeeded');
  } catch (error) {
    const message = String(error?.message ?? error);
    const ok = pattern === undefined || pattern.test(message);
    check(name, ok, ok ? `rejected (${message})` : `unexpected error: ${message}`);
  }
}

// ---------------------------------------------------------------------------
// Migrations
// ---------------------------------------------------------------------------

/** Applies every migration; with a `label`, reports one check for all of them. */
async function applyMigrations(db, label) {
  const files = readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort();
  for (const file of files) {
    const sql = readFileSync(MIGRATIONS + file, 'utf8');
    try {
      await db.exec(sql);
      if (!label) check(`migration ${file}`, true);
    } catch (error) {
      const position = Number(error.position);
      let context = '';
      if (Number.isFinite(position) && position > 0) {
        const line = sql.slice(0, position).split('\n').length;
        context = ` (line ${line}: ${sql.split('\n')[line - 1]?.trim()})`;
      }
      check(label ? `${label}: migration ${file}` : `migration ${file}`, false, `${error.message}${context}`);
      throw error;
    }
  }
  if (label) check(`${label}: all ${files.length} migrations apply`, true);
}

async function freshDatabase(defaults) {
  const db = await PGlite.create();
  await db.exec(SUPABASE_STUB + defaults);
  return db;
}

// ---------------------------------------------------------------------------
// Data API grants
// ---------------------------------------------------------------------------

const DATA_API_ROLES = ['anon', 'authenticated', 'service_role'];
const TABLE_PRIVILEGES = ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'];

/**
 * Every privilege anon, authenticated, service_role and PUBLIC hold on
 * objects in public and private, as sorted strings; equal snapshots mean
 * equal access.
 */
async function privilegeSnapshot(db) {
  const { rows: list } = await db.query(/* sql */ `
    select format('table %s.%s %s %s', n.nspname, c.relname, r.rolname, p.privilege) as entry
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    cross join unnest($1::text[]) r(rolname)
    cross join unnest($2::text[]) p(privilege)
    where n.nspname in ('public', 'private') and c.relkind in ('r', 'v', 'm', 'p', 'f')
      and has_table_privilege(r.rolname, c.oid, p.privilege)
    union all
    select format('column %s.%s.%s %s %s', n.nspname, c.relname, a.attname, r.rolname, p.privilege)
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    cross join unnest($1::text[]) r(rolname)
    cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'REFERENCES']) p(privilege)
    where n.nspname in ('public', 'private') and c.relkind in ('r', 'v', 'm', 'p', 'f')
      and has_column_privilege(r.rolname, c.oid, a.attnum, p.privilege)
      and not has_table_privilege(r.rolname, c.oid, p.privilege)
    union all
    select format('sequence %s.%s %s %s', n.nspname, c.relname, r.rolname, p.privilege)
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    cross join unnest($1::text[]) r(rolname)
    cross join unnest(array['USAGE', 'SELECT', 'UPDATE']) p(privilege)
    where n.nspname in ('public', 'private') and c.relkind = 'S'
      and has_sequence_privilege(r.rolname, c.oid, p.privilege)
    union all
    select format('function %s %s', p.oid::regprocedure, r.rolname)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    cross join unnest($1::text[]) r(rolname)
    where n.nspname in ('public', 'private') and has_function_privilege(r.rolname, p.oid, 'EXECUTE')
    union all
    select format('function %s PUBLIC', p.oid::regprocedure)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x
                  where x.grantee = 0 and x.privilege_type = 'EXECUTE')
    union all
    select format('schema %s %s %s', n.nspname, r.rolname, p.privilege)
    from pg_namespace n
    cross join unnest($1::text[]) r(rolname)
    cross join unnest(array['USAGE', 'CREATE']) p(privilege)
    where n.nspname in ('public', 'private') and has_schema_privilege(r.rolname, n.oid, p.privilege)
    union all
    select format('default %s %s %s %s', coalesce(n.nspname, '*'), d.defaclobjtype, x.grantee::regrole,
                  x.privilege_type)
    from pg_default_acl d left join pg_namespace n on n.oid = d.defaclnamespace
    cross join aclexplode(d.defaclacl) x
    where x.grantee <> 0 and x.grantee::regrole::text = any($1::text[])
    order by 1`, [DATA_API_ROLES, TABLE_PRIVILEGES]);
  return list.map((r) => r.entry);
}

/** Privileges one statement shape needs: { privilege: [columns] } ('*' = every column). */
function requiredPrivileges(usage) {
  const need = new Map();
  const add = (privilege, columns) => {
    const set = need.get(privilege) ?? new Set();
    for (const column of columns) set.add(column);
    need.set(privilege, set);
  };
  for (const verb of usage.verbs) {
    if (verb === 'select') add('SELECT', usage.columns.size > 0 ? usage.columns : ['*']);
    if (verb === 'insert' || verb === 'upsert') add('INSERT', ['any']);
    if (verb === 'update' || verb === 'upsert') add('UPDATE', ['any']);
    if (verb === 'delete') add('DELETE', ['table']);
  }
  if (usage.filters.size > 0) add('SELECT', usage.filters);
  return need;
}

/** Missing privileges of `role` for `usage`, as human-readable strings. */
async function missingPrivileges(db, role, usage) {
  const relation = `public.${usage.table}`;
  const { rows } = await db.query(
    `select attname from pg_attribute where attrelid = $1::regclass and attnum > 0 and not attisdropped`, [relation]);
  const columns = rows.map((r) => r.attname);
  const has = async (sql, params) => (await db.query(sql, params)).rows[0].ok;
  const missing = [];
  for (const [privilege, wanted] of requiredPrivileges(usage)) {
    for (const column of wanted) {
      if (column === 'any') {
        if (!(await has(`select has_any_column_privilege($1, $2::regclass, $3) as ok`, [role, relation, privilege]))) {
          missing.push(`${privilege} on any column`);
        }
      } else if (column === 'table') {
        if (!(await has(`select has_table_privilege($1, $2::regclass, $3) as ok`, [role, relation, privilege]))) {
          missing.push(privilege);
        }
      } else {
        for (const target of column === '*' ? columns : [column]) {
          if (!columns.includes(target)) {
            missing.push(`unknown column ${target}`);
          } else if (!(await has(`select has_column_privilege($1, $2::regclass, $3, $4) as ok`,
            [role, relation, target, privilege]))) {
            missing.push(`${privilege}(${target})`);
          }
        }
      }
    }
  }
  return [...new Set(missing)];
}

/** Table privilege kinds `role` holds on public.<table> (table- or column-level). */
async function heldPrivilegeKinds(db, role) {
  const { rows } = await db.query(/* sql */ `
    select c.relname as table, p.privilege
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    cross join unnest($2::text[]) p(privilege)
    where n.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'p', 'f')
      and (has_table_privilege($1, c.oid, p.privilege)
           or (p.privilege in ('SELECT', 'INSERT', 'UPDATE', 'REFERENCES')
               and has_any_column_privilege($1, c.oid, p.privilege)))
    order by 1, 2`, [role, TABLE_PRIVILEGES]);
  return rows;
}

// The entry shapes returnedMapKeys reads (and the ones it skips or reports)
// in the Dart map literal _serverProfile returns.
const PROFILE_MAP_SAMPLE = `
Future<Map<String, Object?>> _serverProfile(Ref ref, UserProfile p) async {
  final zone = await zoneOf(p); // isn't in the map: {'not_a_field': 1}
  return {
    // Comments may hold quotes ('x': y), commas, colons: and "strings".
    if (p.name.isNotEmpty) 'display_name': p.name.length > 40 ? p.name.substring(0, 40) : p.name,
    if (p.region != null && (p.strict || !p.legacy)) 'region': p.region,
    if (p.jalali) 'calendar': 'jalali' else 'week_start': 6,
    'time_zone': ?zone,
    "locale": 'fa, en',
    'motivation': {'tone': p.tone, 'drivers': [p.a, p.b]},
    ...p.extra,
    if (p.more != null) ...?p.more,
    /* 'commented_out': 1, /* nested */ */
    for (final f in flags) f: true,
    kHandle: handle,
    'ai_evaluation_enabled': f(p.ai, (p.a, p.b)),
  };
}
`;
const PROFILE_MAP_SAMPLE_KEYS = {
  keys: ['display_name', 'region', 'calendar', 'week_start', 'time_zone', 'locale', 'motivation', 'ai_evaluation_enabled'],
  unreadable: ['for (final f in flags) f: true', 'kHandle: handle'],
};

async function publicFunctions(db) {
  const { rows } = await db.query(/* sql */ `
    select p.oid, p.proname as name, p.oid::regprocedure::text as signature,
           has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated,
           has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' order by 2, 3`);
  return rows;
}

/**
 * The grants match what the code uses: the app (authenticated) and the Edge
 * Functions (service_role) can make every call they make, and no role holds
 * table privileges or service RPCs nobody uses.
 */
async function checkDataApi(db) {
  const app = scanDataApi(listSources(APP_LIB, ['.dart']), REPO);
  const functions = scanDataApi(listSources(FUNCTIONS, ['.ts']), REPO, {
    dynamicRpcAllowed: ['backend/supabase/functions/_shared/supabase.ts'],
  });
  const scanErrors = [...app.errors, ...functions.errors];
  check('Data API calls in app/lib and supabase/functions are all readable',
    scanErrors.length === 0 && app.tables.length > 0 && app.rpcs.length > 0 && functions.tables.length > 0,
    scanErrors.join('; ') || `app: ${app.tables.length} table calls, ${app.rpcs.length} RPC calls, `
      + `${app.realtime.length} Realtime tables; functions: ${functions.tables.length} table calls, `
      + `${functions.rpcs.length} RPC calls`);

  const { rows: tableRows } = await db.query(
    `select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'p', 'f')`);
  const knownTables = new Set(tableRows.map((r) => r.relname));
  const fns = await publicFunctions(db);

  for (const [role, scan, who, calls, uses] of [
    ['authenticated', app, 'the app', 'calls', 'does not use'],
    ['service_role', functions, 'the Edge Functions', 'call', 'do not use'],
  ]) {
    // Every table call works for the role that makes it.
    const problems = [];
    for (const usage of scan.tables) {
      if (!knownTables.has(usage.table)) {
        problems.push(`${usage.where}: unknown table ${usage.table}`);
        continue;
      }
      const missing = await missingPrivileges(db, role, usage);
      if (missing.length > 0) problems.push(`${usage.where} ${usage.table}: ${missing.join(', ')}`);
    }
    for (const watch of scan.realtime) {
      const r = await db.query(`select to_regclass($1) is not null and has_table_privilege($2, $1, 'SELECT') as ok`,
        [`public.${watch.table}`, role]);
      if (!r.rows[0].ok) problems.push(`${watch.where}: Realtime on ${watch.table} needs SELECT`);
    }
    check(`${role} may make every table and Realtime call of ${who}`, problems.length === 0, problems.join('; '));

    // ...and every RPC.
    const missingRpcs = [];
    for (const call of scan.rpcs) {
      const overloads = fns.filter((f) => f.name === call.name);
      if (overloads.length === 0) missingRpcs.push(`${call.where}: unknown function ${call.name}`);
      else if (!overloads.some((f) => f[role])) missingRpcs.push(`${call.where}: ${call.name}`);
    }
    check(`${role} may execute every RPC ${who} ${calls}`, missingRpcs.length === 0, missingRpcs.join('; '));

    // Nothing beyond what the code uses (grant exactly what is needed).
    const used = new Map();
    for (const usage of scan.tables) {
      const kinds = used.get(usage.table) ?? new Set();
      for (const privilege of requiredPrivileges(usage).keys()) kinds.add(privilege);
      used.set(usage.table, kinds);
    }
    for (const watch of scan.realtime) used.set(watch.table, (used.get(watch.table) ?? new Set()).add('SELECT'));
    const extra = (await heldPrivilegeKinds(db, role))
      .filter((h) => !(used.get(h.table)?.has(h.privilege)))
      .map((h) => `${h.privilege} on ${h.table}`);
    check(`${role} holds no table privilege ${who} ${uses}`, extra.length === 0, extra.join(', '));
  }

  // Realtime streams exactly what is watched: a published table nobody can
  // or does subscribe to only adds WAL decoding work.
  const { rows: published } = await db.query(`select tablename from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' order by 1`);
  const watched = [...new Set([...app.realtime, ...functions.realtime].map((w) => w.table))].sort();
  check('the Realtime publication holds exactly the tables the app watches',
    published.map((r) => r.tablename).join(',') === watched.join(','),
    `published: ${published.map((r) => r.tablename).join(', ') || 'none'}; watched: ${watched.join(', ')}`);

  // Service RPCs stay with the server; the user API stays with signed-in users.
  const serverOnly = new Set(functions.rpcs.map((c) => c.name).filter((n) => !app.rpcs.some((c) => c.name === n)));
  const leaked = fns.filter((f) => serverOnly.has(f.name) && f.authenticated).map((f) => f.signature);
  check('service RPCs are not executable by authenticated', leaked.length === 0, leaked.join(', '));
  const serviceExtra = fns.filter((f) => f.service_role && !functions.rpcs.some((c) => c.name === f.name))
    .map((f) => f.signature);
  check('service_role executes only the RPCs the Edge Functions call', serviceExtra.length === 0, serviceExtra.join(', '));

  const anonFunctions = fns.filter((f) => f.anon).map((f) => f.signature);
  const anonTables = (await heldPrivilegeKinds(db, 'anon')).map((h) => `${h.privilege} on ${h.table}`);
  check('anon has no table privileges and executes no function in public',
    anonTables.length === 0 && anonFunctions.length === 0, [...anonTables, ...anonFunctions].join(', '));

  const { rows: publicExecutable } = await db.query(/* sql */ `
    select p.oid::regprocedure::text as signature
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x
                  where x.grantee = 0 and x.privilege_type = 'EXECUTE')`);
  check('no function in public or private is executable by PUBLIC', publicExecutable.length === 0,
    publicExecutable.map((r) => r.signature).join(', '));

  const { rows: sequences } = await db.query(/* sql */ `
    select c.relname, r.rolname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    cross join unnest($1::text[]) r(rolname)
    where n.nspname = 'public' and c.relkind = 'S'
      and (has_sequence_privilege(r.rolname, c.oid, 'USAGE') or has_sequence_privilege(r.rolname, c.oid, 'SELECT')
           or has_sequence_privilege(r.rolname, c.oid, 'UPDATE'))`, [DATA_API_ROLES]);
  check('no Data API role can use a sequence', sequences.length === 0,
    sequences.map((s) => `${s.rolname} on ${s.relname}`).join(', '));

  // The profile fields the app syncs (sync_coordinator.dart → remote_api.dart),
  // read by returnedMapKeys, which first has to read a sample of every entry
  // shape correctly.
  const sample = returnedMapKeysIn(PROFILE_MAP_SAMPLE, '_serverProfile');
  check('returnedMapKeys reads plain, conditional and null-aware entries, skips spreads, reports the rest',
    JSON.stringify(sample) === JSON.stringify(PROFILE_MAP_SAMPLE_KEYS)
      && returnedMapKeysIn('void _other() {}', '_serverProfile') === null,
    JSON.stringify(sample));
  const profile = returnedMapKeys(APP_PROFILE_FIELDS, '_serverProfile');
  const fields = profile?.keys ?? [];
  const problems = profile === null
    ? ['no _serverProfile(…) { … return { … }; } in sync_coordinator.dart; extend returnedMapKeys']
    : profile.unreadable.map((e) => `cannot read the entry "${e}"; extend returnedMapKeys in data-api-surface.mjs`);
  for (const field of fields) {
    const r = await db.query(
      `select exists (select 1 from pg_attribute where attrelid = 'public.profiles'::regclass and attname = $1
                       and not attisdropped)
              and has_column_privilege('authenticated', 'public.profiles', $1, 'UPDATE') as ok`, [field]);
    if (!r.rows[0].ok) problems.push(`cannot update profiles.${field}`);
  }
  check('authenticated may update every profile field the app syncs',
    fields.length > 0 && problems.length === 0, problems.join('; ') || fields.join(', '));

  // Informational: user RPCs granted for features the app does not call yet.
  const unused = fns.filter((f) => f.authenticated && !app.rpcs.some((c) => c.name === f.name)
    && !['is_guild_member', 'guild_role_of', 'is_guild_officer', 'is_blocked_by_me'].includes(f.name)).map((f) => f.name);
  if (unused.length > 0) console.log(`  info user RPCs not called from app/lib yet: ${unused.join(', ')}`);
  return { fields };
}

// ---------------------------------------------------------------------------
// Smoke checks
// ---------------------------------------------------------------------------

const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';
const C = '00000000-0000-4000-8000-00000000000c';
/** A user who only ever changes device settings (account_set_at checks). */
const F = '00000000-0000-4000-8000-00000000000f';
const OBJECTIVE = '10000000-0000-4000-8000-000000000001';
const QUEST = '10000000-0000-4000-8000-000000000002';
const QUEST_FULL = '10000000-0000-4000-8000-000000000003';
const SUBTASK = '20000000-0000-4000-8000-000000000001';
const DONE_1 = '30000000-0000-4000-8000-000000000001';
const DONE_2 = '30000000-0000-4000-8000-000000000002';
const DONE_3 = '30000000-0000-4000-8000-000000000003';
const DONE_DUP = '30000000-0000-4000-8000-000000000004';
const PROVISIONAL = '40000000-0000-4000-8000-000000000001';

const hlc = (ms, counter = 0, node = 'devA') =>
  `${new Date(ms).toISOString()}-${counter.toString(16).padStart(4, '0')}-${node}`;

/** Server-side flow of evaluate-completion, minus the AI call. */
async function evaluateAndApply(db, completionId, { staleDayChangeId } = {}) {
  const c = await one(db, 'service_role', null, `
    select c.*, q.title, q.notes, q.tier, q.category as quest_category, q.created_at as quest_created_at,
           q.due_at, q.recurrence, q.intention, q.estimated_minutes
    from public.completions c join public.quests q on q.id = c.quest_id where c.id = $1`, [completionId]);
  const proposal = engine.evaluateHeuristic({
    title: c.title,
    notes: c.notes ?? '',
    tier: c.tier,
    categoryHint: c.quest_category,
    declaredMinutes: c.declared_minutes,
    estimatedMinutes: c.estimated_minutes,
  });
  const day = (await one(db, 'service_role', null,
    `select public.get_day_state($1, $2) as s`, [c.owner_id, c.local_day])).s;
  const facts = {
    tier: c.tier,
    createdAt: new Date(c.quest_created_at),
    completedAt: new Date(c.completed_at),
    declaredMinutes: c.declared_minutes,
    trackedMinutes: c.tracked_minutes,
    dueAt: c.due_at ? new Date(c.due_at) : null,
    isRecurringOccurrence: c.recurrence !== null || c.occurrence_day !== null,
    hasImplementationIntention: Boolean(c.intention),
  };
  const result = engine.evaluate(proposal, facts, engine.dayStateFromJson(day));
  const meta = {
    latency_ms: 3,
    fallback_reason: 'validation',
    day_change_id: staleDayChangeId !== undefined ? staleDayChangeId : day.changeId,
  };
  const applied = (await one(db, 'service_role', null,
    `select public.apply_progression($1, $2, $3, 'heuristic', null, $4) as r`,
    [completionId, engine.resultToJson(result), engine.proposalToJson(proposal), meta])).r;
  return { applied, result, proposal };
}

/**
 * When a feed event last signalled a change in its guild hall
 * (…_reaction_signals.sql), or null; `quiet` clears it before a change.
 */
async function hallChangedAt(db, eventId) {
  const row = await one(db, 'postgres', null,
    'select hall_changed_at from public.feed_events where id = $1', [eventId]);
  return row?.hall_changed_at == null ? null : new Date(row.hall_changed_at).toISOString();
}

const quiet = (db, eventId) =>
  db.query('update public.feed_events set hall_changed_at = null where id = $1', [eventId]);

async function smoke(db, { profileFields }) {
  // --- accounts --------------------------------------------------------------
  await db.query(`insert into auth.users (id, email, raw_user_meta_data) values
    ($1, 'a@example.test', '{"display_name":"Arin","time_zone":"Asia/Tehran","locale":"fa"}'),
    ($2, 'b@example.test', '{"display_name":"Bahar"}'),
    ($3, 'c@example.test', '{}')`, [A, B, C]);
  const profileA = await one(db, 'postgres', null, 'select * from public.profiles where id = $1', [A]);
  check('signup trigger creates profile with metadata', profileA?.display_name === 'Arin'
    && profileA?.time_zone === 'Asia/Tehran' && profileA?.locale === 'fa');
  const charA = await one(db, 'postgres', null, 'select * from public.characters where owner_id = $1', [A]);
  check('signup trigger creates character', charA?.level === 1 && Number(charA?.total_xp) === 0);

  // The app's profile sync, as PostgREST runs it (remote_api.dart):
  // update profiles set <fields> where id = <own id>.
  const sample = {
    display_name: 'Arin', locale: 'fa', ai_locale: 'fa', calendar: 'jalali', time_zone: 'Asia/Tehran',
    week_start: 6, weekly_target: 5, motivation: { tone: 'warm', drivers: ['mastery'] }, ai_evaluation_enabled: true,
  };
  const fields = profileFields.filter((f) => f in sample);
  const profileUpdate = `update public.profiles p set ${fields.map((f) => `${f} = r.${f}`).join(', ')}
    from jsonb_populate_record(null::public.profiles, $1) r where p.id = $2`;
  const own = await as(db, 'authenticated', A, (tx) => tx.query(profileUpdate, [sample, A]));
  const foreign = await as(db, 'authenticated', B, (tx) => tx.query(profileUpdate, [sample, A]));
  check('the app can update its own profile settings and no one else\'s',
    fields.length > 0 && own.affectedRows === 1 && foreign.affectedRows === 0,
    `fields=${fields.join(',')}; own=${own.affectedRows}; foreign=${foreign.affectedRows}`);
  await expectError('clients cannot change server-maintained profile columns',
    as(db, 'authenticated', A, (tx) => tx.query(`update public.profiles set change_id = 0 where id = $1`, [A])),
    /permission denied/);

  // account_set_at (…_profile_account_set_at.sql) moves only when one of the
  // account's own settings changes, never for the device's language or time
  // zone, so a new device can tell a chosen account from a fresh one.
  await db.query(`insert into auth.users (id, email) values ($1, 'f@example.test')`, [F]);
  const fresh = await one(db, 'postgres', null, 'select account_set_at from public.profiles where id = $1', [F]);
  await as(db, 'authenticated', F, (tx) => tx.query(
    `update public.profiles set locale = 'fa', time_zone = 'Asia/Tehran', week_start = 6 where id = $1`, [F]));
  const afterDevice = await one(db, 'postgres', null, 'select account_set_at from public.profiles where id = $1', [F]);
  await as(db, 'authenticated', F, (tx) => tx.query(
    `update public.profiles set ai_evaluation_enabled = false where id = $1`, [F]));
  const afterAccount = await one(db, 'postgres', null, 'select account_set_at from public.profiles where id = $1', [F]);
  check('account_set_at marks only changes to the account\'s own settings',
    fresh?.account_set_at == null && afterDevice?.account_set_at == null && afterAccount?.account_set_at != null,
    `fresh=${fresh?.account_set_at}; after device fields=${afterDevice?.account_set_at}; after AI opt-out=${afterAccount?.account_set_at}`);
  await expectError('clients cannot set account_set_at themselves',
    as(db, 'authenticated', F, (tx) => tx.query('update public.profiles set account_set_at = now() where id = $1', [F])),
    /permission denied/);
  await db.query('delete from auth.users where id = $1', [F]); // keeps later counts to A, B and C

  // Notification settings from the app (sync_coordinator.dart calls
  // set_notification_prefs): known categories merge into the stored ones,
  // unknown keys and non-booleans are dropped, and quiet hours stay unless
  // given again. The table itself stays closed to clients.
  await as(db, 'authenticated', A, (tx) => tx.query(
    `select public.set_notification_prefs($1::jsonb, '23:30', '07:00')`,
    [{ guild_comments: false, weekly_summary: false, bogus: true, reminders: 'yes' }]));
  await as(db, 'authenticated', A, (tx) => tx.query(
    'select public.set_notification_prefs($1::jsonb)', [{ guild_reactions: false }]));
  const prefsA = await one(db, 'postgres', null, 'select * from public.notification_prefs where user_id = $1', [A]);
  const categoriesA = prefsA?.categories ?? {};
  check('the app mirrors its notification switches and quiet hours',
    categoriesA.guild_comments === false && categoriesA.weekly_summary === false
      && categoriesA.guild_reactions === false && !('bogus' in categoriesA) && categoriesA.reminders !== 'yes'
      && String(prefsA?.quiet_hours_start).startsWith('23:30') && String(prefsA?.quiet_hours_end).startsWith('07:00'),
    JSON.stringify(prefsA));
  await expectError('notification settings change only through set_notification_prefs',
    as(db, 'authenticated', A, (tx) => tx.query('update public.notification_prefs set daily_cap = 50 where user_id = $1', [A])),
    /permission denied/);

  // Device tokens (push_platform.dart) are push credentials: clients reach
  // them only through register_push_token and unregister_push_token, and
  // unregistering removes the caller's own token, never another account's.
  const tokenA = 'fcm-token-of-device-a';
  const tokenB = 'fcm-token-of-device-b';
  await one(db, 'authenticated', A, `select public.register_push_token($1, 'android')`, [tokenA]);
  await one(db, 'authenticated', B, `select public.register_push_token($1, 'web')`, [tokenB]);
  await expectError('clients cannot read device tokens',
    rows(db, 'authenticated', A, 'select token from public.push_tokens'), /permission denied/);
  await expectError('clients cannot delete device tokens directly',
    as(db, 'authenticated', A, (tx) => tx.query('delete from public.push_tokens')), /permission denied/);
  await one(db, 'authenticated', A, 'select public.unregister_push_token($1)', [tokenB]);
  const afterForeign = await rows(db, 'postgres', null, 'select token from public.push_tokens order by token');
  await one(db, 'authenticated', A, 'select public.unregister_push_token($1)', [tokenA]);
  const afterOwn = await rows(db, 'postgres', null, 'select token from public.push_tokens order by token');
  check('unregister_push_token removes the caller\'s own token but not another user\'s',
    afterForeign.map((t) => t.token).join(',') === `${tokenA},${tokenB}`
      && afterOwn.map((t) => t.token).join(',') === tokenB,
    `after A unregisters B's token: ${afterForeign.map((t) => t.token).join(',')}; `
      + `after its own: ${afterOwn.map((t) => t.token).join(',')}`);

  // --- curves ---------------------------------------------------------------
  const curveRows = await rows(db, 'postgres', null, `
    select n, public.xp_to_advance_level(n) as level_cost, public.xp_to_advance_rank(n) as rank_cost
    from generate_series(1, 50) n order by n`);
  check('SQL level curve matches curves.json (n = 1..50)',
    curveRows.every((r, i) => r.level_cost === CURVES.levelCosts[i]));
  check('SQL rank curve matches curves.json (n = 1..50)',
    curveRows.every((r, i) => r.rank_cost === CURVES.rankCosts[i]));
  let levelAtOk = true;
  for (const [xp, level] of Object.entries(CURVES.levelAt)) {
    const r = await one(db, 'postgres', null, 'select public.level_for_xp($1) as l', [Number(xp)]);
    if (r.l !== level) levelAtOk = false;
  }
  check('SQL level_for_xp matches curves.json levelAt', levelAtOk);
  await expectError('the XP curve functions are not a public endpoint',
    one(db, 'anon', null, 'select public.level_for_xp(1000000000)'), /permission denied/);

  // --- sync_push --------------------------------------------------------------
  const t0 = Date.parse('2026-11-04T05:00:00.000Z');
  const now = Date.now();
  const recent = new Date(now - 3 * 60 * 60 * 1000).toISOString();
  const batch = [
    { entity: 'quest', op: 'upsert', id: OBJECTIVE, hlc: hlc(t0, 1),
      payload: { title: 'Ship the side business', tier: 'objective', category: 'work',
                 created_at: new Date(now - 48 * 3600e3).toISOString() } },
    { entity: 'quest', op: 'upsert', id: QUEST, hlc: hlc(t0, 2),
      payload: { title: 'Study electronics 90m', tier: 'daily', parent_id: OBJECTIVE,
                 category: 'study', created_at: new Date(now - 24 * 3600e3).toISOString() } },
    { entity: 'subtask', op: 'upsert', id: SUBTASK, hlc: hlc(t0, 3),
      payload: { quest_id: QUEST, title: 'Chapter 3', position: 1 } },
    { entity: 'completion', op: 'insert', id: DONE_1, hlc: hlc(t0, 4),
      payload: { quest_id: QUEST, completed_at: recent, declared_minutes: 90 } },
  ];
  const push1 = (await one(db, 'authenticated', A, 'select public.sync_push($1) as r', [batch])).r;
  check('sync_push applies quests, subtask and completion',
    push1.results.every((r) => r.status === 'applied'), JSON.stringify(push1.results.map((r) => r.status)));
  const push2 = (await one(db, 'authenticated', A, 'select public.sync_push($1) as r', [batch])).r;
  check('sync_push replay is a no-op (idempotent)',
    push2.results.every((r) => r.status === 'ignored'), JSON.stringify(push2.results.map((r) => r.status)));

  // Field-level LWW: two devices edit different fields; an older HLC loses.
  await one(db, 'authenticated', A, 'select public.sync_push($1) as r', [[
    { entity: 'quest', op: 'upsert', id: QUEST, hlc: hlc(t0 + 2000, 0, 'devB'), payload: { notes: 'from device B' } },
    { entity: 'quest', op: 'upsert', id: QUEST, hlc: hlc(t0 + 1000, 0, 'devA'),
      payload: { title: 'Study electronics (90 min)', notes: 'stale note' } },
  ]]);
  const merged = await one(db, 'postgres', null, 'select title, notes, hlc from public.quests where id = $1', [QUEST]);
  check('field-level LWW merges concurrent edits',
    merged.title === 'Study electronics (90 min)' && merged.notes === 'from device B',
    `title=${merged.title}; notes=${merged.notes}`);
  check('row hlc tracks the newest clock', merged.hlc === hlc(t0 + 2000, 0, 'devB'));

  const localDay = await one(db, 'postgres', null,
    `select local_day, (completed_at at time zone 'Asia/Tehran')::date as expected from public.completions where id = $1`, [DONE_1]);
  check('completion local_day is computed in the user time zone',
    String(localDay.local_day) === String(localDay.expected));

  // --- isolation ----------------------------------------------------------------
  // Personal data reaches clients only through sync_pull; the tables themselves
  // are not exposed to the Data API at all (…_data_api_grants.sql).
  await expectError('clients read quests only through sync_pull',
    rows(db, 'authenticated', B, 'select id from public.quests'), /permission denied/);
  await expectError('clients read completions only through sync_pull',
    rows(db, 'authenticated', B, 'select id from public.completions'), /permission denied/);
  await expectError('clients cannot update quests directly',
    as(db, 'authenticated', B, (tx) => tx.query(`update public.quests set title = 'hijacked' where id = $1`, [QUEST])),
    /permission denied/);
  const bPush = (await one(db, 'authenticated', B, 'select public.sync_push($1) as r', [[
    { entity: 'quest', op: 'upsert', id: QUEST, hlc: hlc(t0 + 9e9), payload: { title: 'hijacked' } },
  ]])).r;
  check('sync_push rejects writes to another user\'s quest', bPush.results[0].reason === 'forbidden');
  await expectError('anon has no table access',
    rows(db, 'anon', null, 'select * from public.quests'), /permission denied/);
  await expectError('clients cannot write ledger_entries',
    as(db, 'authenticated', A, (tx) => tx.query(`insert into public.ledger_entries
      (owner_id, attribute, amount, raw_amount, rule_version, local_day, completion_id)
      values ($1, 'strength', 999, 999, 'x', current_date, $2)`, [A, DONE_1])), /permission denied/);
  await expectError('clients cannot write characters',
    as(db, 'authenticated', A, (tx) => tx.query(`update public.characters set total_xp = 1e6`)), /permission denied/);
  await expectError('clients cannot write feed_events',
    as(db, 'authenticated', A, (tx) => tx.query(`insert into public.feed_events (guild_id, kind) values (gen_random_uuid(), 'completion')`)),
    /permission denied/);
  await expectError('clients cannot call apply_progression',
    one(db, 'authenticated', A, `select public.apply_progression($1, '{}', '{}', 'ai', null)`, [DONE_1]),
    /permission denied/);
  await expectError('the service role cannot rewrite completions',
    as(db, 'service_role', null, (tx) => tx.query(`update public.completions set declared_minutes = 600 where id = $1`, [DONE_1])),
    /permission denied/);
  await expectError('completion facts are immutable even for the database owner',
    as(db, 'postgres', null, (tx) => tx.query(`update public.completions set declared_minutes = 600 where id = $1`, [DONE_1])),
    /immutable/);

  // --- sync_pull ---------------------------------------------------------------
  const pull = (await one(db, 'authenticated', A, 'select public.sync_pull(0) as r')).r;
  check('sync_pull returns own rows per table',
    pull.changes.quests.length === 2 && pull.changes.subtasks.length === 1
      && pull.changes.completions.length === 1 && pull.changes.profiles.length === 1
      && pull.changes.characters.length === 1 && pull.cursor > 0 && pull.has_more === false,
    `quests=${pull.changes.quests.length} cursor=${pull.cursor}`);
  const pullAgain = (await one(db, 'authenticated', A, 'select public.sync_pull($1) as r', [pull.cursor])).r;
  check('sync_pull after cursor returns nothing new',
    Object.values(pullAgain.changes).every((list) => list.length === 0) && pullAgain.cursor === pull.cursor);
  const paged = (await one(db, 'authenticated', A, 'select public.sync_pull(0, 2) as r')).r;
  check('sync_pull pages with has_more',
    paged.has_more === true && Object.values(paged.changes).flat().length === 2);
  const pullB = (await one(db, 'authenticated', B, 'select public.sync_pull(0) as r')).r;
  check('sync_pull never returns other users\' rows', pullB.changes.quests.length === 0);

  // --- guild setup ---------------------------------------------------------------
  const guild = await one(db, 'authenticated', A, `select * from public.create_guild('The Iron Pact', 'Study together')`);
  check('create_guild makes the creator guild master',
    (await one(db, 'postgres', null, 'select role from public.guild_members where guild_id = $1 and user_id = $2',
      [guild.id, A]))?.role === 'guild_master');
  const invite = await one(db, 'authenticated', A, 'select * from public.create_invite($1)', [guild.id]);
  check('invite codes are 12 Crockford base32 chars (60 bits)', /^[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){2}$/.test(invite.code), invite.code);
  await expectError('members cannot create invites',
    one(db, 'authenticated', C, 'select * from public.create_invite($1)', [guild.id]), /officers/);
  const typed = ` ${invite.code.replaceAll('-', ' ').toLowerCase()} `;
  await one(db, 'authenticated', B, 'select * from public.join_guild_by_code($1)', [typed]);
  check('join_guild_by_code accepts human-typed codes',
    (await rows(db, 'postgres', null, 'select 1 from public.guild_members where guild_id = $1', [guild.id])).length === 2);
  await expectError('unknown invite codes are rejected',
    one(db, 'authenticated', C, 'select * from public.join_guild_by_code($1)', ['AAAA-BBBB-CCCC']), /not valid/);
  await expectError('co-members cannot read each other\'s guild preferences',
    rows(db, 'authenticated', B, 'select muted from public.guild_members where user_id = $1', [A]), /permission denied/);
  const mine = await rows(db, 'authenticated', B, 'select * from public.my_guilds()');
  check('my_guilds returns own membership and preferences',
    mine.length === 1 && mine[0].effective_share_level === 'completion_only' && mine[0].member_count === 2);
  await one(db, 'authenticated', A, `select * from public.create_challenge($1, '100-Hour Study', 'minutes_in_category', 300,
    now() + interval '30 days', now() - interval '1 day', '', 'study')`, [guild.id]);

  // --- apply_progression ----------------------------------------------------------
  const first = await evaluateAndApply(db, DONE_1);
  check('apply_progression applies the engine result', first.applied.status === 'applied',
    `${first.applied.status}; totalXp=${engine.totalXp(first.result)}`);
  const ledger = await rows(db, 'postgres', null,
    `select attribute, amount, raw_amount from public.ledger_entries where completion_id = $1 and status = 'confirmed'`, [DONE_1]);
  check('one confirmed ledger row per grant', ledger.length === first.result.grants.length
    && ledger.every((l) => first.result.grants.some((g) => g.attribute === l.attribute && g.amount === l.amount)));
  const charAfter = await one(db, 'postgres', null, 'select total_xp, level, attr_xp from public.characters where owner_id = $1', [A]);
  check('character cache updated (total XP and curve level)',
    Number(charAfter.total_xp) === engine.totalXp(first.result)
      && charAfter.level === engine.level(engine.totalXp(first.result)).step);
  const dayRow = await one(db, 'postgres', null,
    `select minutes, completions, similarity_counts from public.day_stats where owner_id = $1`, [A]);
  check('day_stats mirrors RewardResult.applyTo',
    dayRow.minutes === first.result.effectiveMinutes && dayRow.completions === 1
      && dayRow.similarity_counts[first.result.similarityKey] === 1);
  const achievements = await rows(db, 'postgres', null,
    'select achievement_id, title_id from public.achievements where owner_id = $1', [A]);
  check('first_oath achievement unlocked with its title',
    achievements.some((a) => a.achievement_id === 'first_oath' && a.title_id === 'sworn'));

  const again = (await one(db, 'service_role', null,
    `select public.apply_progression($1, $2, '{}', 'heuristic', null) as r`,
    [DONE_1, engine.resultToJson(first.result)])).r;
  const ledgerCount = await one(db, 'postgres', null,
    'select count(*)::int as n from public.ledger_entries where completion_id = $1', [DONE_1]);
  const charAgain = await one(db, 'postgres', null, 'select total_xp from public.characters where owner_id = $1', [A]);
  check('apply_progression is idempotent', again.status === 'already_applied'
    && ledgerCount.n === first.result.grants.length && Number(charAgain.total_xp) === Number(charAfter.total_xp));

  // Feed projection: guild default is completion_only → no title in payload.
  const feedB = await rows(db, 'authenticated', B, `select kind, payload from public.feed_events where kind = 'completion'`);
  check('feed event projected at completion_only (no title, no XP)',
    feedB.length === 1 && Object.keys(feedB[0].payload).sort().join(',') === 'category,share_level,tier',
    JSON.stringify(feedB[0]?.payload));
  const feedC = await rows(db, 'authenticated', C, 'select * from public.feed_events');
  check('non-members cannot read the guild feed', feedC.length === 0);
  const challenge = await one(db, 'authenticated', B, 'select progress, milestones_reached from public.challenges');
  check('challenge contribution counted for a shared completion',
    Number(challenge.progress) === first.result.effectiveMinutes, `progress=${challenge.progress}`);

  // Blocking hides the blocked user's events from the blocker only.
  await one(db, 'authenticated', B, 'select public.block_user($1)', [A]);
  const blockedView = await rows(db, 'authenticated', B, `select * from public.feed_events where actor_id = $1`, [A]);
    check('blocked user\'s feed events are hidden from the blocker', blockedView.length === 0);
  await expectError('blocks are invisible to the blocked party (clients cannot read blocks)',
    rows(db, 'authenticated', A, 'select * from public.blocks'), /permission denied/);
  await one(db, 'authenticated', B, 'select public.unblock_user($1)', [A]);

  // Comments and reactions.
  const event = await one(db, 'authenticated', B, `select id from public.feed_events where kind = 'completion'`);
  await one(db, 'authenticated', B, `select public.react($1, 'honour')`, [event.id]);
  const comment = await one(db, 'authenticated', B, `select * from public.add_comment($1, 'Well fought!')`, [event.id]);
  check('members can react and comment',
    (await rows(db, 'authenticated', A, 'select * from public.reactions')).length === 1 && comment.body === 'Well fought!');
  // Reactions are not in the Realtime publication (deletions would reach
  // every subscriber); each change touches its feed event instead.
  const touched = await hallChangedAt(db, event.id);
  await quiet(db, event.id);
  await one(db, 'authenticated', B, `select public.unreact($1, 'honour')`, [event.id]);
  const retouched = await hallChangedAt(db, event.id);
  check('adding and removing a reaction signals through its feed event', touched !== null && retouched !== null,
    `after react: ${touched}; after unreact: ${retouched}`);
  await one(db, 'authenticated', B, `select public.react($1, 'honour')`, [event.id]);

  // Reaction changes are rate-limited per user (…_reaction_rate_limit.sql):
  // 60 a minute pass and the next one is refused without a trace; calls that
  // change nothing, other members and the next minute are not affected.
  const failure = async (promise) => {
    try {
      await promise;
      return null;
    } catch (error) {
      return error;
    }
  };
  const toggle = (uid, on, kind = 'flame') =>
    failure(one(db, 'authenticated', uid, `select public.${on ? 'react' : 'unreact'}($1, $2)`, [event.id, kind]));
  const flamesOfB = async () => (await one(db, 'postgres', null, `select count(*)::int as n from public.reactions
    where event_id = $1 and user_id = $2 and kind = 'flame'`, [event.id, B])).n;
  await db.query('delete from private.reaction_rate');
  let burstError = null;
  for (let i = 0; i < 60 && burstError === null; i++) burstError = await toggle(B, i % 2 === 0);
  await quiet(db, event.id);
  const refused = await toggle(B, true);
  const signalAfter = await hallChangedAt(db, event.id);
  check('60 reaction changes a minute pass; the 61st is refused (54000, rate_limited)',
    burstError === null && refused?.code === '54000' && refused?.hint === 'rate_limited',
    `burst: ${burstError?.message ?? 'all accepted'}; 61st: ${refused?.message ?? 'accepted'}`);
  check('a refused reaction change leaves no reaction and touches no feed event',
    (await flamesOfB()) === 0 && signalAfter === null, `hall_changed_at=${signalAfter}`);
  const noChange = [await toggle(B, false), await toggle(B, true, 'honour')];
  check('reaction calls that change nothing are neither counted nor refused', noChange.every((e) => e === null),
    noChange.map((e) => e?.message ?? 'ok').join('; '));
  const otherMember = await toggle(A, true, 'steel');
  check('the reaction limit is per user', otherMember === null, otherMember?.message ?? '');
  await toggle(A, false, 'steel');
  await db.query(`update private.reaction_rate set window_start = window_start - interval '1 minute' where user_id = $1`,
    [B]);
  const nextMinute = await toggle(B, true);
  check('the reaction limit lifts once the minute is over', nextMinute === null && (await flamesOfB()) === 1,
    nextMinute?.message ?? '');
  await toggle(B, false);

  await expectError('non-members cannot comment',
    one(db, 'authenticated', C, `select * from public.add_comment($1, 'hi')`, [event.id]), /not found/);
  await expectError('empty comments are rejected',
    one(db, 'authenticated', B, `select * from public.add_comment($1, '   ')`, [event.id]), /1–1000/);

  // Full sharing on a quest exposes title and XP; stale day state is refused.
  await one(db, 'authenticated', A, 'select public.sync_push($1) as r', [[
    { entity: 'quest', op: 'upsert', id: QUEST_FULL, hlc: hlc(t0 + 5000),
      payload: { title: 'Morning run 30m', category: 'fitness', share_level: 'full',
                 created_at: new Date(now - 24 * 3600e3).toISOString() } },
    { entity: 'completion', op: 'insert', id: DONE_2, hlc: hlc(t0 + 5001),
      payload: { quest_id: QUEST_FULL, completed_at: recent, declared_minutes: 30 } },
  ]]);
  const stale = await evaluateAndApply(db, DONE_2, { staleDayChangeId: 1 });
  check('apply_progression refuses a stale day state', stale.applied.status === 'stale_day_state');
  const second = await evaluateAndApply(db, DONE_2);
  check('second completion applied after re-reading the day state', second.applied.status === 'applied');
  const fullEvent = await one(db, 'authenticated', B,
    `select payload from public.feed_events where kind = 'completion' and payload->>'share_level' = 'full'`);
  check('full sharing projects title, total XP and attribute deltas',
    fullEvent?.payload.title === 'Morning run 30m' && fullEvent.payload.total_xp === engine.totalXp(second.result)
      && typeof fullEvent.payload.attributes === 'object');

  // A private member level hides the deed and keeps it out of challenges.
  await as(db, 'postgres', null, (tx) => tx.query(
    `update public.guild_members set share_level = 'private' where guild_id = $1 and user_id = $2`, [guild.id, A]));
  await one(db, 'authenticated', A, 'select public.sync_push($1) as r', [[
    { entity: 'completion', op: 'insert', id: DONE_3, hlc: hlc(t0 + 6000),
      payload: { quest_id: QUEST, completed_at: new Date(now - 60e3).toISOString(), declared_minutes: 45 } },
  ]]);
  const progressBefore = Number((await one(db, 'authenticated', B, 'select progress from public.challenges')).progress);
  await evaluateAndApply(db, DONE_3);
  const privateEvents = await rows(db, 'service_role', null,
    `select 1 from public.feed_events where completion_id = $1`, [DONE_3]);
  const progressAfter = Number((await one(db, 'authenticated', B, 'select progress from public.challenges')).progress);
  check('private share level: no feed event and no challenge contribution',
    privateEvents.length === 0 && progressAfter === progressBefore);
  await expectError('members cannot change their own role',
    as(db, 'authenticated', B, (tx) => tx.query(`update public.guild_members set role = 'guild_master' where user_id = $1`, [B])),
    /permission denied/);

  // Provisional (offline) ledger rows are superseded by the server result.
  await one(db, 'authenticated', A, 'select public.sync_push($1) as r', [[
    { entity: 'provisional_ledger', op: 'insert', id: PROVISIONAL, payload: {
      completion_id: DONE_3, attribute: 'intelligence', amount: 20, raw_amount: 20, rule_version: '2026.11.1' } },
  ]]);
  const prov = await one(db, 'postgres', null, 'select status from public.ledger_entries where id = $1', [PROVISIONAL]);
  check('provisional rows arriving after evaluation are stored as superseded', prov?.status === 'superseded');

  // FR-5: one completion per recurring occurrence.
  const occurrence = (await one(db, 'authenticated', A, 'select public.sync_push($1) as r', [[
    { entity: 'completion', op: 'insert', id: DONE_DUP, hlc: hlc(t0 + 7000),
      payload: { quest_id: QUEST, completed_at: recent, occurrence_day: '2026-11-04' } },
    { entity: 'completion', op: 'insert', id: '30000000-0000-4000-8000-000000000005', hlc: hlc(t0 + 7001),
      payload: { quest_id: QUEST, completed_at: recent, occurrence_day: '2026-11-04' } },
  ]])).r;
  check('a recurring occurrence can be completed only once',
    occurrence.results[0].status === 'applied' && occurrence.results[1].reason === 'conflict');

  // --- undo ------------------------------------------------------------------------
  const xpOfA = async () => Number((await one(db, 'postgres', null,
    'select total_xp from public.characters where owner_id = $1', [A])).total_xp);
  const totalBeforeUndo = await xpOfA();
  const undo = (await one(db, 'authenticated', A, 'select public.undo_completion($1) as r', [DONE_1])).r;
  const reversals = await rows(db, 'postgres', null,
    `select amount from public.ledger_entries where completion_id = $1 and kind = 'reversal'`, [DONE_1]);
  const totalAfterUndo = await xpOfA();
  check('undo appends reversal entries and rolls back the cache',
    undo.status === 'undone' && reversals.length === first.result.grants.length
      && totalAfterUndo === totalBeforeUndo - engine.totalXp(first.result),
    `${totalBeforeUndo} → ${totalAfterUndo}`);
  const undoneEvent = await rows(db, 'service_role', null,
    `select 1 from public.feed_events where completion_id = $1`, [DONE_1]);
  const progressUndone = Number((await one(db, 'authenticated', B, 'select progress from public.challenges')).progress);
  const orphanComments = await rows(db, 'postgres', null, `select 1 from public.comments where body = 'Well fought!'`);
  check('undo removes the feed event (with its reactions/comments) and the challenge contribution',
    undoneEvent.length === 0 && orphanComments.length === 0
      && progressUndone === progressAfter - first.result.effectiveMinutes);
  const undoAgain = (await one(db, 'authenticated', A, 'select public.undo_completion($1) as r', [DONE_1])).r;
  check('undo is idempotent', undoAgain.status === 'already_undone');
  await expectError('users cannot undo someone else\'s completion',
    one(db, 'authenticated', B, 'select public.undo_completion($1)', [DONE_2]), /not found/);

  // --- condition, rest days, character ------------------------------------------------
  const rest = await one(db, 'authenticated', A, `select public.set_rest_day(private_today) as r
    from (select (now() at time zone 'Asia/Tehran')::date - 1 as private_today) t`);
  check('set_rest_day returns the recomputed condition', typeof rest.r.condition === 'number');
  await expectError('equipping a locked title is rejected',
    one(db, 'authenticated', A, `select * from public.update_character(equipped_title => 'oathkeeper')`), /not unlocked/);
  const named = await one(db, 'authenticated', A, `select * from public.update_character(name => ' Arin ', equipped_title => 'sworn')`);
  check('update_character sets name and an unlocked title', named.name === 'Arin' && named.equipped_title === 'sworn');

  // --- chronicle facts ----------------------------------------------------------------
  const facts = (await one(db, 'service_role', null, `select public.chronicle_facts($1, 'month',
    date_trunc('month', now() at time zone 'Asia/Tehran')::date) as f`, [A])).f;
  check('chronicle_facts computes grounded totals',
    facts.totals.completions >= 2 && Array.isArray(facts.topActivities) && facts.level.end >= 1,
    JSON.stringify(facts.totals));
  await expectError('chronicle_facts is service-role only',
    one(db, 'authenticated', A, `select public.chronicle_facts($1, 'week', current_date)`, [A]), /permission denied/);

  // --- cron job functions ----------------------------------------------------------------
  const jobs = await one(db, 'postgres', null, `select
      private.take_monthly_snapshots() as snapshots,
      private.recompute_classes() as classes,
      private.enqueue_weekly_chronicles() as chronicles,
      private.refresh_conditions() as conditions,
      private.end_challenges() as challenges,
      private.retention_cleanup() as retention`);
  await one(db, 'postgres', null, 'select private.dispatch_pending_chronicles()');
  check('cron job functions run without pg_cron/pg_net', jobs.snapshots === 3, JSON.stringify(jobs));

  // --- export and deletion -----------------------------------------------------------------
  const exported = (await one(db, 'authenticated', A, 'select public.export_my_data() as e')).e;
  check('export_my_data contains the user\'s rows',
    exported.quests.length === 3 && exported.ledger_entries.length > 0 && exported.guild_memberships.length === 1
      && exported.push_devices !== undefined);

  await one(db, 'authenticated', A, 'select public.leave_guild($1)', [guild.id]);
  const newMaster = await one(db, 'postgres', null, 'select user_id, role from public.guild_members where guild_id = $1', [guild.id]);
  check('a leaving guild master hands over mastery', newMaster.user_id === B && newMaster.role === 'guild_master');

  const inviteC = await one(db, 'authenticated', B, 'select * from public.create_invite($1)', [guild.id]);
  await one(db, 'authenticated', C, 'select * from public.join_guild_by_code($1)', [inviteC.code]);
  const survivingEvent = await one(db, 'authenticated', B,
    `select id from public.feed_events where kind = 'completion' and completion_id = $1`, [DONE_2]);
  await one(db, 'authenticated', B, `select * from public.add_comment($1, 'Farewell, companions')`, [survivingEvent.id]);
  await one(db, 'authenticated', B, 'select public.delete_my_account()');
  const remaining = await one(db, 'postgres', null, `select
      (select count(*)::int from auth.users where id = $1) as users,
      (select count(*)::int from public.profiles where id = $1) as profiles,
      (select count(*)::int from public.comments where author_id is null and body = 'Farewell, companions') as anonymised,
      (select role::text from public.guild_members where guild_id = $2 and user_id = $3) as successor`,
    [B, guild.id, C]);
  check('delete_my_account removes the user, anonymises comments, hands over the guild',
    remaining.users === 0 && remaining.profiles === 0 && remaining.anonymised === 1
      && remaining.successor === 'guild_master',
    JSON.stringify(remaining));

  await one(db, 'authenticated', C, 'select public.leave_guild($1)', [guild.id]);
  const dissolved = await one(db, 'postgres', null, 'select count(*)::int as n from public.guilds where id = $1', [guild.id]);
  check('the last member leaving dissolves the guild', dissolved.n === 0);

  // --- RLS coverage -----------------------------------------------------------------------
  const unprotected = await rows(db, 'postgres', null, `
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity`);
  check('RLS enabled on every public table', unprotected.length === 0, unprotected.map((r) => r.relname).join(', '));
}

// ---------------------------------------------------------------------------
// Comments leaving the hall (…_reaction_signals.sql)
// ---------------------------------------------------------------------------

// Realtime delivers an UPDATE only to subscribers who may still SELECT the
// new row, and nobody may SELECT a deleted or hidden comment, so deleting or
// hiding one touches its feed event instead, which the members still see.
// In a public guild a comment reported by three members is hidden.
const MASTER = '00000000-0000-4000-8000-000000000101';
const POSTER = '00000000-0000-4000-8000-000000000102';
const READER_1 = '00000000-0000-4000-8000-000000000103';
const READER_2 = '00000000-0000-4000-8000-000000000104';

async function commentSignals(db) {
  await db.query(`insert into auth.users (id, email) values ($1, 'master@example.test'),
    ($2, 'poster@example.test'), ($3, 'reader1@example.test'), ($4, 'reader2@example.test')`,
  [MASTER, POSTER, READER_1, READER_2]);
  const guild = await one(db, 'authenticated', MASTER,
    `select * from public.create_guild('The Open Road', '', 'public')`);
  const code = (await one(db, 'authenticated', MASTER, 'select * from public.create_invite($1)', [guild.id])).code;
  for (const member of [POSTER, READER_1, READER_2]) {
    await one(db, 'authenticated', member, 'select * from public.join_guild_by_code($1)', [code]);
  }
  // The comments go under READER_1's arrival in the hall.
  const event = await one(db, 'authenticated', POSTER,
    `select id from public.feed_events where guild_id = $1 and actor_id = $2 and kind = 'member_joined'`,
    [guild.id, READER_1]);
  const comment = (body) =>
    one(db, 'authenticated', POSTER, 'select * from public.add_comment($1, $2)', [event.id, body]);
  const seen = async (commentId) =>
    (await rows(db, 'authenticated', READER_2, 'select id from public.comments where id = $1', [commentId])).length > 0;

  const greeting = await comment('Welcome!');
  const greetingSeen = await seen(greeting.id);
  await quiet(db, event.id);
  await one(db, 'authenticated', POSTER, 'select public.delete_comment($1)', [greeting.id]);
  const afterDelete = await hallChangedAt(db, event.id);
  check('deleting a comment touches its feed event, which members still see',
    greetingSeen && !(await seen(greeting.id)) && afterDelete !== null,
    `seen before: ${greetingSeen}; hall_changed_at: ${afterDelete}`);

  const spam = await comment('Cheap gold here');
  const spamSeen = await seen(spam.id);
  await quiet(db, event.id);
  for (const reporter of [MASTER, READER_1, READER_2]) {
    await one(db, 'authenticated', reporter, `select public.report_content('comment', $1, 'spam')`, [spam.id]);
  }
  const afterHide = await hallChangedAt(db, event.id);
  check('hiding a comment (report_content, third report) touches its feed event',
    spamSeen && !(await seen(spam.id)) && afterHide !== null,
    `seen before: ${spamSeen}; hall_changed_at: ${afterHide}`);

  // Another report sets hidden_at to itself again: no change, no signal.
  await quiet(db, event.id);
  await one(db, 'authenticated', READER_1, `select public.report_content('comment', $1, 'spam')`, [spam.id]);
  const afterRepeat = await hallChangedAt(db, event.id);
  check('reporting a hidden comment again touches nothing', afterRepeat === null, `hall_changed_at: ${afterRepeat}`);
}

// ---------------------------------------------------------------------------
// Internal Edge Function calls (…_cron_secret_key.sql, …_notify_triggers.sql)
// ---------------------------------------------------------------------------

// Stand-ins with the signatures of pg_net's net.http_post and Supabase Vault;
// requests are recorded instead of sent.
const NET_AND_VAULT_STANDINS = /* sql */ `
  create schema net;
  create table net.requests (
    id bigserial primary key, url text, body jsonb, headers jsonb, timeout_milliseconds integer
  );
  create function net.http_post(
    url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
    headers jsonb default '{}'::jsonb, timeout_milliseconds integer default 5000
  ) returns bigint language sql as $$
    insert into net.requests (url, body, headers, timeout_milliseconds)
    values (url, body, headers, timeout_milliseconds) returning id
  $$;

  create schema vault;
  create table vault.secrets (
    id uuid primary key default gen_random_uuid(), name text unique, secret text not null,
    description text not null default '', created_at timestamptz not null default now()
  );
  create view vault.decrypted_secrets as
    select id, name, secret as decrypted_secret, description, created_at from vault.secrets;
  create function vault.create_secret(
    new_secret text, new_name text default null, new_description text default '', new_key_id uuid default null
  ) returns uuid language sql as $$
    insert into vault.secrets (secret, name, description)
    values (new_secret, new_name, coalesce(new_description, '')) returning id
  $$;
  create function vault.update_secret(
    secret_id uuid, new_secret text default null, new_name text default null,
    new_description text default null, new_key_id uuid default null
  ) returns void language sql as $$
    update vault.secrets set secret = coalesce(new_secret, secret), name = coalesce(new_name, name),
      description = coalesce(new_description, description)
    where id = secret_id
  $$;
`;

const D = '00000000-0000-4000-8000-00000000000d';
const E = '00000000-0000-4000-8000-00000000000e';
const PROJECT_URL = 'https://abcdefghijklmnopqrst.supabase.co';
const SECRET_KEY = 'sb_secret_validation_0123456789';
const LEGACY_KEY = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2lnbmF0dXJl';

async function internalCalls(db) {
  const requests = async () => (await db.query('select * from net.requests order by id')).rows;

  const triggers = await rows(db, 'postgres', null, `select tgrelid::regclass::text as t from pg_trigger
    where tgname in ('reactions_notify', 'comments_notify', 'feed_events_notify') order by 1`);
  check('notification triggers on reactions, comments and feed_events',
    triggers.map((r) => r.t).join(',') === 'comments,feed_events,reactions', triggers.map((r) => r.t).join(','));

  // A project set up from the old README also has dashboard webhooks to
  // notify: triggers running supabase_functions.http_request (a stand-in
  // here) with the URL as first argument. Applied there,
  // …_drop_notify_webhooks.sql drops exactly those, also on a local stack,
  // with a query string, an uppercase scheme, three slashes or one (pg_net's
  // libcurl still posts those to notify), and keeps webhooks to other
  // functions such as notify-moderators, one that names notify only in a
  // later argument, one whose host is empty (libcurl reads "functions" as
  // its host) and a call without arguments.
  const hallTriggers = async () => (await rows(db, 'postgres', null, `select tgname from pg_trigger
    where tgrelid in ('public.reactions'::regclass, 'public.comments'::regclass, 'public.feed_events'::regclass)
      and not tgisinternal`)).map((r) => r.tgname).sort();
  const ownTriggers = await hallTriggers();
  const notify = `${PROJECT_URL}/functions/v1/notify`;
  const hook = (table, name, url, params = '{}') => `
    create trigger "${name}" after insert on public.${table} for each row
      execute function supabase_functions.http_request(
        '${url}', 'POST', '{"Content-type":"application/json"}', '${params}', '5000');`;
  await db.exec(`
    create schema supabase_functions;
    create function supabase_functions.http_request() returns trigger language plpgsql as $$ begin return null; end $$;
    ${hook('reactions', 'notify-reactions', notify)}
    ${hook('comments', 'notify-comments', notify)}
    ${hook('feed_events', 'notify-milestones', notify)}
    ${hook('reactions', 'notify-reactions-local', 'http://host.docker.internal:54321/functions/v1/notify?via=studio')}
    ${hook('reactions', 'notify-reactions-uppercase', notify.replace('https://', 'HTTPS://'))}
    ${hook('comments', 'notify-comments-three-slashes', notify.replace('https://', 'https:///'))}
    ${hook('feed_events', 'notify-milestones-one-slash', notify.replace('https://', 'https:/'))}
    ${hook('feed_events', 'no-host-notify', 'https:///functions/v1/notify')}
    ${hook('reactions', 'audit-reactions', 'https://hooks.example.test/reactions')}
    ${hook('comments', 'notify-moderators', `${notify}-moderators`)}
    ${hook('comments', 'relay-to-notify', `https://relay.example.test/forward?to=${notify}`)}
    ${hook('reactions', 'mirror-notify', 'https://hooks.example.test/mirror/functions/v1/notify')}
    ${hook('feed_events', 'audit-milestones', 'https://hooks.example.test/milestones', `{"then":"${notify}"}`)}
    create trigger "http-request-without-arguments" after insert on public.comments
      for each row execute function supabase_functions.http_request();`);
  const beforeDrop = await hallTriggers();
  await db.exec(readFileSync(MIGRATIONS + DROP_NOTIFY_WEBHOOKS, 'utf8'));
  const afterDrop = await hallTriggers();
  const survivors = [
    'audit-milestones', 'audit-reactions', 'http-request-without-arguments', 'mirror-notify', 'no-host-notify',
    'notify-moderators', 'relay-to-notify',
  ];
  check('dashboard webhooks to notify are dropped; our triggers and webhooks to other URLs (notify-moderators) stay',
    afterDrop.join(',') === [...ownTriggers, ...survivors].sort().join(','),
    `dropped: ${beforeDrop.filter((t) => !afterDrop.includes(t)).join(',')}; kept: ${afterDrop.join(',')}`);
  await db.exec('drop schema supabase_functions cascade');

  const offline = await one(db, 'postgres', null, `select private.call_edge_function('notify', '{}') as id`);
  check('internal calls are a no-op without pg_net and Vault', offline.id === null);

  await db.exec(NET_AND_VAULT_STANDINS);
  const unconfigured = await one(db, 'postgres', null, `select private.call_edge_function('notify', '{}') as id`);
  check('no request while the Vault secrets are missing', unconfigured.id === null && (await requests()).length === 0);

  await one(db, 'postgres', null, 'select private.set_function_credentials($1, $2)', [`${PROJECT_URL}/`, SECRET_KEY]);
  await one(db, 'postgres', null, 'select private.set_function_credentials($1, $2)', [`${PROJECT_URL}/`, SECRET_KEY]);
  const secrets = await rows(db, 'postgres', null, 'select name, decrypted_secret from vault.decrypted_secrets order by name');
  check('set_function_credentials stores the URL and secret key once (re-runnable)',
    secrets.length === 2 && secrets[0].name === 'wyrd_project_url' && secrets[0].decrypted_secret === PROJECT_URL
      && secrets[1].name === 'wyrd_secret_key' && secrets[1].decrypted_secret === SECRET_KEY,
    JSON.stringify(secrets.map((s) => s.name)));
  await expectError('set_function_credentials refuses a publishable key',
    one(db, 'postgres', null, 'select private.set_function_credentials($1, $2)', [PROJECT_URL, 'sb_publishable_x']),
    /secret key/);
  await expectError('set_function_credentials refuses a URL without a scheme',
    one(db, 'postgres', null, 'select private.set_function_credentials($1, $2)', ['abcdefghijklmnopqrst.supabase.co', SECRET_KEY]),
    /project URL/);
  await expectError('clients cannot reach the internal-call helpers',
    one(db, 'authenticated', A, `select private.call_edge_function('notify', '{}')`), /permission denied/);
  await expectError('the service role cannot rewrite the internal-call credentials',
    one(db, 'service_role', null, 'select private.set_function_credentials($1, $2)', [PROJECT_URL, SECRET_KEY]),
    /permission denied/);

  // A guild with a deed, then a reaction, a comment and a milestone.
  await db.query(`insert into auth.users (id, email) values ($1, 'd@example.test'), ($2, 'e@example.test')`, [D, E]);
  const hall = await one(db, 'authenticated', D, `select * from public.create_guild('Hall of Echoes')`);
  const code = (await one(db, 'authenticated', D, 'select * from public.create_invite($1)', [hall.id])).code;
  await one(db, 'authenticated', E, 'select * from public.join_guild_by_code($1)', [code]);
  const deed = await one(db, 'postgres', null, `insert into public.feed_events (guild_id, actor_id, kind, payload)
    values ($1, $2, 'completion', '{"tier":"daily"}') returning id`, [hall.id, D]);
  check('completion events send no notification', (await requests()).length === 0);

  await one(db, 'authenticated', E, `select public.react($1, 'honour')`, [deed.id]);
  const [reaction] = await requests();
  check('a reaction is posted to notify with the secret key as apikey',
    reaction?.url === `${PROJECT_URL}/functions/v1/notify` && reaction.headers.apikey === SECRET_KEY
      && reaction.headers.Authorization === undefined && reaction.timeout_milliseconds === 5000,
    JSON.stringify({ url: reaction?.url, headers: Object.keys(reaction?.headers ?? {}) }));
  check('the request has the Database Webhook shape notify expects',
    reaction?.body.type === 'INSERT' && reaction.body.table === 'reactions' && reaction.body.schema === 'public'
      && reaction.body.record.event_id === deed.id && reaction.body.record.user_id === E
      && reaction.body.old_record === null, JSON.stringify(reaction?.body));

  await one(db, 'authenticated', E, `select * from public.add_comment($1, 'Well met')`, [deed.id]);
  await one(db, 'postgres', null, `insert into public.feed_events (guild_id, kind, payload)
    values ($1, 'challenge_milestone', '{"milestone":25,"title":"Long road"}')`, [hall.id]);
  const posted = (await requests()).map((r) => `${r.body.table}:${r.body.record.body ?? r.body.record.kind ?? ''}`);
  check('comments and challenge milestones are posted too',
    posted.join(',') === 'reactions:honour,comments:Well met,feed_events:challenge_milestone', posted.join(','));

  await db.exec(`create or replace function net.http_post(
      url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
      headers jsonb default '{}'::jsonb, timeout_milliseconds integer default 5000
    ) returns bigint language plpgsql as $$ begin raise exception 'pg_net is down'; end $$`);
  await one(db, 'authenticated', E, `select public.react($1, 'steel')`, [deed.id]);
  const kept = await one(db, 'postgres', null,
    `select count(*)::int as n from public.reactions where event_id = $1 and user_id = $2`, [deed.id, E]);
  check('a failing pg_net never fails the user\'s write', kept.n === 2);

  // pg_cron's dispatch, and a project still on the legacy service-role key.
  await db.exec(`create or replace function net.http_post(
      url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
      headers jsonb default '{}'::jsonb, timeout_milliseconds integer default 5000
    ) returns bigint language sql as $fn$
      insert into net.requests (url, body, headers, timeout_milliseconds)
      values (url, body, headers, timeout_milliseconds) returning id
    $fn$`);
  await db.query(`delete from net.requests`);
  await db.query(`insert into public.chronicles (owner_id, period, period_start, period_end, locale, status)
    values ($1, 'week', date '2026-10-26', date '2026-11-02', 'en', 'pending')`, [D]);
  await one(db, 'postgres', null, 'select private.dispatch_pending_chronicles()');
  const [dispatch] = await requests();
  check('pg_cron dispatch wakes generate-chronicle with the secret key',
    dispatch?.url === `${PROJECT_URL}/functions/v1/generate-chronicle` && dispatch.body.mode === 'pending'
      && dispatch.headers.apikey === SECRET_KEY && dispatch.timeout_milliseconds === 60000,
    JSON.stringify({ url: dispatch?.url, body: dispatch?.body }));

  await db.query(`delete from vault.secrets where name = 'wyrd_secret_key'`);
  await one(db, 'postgres', null, `select vault.create_secret($1, 'wyrd_service_role_key')`, [LEGACY_KEY]);
  await one(db, 'postgres', null, `select private.call_edge_function('notify', '{}')`);
  const legacy = (await requests()).at(-1);
  check('a legacy service-role key is used as fallback, also as bearer token',
    legacy?.headers.apikey === LEGACY_KEY && legacy.headers.Authorization === `Bearer ${LEGACY_KEY}`);
}

async function main() {
  const db = await freshDatabase(NEW_PROJECT_DEFAULTS + REALTIME_PUBLICATION);
  console.log('Applying migrations (new project: nothing exposed without a GRANT)');
  await applyMigrations(db);

  console.log('Data API grants');
  let surface = { fields: [] };
  try {
    surface = await checkDataApi(db);
    const old = await freshDatabase(OLD_PROJECT_DEFAULTS);
    await applyMigrations(old, 'old project (everything exposed by default)');
    const [fresh, legacy] = [await privilegeSnapshot(db), await privilegeSnapshot(old)];
    const onlyFresh = fresh.filter((e) => !legacy.includes(e));
    const onlyLegacy = legacy.filter((e) => !fresh.includes(e));
    check('old and new projects end with the same privileges', onlyFresh.length === 0 && onlyLegacy.length === 0,
      [...onlyFresh.map((e) => `new only: ${e}`), ...onlyLegacy.map((e) => `old only: ${e}`)].join('; ')
        || `${fresh.length} privileges`);
    await old.close();
  } catch (error) {
    check('Data API grant checks completed', false, String(error?.message ?? error));
  }

  console.log('Smoke checks');
  try {
    await smoke(db, { profileFields: surface.fields });
  } catch (error) {
    check('smoke checks completed', false, String(error?.message ?? error));
  }
  try {
    await commentSignals(db);
  } catch (error) {
    check('comment signal checks completed', false, String(error?.message ?? error));
  }

  console.log('Internal calls (pg_cron and notification triggers through pg_net)');
  try {
    await internalCalls(db);
  } catch (error) {
    check('internal call checks completed', false, String(error?.message ?? error));
  }
  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
  await db.close();
  process.exit(failed.length === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error(`\nValidation aborted: ${error?.message ?? error}`);
  process.exit(1);
});
