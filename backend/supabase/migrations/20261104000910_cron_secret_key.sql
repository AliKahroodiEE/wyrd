-- =============================================================================
-- Wyrd · internal Edge Function calls with secret keys
--
-- New projects have no service_role JWT. pg_cron jobs and the notification
-- triggers (…_notify_triggers.sql) call Edge Functions through pg_net with a
-- secret key (sb_secret_…) in the `apikey` header; those functions run with
-- verify_jwt = false and check the key in code. A legacy service-role JWT
-- still works: it is also sent as `Authorization: Bearer`.
--
-- Two Vault secrets, written by .github/workflows/deploy-backend.yml through
-- private.set_function_credentials() on every deploy (or once by hand):
--   wyrd_project_url   https://<project-ref>.supabase.co
--   wyrd_secret_key    sb_secret_…   (fallback: the old wyrd_service_role_key)
-- Without pg_net or the secrets every call below is a no-op.
--
-- Everything here runs as the owner: from pg_cron, from SECURITY DEFINER
-- trigger functions or by hand. Nothing is executable by client roles, and
-- the private schema is not visible to them.
-- =============================================================================

-- One decrypted Vault secret; null when Vault or the secret is missing.
create or replace function private.vault_secret(p_name text)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_value text;
begin
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 order by created_at desc limit 1'
    into v_value using p_name;
  return nullif(btrim(v_value), '');
exception
  when undefined_table or undefined_column or invalid_schema_name or insufficient_privilege then
    return null;
end;
$$;

-- Request headers for an internal call: the key as `apikey`; a legacy JWT key
-- also as a bearer token so it passes a gateway JWT check.
create or replace function private.internal_request_headers(p_key text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('Content-Type', 'application/json', 'apikey', p_key)
    || case
         when p_key ~ '^eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$'
           then jsonb_build_object('Authorization', 'Bearer ' || p_key)
         else '{}'::jsonb
       end;
$$;

-- Queues POST <project>/functions/v1/<p_function> with p_body through pg_net
-- (sent after the transaction commits). Returns the pg_net request id, or
-- null when pg_net or the Vault secrets are not available.
create or replace function private.call_edge_function(
  p_function text,
  p_body jsonb,
  p_timeout_ms integer default 5000
)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_url text := private.vault_secret('wyrd_project_url');
  v_key text := coalesce(private.vault_secret('wyrd_secret_key'), private.vault_secret('wyrd_service_role_key'));
  v_request_id bigint;
begin
  if v_url is null or v_key is null or p_function !~ '^[a-z0-9][a-z0-9_-]*$' then
    return null;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)'
    into v_request_id
    using rtrim(v_url, '/') || '/functions/v1/' || p_function,
          p_body,
          private.internal_request_headers(v_key),
          p_timeout_ms;
  return v_request_id;
exception
  when undefined_function or invalid_schema_name or undefined_table then
    return null;
end;
$$;

-- Wakes generate-chronicle to drain pending rows (same contract as before:
-- does nothing when nothing is pending or the call cannot be made).
create or replace function private.dispatch_pending_chronicles()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.chronicles c where c.status = 'pending' and c.attempts < 5) then
    return;
  end if;
  if private.call_edge_function(
       'generate-chronicle', jsonb_build_object('mode', 'pending', 'limit', 20), 60000
     ) is null then
    raise notice 'chronicle dispatch: pg_net or the Vault secrets wyrd_project_url / wyrd_secret_key are missing';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Vault bootstrap (idempotent)
-- ---------------------------------------------------------------------------

-- Creates or replaces one Vault secret by name.
create or replace function private.upsert_vault_secret(p_name text, p_secret text, p_description text)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  execute 'select id from vault.secrets where name = $1 order by created_at desc limit 1'
    into v_id using p_name;
  if v_id is null then
    execute 'select vault.create_secret($1, $2, $3)' into v_id using p_secret, p_name, p_description;
  else
    execute 'select vault.update_secret($1, $2, $3, $4)' using v_id, p_secret, p_name, p_description;
  end if;
  return v_id;
end;
$$;

-- Stores the project URL and secret key internal callers use. Run as
-- postgres (SQL editor, `supabase db query --remote`, the deploy workflow):
--   select private.set_function_credentials('https://<ref>.supabase.co', 'sb_secret_…');
create or replace function private.set_function_credentials(p_project_url text, p_secret_key text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_url text := rtrim(btrim(coalesce(p_project_url, '')), '/');
  v_key text := btrim(coalesce(p_secret_key, ''));
begin
  if v_url !~ '^https?://[^/[:space:]]+$' then
    raise exception 'project URL must look like https://<ref>.supabase.co' using errcode = '22023';
  end if;
  if v_key = '' or v_key ~ '[[:space:]]' or v_key like 'sb_publishable_%' then
    raise exception 'a secret key (sb_secret_…) or the legacy service-role key is required' using errcode = '22023';
  end if;
  perform private.upsert_vault_secret('wyrd_project_url', v_url,
    'Wyrd: project URL for internal Edge Function calls (pg_cron, notify triggers)');
  perform private.upsert_vault_secret('wyrd_secret_key', v_key,
    'Wyrd: secret API key for internal Edge Function calls (pg_cron, notify triggers)');
end;
$$;

revoke execute on all functions in schema private from public;
