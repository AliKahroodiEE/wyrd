-- =============================================================================
-- Wyrd · Data API grants
--
-- Since 2026-05-30 new Supabase projects give the Data API roles nothing on
-- new objects in `public`: anon, authenticated and service_role (the role
-- behind secret keys) see only what is granted explicitly. Older projects,
-- and a local stack without `[api] auto_expose_new_tables = false`, granted
-- every table to all three. This migration makes both end in the same
-- state: it takes every table and sequence privilege away from the three
-- roles and grants back exactly what the app and the Edge Functions use.
-- RLS (…_rls.sql) still decides which rows a signed-in user sees.
--
--   anon            nothing: guests never reach the server (ADR-003)
--   authenticated   the guild hall tables the app reads and watches with
--                   Realtime, its profile settings, the user RPCs
--   service_role    the tables the Edge Functions read and write, the
--                   service RPCs
--
-- pg_cron jobs, triggers and SECURITY DEFINER functions run as the owner
-- (postgres) and need none of this. scripts/validate-sql.mjs applies the
-- migrations like a new project would, compares the result with an old
-- project's and checks it against every .from() / .rpc() call in app/lib and
-- supabase/functions, so a missing or unused grant fails `npm run verify`.
--
-- Adding a table, column use or RPC: grant it in a new migration, to the
-- role that calls it.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Start from nothing
-- ---------------------------------------------------------------------------

-- Also removes the column grants of …_rls.sql; those still used are granted
-- again below.
revoke all on all tables in schema public from anon, authenticated, service_role;
revoke all on all sequences in schema public from anon, authenticated, service_role;
revoke execute on all functions in schema public from public, anon;

-- Objects created by later migrations start unexposed too, as on a new
-- project. (Postgres' global EXECUTE-to-PUBLIC default for functions stays,
-- so every new function needs its own revoke and grants; the validator
-- fails on any function in public that anon or PUBLIC can execute.)
alter default privileges in schema public revoke all on tables from anon, authenticated, service_role;
alter default privileges in schema public revoke all on sequences from anon, authenticated, service_role;
alter default privileges in schema public revoke all on functions from anon, authenticated, service_role;

grant usage on schema public to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- authenticated: tables (app/lib/data/remote/*.dart)
-- ---------------------------------------------------------------------------

-- Guild hall (guild_api.dart) and its Realtime subscription: Realtime only
-- delivers a change to a subscriber whose role may SELECT the row. RLS:
-- public or joined guilds; members-only feed, reactions, comments and
-- challenges, without hidden events or blocked users' content.
grant select on
  public.guilds, public.feed_events, public.reactions, public.comments, public.challenges
to authenticated;

-- Profile settings (remote_api.dart: update … where id = <own id>). The
-- filter reads id; server-maintained columns stay read-only, and the
-- profile itself reaches the app through sync_pull.
grant select (id) on public.profiles to authenticated;
grant update (
  handle, display_name, locale, ai_locale, region, calendar, time_zone,
  week_start, weekly_target, motivation, ai_evaluation_enabled, ai_chronicles_enabled
) on public.profiles to authenticated;

-- Every other write goes through the SECURITY DEFINER RPCs below.

-- ---------------------------------------------------------------------------
-- authenticated: RPCs
-- ---------------------------------------------------------------------------

-- Signed-in users only. Old projects also gave service_role EXECUTE on
-- every function; it calls none of these (and bypasses RLS, so the policy
-- helpers are no use to it either).
do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    -- Helpers the RLS policies above call as the querying user.
    'public.is_guild_member(uuid)',
    'public.guild_role_of(uuid)',
    'public.is_guild_officer(uuid)',
    'public.is_blocked_by_me(uuid)',
    -- Called by the app: sync (remote_api.dart) and the guild hall (guild_api.dart).
    'public.sync_push(jsonb)',
    'public.sync_pull(bigint, integer)',
    'public.my_guilds()',
    'public.create_guild(text, text, text, text, text, public.share_level)',
    'public.join_guild_by_code(text, public.share_level)',
    'public.create_invite(uuid, integer, integer)',
    'public.leave_guild(uuid)',
    'public.guild_roster(uuid)',
    'public.react(uuid, public.reaction_kind)',
    'public.unreact(uuid, public.reaction_kind)',
    'public.add_comment(uuid, text)',
    'public.create_challenge(uuid, text, text, integer, timestamptz, timestamptz, text, public.quest_category, public.attribute)',
    'public.report_content(text, uuid, text, text)',
    'public.block_user(uuid)',
    -- The rest of the user API (…_rpc_*.sql): account deletion and export,
    -- device tokens, character and guild management. Each checks the caller.
    'public.delete_my_account()',
    'public.export_my_data()',
    'public.register_push_token(text, text)',
    'public.undo_completion(uuid)',
    'public.set_rest_day(date, boolean)',
    'public.update_character(text, text, text, boolean)',
    'public.revoke_invite(text)',
    'public.set_member_role(uuid, uuid, public.guild_role)',
    'public.remove_member(uuid, uuid)',
    'public.delete_comment(uuid)',
    'public.unblock_user(uuid)'
  ] loop
    execute format('revoke execute on function %s from service_role', v_signature);
    execute format('grant execute on function %s to authenticated', v_signature);
  end loop;
end;
$$;

-- The progression curves are internal: the app has its own engine twin, and
-- the definer functions and cron jobs that use them run as the owner.
-- level_for_xp / rank_for_xp loop once per level, so an open endpoint with an
-- unbounded argument was a cheap way to burn CPU.
revoke execute on function
  public.xp_to_advance_level(integer), public.xp_to_advance_rank(integer),
  public.level_for_xp(bigint), public.rank_for_xp(bigint)
from authenticated, service_role;

-- ---------------------------------------------------------------------------
-- service_role: the Edge Functions' admin client (secret key)
-- ---------------------------------------------------------------------------

-- evaluate-completion: the completion, its quest (and the parent's title),
-- the owner's AI settings and the 7-day proposal cache.
grant select on public.completions, public.quests, public.profiles, public.evaluations to service_role;

-- notify: names, membership, blocks and preferences of the recipients; the
-- delivery log; device tokens (unregistered ones are deleted).
grant select on
  public.characters, public.guilds, public.guild_members, public.feed_events,
  public.reactions, public.blocks, public.notification_prefs
to service_role;
grant select, insert on public.notification_deliveries to service_role;
grant select, delete on public.push_tokens to service_role;

-- generate-chronicle: the pending queue and the stored chronicles (upsert).
grant select, insert, update on public.chronicles to service_role;

-- Ledger, character and day writes go through apply_progression and the
-- other service RPCs (…_rpc_progression.sql), restated here.
grant execute on function
  public.apply_progression(uuid, jsonb, jsonb, text, text, jsonb),
  public.get_day_state(uuid, date),
  public.consume_ai_quota(uuid, text, integer),
  public.count_similar_completions(uuid, uuid, text, uuid),
  public.chronicle_facts(uuid, text, date)
to service_role;
