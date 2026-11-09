-- =============================================================================
-- Wyrd · live guild hall updates without exposing who reacted; Realtime
-- publishes only the guild hall
--
-- Realtime cannot apply RLS to DELETE events. With public.reactions in the
-- supabase_realtime publication, anyone subscribed to it received the
-- primary key (event_id, user_id, kind) of every removed reaction, in every
-- guild. Reactions leave the publication. Instead, adding or removing a
-- reaction touches its feed event (hall_changed_at); Realtime filters
-- those UPDATE events through the members-only policy, and the guild hall
-- refetches on them (guild_api.dart, ADR-003).
--
-- The personal tables leave it too. …_rls.sql published quests, subtasks,
-- completions, ledger_entries, characters, day_stats, achievements and
-- chronicles as pull signals, but clients may not SELECT them since
-- …_data_api_grants.sql (personal data comes only through sync_pull), so
-- Realtime delivered none of their changes and only spent work decoding
-- them from the WAL. What stays is what the app watches (guild_api.dart,
-- watchGuild): feed_events, comments and challenges. Where the publication
-- does not exist, nothing changes.
--
-- Comments that disappear need the same signal as reactions. Realtime
-- delivers an UPDATE only to subscribers whose SELECT policy still matches
-- the new row, and comments_select_visible (…_rls.sql) requires deleted_at
-- and hidden_at to be null: a comment being deleted (delete_comment) or
-- hidden (report_content) reached no one, and open halls kept showing it.
-- A change to either column now touches the comment's feed event as well.
--
-- A feed event that is hidden itself cannot carry its own signal:
-- feed_events_select_members requires hidden_at to be null, so the UPDATE
-- that hides an event (report_content) reaches no one either, and open
-- halls keep showing the event until they next refetch (another change in
-- the hall, pull to refresh, reopening it). Signalling that needs a row
-- outside the hidden event; this migration leaves it as it is.
-- =============================================================================

alter table public.feed_events add column if not exists hall_changed_at timestamptz;

-- Touches the feed event a reaction or comment belongs to (both carry
-- event_id). Runs as the owner: no client role may update feed_events.
create or replace function private.touch_feed_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event uuid;
begin
  if tg_op = 'DELETE' then
    v_event := old.event_id;
  else
    v_event := new.event_id;
  end if;
  -- No row when the feed event itself is being deleted (cascade).
  update public.feed_events set hall_changed_at = now() where id = v_event;
  return null;
end;
$$;

-- Only the triggers below run it.
revoke execute on function private.touch_feed_event() from public, anon, authenticated, service_role;

drop trigger if exists reactions_touch_feed_event on public.reactions;
create trigger reactions_touch_feed_event
  after insert or delete on public.reactions
  for each row execute function private.touch_feed_event();

-- Fires only when either column really changes: report_content sets
-- hidden_at to itself again on every further report of a hidden comment,
-- and the retention job's blanking of old deleted comments updates only
-- their body.
drop trigger if exists comments_touch_feed_event on public.comments;
create trigger comments_touch_feed_event
  after update of deleted_at, hidden_at on public.comments
  for each row
  when (old.deleted_at is distinct from new.deleted_at or old.hidden_at is distinct from new.hidden_at)
  execute function private.touch_feed_event();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'reactions',
    'quests', 'subtasks', 'completions', 'ledger_entries', 'characters', 'day_stats',
    'achievements', 'chronicles'
  ] loop
    if exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime drop table public.%I', v_table);
    end if;
  end loop;
end;
$$;
