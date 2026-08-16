import Foundation
import SwiftUI

/// Aggregates expenses into the numbers the Insights screen draws.
///
/// Every amount is converted into the base currency using the rate stored on the
/// expense at the time it was entered, so a trip to Japan two years ago keeps the
/// value it had then.
@MainActor
struct SpendingReport {

    struct MonthPoint: Identifiable {
        var month: Date
        var amount: Int
        var label: String
        var id: Date { month }
        /// Charts plot in major units; minor units would put the axis in cents.
        var majorAmount: Double
    }

    struct Slice: Identifiable {
        var id: String
        var label: String
        var amount: Int
        var category: ExpenseCategory?
        var participant: Participant?
        var group: SpendingGroup?
    }

    private(set) var total = 0
    private(set) var previousTotal = 0
    private(set) var paidByYou = 0
    private(set) var count = 0
    private(set) var monthly: [MonthPoint] = []
    private(set) var byCategory: [Slice] = []
    private(set) var byPerson: [Slice] = []
    private(set) var byGroup: [Slice] = []

    private let baseCode: String

    /// Past this many bars, the tail is folded into "Other" rather than given
    /// its own slot - nobody can read a ninth category.
    private static let sliceLimit = 8

    var isEmpty: Bool { count == 0 }

    /// Percentage change against the preceding, equally long window.
    var deltaPercent: Double? {
        guard previousTotal > 0, total > 0 else { return nil }
        return (Double(total) - Double(previousTotal)) / Double(previousTotal) * 100
    }

    init(
        expenses: [Expense],
        user: Participant,
        baseCode: String,
        range: InsightsRange,
        basis: SpendBasis,
        group: SpendingGroup?
    ) {
        self.baseCode = baseCode

        let bounds = range.bounds()
        let calendar = Calendar.current

        func amount(_ expense: Expense) -> Int {
            let full = expense.amountInBaseMinorUnits
            switch basis {
            case .fullBills:
                return full
            case .yourShare:
                guard expense.amountMinorUnits != 0 else { return 0 }
                // Scale the user's share by the same rate the total used.
                let share = expense.amountOwed(by: user)
                return Int((Double(share) / Double(expense.amountMinorUnits) * Double(full)).rounded())
            }
        }

        let relevant = expenses.filter { expense in
            guard expense.involvedParticipants.contains(where: { $0.id == user.id }) else { return false }
            if let group, expense.group?.id != group.id { return false }
            if let bounds { return expense.date >= bounds.start }
            return true
        }

        count = relevant.count
        total = relevant.reduce(0) { $0 + amount($1) }
        paidByYou = relevant.reduce(0) { partial, expense in
            let paid = expense.amountPaid(by: user)
            guard expense.amountMinorUnits != 0 else { return partial }
            let scaled = Double(paid) / Double(expense.amountMinorUnits) * Double(expense.amountInBaseMinorUnits)
            return partial + Int(scaled.rounded())
        }

        if let bounds {
            let previous = expenses.filter { expense in
                guard expense.involvedParticipants.contains(where: { $0.id == user.id }) else { return false }
                if let group, expense.group?.id != group.id { return false }
                return expense.date >= bounds.previousStart && expense.date < bounds.start
            }
            previousTotal = previous.reduce(0) { $0 + amount($1) }
        }

        // Monthly series - every month in the window appears, including empty
        // ones, so a quiet month reads as a gap rather than disappearing.
        let grouped = Dictionary(grouping: relevant) { expense in
            calendar.date(from: calendar.dateComponents([.year, .month], from: expense.date)) ?? expense.date
        }
        if let earliest = grouped.keys.min() {
            let latest = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
            var cursor = earliest
            var points: [MonthPoint] = []
            let divisor = pow(10.0, Double(Currency.fractionDigits(for: baseCode)))
            while cursor <= latest, points.count < 60 {
                let sum = (grouped[cursor] ?? []).reduce(0) { $0 + amount($1) }
                points.append(
                    MonthPoint(
                        month: cursor,
                        amount: sum,
                        label: cursor.formatted(.dateTime.month(.wide).year()),
                        majorAmount: Double(sum) / divisor
                    )
                )
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
            }
            monthly = points
        }

        // Categories
        var categoryTotals: [ExpenseCategory: Int] = [:]
        for expense in relevant {
            categoryTotals[expense.category, default: 0] += amount(expense)
        }
        byCategory = Self.rank(
            categoryTotals.map { Slice(id: $0.key.rawValue, label: $0.key.title, amount: $0.value, category: $0.key) }
        )

        // People - who you actually shared bills with.
        var personTotals: [UUID: (Participant, Int)] = [:]
        for expense in relevant {
            let value = amount(expense)
            for person in expense.involvedParticipants where person.id != user.id {
                let existing = personTotals[person.id]?.1 ?? 0
                personTotals[person.id] = (person, existing + value)
            }
        }
        byPerson = Self.rank(
            personTotals.values.map {
                Slice(id: $0.0.id.uuidString, label: $0.0.fullName, amount: $0.1, participant: $0.0)
            }
        )

        // Groups
        var groupTotals: [String: (SpendingGroup?, String, Int)] = [:]
        for expense in relevant {
            let key = expense.group?.id.uuidString ?? "none"
            let label = expense.group?.displayName ?? String(localized: "No group")
            let existing = groupTotals[key]?.2 ?? 0
            groupTotals[key] = (expense.group, label, existing + amount(expense))
        }
        byGroup = Self.rank(
            groupTotals.map { Slice(id: $0.key, label: $0.value.1, amount: $0.value.2, group: $0.value.0) }
        )
    }

    /// Sorts descending and folds everything past the limit into "Other".
    private static func rank(_ slices: [Slice]) -> [Slice] {
        let sorted = slices.filter { $0.amount != 0 }.sorted { $0.amount > $1.amount }
        guard sorted.count > sliceLimit else { return sorted }
        let head = Array(sorted.prefix(sliceLimit - 1))
        let tail = sorted.dropFirst(sliceLimit - 1)
        let other = Slice(
            id: "other",
            label: String(
                format: String(localized: "Other (%lld)", comment: "Number of folded categories"),
                tail.count
            ),
            amount: tail.reduce(0) { $0 + $1.amount },
            category: nil
        )
        return head + [other]
    }

    func fraction(of amount: Int, in slices: [Slice]? = nil) -> Double {
        let pool = slices ?? byCategory
        guard let largest = pool.map(\.amount).max(), largest > 0 else { return 0 }
        return min(1, Double(amount) / Double(largest))
    }

    func averageText(baseCode: String) -> String {
        guard count > 0 else { return "" }
        let average = total / count
        return String(
            format: String(localized: "avg %@", comment: "Average expense amount"),
            Money(minorUnits: average, currencyCode: baseCode).formatted()
        )
    }
}
