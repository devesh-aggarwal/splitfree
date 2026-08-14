-- Join codes.
--
-- Sharing no longer needs an account, so an invite is the only thing standing
-- between somebody and a group. It has to be short enough to read aloud or type
-- from a message, and still hard to guess.
--
-- Ten characters from Crockford's base32 alphabet: 32^10, about 2^50. The
-- alphabet leaves out I, L, O and U, so nothing is confusable with 1, 0 or a
-- rude word, and codes are shown grouped as ABCDE-FGHIJ.
--
-- The old 32 hex character tokens still work. Existing links keep resolving.

create or replace function public.generate_join_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  code text := '';
  i int;
begin
  for i in 1..10 loop
    -- gen_random_uuid is core Postgres, so this depends on no extension.
    code := code || substr(
      alphabet,
      1 + floor(random() * length(alphabet))::int,
      1
    );
  end loop;
  return code;
end;
$$;

-- Codes are compared after stripping anything that is not a letter or digit and
-- upper-casing, so "abcde-fghij", "ABCDE FGHIJ" and "ABCDEFGHIJ" are one code.
-- People retype these from a screen, and a dash they did or did not include
-- should never be the reason it fails.
create or replace function public.normalize_join_code(raw text)
returns text
language sql
immutable
set search_path = public
as $$
  select upper(regexp_replace(coalesce(raw, ''), '[^a-zA-Z0-9]', '', 'g'));
$$;

grant execute on function public.normalize_join_code(text) to authenticated;

create index if not exists group_invites_normalized_token_idx
  on public.group_invites (public.normalize_join_code(token));

-- ---------------------------------------------------------------------------
-- Issue, preview and redeem, all speaking the new format
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
  v_attempt int := 0;
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'Not a member of that group';
  end if;

  -- A collision is vanishingly unlikely, but a duplicate would hand somebody
  -- the wrong group, so it is checked rather than assumed.
  loop
    v_token := public.generate_join_code();
    exit when not exists (
      select 1 from public.group_invites
      where public.normalize_join_code(token) = v_token
    );
    v_attempt := v_attempt + 1;
    if v_attempt > 10 then
      raise exception 'Could not allocate a join code';
    end if;
  end loop;

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
  select * into v_invite
  from public.group_invites
  where public.normalize_join_code(token) = public.normalize_join_code(p_token);

  if not found then
    raise exception 'That code is not valid';
  end if;
  if v_invite.expires_at < now() then
    raise exception 'That code has expired';
  end if;

  select * into v_group from public.groups where id = v_invite.group_id;
  if not found or v_group.deleted_at is not null then
    raise exception 'That group no longer exists';
  end if;

  return jsonb_build_object(
    'group_id', v_group.id,
    'group_name', v_group.name,
    'group_kind', v_group.kind,
    'is_direct', v_group.is_direct,
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

  -- Already in the group: hand back the existing slot instead of erroring, so
  -- using a code twice is harmless.
  select member_id into v_member_id
  from public.group_members
  where group_id = v_invite.group_id
    and user_id = auth.uid()
    and deleted_at is null;

  if v_member_id is not null then
    return jsonb_build_object('group_id', v_invite.group_id, 'member_id', v_member_id, 'claimed', false);
  end if;

  select coalesce(nullif(display_name, ''), 'Someone') into v_display_name
  from public.profiles where id = auth.uid();

  if v_invite.member_id is not null then
    update public.group_members
    set user_id = auth.uid(),
        display_name = case when display_name = '' then coalesce(v_display_name, 'Someone') else display_name end
    where group_id = v_invite.group_id
      and member_id = v_invite.member_id
      and user_id is null
      and deleted_at is null
    returning member_id into v_member_id;
  end if;

  if v_member_id is null then
    v_member_id := gen_random_uuid();
    insert into public.group_members (group_id, member_id, user_id, display_name)
    values (v_invite.group_id, v_member_id, auth.uid(), coalesce(v_display_name, 'Someone'));
  end if;

  update public.group_invites
  set accepted_by = auth.uid(), accepted_at = now()
  where id = v_invite.id;

  return jsonb_build_object('group_id', v_invite.group_id, 'member_id', v_member_id, 'claimed', true);
end;
$$;

grant execute on function public.redeem_invite(text) to authenticated;
