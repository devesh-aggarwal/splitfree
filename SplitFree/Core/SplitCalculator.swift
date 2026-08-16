import Foundation

/// Turns "how should this be divided" into exact per-person minor-unit amounts.
///
/// Every function here guarantees the allocated amounts sum **exactly** to the
/// total. Remainders are never dropped or rounded away - they are handed out one
/// minor unit at a time by the largest-remainder method, so a $10.00 bill split
/// three ways comes out as 3.34 / 3.33 / 3.33 rather than 3.33 × 3 and a lost cent.
enum SplitCalculator {

    /// A person's raw input in the split editor, before it is resolved to cents.
    struct Entry: Identifiable, Hashable {
        var participantID: UUID
        /// Included in the split at all.
        var isIncluded: Bool = true
        /// Meaning depends on the method: exact minor units, percent, share
        /// count, or plus/minus adjustment in minor units.
        var value: Double = 0

        var id: UUID { participantID }
    }

    struct Allocation: Hashable {
        var participantID: UUID
        var amountMinorUnits: Int
        /// The input that produced this amount, preserved for round-tripping.
        var weight: Double
    }

    // MARK: - Equal

    /// Splits `total` as evenly as possible. The first `total % n` people in the
    /// given order each absorb one extra minor unit.
    static func equal(total: Int, among participantIDs: [UUID]) -> [Allocation] {
        guard !participantIDs.isEmpty else { return [] }
        let amounts = distributeEvenly(total: total, count: participantIDs.count)
        return zip(participantIDs, amounts).map {
            Allocation(participantID: $0, amountMinorUnits: $1, weight: 1)
        }
    }

    /// Splits an integer into `count` parts that sum exactly to `total`.
    /// Handles negative totals symmetrically (refunds split the same way).
    static func distributeEvenly(total: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let sign = total < 0 ? -1 : 1
        let magnitude = abs(total)
        let base = magnitude / count
        let remainder = magnitude % count
        return (0..<count).map { index in
            sign * (base + (index < remainder ? 1 : 0))
        }
    }

    // MARK: - Weighted (percent, shares)

    /// Distributes `total` in proportion to `weights` using the largest-remainder
    /// method: each person gets `floor(total × wᵢ / Σw)`, then the leftover minor
    /// units go one each to the largest fractional remainders.
    ///
    /// Returns all-zero when every weight is zero, rather than dividing by zero.
    static func weighted(total: Int, weights: [(id: UUID, weight: Double)]) -> [Allocation] {
        guard !weights.isEmpty else { return [] }
        let totalWeight = weights.reduce(0.0) { $0 + max(0, $1.weight) }
        guard totalWeight > 0 else {
            return weights.map { Allocation(participantID: $0.id, amountMinorUnits: 0, weight: $0.weight) }
        }

        let sign = total < 0 ? -1 : 1
        let magnitude = Double(abs(total))

        var floors: [Int] = []
        var remainders: [(index: Int, fraction: Double)] = []
        floors.reserveCapacity(weights.count)

        for (index, entry) in weights.enumerated() {
            let exact = magnitude * max(0, entry.weight) / totalWeight
            let floored = exact.rounded(.down)
            floors.append(Int(floored))
            remainders.append((index, exact - floored))
        }

        var leftover = abs(total) - floors.reduce(0, +)
        // Largest fractional part first; ties fall back to input order so the
        // result is deterministic across runs and devices.
        remainders.sort { lhs, rhs in
            if lhs.fraction == rhs.fraction { return lhs.index < rhs.index }
            return lhs.fraction > rhs.fraction
        }
        var cursor = 0
        while leftover > 0 && !remainders.isEmpty {
            floors[remainders[cursor % remainders.count].index] += 1
            leftover -= 1
            cursor += 1
        }

        return weights.enumerated().map { index, entry in
            Allocation(participantID: entry.id, amountMinorUnits: sign * floors[index], weight: entry.weight)
        }
    }

