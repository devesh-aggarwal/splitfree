-- Sync and invite RPCs.
--
-- The sync contract is deliberately small: pull everything that changed since a
-- cursor, push rows you have edited. Conflicts resolve last-write-wins on the
-- server clock, which is the same rule the offline `.splitfree` file already
-- uses, so the two paths behave identically.

-- ---------------------------------------------------------------------------
-- Pull
-- ---------------------------------------------------------------------------

-- Returns everything visible to the caller that changed after `since`,
-- including tombstones, in one round trip.
--
-- `server_time` comes back with the payload and becomes the client's next
-- cursor. Taking it from the server rather than the device is what keeps a
-- phone with a wrong clock from either missing rows or re-fetching forever.
create or replace function public.pull_changes(since timestamptz default '-infinity')
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select jsonb_build_object(
    'server_time', now(),
    'groups', coalesce((
      select jsonb_agg(to_jsonb(g))
      from public.groups g
      where g.updated_at > since
    ), '[]'::jsonb),
    'members', coalesce((
      select jsonb_agg(to_jsonb(m))
      from public.group_members m
      where m.updated_at > since
    ), '[]'::jsonb),
    'expenses', coalesce((
      select jsonb_agg(to_jsonb(e))
      from public.expenses e
      where e.updated_at > since
    ), '[]'::jsonb),
    'settlements', coalesce((
      select jsonb_agg(to_jsonb(s))
      from public.settlements s
      where s.updated_at > since
    ), '[]'::jsonb),
    'profiles', coalesce((
      select jsonb_agg(to_jsonb(p))
      from public.profiles p
      where p.updated_at > since
    ), '[]'::jsonb)
  );
$$;

grant execute on function public.pull_changes(timestamptz) to authenticated;

-- ---------------------------------------------------------------------------
-- Invites
-- ---------------------------------------------------------------------------

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
  v_token := encode(gen_random_bytes(16), 'hex');

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

-- Look at an invite before accepting it, so the app can say "Ana invited you to
-- Lisbon Trip, 4 members" rather than asking someone to join blind.
--
-- SECURITY DEFINER because the caller is not a member yet, so RLS would hide
-- the group. It returns only what an invitee needs to make a decision.
create or replace function public.preview_invite(p_token text)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_invite public.group_invites;
  v_group public.groups;
begin
  select * into v_invite from public.group_invites where token = p_token;
  if not found then
    raise exception 'That invite link is not valid';
  end if;
  if v_invite.expires_at < now() then
    raise exception 'That invite link has expired';
  end if;

  select * into v_group from public.groups where id = v_invite.group_id;
  if not found or v_group.deleted_at is not null then
    raise exception 'That group no longer exists';
  end if;

  return jsonb_build_object(
    'group_id', v_group.id,
    'group_name', v_group.name,
    'group_kind', v_group.kind,
    'member_count', (
      select count(*) from public.group_members
      where group_id = v_group.id and deleted_at is null
    ),
    'claims_member_id', v_invite.member_id,
    'claims_member_name', (
      select display_name from public.group_members
      where group_id = v_group.id and member_id = v_invite.member_id
    ),
    'already_member', exists (
      select 1 from public.group_members
      where group_id = v_group.id and user_id = auth.uid() and deleted_at is null
    )
  );
end;
$$;

grant execute on function public.preview_invite(text) to authenticated;

-- Accepts an invite: either claims the slot the inviter reserved, or creates a
-- new one.
--
-- SECURITY DEFINER for the same reason as above, and because claiming a slot
-- means writing a `user_id` that the ordinary update policy forbids.
create or replace function public.redeem_invite(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.group_invites;
  v_member_id uuid;
  v_display_name text;
begin
  if auth.uid() is null then
    raise exception 'Sign in first';
  end if;

  select * into v_invite from public.group_invites where token = p_token for update;
  if not found then
    raise exception 'That invite link is not valid';
  end if;
  if v_invite.expires_at < now() then
    raise exception 'That invite link has expired';
  end if;

  -- Already in the group: hand back the existing slot instead of erroring, so
  -- tapping an old link twice is harmless.
  select member_id into v_member_id
  from public.group_members
  where group_id = v_invite.group_id
    and user_id = auth.uid()
    and deleted_at is null;

  if v_member_id is not null then
    return jsonb_build_object('group_id', v_invite.group_id, 'member_id', v_member_id, 'claimed', false);
  end if;

  select coalesce(display_name, 'You') into v_display_name
  from public.profiles where id = auth.uid();

  if v_invite.member_id is not null then
    -- Claim the reserved slot, but only if nobody else already did.
    update public.group_members
    set user_id = auth.uid(),
        display_name = case when display_name = '' then v_display_name else display_name end
    where group_id = v_invite.group_id
      and member_id = v_invite.member_id
      and user_id is null
      and deleted_at is null
    returning member_id into v_member_id;
  end if;

  if v_member_id is null then
    -- No reserved slot, or someone beat us to it. Create a fresh one.
    v_member_id := uuid_generate_v4();
    insert into public.group_members (group_id, member_id, user_id, display_name)
    values (v_invite.group_id, v_member_id, auth.uid(), v_display_name);
  end if;

  update public.group_invites
  set accepted_by = auth.uid(), accepted_at = now()
  where id = v_invite.id;

  return jsonb_build_object('group_id', v_invite.group_id, 'member_id', v_member_id, 'claimed', true);
end;
$$;

grant execute on function public.redeem_invite(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Adopting a local group
-- ---------------------------------------------------------------------------

-- Uploads a group that was created offline, keeping the ids the device already
-- uses so its local expenses keep pointing at the right people.
--
-- Without this, turning on sync for an existing group would mean rewriting
-- every local id, and any expense that failed to migrate would silently detach
-- from its participants.
create or replace function public.adopt_local_group(
  p_group_id uuid,
  p_name text,
  p_kind text,
  p_color_index int,
  p_currency_code text,
  p_simplify_debts boolean,
  p_members jsonb
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
    id, name, kind, color_index, default_currency_code, simplify_debts, created_by
  )
  values (
    p_group_id, p_name, p_kind, p_color_index, p_currency_code, p_simplify_debts, auth.uid()
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

grant execute on function public.adopt_local_group(uuid, text, text, int, text, boolean, jsonb) to authenticated;
