-- Table privileges.
--
-- Row-level security decides *which rows* a role may touch. It does not grant
-- the right to touch the table at all. Both are required, and forgetting this
-- half fails at runtime with "permission denied for table", not at migration
-- time, so it is easy to ship broken.
--
-- Nothing is granted to `anon`: there is no such thing as reading a group
-- without being signed in.

grant usage on schema public to authenticated;

-- Profiles: read (policy-filtered) and update your own.
grant select, update on public.profiles to authenticated;

-- Deletes are absent everywhere on purpose. Clients set `deleted_at` so the
-- tombstone can reach a device that was offline, and a hard delete would leave
-- that device showing a group forever.
grant select, insert, update on public.groups to authenticated;
grant select, insert, update on public.group_members to authenticated;
grant select, insert, update on public.expenses to authenticated;
grant select, insert, update on public.settlements to authenticated;

-- Invites are the exception: revoking a link should really remove it.
grant select, insert, delete on public.group_invites to authenticated;
