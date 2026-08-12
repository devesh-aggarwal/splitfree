-- Two things the clients need that no SQL-only test could have caught.
--
-- Both were found by `supabase/tests/contract_test.sh`, which sends the same
-- HTTP requests the apps send. The pgTAP suite passes on both counts because it
-- talks to Postgres directly: it never goes through PostgREST, and it inserted
-- invite rows itself rather than asking the function to make one.

-- ---------------------------------------------------------------------------
-- 1. Invite tokens
-- ---------------------------------------------------------------------------

-- `gen_random_bytes` lives in the `extensions` schema on Supabase, and
-- `create_invite` pins `search_path = public` — correctly, since a mutable
-- search_path on a function is how privilege escalation gets in. The result was
-- that every attempt to create an invite failed with "function
-- gen_random_bytes(integer) does not exist".
--
-- Fixed by naming the schema rather than by loosening the search path.

create or replace function public.create_invite(
  p_group_id uuid,
  p_member_id uuid default null,
  p_valid_days int default 14
)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_token text;
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'Not a member of that group';
  end if;

  -- 32 hex characters from a cryptographically secure source.
  v_token := encode(extensions.gen_random_bytes(16), 'hex');

  insert into public.group_invites (group_id, token, member_id, created_by, expires_at)
  values (
    p_group_id,
    v_token,
    p_member_id,
    auth.uid(),
    now() + make_interval(days => greatest(1, p_valid_days))
  );

  return v_token;
end;
$$;

grant execute on function public.create_invite(uuid, uuid, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Who created a row
-- ---------------------------------------------------------------------------

-- `groups_insert` requires `created_by = auth.uid()`, and a client upsert of an
-- existing group does not send `created_by` — it has no business deciding who
-- created a group it is only editing. Postgres still evaluates the insert check
-- against the proposed row, which had a null `created_by`, so every push of an
-- edited group name was refused with a 403.
--
-- A column default answers it at the right layer: the server decides who the
-- author is, from the token, and the clients never send the field at all. On the
-- conflict path PostgREST only updates the columns actually present in the
-- payload, so `created_by` keeps naming whoever really created the row rather
-- than the last person to rename it.

alter table public.groups alter column created_by set default auth.uid();
alter table public.expenses alter column created_by set default auth.uid();
alter table public.settlements alter column created_by set default auth.uid();
