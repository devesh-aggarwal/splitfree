import Foundation
import SwiftData

/// Writes to the store. Every mutation the app makes goes through here so that
/// activity logging, timestamps and invariants live in one place instead of
/// being sprinkled through views.
@MainActor
enum Ledger {

    // MARK: - Current user

    /// Returns the current user's `Participant`, creating it on first launch.
    @discardableResult
    static func currentUser(in context: ModelContext) -> Participant {
        let descriptor = FetchDescriptor<Participant>(
            predicate: #Predicate { $0.isCurrentUser == true }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let me = Participant(
            name: String(localized: "You", comment: "Default name for the account owner"),
            colorIndex: 0,
            isCurrentUser: true
        )
        context.insert(me)
        try? context.save()
        return me
    }

    // MARK: - Deletion

    /// Notes that something was deleted so sync can tell a friend's phone about
    /// it. Local-only rows are skipped: nothing on the server ever knew about
    /// them, so there is nothing to tell.
    static func recordTombstone(
        _ entity: SyncEntity,
        id: UUID,
        groupID: UUID? = nil,
        in context: ModelContext
    ) {
        guard let groupID else { return }
        let descriptor = FetchDescriptor<SpendingGroup>(predicate: #Predicate { $0.id == groupID })
        guard let group = try? context.fetch(descriptor).first, group.isShared else { return }
        context.insert(SyncTombstone(entity: entity, entityID: id, groupID: groupID))
    }

    // MARK: - Activity

    static func log(
        _ kind: ActivityKind,
        headline: String,
        detail: String = "",
        expenseID: UUID? = nil,
        groupID: UUID? = nil,
        settlementID: UUID? = nil,
        groupName: String = "",
        in context: ModelContext
    ) {
        let entry = ActivityEntry(
            kind: kind,
            headline: headline,
            detail: detail,
            expenseID: expenseID,
            groupID: groupID,
            settlementID: settlementID,
            groupName: groupName
        )
        context.insert(entry)
    }

    /// Describes what an expense means for the current user: what they get back,
    /// what they owe, or that they're not involved.
    static func personalImpact(of expense: Expense, for user: Participant) -> String {
        let net = expense.net(for: user)
        let money = Money(minorUnits: abs(net), currencyCode: expense.currencyCode)
        if net > 0 {
            return String(format: String(localized: "You get back %@", comment: "Amount owed to user"), money.formatted())
        }
        if net < 0 {
            return String(format: String(localized: "You owe %@", comment: "Amount user owes"), money.formatted())
        }
        let isInvolved = expense.involvedParticipants.contains { $0.id == user.id }
        return isInvolved
            ? String(localized: "You're settled on this")
            : String(localized: "You're not involved")
    }

    // MARK: - Expenses

    /// Replaces an expense's payers and shares with the given allocations.
    ///
    /// Old child objects are deleted rather than mutated so a removed person
    /// can't linger with a stale zero share.
    static func applySplit(
        to expense: Expense,
        payers: [(participant: Participant, amountMinorUnits: Int)],
        shares: [(participant: Participant, amountMinorUnits: Int, weight: Double)],
        in context: ModelContext
    ) {
        for payer in expense.payerList { context.delete(payer) }
        for share in expense.shareList { context.delete(share) }
        expense.payers = []
        expense.shares = []

        for entry in payers where entry.amountMinorUnits != 0 {
            let payer = ExpensePayer(participant: entry.participant, amountMinorUnits: entry.amountMinorUnits)
            payer.expense = expense
            context.insert(payer)
        }

        for entry in shares {
            let share = ExpenseShare(
                participant: entry.participant,
                amountMinorUnits: entry.amountMinorUnits,
                weight: entry.weight
            )
            share.expense = expense
            context.insert(share)
        }

        expense.updatedAt = Date()
    }

    static func delete(expense: Expense, in context: ModelContext) {
        let user = currentUser(in: context)
        log(
            .expenseDeleted,
            headline: String(
                format: String(localized: "%1$@ deleted %2$@", comment: "Person, expense title"),
                user.displayName,
                expense.displayTitle
            ),
            detail: expense.total.formatted(),
            groupID: expense.group?.id,
            groupName: expense.group?.name ?? "",
            in: context
        )
        recordTombstone(.expense, id: expense.id, groupID: expense.group?.id, in: context)
        context.delete(expense)
    }

    static func delete(settlement: Settlement, in context: ModelContext) {
        let user = currentUser(in: context)
        log(
            .settlementDeleted,
            headline: String(
                format: String(localized: "%@ undid a payment", comment: "Person"),
                user.displayName
            ),
            detail: settlement.summary,
            groupID: settlement.group?.id,
            groupName: settlement.group?.name ?? "",
            in: context
        )
        recordTombstone(.settlement, id: settlement.id, groupID: settlement.group?.id, in: context)
        context.delete(settlement)
    }

    // MARK: - Groups

    static func delete(group: SpendingGroup, in context: ModelContext) {
        log(
            .groupArchived,
            headline: String(
                format: String(localized: "Deleted the group %@", comment: "Group name"),
                group.displayName
            ),
            in: context
        )
        recordTombstone(.group, id: group.id, groupID: group.id, in: context)
        for expense in group.expenseList {
            recordTombstone(.expense, id: expense.id, groupID: group.id, in: context)
        }
        for settlement in group.settlementList {
            recordTombstone(.settlement, id: settlement.id, groupID: group.id, in: context)
        }
        context.delete(group)
    }

    /// A member can only leave once they're square with everyone.
    static func canRemove(_ participant: Participant, from group: SpendingGroup) -> Bool {
        let sheet = BalanceEngine.balanceSheet(
            expenses: group.expenseList,
            settlements: group.settlementList,
            simplify: false
        )
        return sheet.position(for: participant.id).isSettled
    }

    static func remove(_ participant: Participant, from group: SpendingGroup, in context: ModelContext) {
        group.members?.removeAll { $0.id == participant.id }
        group.updatedAt = Date()
        recordTombstone(.member, id: participant.id, groupID: group.id, in: context)
        log(
            .memberRemoved,
            headline: String(
                format: String(localized: "%1$@ left %2$@", comment: "Person, group"),
                participant.fullName,
                group.displayName
            ),
            groupID: group.id,
            groupName: group.name,
            in: context
        )
    }

    // MARK: - Settling

    @discardableResult
    static func recordSettlement(
        from: Participant,
        to: Participant,
        amountMinorUnits: Int,
        currencyCode: String,
        date: Date = Date(),
        method: PaymentMethod,
        notes: String = "",
        group: SpendingGroup?,
        baseCurrencyCode: String,
        rate: Double,
        in context: ModelContext
    ) -> Settlement {
        let settlement = Settlement(
            from: from,
            to: to,
            amountMinorUnits: amountMinorUnits,
            currencyCode: currencyCode,
            date: date,
            method: method,
            group: group
        )
        settlement.notes = notes
        settlement.baseCurrencyCode = baseCurrencyCode
        settlement.exchangeRateToBase = rate
        context.insert(settlement)

        log(
            .settlementAdded,
            // The group already appears on the entry's metadata line, so the
            // detail carries the method instead of repeating it.
            headline: settlement.summary,
            detail: method.title,
            groupID: group?.id,
            settlementID: settlement.id,
            groupName: group?.name ?? "",
            in: context
        )
        return settlement
    }

    // MARK: - Queries

    static func allExpenses(in context: ModelContext) -> [Expense] {
        (try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    static func allSettlements(in context: ModelContext) -> [Settlement] {
        (try? context.fetch(FetchDescriptor<Settlement>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    static func allParticipants(in context: ModelContext) -> [Participant] {
        (try? context.fetch(FetchDescriptor<Participant>())) ?? []
    }

    /// Expenses and settlements shared strictly between the user and one friend,
    /// i.e. outside any group.
    static func directLedger(
        between user: Participant,
        and friend: Participant,
        in context: ModelContext
    ) -> (expenses: [Expense], settlements: [Settlement]) {
        let expenses = allExpenses(in: context).filter { expense in
            guard expense.group == nil else { return false }
            let ids = Set(expense.involvedParticipants.map(\.id))
            return ids.contains(user.id) && ids.contains(friend.id)
        }
        let settlements = allSettlements(in: context).filter { settlement in
            guard settlement.group == nil else { return false }
            let ids = [settlement.fromParticipant?.id, settlement.toParticipant?.id].compactMap { $0 }
            return ids.contains(user.id) && ids.contains(friend.id)
        }
        return (expenses, settlements)
    }

    /// Every expense and settlement touching a friend, groups included — the
    /// figure shown next to their name on the Friends tab.
    static func sharedLedger(
        between user: Participant,
        and friend: Participant,
        in context: ModelContext
    ) -> (expenses: [Expense], settlements: [Settlement]) {
        let expenses = allExpenses(in: context).filter { expense in
            let ids = Set(expense.involvedParticipants.map(\.id))
            return ids.contains(user.id) && ids.contains(friend.id)
        }
        let settlements = allSettlements(in: context).filter { settlement in
            let ids = [settlement.fromParticipant?.id, settlement.toParticipant?.id].compactMap { $0 }
            return ids.contains(user.id) && ids.contains(friend.id)
        }
        return (expenses, settlements)
    }
}
