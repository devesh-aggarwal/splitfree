package com.splitfree.data

import com.splitfree.core.BalanceEngine
import com.splitfree.core.BalanceSheet
import com.splitfree.core.ExpenseLedgerEntry
import com.splitfree.core.Money
import com.splitfree.core.NetPosition
import com.splitfree.core.SettlementLedgerEntry
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map

/**
 * Everything the UI reads, assembled in one place.
 *
 * Room gives us flat tables; the screens want an expense with its payers,
 * shares and items attached. [Ledger] is that joined view, recomputed whenever
 * any table changes, and it's cheap because a personal expense ledger is small.
 */
data class Expense(
    val entity: ExpenseEntity,
    val payers: List<PayerEntity> = emptyList(),
    val shares: List<ShareEntity> = emptyList(),
    val items: List<LineItemEntity> = emptyList(),
) {
    val id: String get() = entity.id
    val total: Money get() = Money(entity.amountMinorUnits, entity.currencyCode)

    fun amountPaidBy(participantId: String): Long =
        payers.filter { it.participantId == participantId }.sumOf { it.amountMinorUnits }

    fun amountOwedBy(participantId: String): Long =
        shares.filter { it.participantId == participantId }.sumOf { it.amountMinorUnits }

    /** Positive when this person is up on the expense: paid more than their share. */
    fun netFor(participantId: String): Long =
        amountPaidBy(participantId) - amountOwedBy(participantId)

    val involvedParticipantIds: List<String>
        get() = (payers.map { it.participantId } + shares.filter { it.amountMinorUnits != 0L }
            .map { it.participantId }).distinct()

    fun isInvolved(participantId: String) = involvedParticipantIds.contains(participantId)

    val ledgerEntry: ExpenseLedgerEntry
        get() = ExpenseLedgerEntry(
            currencyCode = entity.currencyCode,
            payers = payers.map { it.participantId to it.amountMinorUnits },
            shares = shares.map { it.participantId to it.amountMinorUnits },
        )
}

/** A whole-ledger snapshot. Everything the screens need, already joined. */
data class Ledger(
    val currentUser: ParticipantEntity? = null,
    val participants: List<ParticipantEntity> = emptyList(),
    val groups: List<GroupEntity> = emptyList(),
    val memberships: List<GroupMemberEntity> = emptyList(),
    val expenses: List<Expense> = emptyList(),
    val settlements: List<SettlementEntity> = emptyList(),
) {
    fun participant(id: String?): ParticipantEntity? =
        if (id == null) null else participants.firstOrNull { it.id == id }

    /** "You" for the signed-in person, their first name for anyone else. */
    fun displayName(id: String?): String {
        val person = participant(id) ?: return "Someone"
        return if (person.id == currentUser?.id) "You" else person.fullName
    }

    fun members(groupId: String): List<ParticipantEntity> {
        val ids = memberships.filter { it.groupId == groupId }.map { it.participantId }.toSet()
        return participants.filter { it.id in ids }
            .sortedWith(compareByDescending<ParticipantEntity> { it.id == currentUser?.id }
                .thenBy { it.fullName.lowercase() })
    }

    fun group(id: String?): GroupEntity? = if (id == null) null else groups.firstOrNull { it.id == id }

    fun expensesIn(groupId: String) = expenses.filter { it.entity.groupId == groupId }

    fun settlementsIn(groupId: String) = settlements.filter { it.groupId == groupId }

    private fun settlementEntries(list: List<SettlementEntity>) = list.map {
        SettlementLedgerEntry(it.fromParticipantId, it.toParticipantId, it.amountMinorUnits, it.currencyCode)
    }

    fun sheetFor(group: GroupEntity): BalanceSheet = BalanceEngine.balanceSheet(
        expensesIn(group.id).map { it.ledgerEntry },
        settlementEntries(settlementsIn(group.id)),
        simplify = group.simplifyDebts,
    )

    /** The user's position across everything, netted pairwise then summed. */
    fun overallSummary(): BalanceSummary {
        val me = currentUser?.id ?: return BalanceSummary()
        val sheet = BalanceEngine.balanceSheet(
            expenses.map { it.ledgerEntry },
            settlementEntries(settlements),
            simplify = false,
        )
        return BalanceSummary.from(me, sheet)
    }

    fun summaryFor(group: GroupEntity): BalanceSummary {
        val me = currentUser?.id ?: return BalanceSummary()
        return BalanceSummary.from(me, sheetFor(group))
    }

    /** Where the user stands with one friend, across groups and direct expenses. */
    fun summaryWith(friendId: String): BalanceSummary {
        val me = currentUser?.id ?: return BalanceSummary()
        val relevant = expenses.filter {
            it.isInvolved(me) && it.isInvolved(friendId)
        }
        val relevantSettlements = settlements.filter {
            (it.fromParticipantId == me && it.toParticipantId == friendId) ||
                (it.fromParticipantId == friendId && it.toParticipantId == me)
        }
        val sheet = BalanceEngine.balanceSheet(
            relevant.map { it.ledgerEntry },
            settlementEntries(relevantSettlements),
            simplify = false,
        )
        // Restrict to the edge between these two: a group expense can create
        // debts that don't involve this pair at all.
        var owedToYou = NetPosition()
        var youOwe = NetPosition()
        for (debt in sheet.debts) {
            if (debt.to == me && debt.from == friendId) {
                owedToYou = owedToYou.adding(debt.amountMinorUnits, debt.currencyCode)
            } else if (debt.from == me && debt.to == friendId) {
                youOwe = youOwe.adding(debt.amountMinorUnits, debt.currencyCode)
            }
        }
        return BalanceSummary(owedToYou, youOwe)
    }
}

