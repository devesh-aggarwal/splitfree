import Foundation
import Observation
import SwiftData
import SwiftUI

/// The working copy of an expense while it's being written.
///
/// Nothing is committed to the store until `save` is called, so backing out of
/// the editor leaves no trace — including on an expense being edited.
@Observable
@MainActor
final class ExpenseDraft {

    // MARK: - Core fields

    var title: String = "" {
        didSet { applyCategorySuggestionIfNeeded() }
    }
    var amountMinorUnits: Int = 0
    var currencyCode: String = Currency.deviceDefaultCode
    var date: Date = Date()
    var notes: String = ""
    var category: ExpenseCategory = .general
    /// Set once the person picks a category, so typing stops overriding them.
    private(set) var hasManualCategory = false

    var group: SpendingGroup?
    var receiptImageData: Data?
    var receiptText: String = ""

    // MARK: - People

    /// Everyone who could be part of this expense — group members, or the
    /// friends chosen for a groupless expense.
    var candidates: [Participant] = []
    /// Who is actually splitting it.
    var includedIDs: Set<UUID> = []

    // MARK: - Paying

    /// When one person covered the whole bill (the common case), this is them.
    var singlePayerID: UUID?
    /// Used when several people chipped in.
    var multiplePayerAmounts: [UUID: Int] = [:]
    var usesMultiplePayers = false

    // MARK: - Splitting

    var splitMethod: SplitMethod = .equal {
        didSet {
            guard oldValue != splitMethod else { return }
            seedValuesForCurrentMethod(previous: oldValue)
        }
    }
    /// Per-person raw input, meaning set by `splitMethod`.
    var splitValues: [UUID: Double] = [:]

    // MARK: - Itemization

    var lineItems: [DraftLineItem] = []
    var taxMinorUnits: Int = 0
    var tipMinorUnits: Int = 0

    // MARK: - Recurrence

    var isRecurring = false
    var recurrenceFrequency: RecurrenceFrequency = .monthly
    var recurrenceEndDate: Date?

    // MARK: - Bookkeeping

    let editingExpense: Expense?
    var currentUser: Participant
    var baseCurrencyCode: String = "USD"
    var exchangeRateToBase: Double = 1.0

    struct DraftLineItem: Identifiable, Hashable {
        var id = UUID()
        var name: String = ""
        var amountMinorUnits: Int = 0
        var quantity: Int = 1
        var assigneeIDs: Set<UUID> = []
    }

    // MARK: - Init

    init(currentUser: Participant, group: SpendingGroup?, candidates: [Participant], currencyCode: String) {
        self.currentUser = currentUser
        self.editingExpense = nil
        self.group = group
        self.candidates = candidates
        self.currencyCode = currencyCode
        self.includedIDs = Set(candidates.map(\.id))
        self.singlePayerID = currentUser.id
    }

