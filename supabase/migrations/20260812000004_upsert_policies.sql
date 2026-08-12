-- Let the clients upsert.
--
-- The clients push with `INSERT ... ON CONFLICT`, because a phone that has been
-- offline cannot know whether a row it edited is already on the server. That
-- clause changes which policies Postgres evaluates, and the change is not
-- obvious: for any statement carrying ON CONFLICT, the proposed row must also
-- satisfy the table's **SELECT** policy. Postgres has to be able to see the row
-- it might collide with, so it applies the read rule to the write.
--
-- Every policy here is keyed on `is_group_member`, and the person creating a
-- group is not a member of it until their own row in `group_members` exists.
-- For the length of one statement they own something they cannot see. A plain
-- INSERT was fine; the same INSERT with `on conflict (id) do nothing` failed
-- with "new row violates row-level security policy", which names the wrong
-- half of the problem and sends you looking at the insert policy, where there
-- is nothing wrong.
--
-- That is what broke `adopt_local_group`, and with it the entire path for
-- turning a local group into a shared one.
--
-- The fix is to let the creator through. It is not a widening of who can see
-- what: `created_by` is set from `auth.uid()` by the insert policy and can never
-- name anybody else, so this grants you sight of groups you made yourself. It
-- is also the rule you would want regardless of upserts.

drop policy if exists groups_select on public.groups;

create policy groups_select on public.groups
  for select to authenticated
  using (public.is_group_member(id) or created_by = auth.uid());

drop policy if exists groups_update on public.groups;

create policy groups_update on public.groups
  for update to authenticated
  using (public.is_group_member(id) or created_by = auth.uid())
  with check (public.is_group_member(id) or created_by = auth.uid());

-- The same window exists for the very first roster row, which is the creator
-- adding themselves. `group_members_insert` already allows it; the select and
-- update policies have to agree or the upsert fails in the same way.

drop policy if exists group_members_select on public.group_members;

create policy group_members_select on public.group_members
  for select to authenticated
  using (
    public.is_group_member(group_id)
    or exists (
      select 1 from public.groups
      where groups.id = group_members.group_id
        and groups.created_by = auth.uid()
    )
  );

drop policy if exists group_members_update on public.group_members;

create policy group_members_update on public.group_members
  for update to authenticated
  using (
    public.is_group_member(group_id)
    or exists (
      select 1 from public.groups
      where groups.id = group_members.group_id
        and groups.created_by = auth.uid()
    )
  )
  with check (
    (
      public.is_group_member(group_id)
      or exists (
        select 1 from public.groups
        where groups.id = group_members.group_id
          and groups.created_by = auth.uid()
      )
    )
    -- Unchanged, and the reason this policy stays strict: you may not hand
    -- someone else's slot to a different account. Claiming a slot happens
    -- through redeem_invite, which is SECURITY DEFINER.
    and (user_id is null or user_id = auth.uid() or user_id = group_members.user_id)
  );