/** What the home screen shows: what's coming back to you, and what isn't. */
data class BalanceSummary(
    val owedToYou: NetPosition = NetPosition(),
    val youOwe: NetPosition = NetPosition(),
) {
    val net: NetPosition
        get() {
            var result = NetPosition()
            owedToYou.byCurrency.forEach { (code, amount) -> result = result.adding(amount, code) }
            youOwe.byCurrency.forEach { (code, amount) -> result = result.adding(-amount, code) }
            return result
        }

    val isSettled: Boolean get() = net.isSettled

    /** True when more than one currency is in play, so the UI can say so. */
    val isMultiCurrency: Boolean
        get() = (owedToYou.byCurrency.keys + youOwe.byCurrency.keys)
            .count { owedToYou.amount(it) != 0L || youOwe.amount(it) != 0L } > 1

    companion object {
        fun from(userId: String, sheet: BalanceSheet): BalanceSummary {
            var owed = NetPosition()
            var owe = NetPosition()
            for (debt in sheet.debts) {
                when (userId) {
                    debt.to -> owed = owed.adding(debt.amountMinorUnits, debt.currencyCode)
                    debt.from -> owe = owe.adding(debt.amountMinorUnits, debt.currencyCode)
                }
            }
            return BalanceSummary(owed, owe)
        }
    }
}

class LedgerRepository(private val dao: LedgerDao) {

