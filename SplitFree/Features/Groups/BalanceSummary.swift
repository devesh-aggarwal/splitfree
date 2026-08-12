import Foundation
import SwiftData

/// Rolls the whole ledger up into the numbers the home screen shows.
///
/// Multi-currency is handled honestly: `byCurrency` keeps each currency
/// separate, and `converted` is offered only as a headline figure, clearly
/// labelled as an approximation in the UI.
struct BalanceSummary {
    var owedToYou: NetPosition = NetPosition()
    var youOwe: NetPosition = NetPosition()

    var net: NetPosition {
        var result = NetPosition()
        for (code, amount) in owedToYou.byCurrency { result.add(amount, currencyCode: code) }
        for (code, amount) in youOwe.byCurrency { result.add(-amount, currencyCode: code) }
        return result
    }

    var isSettled: Bool { net.isSettled }

    /// True when more than one currency is in play, so the UI can explain the
    /// conversion rather than presenting a single number as exact.
    var isMultiCurrency: Bool {
        Set(owedToYou.byCurrency.keys).union(youOwe.byCurrency.keys)
            .filter { code in
                (owedToYou.amount(in: code) != 0) || (youOwe.amount(in: code) != 0)
            }
            .count > 1
    }

    static func make(for user: Participant, sheet: BalanceSheet) -> BalanceSummary {
        var summary = BalanceSummary()
        for debt in sheet.debts {
            if debt.to == user.id {
                summary.owedToYou.add(debt.amountMinorUnits, currencyCode: debt.currencyCode)
            } else if debt.from == user.id {
                summary.youOwe.add(debt.amountMinorUnits, currencyCode: debt.currencyCode)
            }
        }
        return summary
    }
}

/// Cached, whole-ledger balance calculations.
///
/// The engine is cheap for realistic data sizes, but the home screen asks for
/// several views of the same numbers at once, so results are memoised per
/// render pass rather than recomputed per row.
@MainActor
struct LedgerSnapshot {
    let user: Participant
    let expenses: [Expense]
    let settlements: [Settlement]
    let simplifyByDefault: Bool

    init(user: Participant, expenses: [Expense], settlements: [Settlement], simplifyByDefault: Bool) {
        self.user = user
        self.expenses = expenses
        self.settlements = settlements
        self.simplifyByDefault = simplifyByDefault
    }

    /// The user's position across everything.
    var overall: BalanceSummary {
        let sheet = BalanceEngine.balanceSheet(
            expenses: expenses,
            settlements: settlements,
            simplify: false
        )
        return BalanceSummary.make(for: user, sheet: sheet)
    }

    func sheet(for group: SpendingGroup) -> BalanceSheet {
        BalanceEngine.balanceSheet(
            expenses: group.expenseList,
            settlements: group.settlementList,
            simplify: group.simplifyDebts
        )
    }

    func summary(for group: SpendingGroup) -> BalanceSummary {
        BalanceSummary.make(for: user, sheet: sheet(for: group))
    }

    /// The user's position with one friend, across groups and direct expenses.
    func summary(withFriend friend: Participant) -> BalanceSummary {
        let relevantExpenses = expenses.filter { expense in
            let ids = Set(expense.involvedParticipants.map(\.id))
            return ids.contains(user.id) && ids.contains(friend.id)
        }
        let relevantSettlements = settlements.filter { settlement in
            let ids = [settlement.fromParticipant?.id, settlement.toParticipant?.id].compactMap { $0 }
            return ids.contains(user.id) && ids.contains(friend.id)
        }
        let sheet = BalanceEngine.balanceSheet(
            expenses: relevantExpenses,
            settlements: relevantSettlements,
            simplify: false
        )

        // Restrict to the edge between these two people; a group expense can
        // create debts that don't involve this pair at all.
        var summary = BalanceSummary()
        for debt in sheet.debts {
            if debt.to == user.id && debt.from == friend.id {
                summary.owedToYou.add(debt.amountMinorUnits, currencyCode: debt.currencyCode)
            } else if debt.from == user.id && debt.to == friend.id {
                summary.youOwe.add(debt.amountMinorUnits, currencyCode: debt.currencyCode)
            }
        }
        return summary
    }
}

extension NetPosition {
    /// The single figure to show when a summary spans currencies.
    func headline(baseCode: String, rates: ExchangeRateTable, convert: Bool) -> Money {
        let codes = nonZeroCurrencies
        if codes.count == 1, let code = codes.first {
            return Money(minorUnits: amount(in: code), currencyCode: code)
        }
        if convert {
            return converted(to: baseCode, rates: rates)
        }
        return Money(minorUnits: amount(in: baseCode), currencyCode: baseCode)
    }
}
