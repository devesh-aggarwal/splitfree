package com.splitfree.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.splitfree.GroupKind
import com.splitfree.PaymentMethod
import com.splitfree.core.ExpenseCategory
import com.splitfree.core.SplitCalculator
import com.splitfree.core.SplitMethod
import com.splitfree.data.ExpenseEntity
import com.splitfree.data.GroupEntity
import com.splitfree.data.Ledger
import com.splitfree.data.LedgerRepository
import com.splitfree.data.LineItemEntity
import com.splitfree.data.ParticipantEntity
import com.splitfree.data.Settings
import com.splitfree.data.SettingsStore
import com.splitfree.data.SettlementEntity
import com.splitfree.data.newId
import com.splitfree.interchange.ImportSummary
import com.splitfree.interchange.LedgerExchange
import com.splitfree.interchange.LedgerFile
import com.splitfree.sync.SyncEngine
import com.splitfree.ui.theme.AppearanceSetting
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * One view model for the whole app.
 *
 * The screens are all views onto the same ledger, and splitting this into six
 * view models would mean six subscriptions to the same tables. Everything here
 * is either observed state or a suspend write.
 */
class LedgerViewModel(
    private val repository: LedgerRepository,
    private val settingsStore: SettingsStore,
    val sync: SyncEngine,
    private val appContext: android.content.Context,
) : ViewModel() {

    val ledger: StateFlow<Ledger> =
        repository.ledger.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), Ledger())

    val settings: StateFlow<Settings> =
        settingsStore.settings.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), Settings())

    val activity = repository.activity
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    init {
        viewModelScope.launch {
            repository.ensureCurrentUser("You")
            sync.syncNow()
        }
    }

    // MARK: - Sync

    fun syncNow() = viewModelScope.launch { sync.syncNow() }

    /** Finishes an email or browser sign-in when its link comes back to the app. */
    fun completeSignIn(callback: String) = viewModelScope.launch {
        runCatching { sync.completeOAuth(callback) }
        sync.syncNow()
    }

    fun signOut() = viewModelScope.launch { sync.signOut() }

    fun stopSharing(groupId: String) = viewModelScope.launch {
        repository.stopSharing(groupId)
    }

    /**
     * Connects with somebody by link, reusing the friend if they are already in
     * the list so an invite does not create a second copy of someone you owe.
     */
    suspend fun inviteFriend(name: String): String {
        val existing = ledger.value.participants.firstOrNull {
            it.id != ledger.value.currentUser?.id && it.fullName.equals(name, ignoreCase = true)
        }
        val friendId = existing?.id ?: ParticipantEntity(
            name = name,
            colorIndex = kotlin.math.abs(name.hashCode()) % 12,
        ).also { repository.saveParticipant(it) }.id
        val group = repository.directPairGroup(friendId, createIfMissing = true)
            ?: throw IllegalStateException("Couldn't set up that friendship.")
        if (!group.isShared) sync.shareGroup(group.id)
        // The invite reserves their slot, so anything already recorded against
        // their name becomes theirs when they accept.
        return sync.createInviteLink(group.id, friendId)
    }

    /** Opens a link in the browser. */
    fun openUrl(url: String) {
        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { appContext.startActivity(intent) }
    }

    /** Hands a link to the system share sheet. */
    fun shareText(text: String) {
        val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(android.content.Intent.EXTRA_TEXT, text)
            addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        appContext.startActivity(
            android.content.Intent.createChooser(intent, "Send the link")
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    // MARK: - Settings

    fun setBaseCurrency(code: String) = viewModelScope.launch {
        settingsStore.setBaseCurrency(code)
        settingsStore.noteCurrencyUsed(code)
    }

    fun setAppearance(value: AppearanceSetting) = viewModelScope.launch {
        settingsStore.setAppearance(value)
    }

    fun setSimplifyByDefault(value: Boolean) = viewModelScope.launch {
        settingsStore.setSimplifyByDefault(value)
    }

    fun setConvertToBase(value: Boolean) = viewModelScope.launch {
        settingsStore.setConvertToBase(value)
    }

    fun completeOnboarding(name: String, currency: String) = viewModelScope.launch {
        val me = repository.ensureCurrentUser(name)
        repository.saveParticipant(me.copy(name = name.ifBlank { "You" }))
        settingsStore.setBaseCurrency(currency)
        settingsStore.setOnboarded(true)
    }

    // MARK: - People

    fun addFriend(name: String, onCreated: (ParticipantEntity) -> Unit = {}) = viewModelScope.launch {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return@launch
        val person = ParticipantEntity(
            name = trimmed,
            colorIndex = kotlin.math.abs(trimmed.hashCode()) % 12,
        )
        repository.saveParticipant(person)
        onCreated(person)
    }

    fun saveParticipant(participant: ParticipantEntity) = viewModelScope.launch {
        repository.saveParticipant(participant)
    }

    fun archiveFriend(participant: ParticipantEntity) = viewModelScope.launch {
        repository.saveParticipant(participant.copy(isArchived = true))
    }

    // MARK: - Groups

    fun saveGroup(
        existing: GroupEntity?,
        name: String,
        kind: GroupKind,
        colorIndex: Int,
        currencyCode: String,
        simplifyDebts: Boolean,
        memberIds: List<String>,
    ) = viewModelScope.launch {
        val me = repository.ensureCurrentUser("You")
        val group = (existing ?: GroupEntity(sortOrder = -System.currentTimeMillis())).copy(
            name = name.trim(),
            kind = kind.wireName,
            colorIndex = colorIndex,
            defaultCurrencyCode = currencyCode,
            simplifyDebts = simplifyDebts,
        )
        repository.saveGroup(group, (memberIds + me.id).distinct())
        if (existing == null) {
            repository.log(
                kind = "groupCreated",
                headline = "You created the group ${group.displayName}",
                detail = "${memberIds.size + 1} members",
                groupId = group.id,
                groupName = group.name,
            )
        }
    }

    fun setGroupSimplify(group: GroupEntity, value: Boolean) = viewModelScope.launch {
        repository.saveGroup(group.copy(simplifyDebts = value), currentMemberIds(group.id))
    }

    fun setGroupArchived(group: GroupEntity, value: Boolean) = viewModelScope.launch {
        repository.saveGroup(group.copy(isArchived = value), currentMemberIds(group.id))
    }

    fun setGroupPinned(group: GroupEntity, value: Boolean) = viewModelScope.launch {
        repository.saveGroup(group.copy(isPinned = value), currentMemberIds(group.id))
    }

    fun setGroupNotes(group: GroupEntity, notes: String) = viewModelScope.launch {
        repository.saveGroup(group.copy(notes = notes), currentMemberIds(group.id))
    }

    fun deleteGroup(group: GroupEntity) = viewModelScope.launch {
        repository.deleteGroup(group.id)
        repository.log("groupArchived", "Deleted the group ${group.displayName}")
    }

    private fun currentMemberIds(groupId: String): List<String> =
        ledger.value.memberships.filter { it.groupId == groupId }.map { it.participantId }

    // MARK: - Expenses

    /**
     * Saves an expense. The allocations are computed by [SplitCalculator], so
     * the stored shares always sum exactly to the total.
     */
    fun saveExpense(
        existing: ExpenseEntity?,
        title: String,
        amountMinorUnits: Long,
        currencyCode: String,
        dateMillis: Long,
        category: ExpenseCategory,
        groupId: String?,
        splitMethod: SplitMethod,
        payerIds: Map<String, Long>,
        entries: List<SplitCalculator.Entry>,
        items: List<LineItemEntity> = emptyList(),
        taxMinorUnits: Long = 0,
        tipMinorUnits: Long = 0,
        notes: String = "",
    ) = viewModelScope.launch {
        // An expense with no group, shared with exactly one person you are
        // linked to, belongs in that friendship. Sync only carries groups, so
        // without this the expense stays on this phone.
        val resolvedGroupId = groupId ?: run {
            val me = ledger.value.currentUser?.id
            val others = entries.map { it.participantId }.toSet() - setOfNotNull(me)
            others.singleOrNull()?.let { repository.directPairGroup(it, createIfMissing = false)?.id }
        }

        val allocations = SplitCalculator.resolve(
            method = splitMethod,
            total = amountMinorUnits,
            entries = entries,
            items = items.map {
                SplitCalculator.ItemAssignment(it.lineTotalMinorUnits, it.assignees)
            },
            taxMinorUnits = taxMinorUnits,
            tipMinorUnits = tipMinorUnits,
        )

        val base = settings.value.baseCurrencyCode
        val expense = (existing ?: ExpenseEntity()).copy(
            title = title.trim(),
            notes = notes,
            amountMinorUnits = amountMinorUnits,
            currencyCode = currencyCode,
            date = dateMillis,
            category = category.wireName,
            splitMethod = splitMethod.wireName,
            groupId = resolvedGroupId,
            taxMinorUnits = taxMinorUnits,
            tipMinorUnits = tipMinorUnits,
            baseCurrencyCode = base,
        )

        repository.saveExpense(
            expense,
            payerIds.map { it.key to it.value },
            allocations.map { Triple(it.participantId, it.amountMinorUnits, it.weight) },
            items,
        )
        settingsStore.noteCurrencyUsed(currencyCode)

        val me = ledger.value.currentUser?.id
        val net = if (me == null) 0L else {
            (payerIds[me] ?: 0L) - (allocations.firstOrNull { it.participantId == me }?.amountMinorUnits ?: 0L)
        }
        val impact = when {
            net > 0 -> "You get back ${com.splitfree.core.Money(net, currencyCode).formatted()}"
            net < 0 -> "You owe ${com.splitfree.core.Money(-net, currencyCode).formatted()}"
            else -> "You're settled on this"
        }
        repository.log(
            kind = if (existing == null) "expenseAdded" else "expenseEdited",
            headline = if (existing == null) "You added ${expense.displayTitle}"
            else "You updated ${expense.displayTitle}",
            detail = impact,
            groupId = resolvedGroupId,
            groupName = ledger.value.group(resolvedGroupId)?.name ?: "",
            expenseId = expense.id,
        )
    }

    fun deleteExpense(expense: ExpenseEntity) = viewModelScope.launch {
        repository.deleteExpense(expense.id)
        repository.log(
            "expenseDeleted",
            "You deleted ${expense.displayTitle}",
            com.splitfree.core.Money(expense.amountMinorUnits, expense.currencyCode).formatted(),
            groupId = expense.groupId,
        )
    }

    // MARK: - Settling

    fun recordSettlement(
        fromId: String,
        toId: String,
        amountMinorUnits: Long,
        currencyCode: String,
        method: PaymentMethod,
        groupId: String?,
        dateMillis: Long = System.currentTimeMillis(),
        notes: String = "",
    ) = viewModelScope.launch {
        val settlement = SettlementEntity(
            groupId = groupId,
            fromParticipantId = fromId,
            toParticipantId = toId,
            amountMinorUnits = amountMinorUnits,
            currencyCode = currencyCode,
            date = dateMillis,
            method = method.wireName,
            notes = notes,
            baseCurrencyCode = settings.value.baseCurrencyCode,
        )
        repository.recordSettlement(settlement)
        val snapshot = ledger.value
        repository.log(
            kind = "settlementAdded",
            headline = "${snapshot.displayName(fromId)} paid ${snapshot.displayName(toId)} " +
                com.splitfree.core.Money(amountMinorUnits, currencyCode).formatted(),
            detail = method.label,
            groupId = groupId,
            groupName = snapshot.group(groupId)?.name ?: "",
            settlementId = settlement.id,
        )
    }

    fun deleteSettlement(settlement: SettlementEntity) = viewModelScope.launch {
        repository.deleteSettlement(settlement.id)
        repository.log("settlementDeleted", "You undid a payment", groupId = settlement.groupId)
    }

    // MARK: - Interchange

    /** Serialises the ledger, or one group of it, to a `.splitfree` file. */
    suspend fun exportLedger(groupId: String? = null): String =
        LedgerExchange.export(repository.snapshotForExport(), groupId).encode()

    /** Reads a `.splitfree` file and merges it in. */
    suspend fun importLedger(text: String): Result<ImportSummary> =
        LedgerFile.decode(text).mapCatching { file ->
            val summary = LedgerExchange.import(file, repository.rawDao)
            if (summary.changedAnything) {
                repository.log(
                    "transactionsImported",
                    "Imported a ledger from ${file.exportedBy?.name ?: "a file"}",
                    "${summary.totalAdded} added, ${summary.totalUpdated} updated",
                )
            }
            summary
        }

    fun clearActivity() = viewModelScope.launch { repository.clearActivity() }

    fun eraseEverything() = viewModelScope.launch { repository.eraseEverything("You") }

    class Factory(
        private val repository: LedgerRepository,
        private val settingsStore: SettingsStore,
        private val sync: SyncEngine,
        private val appContext: android.content.Context,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            LedgerViewModel(repository, settingsStore, sync, appContext) as T
    }
}
