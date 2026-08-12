# SplitFree backend

Postgres on Supabase: auth, sync between friends, and group invites.

Adding this changes what the app is. Until now nothing left the device. With an
account, expenses in a shared group are stored on a server that can read them.
The trade is deliberate, and it is what makes a friend's expense appear on your
phone. See [Privacy](#privacy) for what has to change in the apps and on the
App Store listing before this ships.

## Running it locally

Needs Docker.

```bash
supabase start          # applies every migration, prints your local keys
supabase test db        # 24 assertions against the real policies
supabase stop           # frees the containers when you're done
```

`supabase start` prints an `API_URL` and a publishable key. Those are the two
values the mobile clients need.

## Deploying

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

Then in the Supabase dashboard:

1. **Authentication → Providers:** enable Apple, Google and email. Apple requires
   Sign in with Apple in any app that offers another third-party sign-in, so
   those two travel together.
2. **Authentication → URL Configuration:** add `splitfree://auth-callback` to the
   redirect allow-list, or browser sign-in returns to nowhere.
3. **Authentication → Email Templates → Magic Link:** the template must contain
   `{{ .Token }}`. This one is easy to miss and fails in a way that gives you
   nothing to go on: the apps ask for a six-digit code, GoTrue generates one
   either way, and the stock template shows only a link — so the code exists,
   nobody is ever shown it, and sign-in just doesn't work. Copy
   `supabase/templates/magic_link.html`, which the local stack already uses.

## How sync works

Offline-first. The device keeps its own database and stays the thing you read
and write; the server is a replica that other people can also reach.

- **Pull:** `pull_changes(since)` returns everything visible to you that changed
  after a cursor, tombstones included, in one round trip. It hands back
  `server_time`, which becomes your next cursor.
- **Push:** ordinary upserts. Row-level security decides what lands.
- **Conflicts:** last write wins on `updated_at`, which is set by a database
  trigger from the server clock and never by the client. A phone with a wrong
  date would otherwise win every conflict it ever entered.
- **Deletes:** soft, via `deleted_at`. A tombstone is the only way a deletion
  reaches a device that was offline when it happened.

This is the same rule the offline `.splitfree` file already uses, so the two
paths behave identically and there is one conflict story to explain rather than
two.

## Two decisions worth understanding before you change anything

**An expense is one row.** Its payers, shares and line items are JSONB columns
rather than child tables. The expense is the unit people edit, and its split
must always sum to the total. With child tables, a partially-applied sync could
leave shares that no longer add up, and every balance touching them would be
quietly wrong.

That invariant is enforced by the database, not just by the clients:

```sql
constraint shares_add_up
  check (public.jsonb_sum_minor_units(shares) = amount_minor_units)
```

No client on any platform, present or future, can write a split that loses a
cent. The cost is that balances can't easily be computed in SQL, so a future web
app would need the balance engine ported to it, or a view added here.

**A group member is not necessarily a user.** You can add "Marco" to a trip
before Marco has an account, or ever. `group_members.member_id` is the stable id
every device uses; `user_id` stays null until a real account claims that slot
through an invite. Claiming keeps the original `member_id`, which is why the
expenses already pointing at Marco still work the moment he joins.

## Privacy

The About screens in both apps and [PRIVACY.md](../PRIVACY.md) now describe this
accurately: local by default, uploaded per group when somebody shares one.

Before submitting to either store, the app's privacy declaration has to match.
"Data Not Collected" is no longer true. The honest answer is:

| Category | Collected | Linked to identity | Used for tracking |
|---|---|---|---|
| Email address | Yes, if you sign in | Yes | No |
| User ID | Yes, if you sign in | Yes | No |
| Other user content (shared expenses) | Yes | Yes | No |

Nothing is used for advertising or tracking, there is no analytics SDK, and no
data is shared with third parties beyond the hosting provider.

What the design already does for you: nothing is granted to `anon`, so there is
no unauthenticated read path at all; you can only read a profile if you share a
group with that person, so accounts can't be enumerated; and every table denies
by default.

## Tests

Two suites, and they catch different things.

```bash
supabase test db                  # 24 pgTAP assertions on the schema and policies
supabase/tests/contract_test.sh   # 19 assertions on what the clients actually send
```

`tests/backend_test.sql` runs against real Postgres with the real policies,
because an untested security policy is a guess. It covers the money
invariant, server-authoritative timestamps, isolation between groups, that
`pull_changes` leaks nothing to an outsider, and invite redemption.

The grants migration exists because these tests caught its absence: row-level
security says *which rows* a role may touch, not whether it may touch the table
at all. Without `GRANT`, every client query fails at runtime with "permission
denied", and nothing in the migrations complains.

`tests/contract_test.sh` sends the same HTTP requests the apps send. SQL tests
cannot catch a disagreement between the schema and the clients, because they
never go through PostgREST. It found three bugs that both codebases looked fine
without:

- **Sharing a group was impossible.** `INSERT ... ON CONFLICT` makes Postgres
  apply the table's **SELECT** policy to the proposed row, and you cannot read a
  group whose member row does not exist yet. A plain insert worked; the same
  insert with `on conflict do nothing` failed with "new row violates row-level
  security policy", which points at the insert policy, where nothing is wrong.
- **Every invite failed.** `gen_random_bytes` lives in the `extensions` schema,
  and `create_invite` correctly pins `search_path = public`. The pgTAP suite
  passed because it inserted invite rows itself instead of calling the function.
- **Renaming a shared group was refused.** The clients do not send `created_by`
  when editing a group they did not create, and the insert policy is still
  evaluated against the proposed row.

## Not built yet

Both apps sync, sign in, invite and join. What is missing:

- **Realtime subscriptions.** Changes arrive on the next sync, which runs at
  launch, when the app comes back to the foreground, and on demand. A friend's
  expense does not appear while you are staring at the screen.
- **Push notifications.**
- **Account deletion in-app.** The privacy policy currently points at an email
  address, which is honest but worse than a button.
- **Rate limiting on invite redemption.** Tokens are 128 bits of randomness and
  expire in 14 days, so guessing is not a practical attack, but there is nothing
  stopping someone trying.
