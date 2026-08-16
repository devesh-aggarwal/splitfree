import Foundation

/// One person owing another a specific amount in a specific currency.
struct Debt: Identifiable, Hashable {
    var from: UUID
    var to: UUID
    var amountMinorUnits: Int
    var currencyCode: String

    var id: String { "\(from)-\(to)-\(currencyCode)" }
    var money: Money { Money(minorUnits: amountMinorUnits, currencyCode: currencyCode) }

    var reversed: Debt {
        Debt(from: to, to: from, amountMinorUnits: amountMinorUnits, currencyCode: currencyCode)
    }
}

/// A person's position, which may span several currencies.
struct NetPosition: Hashable {
    /// Currency code → signed minor units. Positive means they are owed money.
    var byCurrency: [String: Int] = [:]

    var isSettled: Bool { byCurrency.values.allSatisfy { $0 == 0 } }

    var nonZeroCurrencies: [String] {
        byCurrency.filter { $0.value != 0 }.keys.sorted()
    }

    mutating func add(_ minorUnits: Int, currencyCode: String) {
        byCurrency[currencyCode, default: 0] += minorUnits
    }

    func amount(in currencyCode: String) -> Int { byCurrency[currencyCode] ?? 0 }

    /// Collapses every currency into one figure using the supplied rates.
    /// Only meaningful for headline totals - never for settling up.
    func converted(to baseCode: String, rates: ExchangeRateTable) -> Money {
        let total = byCurrency.reduce(0) { partial, entry in
            partial + rates.convert(minorUnits: entry.value, from: entry.key, to: baseCode)
        }
        return Money(minorUnits: total, currencyCode: baseCode)
    }
}

/// Everything the UI needs to describe who owes whom.
struct BalanceSheet {
    /// Participant ID → their net position.
    var positions: [UUID: NetPosition] = [:]
    /// Concrete "A pays B" instructions, already netted between each pair.
    var debts: [Debt] = []

    func position(for id: UUID) -> NetPosition { positions[id] ?? NetPosition() }

    var isFullySettled: Bool { debts.isEmpty }

    func debts(involving id: UUID) -> [Debt] {
        debts.filter { $0.from == id || $0.to == id }
    }

    func debt(from: UUID, to: UUID, currencyCode: String) -> Int {
        debts.first { $0.from == from && $0.to == to && $0.currencyCode == currencyCode }?.amountMinorUnits ?? 0
    }
}

/// Derives balances from expenses and settlements.
///
/// Two modes, matching what people expect:
/// - **Detailed** keeps the actual pairwise history - if you paid for Ana's
///   dinner and Ben paid for yours, you owe Ben and Ana owes you.
/// - **Simplified** collapses the graph so the group settles in the fewest
///   possible payments, even if that means paying someone you never dined with.
enum BalanceEngine {

    // MARK: - Public API

    static func balanceSheet(
        expenses: [Expense],
        settlements: [Settlement],
        simplify: Bool
    ) -> BalanceSheet {
        var pairwise = pairwiseLedger(expenses: expenses, settlements: settlements)
        netMutualDebts(&pairwise)

        var positions: [UUID: NetPosition] = [:]
        for (key, amount) in pairwise where amount != 0 {
            positions[key.from, default: NetPosition()].add(-amount, currencyCode: key.currencyCode)
            positions[key.to, default: NetPosition()].add(amount, currencyCode: key.currencyCode)
        }

        let debts: [Debt]
        if simplify {
            debts = simplifiedDebts(from: positions)
        } else {
            debts = pairwise
                .filter { $0.value > 0 }
                .map { Debt(from: $0.key.from, to: $0.key.to, amountMinorUnits: $0.value, currencyCode: $0.key.currencyCode) }
                .sorted { lhs, rhs in
                    if lhs.currencyCode != rhs.currencyCode { return lhs.currencyCode < rhs.currencyCode }
                    return lhs.amountMinorUnits > rhs.amountMinorUnits
                }
        }

        return BalanceSheet(positions: positions, debts: debts)
    }

    /// A person's overall standing across every group and one-off expense.
    static func overallPosition(
        for participantID: UUID,
        expenses: [Expense],
        settlements: [Settlement]
    ) -> NetPosition {
        var position = NetPosition()
        for expense in expenses {
            let paid = expense.payerList
                .filter { $0.participant?.id == participantID }
                .reduce(0) { $0 + $1.amountMinorUnits }
            let owed = expense.shareList
                .filter { $0.participant?.id == participantID }
                .reduce(0) { $0 + $1.amountMinorUnits }
            let net = paid - owed
            if net != 0 { position.add(net, currencyCode: expense.currencyCode) }
        }
        for settlement in settlements {
            if settlement.fromParticipant?.id == participantID {
                position.add(settlement.amountMinorUnits, currencyCode: settlement.currencyCode)
            } else if settlement.toParticipant?.id == participantID {
                position.add(-settlement.amountMinorUnits, currencyCode: settlement.currencyCode)
            }
        }
        return position
    }

    // MARK: - Pairwise ledger

    struct PairKey: Hashable {
        var from: UUID
        var to: UUID
        var currencyCode: String
    }

