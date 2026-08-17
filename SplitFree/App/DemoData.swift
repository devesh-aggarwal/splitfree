#if DEBUG
import Foundation
import SwiftData

/// Fills the store with a plausible ledger, for App Store screenshots.
///
/// Screenshots taken against an empty app show empty states, and screenshots
/// built by hand cannot be taken again the same way when the design changes.
/// This runs only when the app is launched with `-seedDemoData`, and only in
/// debug builds, so it cannot reach anybody's real data or ship to anybody.
///
/// Regenerate the images with `scripts/screenshots.sh`.
@MainActor
enum DemoData {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedDemoData")
    }

    /// Which tab to open on launch, so the screenshot script never has to tap.
    /// Coordinates drift every time a layout changes; a launch argument does not.
    static var startTab: String? {
        value(after: "-startTab")
    }

    /// Opens the first group, which is the screen worth showing: balances,
    /// simplified debts and a timeline all at once.
    static var opensFirstGroup: Bool {
        ProcessInfo.processInfo.arguments.contains("-openFirstGroup")
    }

    /// Opens the itemized dinner inside the first group, for the screenshot
    /// that shows a bill split line by line.
    static var opensItemizedExpense: Bool {
        ProcessInfo.processInfo.arguments.contains("-openItemizedExpense")
    }

    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    static func seed(into context: ModelContext) {
        wipe(context)

        let you = Ledger.currentUser(in: context)
        you.name = "Ana"
        you.colorIndex = 0

        let marco = person("Marco Silva", colorIndex: 3, in: context)
        let priya = person("Priya Raman", colorIndex: 5, in: context)
        let jonas = person("Jonas Weber", colorIndex: 1, in: context)

        // A trip, mid-flight: some people owe, some are owed, nothing settled.
        let portland = SpendingGroup(
            name: "Portland Trip",
            kind: .trip,
            colorIndex: 2,
            members: [you, marco, priya, jonas],
            defaultCurrencyCode: "USD"
        )
        portland.notes = "Place is on NW 23rd. Check-out is 11am Sunday."
        context.insert(portland)

        add("Hotel, three nights", 84000, .hotel, daysAgo: 6, paidBy: you,
            among: [you, marco, priya, jonas], in: portland, context: context)
        addItemizedDinner(paidBy: marco, you: you, marco: marco, priya: priya, jonas: jonas,
                          in: portland, context: context)
        add("Transit passes", 3600, .publicTransit, daysAgo: 4, paidBy: priya,
            among: [you, marco, priya, jonas], in: portland, context: context)
        add("Art museum", 5000, .activities, daysAgo: 2, paidBy: you,
            among: [you, priya], in: portland, context: context)
        add("Coffee and pastries", 1080, .diningOut, daysAgo: 1, paidBy: jonas,
            among: [you, marco, priya, jonas], in: portland, context: context)

        // A flat share, so the groups list is not one row of one kind.
        let flat = SpendingGroup(
            name: "Oak Street",
            kind: .home,
            colorIndex: 0,
            members: [you, jonas],
            defaultCurrencyCode: "USD"
        )
        context.insert(flat)
        add("Rent, February", 142000, .rent, daysAgo: 12, paidBy: you,
            among: [you, jonas], in: flat, context: context)
        add("Internet", 3200, .internet, daysAgo: 9, paidBy: jonas,
            among: [you, jonas], in: flat, context: context)
        add("Groceries", 6740, .groceries, daysAgo: 3, paidBy: you,
            among: [you, jonas], in: flat, context: context)

        let brunch = SpendingGroup(
            name: "Sunday brunch",
            kind: .event,
            colorIndex: 4,
            members: [you, marco, priya],
            defaultCurrencyCode: "USD"
        )
        context.insert(brunch)
        add("Brunch", 9600, .diningOut, daysAgo: 8, paidBy: priya,
            among: [you, marco, priya], in: brunch, context: context)

        // One settled payment, so the timeline shows both kinds of row.
        let payment = Settlement(
            from: marco,
            to: you,
            amountMinorUnits: 4200,
            currencyCode: "USD",
            date: Date().addingTimeInterval(-2 * 86400),
            method: .venmo,
            group: brunch
        )
        context.insert(payment)

        try? context.save()
    }

    // MARK: - Building blocks

    /// The dinner is split line by line off the receipt, because that is the
    /// screen the screenshots most want to show.
    private static func addItemizedDinner(
        paidBy payer: Participant,
        you: Participant,
        marco: Participant,
        priya: Participant,
        jonas: Participant,
        in group: SpendingGroup,
        context: ModelContext
    ) {
        let everyone = [you, marco, priya, jonas]
        let expense = Expense(
            title: "Dinner downtown",
            amountMinorUnits: 14250,
            currencyCode: group.defaultCurrencyCode,
            date: Date().addingTimeInterval(-4 * 86400),
            category: .diningOut,
            splitMethod: .itemized,
            group: group
        )
        expense.baseCurrencyCode = group.defaultCurrencyCode
        expense.taxMinorUnits = 1150
        expense.tipMinorUnits = 2400
        context.insert(expense)

        let lines: [(name: String, unit: Int, quantity: Int, had: [Participant])] = [
            ("Wood-fired margherita", 1900, 1, [you, marco]),
            ("Rigatoni alla vodka", 2200, 1, [priya]),
            ("Roast half chicken", 2600, 1, [jonas]),
            ("House salad", 1400, 1, [you, marco, priya, jonas]),
            ("Tiramisu", 950, 2, [you, priya]),
            ("Sparkling water", 700, 1, [marco, jonas]),
        ]
        for (index, line) in lines.enumerated() {
            let item = ExpenseLineItem(
                name: line.name,
                amountMinorUnits: line.unit,
                quantity: line.quantity,
                sortOrder: index,
                assignees: line.had
            )
            item.expense = expense
            context.insert(item)
        }

        let allocations = SplitCalculator.itemized(
            total: expense.amountMinorUnits,
            items: lines.map {
                SplitCalculator.ItemAssignment(
                    amountMinorUnits: $0.unit * max(1, $0.quantity),
                    participantIDs: $0.had.map(\.id)
                )
            },
            taxMinorUnits: expense.taxMinorUnits,
            tipMinorUnits: expense.tipMinorUnits,
            fallbackParticipants: everyone.map(\.id)
        )
        Ledger.applySplit(
            to: expense,
            payers: [(participant: payer, amountMinorUnits: expense.amountMinorUnits)],
            shares: allocations.compactMap { allocation in
                everyone.first { $0.id == allocation.participantID }.map {
                    (participant: $0, amountMinorUnits: allocation.amountMinorUnits, weight: 1)
                }
            },
            in: context
        )
    }

    private static func person(_ name: String, colorIndex: Int, in context: ModelContext) -> Participant {
        let participant = Participant(name: name, colorIndex: colorIndex)
        context.insert(participant)
        return participant
    }

    /// Adds an expense split equally, using the same calculator the app uses, so
    /// the totals on screen are the ones the app would really produce.
    private static func add(
        _ title: String,
        _ amount: Int,
        _ category: ExpenseCategory,
        daysAgo: Int,
        paidBy payer: Participant,
        among people: [Participant],
        in group: SpendingGroup,
        context: ModelContext
    ) {
        let expense = Expense(
            title: title,
            amountMinorUnits: amount,
            currencyCode: group.defaultCurrencyCode,
            date: Date().addingTimeInterval(-Double(daysAgo) * 86400),
            category: category,
            splitMethod: .equal,
            group: group
        )
        expense.baseCurrencyCode = group.defaultCurrencyCode
        context.insert(expense)

        let shares = SplitCalculator.distributeEvenly(total: amount, count: people.count)
        Ledger.applySplit(
            to: expense,
            payers: [(participant: payer, amountMinorUnits: amount)],
            shares: zip(people, shares).map {
                (participant: $0, amountMinorUnits: $1, weight: 1)
            },
            in: context
        )
    }

    private static func wipe(_ context: ModelContext) {
        for expense in (try? context.fetch(FetchDescriptor<Expense>())) ?? [] { context.delete(expense) }
        for settlement in (try? context.fetch(FetchDescriptor<Settlement>())) ?? [] { context.delete(settlement) }
        for group in (try? context.fetch(FetchDescriptor<SpendingGroup>())) ?? [] { context.delete(group) }
        for entry in (try? context.fetch(FetchDescriptor<ActivityEntry>())) ?? [] { context.delete(entry) }
        for person in (try? context.fetch(FetchDescriptor<Participant>())) ?? [] where !person.isCurrentUser {
            context.delete(person)
        }
        try? context.save()
    }
}
#endif
