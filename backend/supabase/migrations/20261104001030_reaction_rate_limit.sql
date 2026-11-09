-- =============================================================================
-- Wyrd · a rate limit on reaction changes
--
-- add_comment refuses a member's 31st comment in a guild within an hour
-- (…_rpc_social.sql); react and unreact had no limit. Yet every new reaction
-- posts to the notify Edge Function through pg_net (…_notify_triggers.sql),
-- which logs a notification_deliveries row, and every added or removed one
-- touches its feed event (…_reaction_signals.sql), on which every open guild
-- hall refetches. A member toggling a reaction in a loop would burn the
-- project's Edge Function invocations and keep the whole guild reloading.
--
-- The limit is 60 changes per user per minute, across all guilds. Reacting
-- by hand takes a tap per change, a few a minute even when going through a
-- full hall (50 deeds, 4 kinds), so people never reach it; a script gets
-- about one notify call and one hall refresh a second instead of hundreds.
-- Only changes count: adding a reaction that is already there or removing
-- one that is not changes nothing and is never refused. A refused change
-- fails with 54000 / rate_limited like add_comment, and rolls back with all
-- its triggers did (pg_net sends only after commit), so nobody is notified
-- and no hall refetches.
--
-- add_comment counts rows of public.comments, but a removed reaction leaves
-- no row, so a counter in private does the counting: one row per user, for
-- a one-minute window that opens with the first change after the previous
-- window closed. Two windows back to back can pass up to 120 changes in a
-- short span; still bounded, and a single row per user needs no clean-up.
-- react and unreact keep their signatures, behaviour and grants.
-- =============================================================================

create table private.reaction_rate (
  user_id uuid primary key references auth.users (id) on delete cascade,
  window_start timestamptz not null,
  changes integer not null
);

-- Only the definer functions below touch it; no Data API role can reach
-- the private schema either.
alter table private.reaction_rate enable row level security;
revoke all on table private.reaction_rate from public, anon, authenticated, service_role;

-- Counts one reaction change by p_user_id. Past 60 in the current window it
-- raises, which rolls the change back together with this count.
create or replace function private.count_reaction_change(p_user_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_changes integer;
begin
  -- The upsert locks the user's row, so concurrent changes count one by one.
  insert into private.reaction_rate as r (user_id, window_start, changes)
  values (p_user_id, now(), 1)
  on conflict (user_id) do update
    set window_start = case when r.window_start > now() - interval '1 minute' then r.window_start else now() end,
        changes = case when r.window_start > now() - interval '1 minute' then r.changes + 1 else 1 end
  returning r.changes into v_changes;
  if v_changes > 60 then
    raise exception 'reaction limit reached, try again later' using errcode = '54000', hint = 'rate_limited';
  end if;
end;
$$;

revoke execute on function private.count_reaction_change(uuid) from public, anon, authenticated, service_role;

create or replace function public.react(event_id uuid, kind public.reaction_kind)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_uid();
begin
  perform private.visible_event(react.event_id, v_uid);
  insert into public.reactions (event_id, user_id, kind)
  values (react.event_id, v_uid, react.kind)
  on conflict do nothing;
  if found then
    perform private.count_reaction_change(v_uid);
  end if;
end;
$$;

create or replace function public.unreact(event_id uuid, kind public.reaction_kind)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_uid();
begin
  delete from public.reactions r
  where r.event_id = unreact.event_id and r.user_id = v_uid and r.kind = unreact.kind;
  if found then
    perform private.count_reaction_change(v_uid);
  end if;
end;
$$;

-- Unchanged: signed-in users only (…_rpc_social.sql, …_data_api_grants.sql).
revoke execute on function
  public.react(uuid, public.reaction_kind), public.unreact(uuid, public.reaction_kind)
from public, anon, service_role;
grant execute on function
  public.react(uuid, public.reaction_kind), public.unreact(uuid, public.reaction_kind)
to authenticated;
