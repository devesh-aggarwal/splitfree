-- Backend tests.
--
-- These run against a real Postgres with the real policies. Anything that
-- claims to protect data is asserted here, because a row-level security policy
-- that was never exercised is a guess.
--
-- Run with:  supabase test db   (or pipe this file into psql)

begin;

create extension if not exists pgtap with schema extensions;
select plan(24);

-- ---------------------------------------------------------------------------
-- Fixtures: two users who share a group, and a third who does not.
-- ---------------------------------------------------------------------------

\set ana  '11111111-1111-1111-1111-111111111111'
\set ben  '22222222-2222-2222-2222-222222222222'
\set eve  '33333333-3333-3333-3333-333333333333'
\set trip '44444444-4444-4444-4444-444444444444'
\set marco_slot '55555555-5555-5555-5555-555555555555'
\set other_group '66666666-6666-6666-6666-666666666666'

insert into auth.users (id, email, instance_id, aud, role)
values
  (:'ana', 'ana@example.com',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  (:'ben', 'ben@example.com',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  (:'eve', 'eve@example.com',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

-- The trigger should have made a profile for each of them.
select is(
  (select count(*)::int from public.profiles where id in (:'ana', :'ben', :'eve')),
  3,
  'every new auth user automatically gets a profile'
);

select is(
  (select display_name from public.profiles where id = :'ana'),
  'ana',
  'profile display name falls back to the local part of the email'
);

-- Ana creates a trip with herself, Ben, and an unclaimed slot for Marco.
insert into public.groups (id, name, kind, created_by, default_currency_code)
values (:'trip', 'Lisbon Trip', 'trip', :'ana', 'USD');

insert into public.group_members (group_id, member_id, user_id, display_name)
values
  (:'trip', :'ana', :'ana', 'Ana'),
  (:'trip', :'ben', :'ben', 'Ben'),
  (:'trip', :'marco_slot', null, 'Marco');

-- Eve has a group of her own that the others know nothing about.
insert into public.groups (id, name, created_by) values (:'other_group', 'Eve only', :'eve');
insert into public.group_members (group_id, member_id, user_id, display_name)
values (:'other_group', :'eve', :'eve', 'Eve');

-- ---------------------------------------------------------------------------
-- The money invariant, enforced by the database
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.expenses (id, group_id, amount_minor_units, currency_code, payers, shares)
    values (
      '77777777-7777-7777-7777-777777777777',
      '44444444-4444-4444-4444-444444444444',
      8450, 'USD',
      '[{"participantId":"11111111-1111-1111-1111-111111111111","amountMinorUnits":8450}]',
      '[{"participantId":"11111111-1111-1111-1111-111111111111","amountMinorUnits":2817},
        {"participantId":"22222222-2222-2222-2222-222222222222","amountMinorUnits":2817},
        {"participantId":"55555555-5555-5555-5555-555555555555","amountMinorUnits":2816}]'
    )$$,
  'an expense whose shares sum exactly to the total is accepted'
);

select throws_ok(
  $$insert into public.expenses (group_id, amount_minor_units, currency_code, payers, shares)
    values (
      '44444444-4444-4444-4444-444444444444', 1000, 'USD',
      '[{"participantId":"11111111-1111-1111-1111-111111111111","amountMinorUnits":1000}]',
      '[{"participantId":"11111111-1111-1111-1111-111111111111","amountMinorUnits":333},
        {"participantId":"22222222-2222-2222-2222-222222222222","amountMinorUnits":333},
        {"participantId":"55555555-5555-5555-5555-555555555555","amountMinorUnits":333}]'
    )$$,
  '23514',
  null,
  'an expense that loses a cent is rejected by the database, not just the client'
);

select throws_ok(
  $$insert into public.expenses (group_id, amount_minor_units, currency_code, payers, shares)
    values (
      '44444444-4444-4444-4444-444444444444', 1000, 'USD',
      '[{"participantId":"11111111-1111-1111-1111-111111111111","amountMinorUnits":900}]',
      '[{"participantId":"11111111-1111-1111-1111-111111111111","amountMinorUnits":1000}]'
    )$$,
  '23514',
  null,
  'an expense where the payers do not cover the total is rejected'
);

select throws_ok(
  $$insert into public.expenses (group_id, amount_minor_units, currency_code, payers, shares)
    values ('44444444-4444-4444-4444-444444444444', 0, 'USD', '[]', '[]')$$,
  '23514',
  null,
  'a zero-amount expense is rejected'
);