    /**
     * The one source of truth for the UI. Combining eight tables looks heavy,
     * but a personal ledger is a few hundred rows, and doing the join here keeps
     * every screen free of database code.
     */
    val ledger: Flow<Ledger> = combine(
        dao.observeParticipants(),
        dao.observeGroups(),
        dao.observeMemberships(),
        dao.observeExpenses(),
        dao.observePayers(),
        dao.observeShares(),
        dao.observeItems(),
        dao.observeSettlements(),
    ) { values ->
        @Suppress("UNCHECKED_CAST")
        val participants = values[0] as List<ParticipantEntity>
        @Suppress("UNCHECKED_CAST")
        val groups = values[1] as List<GroupEntity>
        @Suppress("UNCHECKED_CAST")
        val memberships = values[2] as List<GroupMemberEntity>
        @Suppress("UNCHECKED_CAST")
        val expenses = values[3] as List<ExpenseEntity>
        @Suppress("UNCHECKED_CAST")
        val payers = values[4] as List<PayerEntity>
        @Suppress("UNCHECKED_CAST")
        val shares = values[5] as List<ShareEntity>
        @Suppress("UNCHECKED_CAST")
        val items = values[6] as List<LineItemEntity>
        @Suppress("UNCHECKED_CAST")
        val settlements = values[7] as List<SettlementEntity>

        val payersByExpense = payers.groupBy { it.expenseId }
        val sharesByExpense = shares.groupBy { it.expenseId }
        val itemsByExpense = items.groupBy { it.expenseId }

        Ledger(
            currentUser = participants.firstOrNull { it.isCurrentUser },
            participants = participants,
            groups = groups,
            memberships = memberships,
            expenses = expenses.map { entity ->
                Expense(
                    entity,
                    payersByExpense[entity.id].orEmpty(),
                    sharesByExpense[entity.id].orEmpty(),
                    itemsByExpense[entity.id].orEmpty().sortedBy { it.sortOrder },
                )
            },
            settlements = settlements,
        )
    }

    val activity: Flow<List<ActivityEntity>> = dao.observeActivity()
    val rules: Flow<List<RecurringRuleEntity>> = dao.observeRules()
    val templates: Flow<List<SplitTemplateEntity>> = dao.observeTemplates()

    val groupCount: Flow<Int> = dao.observeGroups().map { it.size }

    /** Creates the signed-in person's record on first launch. */
    suspend fun ensureCurrentUser(defaultName: String): ParticipantEntity {
        dao.currentUser()?.let { return it }
        val me = ParticipantEntity(name = defaultName, isCurrentUser = true, colorIndex = 0)
        dao.upsertParticipant(me)
        return me
    }

    suspend fun saveParticipant(participant: ParticipantEntity) =
        dao.upsertParticipant(participant.copy(updatedAt = System.currentTimeMillis()))

    suspend fun saveGroup(group: GroupEntity, memberIds: List<String>) {
        dao.upsertGroup(group.copy(updatedAt = System.currentTimeMillis()))
        dao.clearMembers(group.id)
        dao.addMembers(memberIds.distinct().map { GroupMemberEntity(group.id, it) })
    }

    suspend fun deleteGroup(id: String) {
        // Tombstones for the contents as well as the group: a friend's phone
        // that was offline needs to be told about each row it already has.
        recordTombstone("group", id, id)
        for (expense in dao.allExpenses().filter { it.groupId == id }) {
            recordTombstone("expense", expense.id, id)
        }
        for (settlement in dao.allSettlements().filter { it.groupId == id }) {
            recordTombstone("settlement", settlement.id, id)
        }
        dao.deleteGroup(id)
    }

    suspend fun saveExpense(
        expense: ExpenseEntity,
        payers: List<Pair<String, Long>>,
        shares: List<Triple<String, Long, Double>>,
        items: List<LineItemEntity>,
    ) {
        dao.saveExpense(
            expense.copy(updatedAt = System.currentTimeMillis()),
            payers.filter { it.second != 0L }
                .map { PayerEntity(expenseId = expense.id, participantId = it.first, amountMinorUnits = it.second) },
            shares.map {
                ShareEntity(
                    expenseId = expense.id,
                    participantId = it.first,
                    amountMinorUnits = it.second,
                    weight = it.third,
                )
            },
            items.map { it.copy(expenseId = expense.id) },
        )
    }

    suspend fun deleteExpense(id: String) {
        recordTombstone("expense", id, dao.expense(id)?.groupId)
        dao.deleteExpense(id)
    }

    suspend fun recordSettlement(settlement: SettlementEntity) = dao.upsertSettlement(settlement)

    suspend fun deleteSettlement(id: String) {
        recordTombstone("settlement", id, dao.allSettlements().firstOrNull { it.id == id }?.groupId)
        dao.deleteSettlement(id)
    }