    // MARK: - Adjustment (+/-)

    /// Splits what's left after each person's personal extra is taken off the top,
    /// then adds those extras back. Someone who ordered a $6 dessert on a shared
    /// bill enters +6.00 and pays their even share of the rest plus the dessert.
    static func adjustment(total: Int, entries: [(id: UUID, adjustment: Int)]) -> [Allocation] {
        guard !entries.isEmpty else { return [] }
        let adjustmentSum = entries.reduce(0) { $0 + $1.adjustment }
        let shared = total - adjustmentSum
        let evenParts = distributeEvenly(total: shared, count: entries.count)
        return entries.enumerated().map { index, entry in
            Allocation(
                participantID: entry.id,
                amountMinorUnits: evenParts[index] + entry.adjustment,
                weight: Double(entry.adjustment)
            )
        }
    }

    // MARK: - Exact amounts

    /// Passes typed amounts through unchanged. Any shortfall or overage is the
    /// caller's problem to surface - `exactRemainder` reports it.
    static func exact(entries: [(id: UUID, amount: Int)]) -> [Allocation] {
        entries.map {
            Allocation(participantID: $0.id, amountMinorUnits: $0.amount, weight: Double($0.amount))
        }
    }

    static func exactRemainder(total: Int, entries: [(id: UUID, amount: Int)]) -> Int {
        total - entries.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Itemized

    struct ItemAssignment {
        /// Line total in minor units (unit price × quantity).
        var amountMinorUnits: Int
        /// Who had it. Empty means everyone in `fallbackParticipants`.
        var participantIDs: [UUID]
    }

    /// Builds shares from receipt line items, then spreads tax and tip across
    /// people in proportion to what they actually ordered.
    ///
    /// The final amounts are reconciled against `total` so the shares always add
    /// up even when the receipt's own arithmetic doesn't.
    static func itemized(
        total: Int,
        items: [ItemAssignment],
        taxMinorUnits: Int,
        tipMinorUnits: Int,
        fallbackParticipants: [UUID]
    ) -> [Allocation] {
        guard !fallbackParticipants.isEmpty else { return [] }

        var subtotals: [UUID: Int] = [:]
        for id in fallbackParticipants { subtotals[id] = 0 }

        for item in items {
            let people = item.participantIDs.isEmpty ? fallbackParticipants : item.participantIDs
            guard !people.isEmpty else { continue }
            let parts = distributeEvenly(total: item.amountMinorUnits, count: people.count)
            for (person, part) in zip(people, parts) {
                subtotals[person, default: 0] += part
            }
        }

        let itemsTotal = subtotals.values.reduce(0, +)
        let extras = taxMinorUnits + tipMinorUnits

        // Tax and tip ride along in proportion to each person's item subtotal.
        // When nothing was itemized yet, fall back to an even spread.
        let extraAllocations: [UUID: Int]
        if itemsTotal != 0 && extras != 0 {
            let weights = fallbackParticipants.map { (id: $0, weight: Double(subtotals[$0] ?? 0)) }
            extraAllocations = Dictionary(
                uniqueKeysWithValues: weighted(total: extras, weights: weights)
                    .map { ($0.participantID, $0.amountMinorUnits) }
            )
        } else if extras != 0 {
            let parts = distributeEvenly(total: extras, count: fallbackParticipants.count)
            extraAllocations = Dictionary(uniqueKeysWithValues: zip(fallbackParticipants, parts))
        } else {
            extraAllocations = [:]
        }

        var amounts = fallbackParticipants.map { id in
            (id: id, amount: (subtotals[id] ?? 0) + (extraAllocations[id] ?? 0))
        }

        // Reconcile against the stated total - receipts round, ours must not.
        let drift = total - amounts.reduce(0) { $0 + $1.amount }
        if drift != 0 {
            let correction = distributeEvenly(total: drift, count: amounts.count)
            for index in amounts.indices { amounts[index].amount += correction[index] }
        }

        return amounts.map {
            Allocation(participantID: $0.id, amountMinorUnits: $0.amount, weight: Double($0.amount))
        }
    }

    // MARK: - Unified entry point

    /// Resolves the editor's state into final per-person amounts.
    ///
    /// `entries` must already be filtered to included people for methods that
    /// don't carry their own inclusion rules.
    static func resolve(
        method: SplitMethod,
        total: Int,
        currencyCode: String,
        entries: [Entry],
        items: [ItemAssignment] = [],
        taxMinorUnits: Int = 0,
        tipMinorUnits: Int = 0
    ) -> [Allocation] {
        let included = entries.filter(\.isIncluded)
        let ids = included.map(\.participantID)
        guard !ids.isEmpty else { return [] }

        switch method {
        case .equal:
            return equal(total: total, among: ids)
        case .percent:
            return weighted(total: total, weights: included.map { (id: $0.participantID, weight: $0.value) })
        case .shares:
            return weighted(total: total, weights: included.map { (id: $0.participantID, weight: $0.value) })
        case .exact:
            return exact(entries: included.map { (id: $0.participantID, amount: Int($0.value.rounded())) })
        case .adjustment:
            return adjustment(total: total, entries: included.map { (id: $0.participantID, adjustment: Int($0.value.rounded())) })
        case .itemized:
            return itemized(
                total: total,
                items: items,
                taxMinorUnits: taxMinorUnits,
                tipMinorUnits: tipMinorUnits,
                fallbackParticipants: ids
            )
        }
    }

    // MARK: - Validation

    enum ValidationIssue: Equatable {
        case noOneSelected
        case amountsDontAddUp(remainder: Int, currencyCode: String)
        case percentagesDontAddUp(remainder: Double)
        case noShares
        case negativeTotal

        var message: String {
            switch self {
            case .noOneSelected:
                String(localized: "Pick at least one person to split with.")
            case .amountsDontAddUp(let remainder, let currencyCode):
                remainder > 0
                    ? String(
                        format: String(localized: "%@ left to assign.", comment: "Remaining amount"),
                        Money(minorUnits: remainder, currencyCode: currencyCode).formatted()
                    )
                    : String(
                        format: String(localized: "%@ over the total.", comment: "Over-assigned amount"),
                        Money(minorUnits: -remainder, currencyCode: currencyCode).formatted()
                    )
            case .percentagesDontAddUp(let remainder):
                remainder > 0
                    ? String(format: String(localized: "%.1f%% left to assign.", comment: "Remaining percent"), remainder)
                    : String(format: String(localized: "%.1f%% over 100%%.", comment: "Excess percent"), -remainder)
            case .noShares:
                String(localized: "Give at least one person a share.")
            case .negativeTotal:
                String(localized: "Enter an amount greater than zero.")
            }
        }
    }

    static func validate(
        method: SplitMethod,
        total: Int,
        currencyCode: String,
        entries: [Entry]
    ) -> ValidationIssue? {
        let included = entries.filter(\.isIncluded)
        guard !included.isEmpty else { return .noOneSelected }

        switch method {
        case .equal, .adjustment, .itemized:
            return nil
        case .exact:
            let sum = included.reduce(0) { $0 + Int($1.value.rounded()) }
            let remainder = total - sum
            return remainder == 0 ? nil : .amountsDontAddUp(remainder: remainder, currencyCode: currencyCode)
        case .percent:
            let sum = included.reduce(0.0) { $0 + $1.value }
            let remainder = 100 - sum
            // Tolerate float noise from repeated typing, but not real gaps.
            return abs(remainder) < 0.05 ? nil : .percentagesDontAddUp(remainder: remainder)
        case .shares:
            let sum = included.reduce(0.0) { $0 + max(0, $1.value) }
            return sum > 0 ? nil : .noShares
        }
    }
}
