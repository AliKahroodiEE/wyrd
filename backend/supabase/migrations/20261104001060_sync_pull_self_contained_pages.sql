-- =============================================================================
-- Wyrd · sync_pull pages that can be applied on their own
--
-- sync_pull (…_rpc_sync.sql) pages the caller's rows of every pulled table
-- together, oldest change_id first, max_rows (default 1000) at a time. Every
-- update gives a row a new change_id, so a quest edited after it was
-- completed (a reminder, a new title) comes after its older subtasks and
-- completions, which can be a page or more ahead of it. The app applies a
-- page in one transaction, quests first, and its local foreign keys refuse a
-- subtask or completion whose quest it does not have yet: those were left
-- out, and the cursor moved past them for good. A new device, a reinstall or
-- an account switch on a shared device lost that history: the completions,
-- the XP the app builds from their results, and the subtasks.
--
-- The app also reads a completion's evaluation (the evaluator's proposal,
-- with the reason it shows for each attribute grant) only from the page
-- that brings the completion. apply_progression writes the evaluation just
-- before the completion's result, so a page can end between the two; the
-- app then made do without it and showed a generic reason for every grant.
--
-- Each page now also carries the current version of the quest of every
-- subtask and completion in it when that quest's own place is in a later
-- page, and the evaluation of every completion in it that lies outside the
-- page, before or after it. The cursor and has_more still come from the
-- page's own rows only: every row is still sent in its own page, so nothing
-- is skipped and the last page still ends the pull. A row sent twice changes
-- nothing the second time: the app upserts quests and only reads
-- evaluations. The extra rows are at most one quest per subtask or
-- completion in the page and one evaluation per completion, usually none.
-- Signature, the rest of the behaviour and the grants are unchanged.
-- =============================================================================

create or replace function public.sync_pull("cursor" bigint default 0, max_rows integer default 1000)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_cursor bigint := greatest(coalesce(sync_pull."cursor", 0), 0);
  v_limit integer := least(greatest(coalesce(sync_pull.max_rows, 1000), 1), 5000);
  v_changes jsonb;
  v_next bigint;
  v_more boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  with changed as (
    select 'profiles'::text as entity, t.change_id, to_jsonb(t) as row
      from public.profiles t where t.id = v_uid and t.change_id > v_cursor
    union all
    select 'characters', t.change_id, to_jsonb(t)
      from public.characters t where t.owner_id = v_uid and t.change_id > v_cursor
    union all
    select 'quests', t.change_id, to_jsonb(t)
      from public.quests t where t.owner_id = v_uid and t.change_id > v_cursor
    union all
    select 'subtasks', t.change_id, to_jsonb(t)
      from public.subtasks t where t.owner_id = v_uid and t.change_id > v_cursor
    union all
    select 'completions', t.change_id, to_jsonb(t)
      from public.completions t where t.owner_id = v_uid and t.change_id > v_cursor
    union all
    select 'evaluations', t.change_id, to_jsonb(t) - 'input_hash'
      from public.evaluations t where t.owner_id = v_uid and t.change_id > v_cursor
    union all
    select 'ledger_entries', t.change_id, to_jsonb(t)
      from public.ledger_entries t where t.owner_id = v_uid and t.change_id > v_cursor
    union all
    select 'achievements', t.change_id, to_jsonb(t)
      from public.achievements t where t.owner_id = v_uid and t.change_id > v_cursor
    union all
    select 'day_stats', t.change_id, to_jsonb(t)
      from public.day_stats t where t.owner_id = v_uid and t.change_id > v_cursor
    union all
    select 'chronicles', t.change_id, to_jsonb(t)
      from public.chronicles t where t.owner_id = v_uid and t.change_id > v_cursor
    union all
    select 'notification_prefs', t.change_id, to_jsonb(t)
      from public.notification_prefs t where t.user_id = v_uid and t.change_id > v_cursor
  ),
  page as (
    select c.entity, c.change_id, c.row from changed c order by c.change_id limit v_limit + 1
  ),
  ranked as (
    select p.*, row_number() over (order by p.change_id) as rn, count(*) over () as total
    from page p
  ),
  -- The page's own rows: exactly those with cursor < change_id <= last.
  own as (
    select r.entity, r.change_id, r.row from ranked r where r.rn <= v_limit
  ),
  -- One row: where the page ends, the quests of its subtasks and
  -- completions, and its completions. As arrays they are looked up by index
  -- below, also on tables the planner has no statistics for yet.
  refs as (
    select
      coalesce(max(o.change_id), v_cursor) as last,
      array_agg(distinct (o.row ->> 'quest_id')::uuid)
        filter (where o.entity in ('subtasks', 'completions')) as quest_ids,
      array_agg((o.row ->> 'id')::uuid) filter (where o.entity = 'completions') as completion_ids
    from own o
  ),
  -- Quests of the page's subtasks and completions that come in a later page
  -- (one at or before the cursor reached the app with an earlier page).
  quests_ahead as (
    select 'quests'::text as entity, q.change_id, to_jsonb(q) as row
    from refs f join public.quests q on q.id = any (f.quest_ids)
    where q.owner_id = v_uid and q.change_id > f.last
  ),
  -- Evaluations of the page's completions that are not among its own rows.
  evaluations_elsewhere as (
    select 'evaluations'::text as entity, e.change_id, to_jsonb(e) - 'input_hash' as row
    from refs f join public.evaluations e on e.completion_id = any (f.completion_ids)
    where e.owner_id = v_uid and (e.change_id <= v_cursor or e.change_id > f.last)
  ),
  sent as (
    select o.entity, o.change_id, o.row from own o
    union all
    select a.entity, a.change_id, a.row from quests_ahead a
    union all
    select e.entity, e.change_id, e.row from evaluations_elsewhere e
  )
  select
    coalesce((
      select jsonb_object_agg(g.entity, g.rows)
      from (
        select s.entity, jsonb_agg(s.row order by s.change_id) as rows
        from sent s group by s.entity
      ) g
    ), '{}'::jsonb),
    (select f.last from refs f),
    coalesce((select max(r.total) from ranked r), 0) > v_limit
  into v_changes, v_next, v_more;

  return jsonb_build_object(
    'cursor', v_next,
    'has_more', v_more,
    'server_time', now(),
    'changes', jsonb_build_object(
      'profiles', '[]'::jsonb, 'characters', '[]'::jsonb, 'quests', '[]'::jsonb,
      'subtasks', '[]'::jsonb, 'completions', '[]'::jsonb, 'evaluations', '[]'::jsonb,
      'ledger_entries', '[]'::jsonb, 'achievements', '[]'::jsonb, 'day_stats', '[]'::jsonb,
      'chronicles', '[]'::jsonb, 'notification_prefs', '[]'::jsonb
    ) || v_changes
  );
end;
$$;

-- Unchanged: signed-in users only (…_rpc_sync.sql, …_data_api_grants.sql).
revoke execute on function public.sync_pull(bigint, integer) from public, anon, service_role;
grant execute on function public.sync_pull(bigint, integer) to authenticated;
