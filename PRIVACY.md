# Privacy policy

Last updated: 12 August 2026

SplitFree is a bill-splitting app for iPhone and Android. This policy describes
what it stores, what it sends, and what you can do about it. It is written to be
read rather than to be defensible, and it describes what the code actually does.
The code is public, so you can check.

## The short version

Everything you type stays on your phone unless you deliberately share a group
with someone. If you never sign in, SplitFree never sends anything anywhere.

There are no adverts, no analytics, no tracking, and no third party is sold or
given anything about how you spend.

## What stays on your device

By default, all of it: your groups, expenses, who paid, who owes what, payments
you have recorded, friends' names, receipt photos, notes, recurring rules and
your settings.

On iPhone you can turn on iCloud sync, which copies that data to **your own**
private iCloud database. That is between you and Apple; the developers of
SplitFree cannot read it.

## What happens when you share a group

Sharing a group is the only thing that sends your data to a SplitFree server.
It is per group, it always takes an explicit tap, and the app tells you what it
means before you do it.

When you share a group, this is uploaded:

- The group's name, type, colour, currency, notes and archived state
- The display names and colours of everyone in it
- Every expense in it: title, notes, total, currency, date, category, how it was
  split, any tax and tip, and the exact amounts each person paid and owes
- Any line items on those expenses, and who they were assigned to
- Every settle-up payment recorded in it: who paid whom, how much, when, by what
  method, and any note
- Which account created each row

**Everyone you invite to that group can read all of it.** That is the point of
sharing; there is no partial view.

These are **not** uploaded, ever, for any group:

- Receipt photos and the text read off them
- Profile photos and group cover images
- Your Venmo, PayPal, Cash App or UPI handles
- Recurring expense rules and saved split templates
- Your activity history
- Groups you have not shared, and one-off expenses between you and a friend
  outside any group

## Accounts

You only need an account to share a group. Everything else works signed out, and
the app never asks you to sign in to keep using it.

If you do sign in, we store your email address and an account identifier. You can
sign in with an emailed code, with Apple, or with Google. If you use Apple or
Google, that provider tells us your identifier and email and learns that you
signed in to SplitFree; it does not learn anything about your expenses.

Signing out leaves everything on your phone. Shared groups become ordinary local
groups and simply stop travelling.

## Invite links

An invite link contains a random token that is valid for 14 days. **Anyone who
has the link can join that group and see everything in it**, so treat it like the
group itself and send it only to the person it is for.

The token is placed in the link's fragment (after the `#`). Browsers never send
a fragment to a web server, so opening an invite in a browser does not leave a
copy of the token in anyone's access log.

## Who else is involved

- **Supabase** hosts the database and handles sign-in. Shared-group data is
  stored there.
- **Apple** and **Google**, only if you choose to sign in with them.
- **open.er-api.com** provides currency exchange rates. The app asks for the
  daily rate table and sends nothing about you. It works offline with rates built
  into the app, and you can turn currency conversion off entirely.

There is no analytics SDK, no crash reporter, no advertising network and no data
broker. Nothing in the app measures how you use it.

## How long it is kept, and how to get rid of it

Data in a shared group is kept while the group exists. Deleting an expense, a
payment or a whole group removes it and records a marker so the deletion reaches
everyone else's phone; those markers are discarded after 30 days.

- **Stop sharing one group:** open the group, tap the sharing button, and choose
  "Stop sharing on this device". Your copy stays; it stops travelling.
- **Erase everything on this phone:** Account, then "Erase all data".
- **Delete your account and everything on the server:** email
  privacy@splitfree.app from the address you signed in with, and it will be
  deleted within 30 days.

Deleting your account does not remove expenses from other members' phones. They
have their own copies, and a shared group belongs to everyone in it.

## Children

SplitFree is not directed at children under 13, and we do not knowingly collect
anything from them.

## Changes

If this policy changes in a way that affects what is collected or who can see it,
the app will say so before the change takes effect rather than quietly updating
this page.

## Contact

privacy@splitfree.app