    /// Builds "X owes Y" edges expense by expense.
    ///
    /// Within a single expense we settle the people who underpaid against the
    /// people who overpaid using the same greedy match as debt simplification.
    /// That keeps the edge count small while staying faithful to who actually
    /// benefited from whose money.
    static func pairwiseLedger(expenses: [Expense], settlements: [Settlement]) -> [PairKey: Int] {
        var ledger: [PairKey: Int] = [:]

        for expense in expenses {
            var nets: [UUID: Int] = [:]
            for payer in expense.payerList {
                guard let id = payer.participant?.id else { continue }
                nets[id, default: 0] += payer.amountMinorUnits
            }
            for share in expense.shareList {
                guard let id = share.participant?.id else { continue }
                nets[id, default: 0] -= share.amountMinorUnits
            }

            for transfer in greedyTransfers(nets: nets) {
                let key = PairKey(from: transfer.from, to: transfer.to, currencyCode: expense.currencyCode)
                ledger[key, default: 0] += transfer.amount
            }
        }

        // A payment from A to B cancels A's debt to B.
        for settlement in settlements {
            guard let from = settlement.fromParticipant?.id,
                  let to = settlement.toParticipant?.id,
                  from != to
            else { continue }
            let key = PairKey(from: from, to: to, currencyCode: settlement.currencyCode)
            ledger[key, default: 0] -= settlement.amountMinorUnits
        }

        return ledger
    }

    /// Collapses A→B and B→A into a single net edge in one direction.
    static func netMutualDebts(_ ledger: inout [PairKey: Int]) {
        for key in ledger.keys {
            guard let forward = ledger[key], forward != 0 else { continue }
            let reverseKey = PairKey(from: key.to, to: key.from, currencyCode: key.currencyCode)
            guard let backward = ledger[reverseKey], backward != 0 else { continue }
            let net = forward - backward
            if net > 0 {
                ledger[key] = net
                ledger[reverseKey] = 0
            } else {
                ledger[key] = 0
                ledger[reverseKey] = -net
            }
        }
        ledger = ledger.filter { $0.value != 0 }

        // Flip any negative edge rather than showing "A owes B −$5".
        var flipped: [PairKey: Int] = [:]
        for (key, amount) in ledger {
            if amount < 0 {
                let reverseKey = PairKey(from: key.to, to: key.from, currencyCode: key.currencyCode)
                flipped[reverseKey, default: 0] += -amount
            } else {
                flipped[key, default: 0] += amount
            }
        }
        ledger = flipped.filter { $0.value != 0 }
    }

    // MARK: - Simplification

    /// Rebuilds the debt graph as the fewest payments that settle everyone.
    ///
    /// Repeatedly matches the largest debtor with the largest creditor. For *n*
    /// people with a non-zero balance this always terminates in at most *n − 1*
    /// transfers, because each step zeroes out at least one person.
    static func simplifiedDebts(from positions: [UUID: NetPosition]) -> [Debt] {
        var currencies = Set<String>()
        for position in positions.values { currencies.formUnion(position.byCurrency.keys) }

        var result: [Debt] = []
        for currency in currencies.sorted() {
            var nets: [UUID: Int] = [:]
            for (id, position) in positions {
                let amount = position.amount(in: currency)
                if amount != 0 { nets[id] = amount }
            }
            let transfers = greedyTransfers(nets: nets)
            result.append(contentsOf: transfers.map {
                Debt(from: $0.from, to: $0.to, amountMinorUnits: $0.amount, currencyCode: currency)
            })
        }
        return result.sorted { lhs, rhs in
            if lhs.currencyCode != rhs.currencyCode { return lhs.currencyCode < rhs.currencyCode }
            return lhs.amountMinorUnits > rhs.amountMinorUnits
        }
    }

    struct Transfer: Hashable {
        var from: UUID
        var to: UUID
        var amount: Int
    }

    /// One side of the match: a person and how much they still owe or are owed.
    private struct Party {
        var id: UUID
        var amount: Int
    }

    /// Greedy largest-debtor-to-largest-creditor matching.
    ///
    /// `nets` maps a person to their signed balance; positive means they are owed.
    /// Sorting by ID as a tiebreaker keeps the output stable so the settle-up
    /// screen doesn't reshuffle between launches.
    static func greedyTransfers(nets: [UUID: Int]) -> [Transfer] {
        // Largest amount first; UUID order breaks ties so the same inputs always
        // produce the same payment list.
        func descendingByAmount(_ lhs: Party, _ rhs: Party) -> Bool {
            if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var creditors: [Party] = nets.compactMap { key, value in
            value > 0 ? Party(id: key, amount: value) : nil
        }
        var debtors: [Party] = nets.compactMap { key, value in
            value < 0 ? Party(id: key, amount: -value) : nil
        }
        creditors.sort(by: descendingByAmount)
        debtors.sort(by: descendingByAmount)

        var transfers: [Transfer] = []
        var creditorIndex = 0
        var debtorIndex = 0

        while creditorIndex < creditors.count && debtorIndex < debtors.count {
            let amount = min(creditors[creditorIndex].amount, debtors[debtorIndex].amount)
            if amount > 0 {
                transfers.append(
                    Transfer(from: debtors[debtorIndex].id, to: creditors[creditorIndex].id, amount: amount)
                )
            }
            creditors[creditorIndex].amount -= amount
            debtors[debtorIndex].amount -= amount
            if creditors[creditorIndex].amount == 0 { creditorIndex += 1 }
            if debtors[debtorIndex].amount == 0 { debtorIndex += 1 }
        }

        return transfers
    }

    // MARK: - Summaries

    /// How many payments simplification would save, for the toggle's subtitle.
    static func simplificationSaving(
        expenses: [Expense],
        settlements: [Settlement]
    ) -> (detailed: Int, simplified: Int) {
        let detailed = balanceSheet(expenses: expenses, settlements: settlements, simplify: false)
        let simplified = balanceSheet(expenses: expenses, settlements: settlements, simplify: true)
        return (detailed.debts.count, simplified.debts.count)
    }
}
