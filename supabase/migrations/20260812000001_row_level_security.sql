-- Row-level security.
--
-- The whole privacy story rests on this file. Every table denies by default and
-- only opens up to members of the group a row belongs to.
--
-- The one trap worth naming: a policy on `group_members` that queries
-- `group_members` recurses forever, because evaluating the policy triggers the
-- policy. `is_group_member` is SECURITY DEFINER so it runs with the owner's
-- rights and bypasses RLS, which breaks the cycle.

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.expenses enable row level security;
alter table public.settlements enable row level security;
alter table public.group_invites enable row level security;

-- ---------------------------------------------------------------------------
-- Membership predicate
-- ---------------------------------------------------------------------------

create or replace function public.is_group_member(gid uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.group_members
    where group_id = gid
      and user_id = auth.uid()
      and deleted_at is null
  );
$$;

revoke execute on function public.is_group_member(uuid) from public;
grant execute on function public.is_group_member(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

-- You can read a profile if you share a group with that person. Without this
-- restriction, any signed-in user could enumerate every account on the server.
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.group_members mine
      join public.group_members theirs on theirs.group_id = mine.group_id
      where mine.user_id = auth.uid()
        and mine.deleted_at is null
        and theirs.user_id = profiles.id
        and theirs.deleted_at is null
    )
  );

create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- Groups
-- ---------------------------------------------------------------------------

create policy groups_select on public.groups
  for select to authenticated
  using (public.is_group_member(id));

-- Anyone signed in may create a group, but only as themselves.
create policy groups_insert on public.groups
  for insert to authenticated
  with check (created_by = auth.uid());

create policy groups_update on public.groups
  for update to authenticated
  using (public.is_group_member(id))
  with check (public.is_group_member(id));

-- Deleting a group outright is not allowed; clients set `deleted_at` instead,
-- so the tombstone can reach everyone else's device.
-- ---------------------------------------------------------------------------
-- Group members
-- ---------------------------------------------------------------------------

create policy group_members_select on public.group_members
  for select to authenticated
  using (public.is_group_member(group_id));

-- The first row in a brand new group is the creator adding themselves, at which
-- point they are not yet a member, so `is_group_member` is still false. Allow
-- that specific case as well as ordinary members adding people.
create policy group_members_insert on public.group_members
  for insert to authenticated
  with check (
    public.is_group_member(group_id)
    or exists (
      select 1 from public.groups
      where groups.id = group_members.group_id
        and groups.created_by = auth.uid()
    )
  );

create policy group_members_update on public.group_members
  for update to authenticated
  using (public.is_group_member(group_id))
  with check (
    public.is_group_member(group_id)
    -- You may not hand someone else's slot to a different account. Claiming a
    -- slot happens through redeem_invite, which is SECURITY DEFINER.
    and (user_id is null or user_id = auth.uid() or user_id = group_members.user_id)
  );

-- ---------------------------------------------------------------------------
-- Expenses
-- ---------------------------------------------------------------------------

create policy expenses_select on public.expenses
  for select to authenticated
  using (public.is_group_member(group_id));

create policy expenses_insert on public.expenses
  for insert to authenticated
  with check (public.is_group_member(group_id));

-- Any member can edit any expense in the group. That matches how these apps
-- work in practice: someone mistypes a total and a flatmate fixes it. The
-- activity feed records who changed what.
create policy expenses_update on public.expenses
  for update to authenticated
  using (public.is_group_member(group_id))
  with check (public.is_group_member(group_id));

-- ---------------------------------------------------------------------------
-- Settlements
-- ---------------------------------------------------------------------------

create policy settlements_select on public.settlements
  for select to authenticated
  using (public.is_group_member(group_id));

create policy settlements_insert on public.settlements
  for insert to authenticated
  with check (public.is_group_member(group_id));

create policy settlements_update on public.settlements
  for update to authenticated
  using (public.is_group_member(group_id))
  with check (public.is_group_member(group_id));

-- ---------------------------------------------------------------------------
-- Invites
-- ---------------------------------------------------------------------------

create policy group_invites_select on public.group_invites
  for select to authenticated
  using (public.is_group_member(group_id));

create policy group_invites_insert on public.group_invites
  for insert to authenticated
  with check (public.is_group_member(group_id) and created_by = auth.uid());

create policy group_invites_delete on public.group_invites
  for delete to authenticated
  using (public.is_group_member(group_id));
