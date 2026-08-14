-- SplitFree sync backend.
--
-- Design notes worth reading before changing anything here.
--
-- 1. An expense is one row, not a parent with child tables. Its payers, shares
--    and line items live in JSONB columns. That is deliberate: the expense is
--    the atomic unit of editing, and the split must always sum to the total.
--    With separate tables, a partially-applied sync could leave shares that no
--    longer add up, which corrupts every balance that touches them.
--
-- 2. That invariant is enforced by the database, not just the clients. See the
--    check constraints on `expenses`. A buggy client cannot write a broken
--    split, on any platform, ever.
--
-- 3. `updated_at` is set by a trigger using the server clock, never by the
--    client. Clients have skewed clocks, and last-write-wins on a client clock
--    lets a phone with a wrong date win every conflict forever.
--
-- 4. Deletes are soft. Tombstones are how a deletion reaches a device that was
--    offline when it happened.
--
-- 5. A group member is not necessarily a user. You can add "Marco" to a trip
--    before Marco has an account, or ever. `group_members.user_id` stays null
--    until a real account claims that slot through an invite.

-- Everything here uses core Postgres only. `gen_random_uuid()` has been built
-- in since Postgres 13, so no extension is required.
--
-- The obvious alternative, `uuid_generate_v4()`, needs uuid-ossp, which is
-- installed into the `extensions` schema on Supabase and is not on the search
-- path a migration runs with. It works on a local stack and fails on a hosted
-- project with "function uuid_generate_v4() does not exist", which is a
-- miserable way to find out.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Server-authoritative modification time. See design note 3.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Sums the `amountMinorUnits` field across a JSONB array. Immutable so it can
-- be used in a check constraint, which is the whole point of it existing.
create or replace function public.jsonb_sum_minor_units(entries jsonb)
returns bigint
language sql
immutable
as $$
  select coalesce(sum((elem ->> 'amountMinorUnits')::bigint), 0)
  from jsonb_array_elements(coalesce(entries, '[]'::jsonb)) elem;
$$;

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null default '',
  email text,
  avatar_url text,
  venmo_handle text not null default '',
  paypal_handle text not null default '',
  cash_app_handle text not null default '',
  upi_handle text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- Every authenticated user gets a profile row automatically, so the client
-- never has to handle "signed in but no profile yet".
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, email)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      split_part(coalesce(new.email, ''), '@', 1),
      'You'
    ),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Groups and membership
-- ---------------------------------------------------------------------------

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null default '',
  kind text not null default 'other',
  color_index int not null default 0,
  default_currency_code text not null default 'USD',
  simplify_debts boolean not null default true,
  notes text not null default '',
  is_archived boolean not null default false,
  created_by uuid references auth.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create trigger groups_touch
  before update on public.groups
  for each row execute function public.touch_updated_at();

create index groups_updated_at_idx on public.groups (updated_at);

create table public.group_members (
  group_id uuid not null references public.groups on delete cascade,
  -- The participant id the clients already use locally. Shared by every device
  -- in the group, which is what lets an expense reference a person.
  member_id uuid not null,
  -- Null until a real account claims this slot. See design note 5.
  user_id uuid references auth.users on delete set null,
  display_name text not null default '',
  color_index int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (group_id, member_id)
);

create trigger group_members_touch
  before update on public.group_members
  for each row execute function public.touch_updated_at();

create index group_members_user_idx on public.group_members (user_id);
create index group_members_updated_at_idx on public.group_members (updated_at);

-- One account can only occupy one slot per group.
create unique index group_members_one_slot_per_user
  on public.group_members (group_id, user_id)
  where user_id is not null and deleted_at is null;

-- ---------------------------------------------------------------------------
-- Expenses
-- ---------------------------------------------------------------------------

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  title text not null default '',
  notes text not null default '',
  amount_minor_units bigint not null,
  currency_code text not null,
  date timestamptz not null default now(),
  category text not null default 'general',
  split_method text not null default 'equal',
  tax_minor_units bigint not null default 0,
  tip_minor_units bigint not null default 0,
  base_currency_code text not null default 'USD',
  exchange_rate_to_base double precision not null default 1.0,
  -- [{ "participantId": uuid, "amountMinorUnits": int }]
  payers jsonb not null default '[]'::jsonb,
  -- [{ "participantId": uuid, "amountMinorUnits": int, "weight": number }]
  shares jsonb not null default '[]'::jsonb,
  -- [{ "id": uuid, "name": text, "amountMinorUnits": int, "quantity": int,
  --    "sortOrder": int, "assigneeIds": [uuid] }]
  items jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint amount_is_positive check (amount_minor_units > 0),
  constraint payers_is_array check (jsonb_typeof(payers) = 'array'),
  constraint shares_is_array check (jsonb_typeof(shares) = 'array'),
  constraint items_is_array check (jsonb_typeof(items) = 'array'),
  -- The money invariant, enforced by the database. See design note 2.
  constraint shares_add_up
    check (public.jsonb_sum_minor_units(shares) = amount_minor_units),
  constraint payers_add_up
    check (public.jsonb_sum_minor_units(payers) = amount_minor_units)
);

create trigger expenses_touch
  before update on public.expenses
  for each row execute function public.touch_updated_at();

create index expenses_group_idx on public.expenses (group_id);
create index expenses_updated_at_idx on public.expenses (updated_at);

-- ---------------------------------------------------------------------------
-- Settlements
-- ---------------------------------------------------------------------------

create table public.settlements (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references public.groups on delete cascade,
  from_member_id uuid not null,
  to_member_id uuid not null,
  amount_minor_units bigint not null,
  currency_code text not null,
  date timestamptz not null default now(),
  method text not null default 'cash',
  notes text not null default '',
  base_currency_code text not null default 'USD',
  exchange_rate_to_base double precision not null default 1.0,
  created_by uuid references auth.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint settlement_amount_is_positive check (amount_minor_units > 0),
  constraint settlement_has_two_parties check (from_member_id <> to_member_id)
);

create trigger settlements_touch
  before update on public.settlements
  for each row execute function public.touch_updated_at();

create index settlements_group_idx on public.settlements (group_id);
create index settlements_updated_at_idx on public.settlements (updated_at);

-- ---------------------------------------------------------------------------
-- Invites
-- ---------------------------------------------------------------------------

create table public.group_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  token text not null unique,
  -- The member slot this invite claims. Null means "create a new slot", which
  -- is what a generic share link does.
  member_id uuid,
  created_by uuid references auth.users on delete set null,
  expires_at timestamptz not null default (now() + interval '14 days'),
  accepted_by uuid references auth.users on delete set null,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create index group_invites_token_idx on public.group_invites (token);
