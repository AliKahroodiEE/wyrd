-- =============================================================================
-- Wyrd · notification triggers
--
-- Push notifications for guild activity come from the notify Edge Function.
-- These AFTER INSERT triggers replace the three Database Webhooks that used
-- to be created by hand in the dashboard: every new reaction, comment and
-- challenge milestone is posted to /functions/v1/notify through pg_net, in
-- the same Database-Webhook shape ({type, table, schema, record,
-- old_record}), with the project secret key as apikey
-- (private.call_edge_function, …_cron_secret_key.sql). Do not also create
-- dashboard webhooks for these tables: members would be notified twice.
--
-- pg_net sends the request after the transaction commits, so a rolled-back
-- insert sends nothing. Without pg_net or the Vault secrets the triggers do
-- nothing, and no error in them ever fails the insert.
-- =============================================================================

-- pg_net may be missing if pg_cron was (…_cron.sql installs both together).
do $$
begin
  create extension if not exists pg_net with schema extensions;
exception when others then
  raise notice 'pg_net is not available (%); notification triggers stay no-ops', sqlerrm;
end;
$$;

-- Runs as the owner whoever inserts the row, so neither pg_net nor Vault ever
-- needs a grant for client roles.
create or replace function private.notify_on_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform private.call_edge_function(
      'notify',
      jsonb_build_object(
        'type', 'INSERT',
        'table', tg_table_name,
        'schema', tg_table_schema,
        'record', to_jsonb(new),
        'old_record', null
      )
    );
  exception when others then
    -- A notification is never worth failing the user's write.
    raise warning 'notify trigger on %.%: % (%)', tg_table_schema, tg_table_name, sqlerrm, sqlstate;
  end;
  return null;
end;
$$;

drop trigger if exists reactions_notify on public.reactions;
create trigger reactions_notify
  after insert on public.reactions
  for each row execute function private.notify_on_insert();

drop trigger if exists comments_notify on public.comments;
create trigger comments_notify
  after insert on public.comments
  for each row execute function private.notify_on_insert();

-- Only milestones notify (notify ignores every other kind), so completions
-- and joins cost no Edge Function invocation.
drop trigger if exists feed_events_notify on public.feed_events;
create trigger feed_events_notify
  after insert on public.feed_events
  for each row
  when (new.kind = 'challenge_milestone')
  execute function private.notify_on_insert();

revoke execute on all functions in schema private from public;
