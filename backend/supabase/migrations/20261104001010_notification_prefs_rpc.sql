-- =============================================================================
-- Wyrd · notification settings from the app
--
-- The Settings switches and quiet hours are edited on the device, but the
-- notify Edge Function decides from public.notification_prefs. The sync
-- engine mirrors them here (sync_coordinator.dart), so a switched-off kind
-- of push stops arriving in the background too. Only known categories with
-- true/false values are kept and merged into the stored ones; users still
-- get no direct access to the table.
-- =============================================================================

create or replace function public.set_notification_prefs(
  categories jsonb,
  quiet_hours_start time default null,
  quiet_hours_end time default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_uid();
  v_categories jsonb;
begin
  if jsonb_typeof(set_notification_prefs.categories) is distinct from 'object' then
    raise exception 'categories must be a JSON object' using errcode = '22023';
  end if;
  -- The categories of notification-policy.ts; anything else is dropped.
  select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb)
    into v_categories
    from jsonb_each(set_notification_prefs.categories) c
   where c.key in (
       'reminders', 'guild_reactions', 'guild_comments', 'challenge_milestones',
       'objectives', 'weekly_summary', 'briefing', 're_engagement'
     )
     and jsonb_typeof(c.value) = 'boolean';

  insert into public.notification_prefs as n (user_id, categories, quiet_hours_start, quiet_hours_end)
  values (
    v_uid,
    v_categories,
    coalesce(set_notification_prefs.quiet_hours_start, time '22:00'),
    coalesce(set_notification_prefs.quiet_hours_end, time '08:00')
  )
  on conflict (user_id) do update
    set categories = n.categories || excluded.categories,
        quiet_hours_start = coalesce(set_notification_prefs.quiet_hours_start, n.quiet_hours_start),
        quiet_hours_end = coalesce(set_notification_prefs.quiet_hours_end, n.quiet_hours_end);
end;
$$;

revoke execute on function public.set_notification_prefs(jsonb, time, time) from public, anon, service_role;
grant execute on function public.set_notification_prefs(jsonb, time, time) to authenticated;
