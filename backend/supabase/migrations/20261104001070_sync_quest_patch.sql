-- =============================================================================
-- Wyrd · a partial quest edit can never create a quest
--
-- The app sends an edit as only the fields it changed (op 'patch'), so that
-- it cannot put back what another device changed in the others; a new quest
-- goes up whole (op 'upsert'). sync_quest (…_rpc_sync.sql) built a missing
-- row from whatever arrived, and the title is the only field without a
-- default. A rename reaching the server before the quest did (its first
-- version waiting for its objective, or refused) therefore made a quest of
-- defaults: daily, priority 0, no notes, no due date. Every device then
-- pulled that, the device that wrote the quest included.
--
-- A patch of a quest the server does not have is refused instead ('invalid'),
-- and the app answers with the whole row.
-- =============================================================================

create or replace function private.sync_quest(
  p_uid uuid, p_id uuid, p_op text, p_hlc text, p_payload jsonb
)
returns text
language plpgsql
set search_path = ''
as $$
declare
  c_fields constant text[] := array[
    'parent_id', 'tier', 'title', 'notes', 'category', 'priority', 'status', 'due_at',
    'estimated_minutes', 'recurrence', 'intention', 'share_level', 'reminder_at', 'deleted_at'
  ];
  v_payload jsonb := p_payload;
  v_row public.quests;
  v_new public.quests;
  v_merge record;
  v_created timestamptz;
begin
  if p_op = 'delete' then
    v_payload := jsonb_build_object('deleted_at', coalesce(p_payload -> 'deleted_at', to_jsonb(now())));
  elsif p_op not in ('upsert', 'patch') then
    raise exception 'unsupported op "%" for quest', p_op using errcode = '22023';
  end if;

  select * into v_row from public.quests q where q.id = p_id for update;

  if not found then
    if p_op = 'delete' then
      return 'ignored';                      -- tombstone for a quest the server never saw
    end if;
    if p_op = 'patch' then
      -- Part of a row cannot become a row: the sender's whole row comes next.
      raise exception 'quest % is not on the server yet', p_id using errcode = '22023';
    end if;
    v_created := least(coalesce((p_payload ->> 'created_at')::timestamptz, now()), now());
    select * into v_merge from private.lww_merge(
      jsonb_build_object(
        'id', p_id, 'owner_id', p_uid, 'tier', 'daily', 'priority', 0, 'status', 'active',
        'created_at', v_created, 'updated_at', now(), 'change_id', 0
      ),
      '{}'::jsonb, v_payload, c_fields, p_hlc
    );
    v_new := jsonb_populate_record(
      null::public.quests,
      v_merge.merged || jsonb_build_object('hlc', p_hlc, 'field_hlc', v_merge.field_hlc)
    );
    insert into public.quests values (v_new.*);
    return 'applied';
  end if;

  if v_row.owner_id <> p_uid then
    raise exception 'quest belongs to another user' using errcode = '42501';
  end if;

  select * into v_merge from private.lww_merge(to_jsonb(v_row), v_row.field_hlc, v_payload, c_fields, p_hlc);
  if not v_merge.changed then
    return 'ignored';
  end if;
  v_new := jsonb_populate_record(null::public.quests, v_merge.merged);
  update public.quests q set
    parent_id = v_new.parent_id,
    tier = v_new.tier,
    title = v_new.title,
    notes = v_new.notes,
    category = v_new.category,
    priority = v_new.priority,
    status = v_new.status,
    due_at = v_new.due_at,
    estimated_minutes = v_new.estimated_minutes,
    recurrence = v_new.recurrence,
    intention = v_new.intention,
    share_level = v_new.share_level,
    reminder_at = v_new.reminder_at,
    deleted_at = v_new.deleted_at,
    hlc = greatest(q.hlc collate "C", p_hlc collate "C"),
    field_hlc = v_merge.field_hlc
  where q.id = p_id;
  return 'applied';
end;
$$;
