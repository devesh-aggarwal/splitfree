# SplitFree

Split shared expenses with friends, flatmates and travel companions. Every
feature Splitwise keeps behind Splitwise Pro is here: receipt scanning, currency
conversion, itemized bills, charts, expense search, unlimited expenses.

There are no accounts, no servers, no ads and no subscription. Data stays on the
device and syncs through the user's own iCloud if they turn it on.

iOS 18+. SwiftUI, SwiftData, Swift Charts. No third-party dependencies.

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

## Build and run

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

## Tests

```bash
xcodebuild test -project SplitFree.xcodeproj -scheme SplitFree \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

62 tests, all pure logic, no UI. They cover exact-sum guarantees for every split
method, balance netting, settlement, debt simplification, multi-currency
separation, currency precision, amount parsing, receipt parsing and bank-CSV
import.

Three of them exist because they caught real bugs: the receipt parser read
"Subtotal" as "Total" because one string contains the other, and CSV import
turned refunds into expenses when a statement used separate debit and credit
columns.


## Layout

```
SplitFree/
  App/           App entry, root tab view, settings, app lock
  Models/        SwiftData models: Participant, SpendingGroup, Expense, Settlement
  Core/          Money, currencies, split calculator, balance engine, parsers, export
  DesignSystem/  Palette, typography, components, money fields, chart palette
  Features/      One folder per screen area
  Resources/     Asset catalog, Localizable.xcstrings
SplitFreeTests/  62 tests
```

## Contributing

Issues and pull requests are welcome.

## License

MIT. See [LICENSE](LICENSE).
