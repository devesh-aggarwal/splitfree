-- Let somebody say who they are when they join.
--
-- Without a sign-in there is no email to derive a name from, so everyone who
-- joined arrived in the group as "Someone". The app already knows what the
-- person called themselves when they first opened it, so it passes that along.
--
-- The name only fills a blank. A slot that was reserved for "Marco" keeps
-- saying Marco, because the person who set the group up chose that on purpose.

create or replace function public.redeem_invite(
  p_token text,
  p_display_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.group_invites;
  v_member_id uuid;
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'No identity';
  end if;

  select * into v_invite
  from public.group_invites
  where public.normalize_join_code(token) = public.normalize_join_code(p_token)
  for update;

  if not found then
    raise exception 'That code is not valid';
  end if;
  if v_invite.expires_at < now() then
    raise exception 'That code has expired';
  end if;

  select member_id into v_member_id
  from public.group_members
  where group_id = v_invite.group_id
    and user_id = auth.uid()
    and deleted_at is null;

  if v_member_id is not null then
    return jsonb_build_object('group_id', v_invite.group_id, 'member_id', v_member_id, 'claimed', false);
  end if;

  v_name := nullif(trim(coalesce(p_display_name, '')), '');

  -- Remember it, so the next group they join does not ask again.
  if v_name is not null then
    update public.profiles set display_name = v_name
    where id = auth.uid() and (display_name is null or display_name = '' or display_name = 'You');
  end if;

  v_name := coalesce(
    v_name,
    nullif((select display_name from public.profiles where id = auth.uid()), ''),
    'Someone'
  );

  if v_invite.member_id is not null then
    update public.group_members
    set user_id = auth.uid(),
        display_name = case when display_name = '' then v_name else display_name end
    where group_id = v_invite.group_id
      and member_id = v_invite.member_id
      and user_id is null
      and deleted_at is null
    returning member_id into v_member_id;
  end if;

  if v_member_id is null then
    v_member_id := gen_random_uuid();
    insert into public.group_members (group_id, member_id, user_id, display_name)
    values (v_invite.group_id, v_member_id, auth.uid(), v_name);
  end if;

  update public.group_invites
  set accepted_by = auth.uid(), accepted_at = now()
  where id = v_invite.id;

  return jsonb_build_object('group_id', v_invite.group_id, 'member_id', v_member_id, 'claimed', true);
end;
$$;

-- The one-argument form would otherwise linger as an overload and make
-- PostgREST refuse every call as ambiguous.
drop function if exists public.redeem_invite(text);

grant execute on function public.redeem_invite(text, text) to authenticated;
