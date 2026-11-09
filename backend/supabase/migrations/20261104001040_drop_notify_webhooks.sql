-- =============================================================================
-- Wyrd · retiring the dashboard notification webhooks
--
-- Before …_notify_triggers.sql, the README told owners to create three
-- Database Webhooks in the dashboard: INSERT on public.reactions,
-- public.comments and public.feed_events, POST to /functions/v1/notify. A
-- Database Webhook is a trigger that runs supabase_functions.http_request
-- with the URL as its first argument; next to our own triggers it would send
-- every push twice. This drops every such trigger on those three tables
-- whose URL's path, right after the host, is /functions/v1/notify (or
-- continues with a query, fragment or further path); a relay that only
-- carries such a URL somewhere later stays. The URL is read the way pg_net's
-- libcurl reads it: the scheme in any case (HTTPS:// is https://) and one to
-- three slashes after it (Studio accepts https:///<ref>…), then a host that
-- is not empty. Our triggers (private.notify_on_insert),
-- webhooks to any other URL, /functions/v1/notify-moderators included, and
-- webhooks that mention notify only in a later argument stay. Where the
-- supabase_functions schema does not exist (no webhook was ever created,
-- or PGlite in the validator) nothing matches.
-- =============================================================================

do $$
declare
  v_hook record;
begin
  for v_hook in
    select t.tgname, c.relname
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
    where n.nspname = 'public'
      and c.relname in ('reactions', 'comments', 'feed_events')
      and not t.tgisinternal
      and pn.nspname = 'supabase_functions' and p.proname = 'http_request'
      -- tgargs: the arguments (URL, method, headers, params, timeout), each
      -- ended by a NUL byte, which encode(…, 'escape') writes as the four
      -- characters \000 (E'\\000'; a backslash in an argument becomes \\).
      -- The URL is what comes before the first one. Without arguments there
      -- is no URL. libcurl refuses no slash or four, and https:///functions/…
      -- has the host "functions", so neither reaches notify.
      and t.tgnargs > 0
      and split_part(encode(t.tgargs, 'escape'), E'\\000', 1)
        ~ '^[A-Za-z][A-Za-z0-9+.-]*:/{1,3}[^/?#]+/functions/v1/notify([/?#]|$)'
  loop
    execute format('drop trigger %I on public.%I', v_hook.tgname, v_hook.relname);
    raise notice 'dropped dashboard webhook % on public.%: the notify triggers replace it',
      v_hook.tgname, v_hook.relname;
  end loop;
end;
$$;
