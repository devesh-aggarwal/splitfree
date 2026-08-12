import Foundation
import SwiftData
import Testing

@testable import SplitFree

/// Balance tests run against a real in-memory SwiftData store, because the
/// engine reads through the model relationships.
@MainActor
@Suite("Balance engine")
struct BalanceEngineTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Participant.self, SpendingGroup.self, Expense.self, ExpensePayer.self,
            ExpenseShare.self, ExpenseLineItem.self, ExpenseComment.self,
            Settlement.self, RecurringRule.self, SplitTemplate.self, ActivityEntry.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @discardableResult
    private func addExpense(
        _ context: ModelContext,
        total: Int,
        currency: String = "USD",
        paidBy: [(Participant, Int)],
        owedBy: [(Participant, Int)]
    ) -> Expense {
        let expense = Expense(title: "Test", amountMinorUnits: total, currencyCode: currency)
        context.insert(expense)
        for (person, amount) in paidBy {
            let payer = ExpensePayer(participant: person, amountMinorUnits: amount)
            payer.expense = expense
            context.insert(payer)
        }
        for (person, amount) in owedBy {
            let share = ExpenseShare(participant: person, amountMinorUnits: amount)
            share.expense = expense
            context.insert(share)
        }
        return expense
    }

    // MARK: - Basics

    @Test("One person paying for two produces a single debt")
    func simpleDebt() throws {
        let context = try makeContext()
        let me = Participant(name: "Me", isCurrentUser: true)
        let ana = Participant(name: "Ana")
        context.insert(me)
        context.insert(ana)

        addExpense(context, total: 1000, paidBy: [(me, 1000)], owedBy: [(me, 500), (ana, 500)])

        let sheet = BalanceEngine.balanceSheet(
            expenses: [try #require(context.fetch(FetchDescriptor<Expense>()).first)],
            settlements: [],
            simplify: false
        )
        #expect(sheet.debts.count == 1)
        let debt = try #require(sheet.debts.first)
        #expect(debt.from == ana.id)
        #expect(debt.to == me.id)
        #expect(debt.amountMinorUnits == 500)
    }

    @Test("Debts in both directions net out into one")
    func mutualDebtsNet() throws {
        let context = try makeContext()
        let me = Participant(name: "Me", isCurrentUser: true)
        let ana = Participant(name: "Ana")
        context.insert(me)
        context.insert(ana)

        addExpense(context, total: 1000, paidBy: [(me, 1000)], owedBy: [(me, 500), (ana, 500)])
        addExpense(context, total: 600, paidBy: [(ana, 600)], owedBy: [(me, 300), (ana, 300)])

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let sheet = BalanceEngine.balanceSheet(expenses: expenses, settlements: [], simplify: false)

        #expect(sheet.debts.count == 1)
        let debt = try #require(sheet.debts.first)
        #expect(debt.from == ana.id)
        #expect(debt.to == me.id)
        #expect(debt.amountMinorUnits == 200)
    }

    @Test("A settlement cancels the debt it pays off")
    func settlementClearsDebt() throws {
        let context = try makeContext()
        let me = Participant(name: "Me", isCurrentUser: true)
        let ana = Participant(name: "Ana")
        context.insert(me)
        context.insert(ana)

        addExpense(context, total: 1000, paidBy: [(me, 1000)], owedBy: [(me, 500), (ana, 500)])
        let settlement = Settlement(from: ana, to: me, amountMinorUnits: 500, currencyCode: "USD")
        context.insert(settlement)

        let sheet = BalanceEngine.balanceSheet(
            expenses: try context.fetch(FetchDescriptor<Expense>()),
            settlements: [settlement],
            simplify: false
        )
        #expect(sheet.isFullySettled)
    }

    @Test("A part payment leaves the remainder outstanding")
    func partialSettlement() throws {
        let context = try makeContext()
        let me = Participant(name: "Me", isCurrentUser: true)
        let ana = Participant(name: "Ana")
        context.insert(me)
        context.insert(ana)

        addExpense(context, total: 1000, paidBy: [(me, 1000)], owedBy: [(me, 500), (ana, 500)])
        let settlement = Settlement(from: ana, to: me, amountMinorUnits: 200, currencyCode: "USD")
        context.insert(settlement)

        let sheet = BalanceEngine.balanceSheet(
            expenses: try context.fetch(FetchDescriptor<Expense>()),
            settlements: [settlement],
            simplify: false
        )
        #expect(sheet.debts.first?.amountMinorUnits == 300)
    }

    // MARK: - Simplification

    @Test("Simplifying a circular debt removes the middle leg entirely")
    func simplifyCircularDebt() throws {
        let context = try makeContext()
        let a = Participant(name: "A", isCurrentUser: true)
        let b = Participant(name: "B")
        let c = Participant(name: "C")
        [a, b, c].forEach(context.insert)

        // A pays for B, B pays for C, C pays for A — all $10.
        addExpense(context, total: 1000, paidBy: [(a, 1000)], owedBy: [(b, 1000)])
        addExpense(context, total: 1000, paidBy: [(b, 1000)], owedBy: [(c, 1000)])
        addExpense(context, total: 1000, paidBy: [(c, 1000)], owedBy: [(a, 1000)])

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let detailed = BalanceEngine.balanceSheet(expenses: expenses, settlements: [], simplify: false)
        let simplified = BalanceEngine.balanceSheet(expenses: expenses, settlements: [], simplify: true)

        #expect(detailed.debts.count == 3)
        // Everyone is square once you follow the circle round.
        #expect(simplified.debts.isEmpty)
    }

    @Test("Simplification never needs more than one payment fewer than there are people")
    func simplifyBoundsPaymentCount() throws {
        let context = try makeContext()
        let people = (0..<5).map { Participant(name: "P\($0)") }
        people.forEach(context.insert)

        for (index, payer) in people.enumerated() {
            let total = 1000 * (index + 1)
            let shares = SplitCalculator.equal(total: total, among: people.map(\.id))
            addExpense(
                context,
                total: total,
                paidBy: [(payer, total)],
                owedBy: shares.map { allocation in
                    (people.first { $0.id == allocation.participantID }!, allocation.amountMinorUnits)
                }
            )
        }

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let simplified = BalanceEngine.balanceSheet(expenses: expenses, settlements: [], simplify: true)
        #expect(simplified.debts.count <= people.count - 1)
    }

    @Test("Simplified debts settle everyone: net positions all reach zero")
    func simplifyIsComplete() throws {
        let context = try makeContext()
        let people = (0..<4).map { Participant(name: "P\($0)") }
        people.forEach(context.insert)

        addExpense(
            context,
            total: 10_000,
            paidBy: [(people[0], 7000), (people[1], 3000)],
            owedBy: [(people[0], 2500), (people[1], 2500), (people[2], 2500), (people[3], 2500)]
        )

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let sheet = BalanceEngine.balanceSheet(expenses: expenses, settlements: [], simplify: true)

        // Applying every suggested payment must zero every position.
        var net: [UUID: Int] = [:]
        for person in people {
            net[person.id] = BalanceEngine.overallPosition(
                for: person.id,
                expenses: expenses,
                settlements: []
            ).amount(in: "USD")
        }
        for debt in sheet.debts {
            net[debt.from, default: 0] += debt.amountMinorUnits
            net[debt.to, default: 0] -= debt.amountMinorUnits
        }
        #expect(net.values.allSatisfy { $0 == 0 }, "left over: \(net)")
    }

    @Test("Debts in different currencies are never mixed together")
    func currenciesStaySeparate() throws {
        let context = try makeContext()
        let me = Participant(name: "Me", isCurrentUser: true)
        let ana = Participant(name: "Ana")
        context.insert(me)
        context.insert(ana)

        addExpense(context, total: 1000, currency: "USD", paidBy: [(me, 1000)], owedBy: [(ana, 1000)])
        addExpense(context, total: 900, currency: "EUR", paidBy: [(ana, 900)], owedBy: [(me, 900)])

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let sheet = BalanceEngine.balanceSheet(expenses: expenses, settlements: [], simplify: false)

        #expect(sheet.debts.count == 2)
        #expect(Set(sheet.debts.map(\.currencyCode)) == ["USD", "EUR"])
    }

    @Test("The same inputs always produce the same payment list")
    func simplificationIsDeterministic() throws {
        let context = try makeContext()
        let people = (0..<4).map { Participant(name: "P\($0)") }
        people.forEach(context.insert)
        addExpense(
            context,
            total: 12_000,
            paidBy: [(people[0], 12_000)],
            owedBy: people.map { ($0, 3000) }
        )

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let first = BalanceEngine.balanceSheet(expenses: expenses, settlements: [], simplify: true).debts
        let second = BalanceEngine.balanceSheet(expenses: expenses, settlements: [], simplify: true).debts
        #expect(first == second)
    }

    @Test("Greedy matching zeroes out the balances it is given")
    func greedyTransfersBalance() {
        let a = UUID(), b = UUID(), c = UUID()
        let nets: [UUID: Int] = [a: 500, b: -300, c: -200]
        let transfers = BalanceEngine.greedyTransfers(nets: nets)

        var result = nets
        for transfer in transfers {
            result[transfer.from, default: 0] += transfer.amount
            result[transfer.to, default: 0] -= transfer.amount
        }
        #expect(result.values.allSatisfy { $0 == 0 })
        #expect(transfers.count == 2)
    }
}
