# SplitFree

Split shared expenses with friends, flatmates and travel companions. Every
feature Splitwise keeps behind Splitwise Pro is here: receipt scanning, currency
conversion, itemized bills, charts, expense search, unlimited expenses.

All features free, with no ads, no subscription and no paid tier. Native apps for
iOS and Android that read and write the same ledger.

Groups stay on the device. Sharing one with a friend is a separate, deliberate
act that uploads that group so their phone can reach it; everything else never
leaves. [PRIVACY.md](PRIVACY.md) says exactly what is sent when.

iOS 18+, SwiftUI and SwiftData, no third-party dependencies. Android 8+, Compose
and Room. Postgres on Supabase for the parts that are shared.

## Turning sharing on

Skip this and both apps still work. Every group stays on the device and nothing
is sent anywhere. Sharing is the only part that needs a backend.

**1. Deploy the database.**

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

**2. Give the apps your project's address.** From Project Settings, then API,
copy the project URL and the publishable key into:

- `Config/Supabase.xcconfig` for iOS, host written **without** `https://`
- `android/supabase.properties` for Android

Both are committed blank. Both values are safe to commit: the publishable key
grants nothing on its own, because every table denies by default.

**3. Turn on anonymous sign-ins.** Authentication, then Sign In / Providers,
then "Allow anonymous sign-ins".

Sharing needs the server to tell one device from another. Nobody is asked for
anything: the first time a device shares or joins, it is issued a random
identifier. There is no sign-in screen anywhere in the app.

**4. Check it.** `supabase/tests/contract_test.sh` sends the same requests the
apps send, against a local stack or a real project.

## Features

**Splitting**

- Six ways to divide a bill: equally, exact amounts, percentages, shares,
  plus/minus adjustments, or line by line off the receipt
- Several people can pay for one bill
- Save a split you use often and reapply it in one tap
- Recurring expenses from daily to yearly, created on launch with the correct
  date even after weeks away

**Balances**

- Balances per group, per friend, and overall
- Debt simplification collapses the graph into the fewest payments that settle
  everyone
- Settle up in full or in part, with the payment method recorded
- Expenses and settle-ups between two people with no group involved

**Money**

- 154 currencies at the right precision, including zero-decimal (JPY, KRW, VND)
  and three-decimal (KWD, BHD, TND)
- Live exchange rates when online, a bundled snapshot when not. Each expense
  stores the rate it used, so old totals don't drift when rates move.

**Everything else**

- Receipt scanning with on-device OCR, parsed into line items
- Bank and card CSV import with column inference and a review step
- CSV export, one group or the whole ledger
- Charts for spending by month, category, person and group
- Search across titles, notes, categories, people, line items and scanned
  receipt text
- Activity feed, per-expense comments, group notes
- Nine languages: English, Spanish, French, German, Italian, Portuguese (Brazil),
  Hindi, Japanese, Simplified Chinese
- Light and dark, Dynamic Type, VoiceOver labels
- Optional Face ID lock

**Sharing**

- Export a `.splitfree` file and hand it to anyone, on either platform. It is a
  snapshot, and merges rather than duplicates when re-imported.
- Or share a group with a ten character code and changes travel both ways. No
  account, no email, no sign-up. A code can hand over an existing member's slot,
  so the expenses already recorded against "Marco" become Marco's when he joins.
- Connect with one person the same way, without a group.
- Sharing is per group and always opt-in. An account is optional; the app is
  fully usable without one.

## Build and run

### iOS

Xcode 26 or later, targeting iOS 18+.

```bash
git clone https://github.com/YOUR-USERNAME/splitfree.git
cd splitfree
open SplitFree.xcodeproj
```

Pick a simulator and press Run. From the command line:

```bash
xcodebuild -project SplitFree.xcodeproj -scheme SplitFree \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Android

```bash
cd android
./gradlew :app:assembleDebug
```

### The backend

Optional. With no backend configured, both apps build and run exactly as they
did before accounts existed: no sign-in screen, no sync, everything local.

To run one locally you need Docker:

```bash
supabase start
```

Put the URL and publishable key it prints into the two config files from
[step 2](#turning-sync-on). [supabase/README.md](supabase/README.md) explains how
the schema and the sync protocol are designed.

## Tests

```bash
xcodebuild test -project SplitFree.xcodeproj -scheme SplitFree \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

83 tests, all pure logic, no UI. They cover exact-sum guarantees for every split
method, balance netting, settlement, debt simplification, multi-currency
separation, currency precision, amount parsing, receipt parsing, bank-CSV import
and the sync fingerprints.

```bash
cd android && ./gradlew :app:testDebugUnitTest    # 52 tests
supabase test db                                  # 24 assertions on the schema and policies
supabase/tests/contract_test.sh                   # 20 assertions on what the clients send
```

Several of these exist because they caught real bugs. The receipt parser read
"Subtotal" as "Total" because one string contains the other. CSV import turned
refunds into expenses when a statement used separate debit and credit columns.
The contract test found that sharing a group was impossible: `ON CONFLICT` makes
Postgres apply the *read* policy to a write, and you cannot yet read a group
whose member row does not exist.

The fingerprint tests on both platforms assert the same fixed hash values,
computed from the FNV-1a specification rather than from either app. If the two
implementations drift apart, each phone decides the other's rows have changed and
pushes them back forever, with nothing on screen to suggest anything is wrong.


## Layout

```
SplitFree/         iOS app
  App/             App entry, root tab view, settings, app lock
  Models/          SwiftData models: Participant, SpendingGroup, Expense, Settlement
  Core/            Money, currencies, split calculator, balance engine, parsers, export
  Core/Sync/       Supabase client, sync engine, fingerprints
  DesignSystem/    Palette, typography, components, money fields, chart palette
  Features/        One folder per screen area
  Resources/       Asset catalog, Localizable.xcstrings
SplitFreeTests/    83 tests
android/           Android app, same core ported line for line
supabase/          Schema, row-level security, sync functions, tests
Config/            Info.plist and the backend xcconfig
```

The money maths is duplicated rather than shared: `SplitCalculator` and
`BalanceEngine` exist twice, once in Swift and once in Kotlin, with the same
tie-breaking rules so both platforms produce byte-identical results. A shared
Kotlin Multiplatform module would remove the duplication and add a build system
to the iOS app that currently has none.

## Contributing

Issues and pull requests are welcome.

## License

MIT. See [LICENSE](LICENSE).