    suspend fun log(
        kind: String,
        headline: String,
        detail: String = "",
        groupId: String? = null,
        groupName: String = "",
        expenseId: String? = null,
        settlementId: String? = null,
    ) = dao.insertActivity(
        ActivityEntity(
            kind = kind,
            headline = headline,
            detail = detail,
            groupId = groupId,
            groupName = groupName,
            expenseId = expenseId,
            settlementId = settlementId,
        )
    )

    suspend fun clearActivity() = dao.clearActivity()

    suspend fun eraseEverything(defaultName: String) {
        dao.eraseEverything()
        ensureCurrentUser(defaultName)
    }

    suspend fun saveTemplate(template: SplitTemplateEntity) = dao.upsertTemplate(template)
    suspend fun deleteTemplate(id: String) = dao.deleteTemplate(id)
    suspend fun saveRule(rule: RecurringRuleEntity) = dao.upsertRule(rule)
    suspend fun deleteRule(id: String) = dao.deleteRule(id)
    suspend fun activeRules() = dao.activeRules()

    /** Raw access for the interchange importer/exporter, which needs whole tables. */
    suspend fun snapshotForExport(): Ledger {
        val participants = dao.allParticipants()
        val payersByExpense = dao.allPayers().groupBy { it.expenseId }
        val sharesByExpense = dao.allShares().groupBy { it.expenseId }
        val expenses = dao.allExpenses().map { entity ->
            Expense(
                entity,
                payersByExpense[entity.id].orEmpty(),
                sharesByExpense[entity.id].orEmpty(),
                dao.items(entity.id),
            )
        }
        return Ledger(
            currentUser = participants.firstOrNull { it.isCurrentUser },
            participants = participants,
            groups = dao.allGroups(),
            memberships = dao.allMemberships(),
            expenses = expenses,
            settlements = dao.allSettlements(),
        )
    }

    internal val rawDao: LedgerDao get() = dao

    /**
     * Takes a group back off the server for this device only. Everyone else
     * keeps their copy, and this phone keeps its own: nothing is deleted, the
     * group simply stops travelling.
     */
    suspend fun stopSharing(groupId: String) {
        val group = dao.group(groupId) ?: return
        dao.upsertGroup(group.copy(isShared = false, syncedFingerprint = ""))
    }

    /**
     * Notes that something was deleted so sync can tell a friend's phone about
     * it. Local-only rows are skipped: nothing on the server ever knew about
     * them, so there is nothing to tell.
     */
    suspend fun recordTombstone(entity: String, entityId: String, groupId: String?) {
        if (groupId == null) return
        val group = dao.group(groupId) ?: return
        if (!group.isShared) return
        dao.insertTombstone(TombstoneEntity(entity = entity, entityId = entityId, groupId = groupId))
    }

    /**
     * The two-person group that stands for a friendship, creating it if needed.
     *
     * A friendship has to have a group behind it because sync only carries
     * groups: without one, the expenses two friends share would never leave
     * either phone and the friend link would mean nothing.
     */
    suspend fun directPairGroup(friendId: String, createIfMissing: Boolean): GroupEntity? {
        val me = dao.currentUser() ?: return null
        val memberships = dao.allMemberships()
        val existing = dao.allGroups().filter { it.isDirect }.firstOrNull { group ->
            val ids = memberships.filter { it.groupId == group.id }.map { it.participantId }.toSet()
            ids == setOf(me.id, friendId)
        }
        if (existing != null || !createIfMissing) return existing

        val friend = dao.participant(friendId) ?: return null
        val group = GroupEntity(
            name = friend.fullName,
            colorIndex = friend.colorIndex,
            isDirect = true,
        )
        dao.upsertGroup(group)
        dao.addMembers(
            listOf(
                GroupMemberEntity(groupId = group.id, participantId = me.id),
                GroupMemberEntity(groupId = group.id, participantId = friendId),
            )
        )
        return group
    }
}
