# App Store submission

Everything App Store Connect asks for, drafted and ready to paste. Character
limits are noted where Apple enforces one.

## Before you submit

Two things are not optional, and neither shows up as an error anywhere.

**Connect an SMTP provider.** Supabase's built-in sender only delivers to
addresses in your own Supabase organisation. An App Review tester will type
their own address into the sign-in screen, receive nothing, and reasonably
conclude the feature is broken. Any free tier fixes it: Authentication, then
Emails, then SMTP Settings.

**Check the name is free.** Reserve it in App Store Connect early. If "SplitFree"
is taken you will find out at the point of creating the app record, and the
description below leans on the name in a few places.

## Listing

| Field | Value |
|---|---|
| Name (30) | `SplitFree` |
| Subtitle (30) | `Split bills. No ads, no fees.` |
| Category | Finance (primary), Productivity (secondary) |
| Price | Free, no in-app purchases |
| Age rating | 4+ |
| Support URL | `https://devesh-aggarwal.github.io/splitfree/` |
| Marketing URL | `https://devesh-aggarwal.github.io/splitfree/` |
| Privacy Policy URL | `https://devesh-aggarwal.github.io/splitfree/privacy.html` |
| Copyright | `2026 Devesh Aggarwal` |

### Promotional text (170)

Editable without submitting an update, so use it for whatever is current.

```
Every feature, free. Split a bill six ways, scan a receipt, settle up in the
fewest payments, and share a group with friends on iPhone or Android.
```

### Description (4000)

```
Split shared expenses with friends, flatmates and travel companions. Everyone's
balance stays exact, down to the last cent.

Every feature is included from the moment you install it. No subscription, no
upgrade screen, no adverts, and nothing held back for a paid tier.


SPLITTING

Six ways to divide a bill: equally, exact amounts, percentages, shares,
plus and minus adjustments, or line by line off the receipt. Several people can
chip in on the same bill. Save a split you use often and reapply it in one tap.

Scan a receipt with the camera and SplitFree reads the line items off it, so
assigning the starters to the two people who ate them takes seconds.


BALANCES THAT ADD UP

Debt simplification collapses a tangle of IOUs into the fewest payments that
settle everyone. Three people stop owing each other in six directions and settle
in two.

Every split is exact. Awkward totals are distributed to the cent, never rounded
away, so the numbers always reconcile.

Settle up in full or in part, record how it was paid, and hand off to Venmo,
PayPal, Cash App or UPI.


MONEY

Over 150 currencies at the right precision, including ones with no decimal
places like the yen and three-decimal ones like the dinar. Live exchange rates
when you are online and a built-in snapshot when you are not. Each expense
remembers the rate it used, so last year's trip does not change value when rates
move.


SHARING, ON YOUR TERMS

Groups stay on your phone. Sharing one with a friend is a separate, deliberate
choice that uploads that group so their phone can reach it. Everything you never
share never leaves the device.

Invite by link. You can hand over an existing member's place, so the four
expenses already recorded against "Marco" become Marco's the moment he joins.
Connect with one person the same way, without a group.

There is an Android app that reads and writes the same ledger, so nobody is left
out.


EVERYTHING ELSE

Recurring expenses from daily to yearly. Import a bank or card CSV. Export
everything as CSV whenever you want, because it is your data. Charts for
spending by month, category, person and group. Search that reaches into notes,
line items and scanned receipt text. Activity feed, per-expense comments and
group notes.

Light and dark. Dynamic Type and VoiceOver throughout. Optional Face ID lock.
Nine languages: English, Spanish, French, German, Italian, Portuguese, Hindi,
Japanese and Simplified Chinese.

Works completely offline.


PRIVACY

No analytics. No advertising. No third party is sold or given anything about how
you spend. An account is optional and the app is fully usable without one.

SplitFree is open source. The apps, the database and the tests are public, so
none of this has to be taken on trust.
```

### Keywords (100, comma separated, no spaces)

```
bills,expenses,roommate,shared,trip,travel,group,budget,debt,settle,tab,friends,receipt,ious
```

That is 94 characters. Apple already indexes the app name and subtitle, so
"split" and "free" are deliberately left out to avoid wasting the budget.

## Age rating questionnaire

Answer **None** to every content question. The app has no violence, no mature
themes, no gambling, no contests and no web browsing.

One question needs thought rather than a reflex. Apple asks about
user-generated content. SplitFree does let people type expense titles and notes
that others in the same group can read, but there is no public feed, no
discovery, and no way to reach anybody who has not been handed an invite link.
That is private correspondence between people who already know each other, not a
social platform, so **4+** is the right rating. If the questionnaire pushes you
toward a content-moderation commitment, the honest answer to "can users
communicate with each other" is yes, and the mitigating detail is that the
audience is closed.

## App Privacy

No longer "Data Not Collected". Declare exactly this:

| Data type | Collected | Linked to identity | Used for tracking | Purpose |
|---|---|---|---|---|
| Email Address | Yes | Yes | No | App Functionality |
| User ID | Yes | Yes | No | App Functionality |
| Other User Content | Yes | Yes | No | App Functionality |

"Other User Content" covers expense titles, notes and amounts inside a shared
group. Nothing is collected from someone who never signs in, but Apple's form
has no way to express that, so the safe and truthful answer is to declare it.

Answer **No** to tracking across apps and websites. There is no ad network, no
analytics SDK and no crash reporter in the build.

## Notes for App Review

```
An account is optional. SplitFree works fully without signing in: create
groups, add expenses, split them six ways, scan receipts, settle up, and
view charts. Nothing is uploaded and no login screen blocks any of it.

Signing in unlocks one thing only: sharing a group so a friend's phone can
see it too. To test that path:

1. Account tab, then "Sign in to share groups".
2. Enter any email address you control and tap "Email me a link".
3. Open the email and tap the link. It returns to the app signed in.
   The email also contains a six-digit code if you would rather type it.
4. Open any group, tap the menu at the top right, then "Share with
   friends", then "Share this group" and "Create invite link".

There is no demo account because there are no passwords. Sign-in is by
emailed link, so any address you own works.

The app is open source at github.com/devesh-aggarwal/splitfree if any
behaviour needs checking against the code.
```

## Screenshots

Required sizes, six each at most:

| Device | Size | Simulator |
|---|---|---|
| iPhone 6.9" | 1320 x 2868 | iPhone 17 Pro Max |
| iPad 13" | 2064 x 2752 | iPad Pro 13-inch (M5) |

The iPad set is required because the app is built for both, which
`TARGETED_DEVICE_FAMILY = "1,2"` in the project settings commits you to.

Captured files live in `screenshots/`. Regenerate them with
`scripts/screenshots.sh`.

## Version

| Field | Value |
|---|---|
| Version | 1.0 |
| Build | 1 |
| Bundle ID | com.splitfree.SplitFree |
| Team | W2CWQF9D62 |
| Minimum iOS | 18.0 |

Export compliance is already answered in the project:
`ITSAppUsesNonExemptEncryption = NO`. The app uses HTTPS and nothing else, which
is exempt.
