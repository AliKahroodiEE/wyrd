-- =============================================================================
-- Wyrd · when the account's own settings were last chosen
--
-- A new device takes over the account's name, weekly target, motivation and
-- AI opt-in from the server (sync_coordinator.dart), unless no client has
-- chosen them yet: then the choices made on that device (during onboarding,
-- as a guest) go up instead. updated_at cannot tell the two apart, because a
-- device sending its language or time zone moves it too, and a failed
-- account upload right after such an update would make the device take over
-- the server's defaults (turning an AI opt-out back on). account_set_at
-- moves only when one of those four settings changes. Clients cannot write
-- it: their UPDATE grant on profiles covers named columns only.
-- =============================================================================

alter table public.profiles add column if not exists account_set_at timestamptz;

create or replace function private.touch_profile_account()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.display_name, new.weekly_target, new.motivation, new.ai_evaluation_enabled)
     is distinct from (old.display_name, old.weekly_target, old.motivation, old.ai_evaluation_enabled) then
    new.account_set_at := pg_catalog.now();
  end if;
  return new;
end;
$$;

revoke execute on function private.touch_profile_account() from public;

drop trigger if exists profiles_account_set on public.profiles;
create trigger profiles_account_set
  before update on public.profiles
  for each row execute function private.touch_profile_account();

-- Profiles a client already changed before this migration count as chosen.
update public.profiles p set account_set_at = p.updated_at
 where p.account_set_at is null and p.updated_at > p.created_at;
