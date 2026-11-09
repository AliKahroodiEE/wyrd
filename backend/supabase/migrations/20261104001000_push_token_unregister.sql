-- =============================================================================
-- Wyrd · unregistering a device from push
--
-- On sign-out the app removes this device's FCM token while the session is
-- still valid (push_platform.dart), so the account stops receiving pushes on
-- a device it left. Device tokens are credentials for the push service
-- (export_my_data leaves them out), so clients get no access to
-- public.push_tokens itself: with table access, anyone holding a leaked
-- access token could list the account's device tokens. This function
-- deletes the given token only when it belongs to the caller, and answers
-- the same whether or not it did.
-- =============================================================================

create or replace function public.unregister_push_token(token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_uid();
begin
  delete from public.push_tokens t
  where t.token = unregister_push_token.token and t.user_id = v_uid;
end;
$$;

revoke execute on function public.unregister_push_token(text) from public, anon, service_role;
grant execute on function public.unregister_push_token(text) to authenticated;
