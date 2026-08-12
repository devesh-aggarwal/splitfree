-- Deleting, as one call.
--
-- Clients previously sent tombstones as `PATCH /rest/v1/<table>?id=eq.<uuid>`
-- with `{"deleted_at": ...}`. That works from iOS and cannot be done at all from
-- Android: `java.net.HttpURLConnection` validates the method against a fixed
-- list that has no PATCH in it, and PostgREST does not honour an override
-- header. The workarounds are reflection into a private field or a whole HTTP
-- library added for one verb.
--
-- A function is the better answer regardless. It gives one shape for the four
-- tables instead of four, it puts the membership check on the server rather than
-- trusting row-level security to catch a malformed filter, and it is the only
-- version that can refuse a delete for a reason worth reporting.

create or replace function public.mark_deleted(
  p_entity text,
  p_id uuid,
  p_group_id uuid default null
)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_group_id uuid;
begin
  -- Work out which group this row belongs to, then check membership once.
  -- Doing it here rather than leaning on the update policies means a caller
  -- who is not a member gets told so, instead of silently updating no rows.
  v_group_id := case p_entity
    when 'group' then p_id
    when 'member' then p_group_id
    when 'expense' then (select group_id from public.expenses where id = p_id)
    when 'settlement' then (select group_id from public.settlements where id = p_id)
  end;

  if v_group_id is null then
    -- The row is already gone, or was never uploaded. Either way the tombstone
    -- has nothing left to say, and reporting success lets the client stop
    -- retrying it forever.
    return false;
  end if;

  if not public.is_group_member(v_group_id) then
    raise exception 'Not a member of that group';
  end if;

  case p_entity
    when 'group' then
      update public.groups set deleted_at = now() where id = p_id and deleted_at is null;
    when 'member' then
      update public.group_members set deleted_at = now()
      where group_id = p_group_id and member_id = p_id and deleted_at is null;
    when 'expense' then
      update public.expenses set deleted_at = now() where id = p_id and deleted_at is null;
    when 'settlement' then
      update public.settlements set deleted_at = now() where id = p_id and deleted_at is null;
    else
      raise exception 'Unknown entity %', p_entity;
  end case;

  return true;
end;
$$;

grant execute on function public.mark_deleted(text, uuid, uuid) to authenticated;
