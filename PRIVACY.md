# Privacy policy

Last updated: 14 August 2026

SplitFree is a bill-splitting app for iPhone and Android, made by Devesh. This
describes what it stores and what it sends. The code is public, so you can check.

## The short version

There are no accounts. You never give SplitFree your name, your email or a
password, because it never asks.

Everything you type stays on your phone unless you deliberately share a group.
There are no adverts, no analytics and no tracking.

## What stays on your device

All of it, by default: groups, expenses, who paid, who owes what, payments,
friends' names, receipt photos, notes and settings.

On iPhone you can turn on iCloud sync, which copies that to your own private
iCloud database. That is between you and Apple.

## What happens when you share a group

Sharing is the only thing that sends anything to a SplitFree server. It is per
group and always takes a deliberate tap.

Uploaded: the group's name, type and currency; the names you gave its members;
its expenses, including titles, notes, amounts, dates, categories and who owes
what; and any payments recorded in it.

Never uploaded: receipt photos, profile pictures, your payment handles, recurring
rules, your activity history, and any group you have not shared.

Everyone in a shared group can read all of it. That is what sharing means.

## Identity

Sharing needs the server to tell one device from another, so the first time you
share or join, your device is issued a random identifier. No email, no name,
nothing you typed. It is not connected to you, and it is not used anywhere else.

Losing your phone means losing that identifier. Your groups stay on the server
for everyone else, and a friend can send you a fresh code to get back in.

## Join codes

A code is valid for 14 days. **Anyone holding it can join that group and see
everything in it**, so send it only to the person it is for.

In a link, the code sits after the `#`. Browsers never send that part to a
server, so opening an invite on the web reveals nothing to anyone.

## Who else is involved

- **Supabase** hosts the database. Shared-group data is stored there.
- **open.er-api.com** provides exchange rates. It is asked for the daily rate
  table and told nothing about you. The app works offline without it.

No analytics SDK, no crash reporter, no advertising network, no data broker.

## Deleting things

Deleting an expense, a payment or a group removes it and tells everyone else's
phone to do the same.

- **Stop sharing a group:** open it, tap the share button, choose "Stop sharing
  on this device". Your copy stays.
- **Erase everything here:** Account, then "Erase all data".
- **Remove your data from the server:** open an issue at
  [github.com/devesh-aggarwal/splitfree/issues](https://github.com/devesh-aggarwal/splitfree/issues).
  Deletion happens within 30 days.

Deleting your own data does not remove expenses from other members' phones. They
have their own copies, and a shared group belongs to everyone in it.

## Children

SplitFree is not directed at children under 13 and does not knowingly collect
anything from them.

## Changes

If this changes in a way that affects what is collected or who can see it, the
app will say so before it takes effect.

## Contact

[github.com/devesh-aggarwal/splitfree/issues](https://github.com/devesh-aggarwal/splitfree/issues)