select throws_ok(
  $$insert into public.settlements (group_id, from_member_id, to_member_id, amount_minor_units, currency_code)
    values (
      '44444444-4444-4444-4444-444444444444',
      '11111111-1111-1111-1111-111111111111',
      '11111111-1111-1111-1111-111111111111',
      500, 'USD'
    )$$,
  '23514',
  null,
  'a settlement from someone to themselves is rejected'
);

-- ---------------------------------------------------------------------------
-- Server-authoritative timestamps
-- ---------------------------------------------------------------------------

-- A client that sends a wildly wrong updated_at must not be able to win every
-- future conflict.
update public.expenses
set title = 'Dinner', updated_at = '2099-01-01'
where id = '77777777-7777-7777-7777-777777777777';

select ok(
  (select updated_at from public.expenses where id = '77777777-7777-7777-7777-777777777777') < now() + interval '1 minute',
  'the server overrides a client-supplied updated_at'
);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

set local role authenticated;

-- Ana is a member and sees the trip.
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (select count(*)::int from public.groups where id = '44444444-4444-4444-4444-444444444444'),
  1,
  'a member can read their own group'
);

select is(
  (select count(*)::int from public.expenses),
  1,
  'a member can read expenses in their group'
);

select is(
  (select count(*)::int from public.group_members where group_id = '44444444-4444-4444-4444-444444444444'),
  3,
  'a member can read the roster, and the membership policy does not recurse'
);

select is(
  (select count(*)::int from public.groups where id = '66666666-6666-6666-6666-666666666666'),
  0,
  'a member cannot see a group they do not belong to'
);

-- Eve is the outsider. This is the test that matters most.
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

select is(
  (select count(*)::int from public.expenses where group_id = '44444444-4444-4444-4444-444444444444'),
  0,
  'an outsider cannot read another group''s expenses'
);

select is(
  (select count(*)::int from public.groups where id = '44444444-4444-4444-4444-444444444444'),
  0,
  'an outsider cannot read another group'
);

select is(
  (select count(*)::int from public.group_members where group_id = '44444444-4444-4444-4444-444444444444'),
  0,
  'an outsider cannot read another group''s roster'
);

select is(
  (select count(*)::int from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  0,
  'an outsider cannot read the profile of someone they share no group with'
);

select throws_ok(
  $$insert into public.expenses (group_id, amount_minor_units, currency_code, payers, shares)
    values (
      '44444444-4444-4444-4444-444444444444', 500, 'USD',
      '[{"participantId":"33333333-3333-3333-3333-333333333333","amountMinorUnits":500}]',
      '[{"participantId":"33333333-3333-3333-3333-333333333333","amountMinorUnits":500}]'
    )$$,
  '42501',
  null,
  'an outsider cannot write an expense into a group they do not belong to'
);

-- Ben shares a group with Ana, so he may see her profile.
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select is(
  (select count(*)::int from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  1,
  'you can read the profile of someone you share a group with'
);

-- ---------------------------------------------------------------------------
-- pull_changes
-- ---------------------------------------------------------------------------

select is(
  jsonb_array_length(public.pull_changes('-infinity') -> 'expenses'),
  1,
  'pull_changes returns the expenses a member can see'
);

set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

select is(
  jsonb_array_length(public.pull_changes('-infinity') -> 'expenses'),
  0,
  'pull_changes respects row-level security and leaks nothing to an outsider'
);

select is(
  jsonb_array_length(public.pull_changes(now() + interval '1 hour') -> 'groups'),
  0,
  'pull_changes with a future cursor returns nothing'
);

-- ---------------------------------------------------------------------------
-- Invites
-- ---------------------------------------------------------------------------

reset role;

insert into public.group_invites (group_id, token, member_id, created_by, expires_at)
values (
  '44444444-4444-4444-4444-444444444444',
  'testtoken',
  '55555555-5555-5555-5555-555555555555',
  '11111111-1111-1111-1111-111111111111',
  now() + interval '7 days'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

-- Eve redeems the invite Ana made for Marco, claiming that slot.
select is(
  (public.redeem_invite('testtoken') ->> 'claimed')::boolean,
  true,
  'redeeming an invite claims the reserved member slot'
);

reset role;

select is(
  (select user_id from public.group_members
   where group_id = '44444444-4444-4444-4444-444444444444'
     and member_id = '55555555-5555-5555-5555-555555555555'),
  '33333333-3333-3333-3333-333333333333'::uuid,
  'the claimed slot keeps its member id, so existing expenses still point at it'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

select is(
  (select count(*)::int from public.expenses where group_id = '44444444-4444-4444-4444-444444444444'),
  1,
  'after joining, the new member can read the group history'
);

select * from finish();
rollback;
