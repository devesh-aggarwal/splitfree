# SplitFree

Split shared expenses with friends, flatmates and travel companions. Every
feature Splitwise keeps behind Splitwise Pro is here: receipt scanning, currency
conversion, itemized bills, charts, expense search, unlimited expenses.

No ads, no subscription, no paid tier. Native apps for iOS and Android that read
and write the same ledger.

Groups stay on the device. Sharing one with a friend is a separate, deliberate
act that uploads that group so their phone can reach it; everything else never
leaves. [PRIVACY.md](PRIVACY.md) says exactly what is sent when.

iOS 18+, SwiftUI and SwiftData, no third-party dependencies. Android 8+, Compose
and Room. Postgres on Supabase for the parts that are shared.

## Turning sync on

Skip this and both apps still work. They keep every group on the device, no
sign-in screen appears, and nothing is sent anywhere. Sync is the only part that
needs setting up.

**1. Deploy the database.** Either connect the repo to Supabase's GitHub
integration, which applies `supabase/migrations` on every push, or run it
yourself:

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

**2. Give the apps your project's address.** From the Supabase dashboard, under
Project Settings → API, copy the project URL and the anon (public) key into:

- `Config/Supabase.xcconfig` for iOS — write the host **without** `https://`
- `android/supabase.properties` for Android

Both files are committed, blank. Both values are safe to commit: the anon key
grants nothing on its own, because every table denies by default and row-level
security decides the rest.

**3. Set up sign-in.** In the dashboard, under Authentication:

- **Providers** → enable Email. Enable Apple and Google too if you want those
  buttons; each needs credentials from Apple and Google respectively. Apple
  requires Sign in with Apple in any app offering another third-party sign-in,
  so on iOS those two travel together.
- **URL Configuration** → add `splitfree://auth-callback` to the redirect
  allow-list, or a browser sign-in comes back to nowhere.
- **Email Templates → Magic Link** → the template must contain `{{ .Token }}`.
  Paste in `supabase/templates/magic_link.html`.

That last one is worth the extra sentence, because it fails in a way that gives
you nothing to go on. The apps ask for a six-digit code, and the stock template
sends only a link. The code is generated either way and simply never shown, so
sign-in just doesn't work and nothing anywhere says why.

**4. Check it.** With the stack running locally, `supabase/tests/contract_test.sh`
sends the same requests the apps send and tells you which part is wrong.

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
- Or sign in and share a group, and changes travel both ways. Invite by link,
  optionally handing over an existing member's slot so the expenses already
  recorded against "Marco" become Marco's when he joins.
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

80 tests, all pure logic, no UI. They cover exact-sum guarantees for every split
method, balance netting, settlement, debt simplification, multi-currency
separation, currency precision, amount parsing, receipt parsing, bank-CSV import
and the sync fingerprints.

```bash
cd android && ./gradlew :app:testDebugUnitTest    # 52 tests
supabase test db                                  # 24 assertions on the schema and policies
supabase/tests/contract_test.sh                   # 19 assertions on what the clients send
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
SplitFreeTests/    80 tests
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
