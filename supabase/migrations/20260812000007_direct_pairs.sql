-- Friendships.
--
-- Adding a friend by link has to mean something: if the expenses the two of you
-- share do not travel, the link is decoration and the friend list is a lie.
--
-- A friendship is therefore stored as an ordinary two-person group, flagged. It
-- gets the sync engine, the row-level security, the invites and the tombstones
-- that groups already have, and adds one column instead of a parallel concept
-- with its own policies to get wrong.
--
-- The flag exists only so the clients can present it as a friend rather than as
-- a group in the list. Nothing on the server treats these rows differently.

alter table public.groups
  add column if not exists is_direct boolean not null default false;

comment on column public.groups.is_direct is
  'A two-person group shown as a friendship rather than as a group. Server '
  'behaviour is identical either way.';

-- `adopt_local_group` is how a group created offline reaches the server, so it
-- has to be able to carry the flag.
--
-- The old version is dropped first. `create or replace` does not replace a
-- function when the argument count differs: it adds an overload, and PostgREST
-- then refuses every call with "could not choose the best candidate function",
-- because a default argument makes both signatures match the same request.
drop function if exists public.adopt_local_group(uuid, text, text, int, text, boolean, jsonb);

create or replace function public.adopt_local_group(
  p_group_id uuid,
  p_name text,
  p_kind text,
  p_color_index int,
  p_currency_code text,
  p_simplify_debts boolean,
  p_members jsonb,
  p_is_direct boolean default false
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_member jsonb;
begin
  insert into public.groups (
    id, name, kind, color_index, default_currency_code, simplify_debts,
    is_direct, created_by
  )
  values (
    p_group_id, p_name, p_kind, p_color_index, p_currency_code, p_simplify_debts,
    coalesce(p_is_direct, false), auth.uid()
  )
  on conflict (id) do nothing;

  for v_member in select * from jsonb_array_elements(p_members)
  loop
    insert into public.group_members (group_id, member_id, user_id, display_name, color_index)
    values (
      p_group_id,
      (v_member ->> 'member_id')::uuid,
      case when (v_member ->> 'is_me')::boolean then auth.uid() else null end,
      coalesce(v_member ->> 'display_name', ''),
      coalesce((v_member ->> 'color_index')::int, 0)
    )
    on conflict (group_id, member_id) do nothing;
  end loop;

  return p_group_id;
end;
$$;

grant execute on function
  public.adopt_local_group(uuid, text, text, int, text, boolean, jsonb, boolean)
  to authenticated;