    init(editing expense: Expense, currentUser: Participant, candidates: [Participant]) {
        self.currentUser = currentUser
        self.editingExpense = expense
        self.title = expense.title
        self.amountMinorUnits = expense.amountMinorUnits
        self.currencyCode = expense.currencyCode
        self.date = expense.date
        self.notes = expense.notes
        self.category = expense.category
        self.hasManualCategory = true
        self.group = expense.group
        self.receiptImageData = expense.receiptImageData
        self.receiptText = expense.receiptText
        self.taxMinorUnits = expense.taxMinorUnits
        self.tipMinorUnits = expense.tipMinorUnits
        self.baseCurrencyCode = expense.baseCurrencyCode
        self.exchangeRateToBase = expense.exchangeRateToBase

        // Anyone already on the expense must remain selectable even if they've
        // since left the group.
        var people = candidates
        for person in expense.involvedParticipants where !people.contains(where: { $0.id == person.id }) {
            people.append(person)
        }
        self.candidates = people
        self.includedIDs = Set(expense.shareList.compactMap { $0.participant?.id })

        let payers = expense.payerList.filter { $0.amountMinorUnits != 0 }
        if payers.count <= 1 {
            self.usesMultiplePayers = false
            self.singlePayerID = payers.first?.participant?.id ?? currentUser.id
        } else {
            self.usesMultiplePayers = true
            self.multiplePayerAmounts = Dictionary(
                payers.compactMap { payer in
                    payer.participant.map { ($0.id, payer.amountMinorUnits) }
                },
                uniquingKeysWith: { first, _ in first }
            )
        }

        self.splitMethod = expense.splitMethod
        self.splitValues = Dictionary(
            expense.shareList.compactMap { share in
                share.participant.map { ($0.id, ExpenseDraft.storedValue(for: share, method: expense.splitMethod)) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        self.lineItems = expense.lineItemList.map { item in
            DraftLineItem(
                id: item.id,
                name: item.name,
                amountMinorUnits: item.amountMinorUnits,
                quantity: item.quantity,
                assigneeIDs: Set(item.assigneeList.map(\.id))
            )
        }
    }

    /// Recovers the editor value that produced a stored share.
    private static func storedValue(for share: ExpenseShare, method: SplitMethod) -> Double {
        switch method {
        case .equal, .itemized: 1
        case .exact: Double(share.amountMinorUnits)
        case .percent, .shares, .adjustment: share.weight
        }
    }

    // MARK: - Derived people

    var includedParticipants: [Participant] {
        candidates.filter { includedIDs.contains($0.id) }
    }

    func participant(id: UUID) -> Participant? {
        candidates.first { $0.id == id }
    }

    func isIncluded(_ participant: Participant) -> Bool {
        includedIDs.contains(participant.id)
    }

    func toggleInclusion(_ participant: Participant) {
        if includedIDs.contains(participant.id) {
            // Never leave a split with nobody in it.
            guard includedIDs.count > 1 else { return }
            includedIDs.remove(participant.id)
            splitValues[participant.id] = nil
        } else {
            includedIDs.insert(participant.id)
            seedValue(for: participant.id)
        }
    }

    // MARK: - Paying

    var payerIDs: [UUID] {
        if usesMultiplePayers {
            return multiplePayerAmounts.filter { $0.value != 0 }.keys.sorted { lhs, rhs in
                (participant(id: lhs)?.fullName ?? "") < (participant(id: rhs)?.fullName ?? "")
            }
        }
        return singlePayerID.map { [$0] } ?? []
    }

    var payerAllocations: [(participant: Participant, amountMinorUnits: Int)] {
        if usesMultiplePayers {
            return multiplePayerAmounts.compactMap { id, amount in
                guard amount != 0, let person = participant(id: id) else { return nil }
                return (person, amount)
            }
            .sorted { $0.participant.fullName < $1.participant.fullName }
        }
        guard let id = singlePayerID, let person = participant(id: id) else { return [] }
        return [(person, amountMinorUnits)]
    }

    var totalPaidMinorUnits: Int {
        payerAllocations.reduce(0) { $0 + $1.amountMinorUnits }
    }

    /// Nonzero when several payers' contributions don't add up to the total.
    var payerRemainder: Int {
        usesMultiplePayers ? amountMinorUnits - totalPaidMinorUnits : 0
    }

    /// "You", "Ana", or "3 people".
    var payerSummaryText: String {
        let payers = payerAllocations
        if payers.isEmpty { return String(localized: "someone") }
        if payers.count == 1 { return payers[0].participant.displayName }
        return String(localized: "^[\(payers.count) person](inflect: true)", comment: "Payer count")
    }

    // MARK: - Splitting

    var splitEntries: [SplitCalculator.Entry] {
        candidates.map { person in
            SplitCalculator.Entry(
                participantID: person.id,
                isIncluded: includedIDs.contains(person.id),
                value: splitValues[person.id] ?? defaultValue(for: splitMethod)
            )
        }
    }

    var itemAssignments: [SplitCalculator.ItemAssignment] {
        lineItems.map { item in
            SplitCalculator.ItemAssignment(
                amountMinorUnits: item.amountMinorUnits * max(1, item.quantity),
                participantIDs: Array(item.assigneeIDs)
            )
        }
    }

    var allocations: [SplitCalculator.Allocation] {
        SplitCalculator.resolve(
            method: splitMethod,
            total: amountMinorUnits,
            currencyCode: currencyCode,
            entries: splitEntries,
            items: itemAssignments,
            taxMinorUnits: taxMinorUnits,
            tipMinorUnits: tipMinorUnits
        )
    }

    func allocatedAmount(for participantID: UUID) -> Int {
        allocations.first { $0.participantID == participantID }?.amountMinorUnits ?? 0
    }

    var validationIssue: SplitCalculator.ValidationIssue? {
        guard amountMinorUnits > 0 else { return .negativeTotal }
        return SplitCalculator.validate(
            method: splitMethod,
            total: amountMinorUnits,
            currencyCode: currencyCode,
            entries: splitEntries
        )
    }

    var canSave: Bool {
        amountMinorUnits > 0
            && !includedIDs.isEmpty
            && !payerAllocations.isEmpty
            && validationIssue == nil
            && (!usesMultiplePayers || payerRemainder == 0)
    }

    /// "Split equally between 4 people" — the one-line summary on the main form.
    var splitSummaryText: String {
        let count = includedIDs.count
        switch splitMethod {
        case .equal:
            let each = Money(minorUnits: count > 0 ? amountMinorUnits / count : 0, currencyCode: currencyCode)
            return count > 0
                ? String(
                    localized: "Equally · \(each.formatted()) each · ^[\(count) person](inflect: true)",
                    comment: "Amount, count"
                )
                : splitMethod.title
        case .itemized:
            return String(
                localized: "By item · ^[\(lineItems.count) item](inflect: true)",
                comment: "Item count"
            )
        default:
            return String(
                localized: "\(splitMethod.title) · ^[\(count) person](inflect: true)",
                comment: "Split method, count"
            )
        }
    }

    private func defaultValue(for method: SplitMethod) -> Double {
        switch method {
        case .equal, .itemized: 1
        case .shares: 1
        case .percent: includedIDs.isEmpty ? 0 : 100.0 / Double(includedIDs.count)
        case .exact, .adjustment: 0
        }
    }

    private func seedValue(for id: UUID) {
        splitValues[id] = defaultValue(for: splitMethod)
    }

    /// Gives every included person a sensible starting value when the method
    /// changes, seeded from what they were already going to pay so switching
    /// from "equally" to "exact amounts" doesn't wipe the screen.
    private func seedValuesForCurrentMethod(previous: SplitMethod) {
        let previousAllocations = SplitCalculator.resolve(
            method: previous,
            total: amountMinorUnits,
            currencyCode: currencyCode,
            entries: candidates.map { person in
                SplitCalculator.Entry(
                    participantID: person.id,
                    isIncluded: includedIDs.contains(person.id),
                    value: splitValues[person.id] ?? defaultValue(for: previous)
                )
            },
            items: itemAssignments,
            taxMinorUnits: taxMinorUnits,
            tipMinorUnits: tipMinorUnits
        )
        let previousByID = Dictionary(
            previousAllocations.map { ($0.participantID, $0.amountMinorUnits) },
            uniquingKeysWith: { first, _ in first }
        )

        var updated: [UUID: Double] = [:]
        for id in includedIDs {
            switch splitMethod {
            case .equal, .itemized:
                updated[id] = 1
            case .shares:
                updated[id] = 1
            case .exact:
                updated[id] = Double(previousByID[id] ?? 0)
            case .percent:
                let amount = Double(previousByID[id] ?? 0)
                updated[id] = amountMinorUnits > 0
                    ? (amount / Double(amountMinorUnits) * 100).rounded(toPlaces: 2)
                    : (includedIDs.isEmpty ? 0 : 100.0 / Double(includedIDs.count))
            case .adjustment:
                updated[id] = 0
            }
        }

        // Rounding each percentage independently can leave the total a hair off
        // 100. Put the difference on the largest share so the seeded state is
        // already valid and nobody has to hunt for the stray 0.01%.
        if splitMethod == .percent, !updated.isEmpty {
            let sum = updated.values.reduce(0, +)
            let drift = (100 - sum).rounded(toPlaces: 2)
            if drift != 0, let largest = updated.max(by: { $0.value < $1.value })?.key {
                updated[largest] = ((updated[largest] ?? 0) + drift).rounded(toPlaces: 2)
            }
        }

        splitValues = updated
    }

    /// Redistributes percentages so they hit exactly 100 — the "even it out"
    /// affordance on the split sheet.
    func balancePercentages() {
        let ids = Array(includedIDs)
        guard !ids.isEmpty else { return }
        let each = (100.0 / Double(ids.count)).rounded(toPlaces: 2)
        var values: [UUID: Double] = [:]
        for id in ids { values[id] = each }
        // Put whatever the rounding left over onto the first person.
        let assigned = each * Double(ids.count)
        if let first = ids.first {
            values[first] = ((values[first] ?? 0) + (100 - assigned)).rounded(toPlaces: 2)
        }
        splitValues = values
    }

    /// Fills the remaining amount onto one person in exact-amount mode.
    func assignRemainder(to id: UUID) {
        let others = includedIDs.filter { $0 != id }
            .reduce(0) { $0 + Int((splitValues[$1] ?? 0).rounded()) }
        splitValues[id] = Double(max(0, amountMinorUnits - others))
    }

    private func applyCategorySuggestionIfNeeded() {
        guard !hasManualCategory else { return }
        if let suggestion = ExpenseCategory.suggestion(for: title) {
            category = suggestion
        }
    }

    func setCategory(_ newValue: ExpenseCategory) {
        category = newValue
        hasManualCategory = true
    }

    // MARK: - Itemization helpers

    var lineItemsTotalMinorUnits: Int {
        lineItems.reduce(0) { $0 + $1.amountMinorUnits * max(1, $1.quantity) }
    }

    /// The gap between the receipt lines plus extras and the stated total.
    var itemizationRemainder: Int {
        amountMinorUnits - (lineItemsTotalMinorUnits + taxMinorUnits + tipMinorUnits)
    }

    /// Sets the total from the receipt so the two can't disagree.
    func adoptItemizedTotal() {
        amountMinorUnits = lineItemsTotalMinorUnits + taxMinorUnits + tipMinorUnits
    }

    // MARK: - Saving

    @discardableResult
    func save(in context: ModelContext, settings: AppSettings, rates: ExchangeRateTable) -> Expense {
        let isNew = editingExpense == nil
        let expense = editingExpense ?? Expense()
        if isNew { context.insert(expense) }

        expense.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.amountMinorUnits = amountMinorUnits
        expense.currencyCode = currencyCode
        expense.date = date
        expense.notes = notes
        expense.category = category
        expense.splitMethod = splitMethod
        expense.group = group
        expense.receiptImageData = receiptImageData
        expense.receiptText = receiptText
        expense.taxMinorUnits = taxMinorUnits
        expense.tipMinorUnits = tipMinorUnits
        expense.updatedAt = Date()

        expense.baseCurrencyCode = settings.baseCurrencyCode
        expense.exchangeRateToBase = rates.rate(from: currencyCode, to: settings.baseCurrencyCode) ?? 1.0

        // Payers
        var payers: [(participant: Participant, amountMinorUnits: Int)] = payerAllocations
        if !usesMultiplePayers, let id = singlePayerID, let person = participant(id: id) {
            payers = [(person, amountMinorUnits)]
        }

        // Shares
        let resolved = allocations
        let shares: [(participant: Participant, amountMinorUnits: Int, weight: Double)] = resolved.compactMap { allocation in
            guard let person = participant(id: allocation.participantID) else { return nil }
            return (person, allocation.amountMinorUnits, allocation.weight)
        }

        Ledger.applySplit(to: expense, payers: payers, shares: shares, in: context)

        // Line items
        for existing in expense.lineItemList { context.delete(existing) }
        expense.lineItems = []
        for (index, item) in lineItems.enumerated() where !item.name.isEmpty || item.amountMinorUnits != 0 {
            let stored = ExpenseLineItem(
                name: item.name,
                amountMinorUnits: item.amountMinorUnits,
                quantity: item.quantity,
                sortOrder: index,
                assignees: item.assigneeIDs.compactMap { participant(id: $0) }
            )
            stored.expense = expense
            context.insert(stored)
        }

        settings.noteCurrencyUsed(currencyCode)

        if isRecurring {
            createOrUpdateRecurringRule(for: expense, in: context)
        }

        Ledger.log(
            isNew ? .expenseAdded : .expenseEdited,
            headline: String(
                format: isNew
                    ? String(localized: "%1$@ added %2$@", comment: "Person, expense")
                    : String(localized: "%1$@ updated %2$@", comment: "Person, expense"),
                currentUser.displayName,
                expense.displayTitle
            ),
            detail: Ledger.personalImpact(of: expense, for: currentUser),
            expenseID: expense.id,
            groupID: group?.id,
            groupName: group?.name ?? "",
            in: context
        )

        try? context.save()
        return expense
    }

    private func createOrUpdateRecurringRule(for expense: Expense, in context: ModelContext) {
        let rule = RecurringRule(
            title: expense.title,
            amountMinorUnits: expense.amountMinorUnits,
            currencyCode: expense.currencyCode,
            frequency: recurrenceFrequency,
            startDate: recurrenceFrequency.nextDate(after: expense.date),
            group: group,
            category: category,
            splitMethod: splitMethod
        )
        rule.notes = notes
        rule.endDate = recurrenceEndDate
        rule.splitPlan = RecurrenceService.plan(from: expense)
        context.insert(rule)
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
