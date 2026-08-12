import Foundation
import SwiftData

/// Materialises recurring rules into real expenses.
///
/// Rules are evaluated lazily on launch and on foreground rather than by a
/// background task, which keeps the app free of servers and push infrastructure.
/// A rule that hasn't fired for six months simply creates six months of expenses
/// the next time you open the app, each dated correctly.
@MainActor
enum RecurrenceService {

    struct CatchUpResult {
        var createdCount: Int = 0
        /// "Rent, Internet" — the titles that were created, for the toast.
        var summary: String = ""
    }

    /// Hard stop so a daily rule left running for years can't create tens of
    /// thousands of rows in one pass. Anything beyond this is created on the
    /// next launch.
    private static let maxOccurrencesPerRun = 120

    @discardableResult
    static func catchUp(in context: ModelContext, baseCurrencyCode: String) -> CatchUpResult {
        let descriptor = FetchDescriptor<RecurringRule>(
            predicate: #Predicate { $0.isActive == true }
        )
        guard let rules = try? context.fetch(descriptor), !rules.isEmpty else {
            return CatchUpResult()
        }

        var created: [String] = []
        let now = Date()

        for rule in rules {
            var iterations = 0
            while rule.nextOccurrence <= now && iterations < maxOccurrencesPerRun {
                if let endDate = rule.endDate, rule.nextOccurrence > endDate {
                    rule.isActive = false
                    break
                }
                let expense = makeExpense(from: rule, on: rule.nextOccurrence, baseCurrencyCode: baseCurrencyCode, in: context)
                if expense != nil {
                    created.append(rule.displayTitle)
                    rule.generatedCount += 1
                    rule.lastGeneratedAt = Date()
                }
                rule.nextOccurrence = rule.frequency.nextDate(after: rule.nextOccurrence)
                iterations += 1
            }

            if let endDate = rule.endDate, rule.nextOccurrence > endDate {
                rule.isActive = false
            }
        }

        guard !created.isEmpty else { return CatchUpResult() }
        try? context.save()

        let uniqueTitles = Array(Set(created)).sorted()
        return CatchUpResult(
            createdCount: created.count,
            summary: uniqueTitles.prefix(3).joined(separator: ", ")
        )
    }

    /// Builds one expense from a rule, replaying the frozen split plan.
    /// Returns nil when every person in the plan has since been deleted.
    @discardableResult
    static func makeExpense(
        from rule: RecurringRule,
        on date: Date,
        baseCurrencyCode: String,
        in context: ModelContext
    ) -> Expense? {
        let plan = rule.splitPlan
        let peopleByID = Dictionary(
            Ledger.allParticipants(in: context).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let payers = plan.payers.compactMap { entry -> (Participant, Int)? in
            guard let person = peopleByID[entry.participantID] else { return nil }
            return (person, entry.amountMinorUnits)
        }
        let shares = plan.shares.compactMap { entry -> (Participant, Int, Double)? in
            guard let person = peopleByID[entry.participantID] else { return nil }
            return (person, entry.amountMinorUnits, entry.weight)
        }

        guard !payers.isEmpty, !shares.isEmpty else { return nil }

        // A person leaving the group would otherwise silently shrink the total.
        // Re-spread the difference across whoever is left.
        let plannedTotal = shares.reduce(0) { $0 + $1.1 }
        var resolvedShares = shares
        if plannedTotal != rule.amountMinorUnits {
            let redistributed = SplitCalculator.distributeEvenly(
                total: rule.amountMinorUnits,
                count: shares.count
            )
            resolvedShares = zip(shares, redistributed).map { ($0.0.0, $0.1, $0.0.2) }
        }

        let paidTotal = payers.reduce(0) { $0 + $1.1 }
        var resolvedPayers = payers
        if paidTotal != rule.amountMinorUnits {
            let redistributed = SplitCalculator.distributeEvenly(
                total: rule.amountMinorUnits,
                count: payers.count
            )
            resolvedPayers = zip(payers, redistributed).map { ($0.0.0, $0.1) }
        }

        let expense = Expense(
            title: rule.title,
            amountMinorUnits: rule.amountMinorUnits,
            currencyCode: rule.currencyCode,
            date: date,
            category: rule.category,
            splitMethod: rule.splitMethod,
            group: rule.group
        )
        expense.notes = rule.notes
        expense.generatedByRuleID = rule.id
        expense.baseCurrencyCode = baseCurrencyCode
        context.insert(expense)

        Ledger.applySplit(
            to: expense,
            payers: resolvedPayers.map { (participant: $0.0, amountMinorUnits: $0.1) },
            shares: resolvedShares.map { (participant: $0.0, amountMinorUnits: $0.1, weight: $0.2) },
            in: context
        )

        Ledger.log(
            .recurringGenerated,
            headline: String(
                format: String(localized: "Added the recurring expense %@", comment: "Expense title"),
                expense.displayTitle
            ),
            detail: expense.total.formatted(),
            expenseID: expense.id,
            groupID: rule.group?.id,
            groupName: rule.group?.name ?? "",
            in: context
        )

        return expense
    }

    /// Captures the current split of an expense so a rule can reproduce it.
    static func plan(from expense: Expense) -> RecurringSplitPlan {
        RecurringSplitPlan(
            payers: expense.payerList.compactMap { payer in
                guard let id = payer.participant?.id else { return nil }
                return RecurringSplitPlan.Entry(
                    participantID: id,
                    amountMinorUnits: payer.amountMinorUnits,
                    weight: 0
                )
            },
            shares: expense.shareList.compactMap { share in
                guard let id = share.participant?.id else { return nil }
                return RecurringSplitPlan.Entry(
                    participantID: id,
                    amountMinorUnits: share.amountMinorUnits,
                    weight: share.weight
                )
            }
        )
    }

    /// Every date a rule will fire between now and `limit`, for the preview list.
    static func upcomingDates(for rule: RecurringRule, limit: Int = 5) -> [Date] {
        var dates: [Date] = []
        var cursor = rule.nextOccurrence
        while dates.count < limit {
            if let endDate = rule.endDate, cursor > endDate { break }
            dates.append(cursor)
            cursor = rule.frequency.nextDate(after: cursor)
        }
        return dates
    }
}
