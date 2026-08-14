package com.splitfree.sync

import android.content.Context
import com.splitfree.data.ExpenseEntity
import com.splitfree.data.GroupEntity
import com.splitfree.data.GroupMemberEntity
import com.splitfree.data.LedgerDao
import com.splitfree.data.LineItemEntity
import com.splitfree.data.ParticipantEntity
import com.splitfree.data.PayerEntity
import com.splitfree.data.SettlementEntity
import com.splitfree.data.ShareEntity
import com.splitfree.data.TombstoneEntity
import com.splitfree.data.newId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * Moves shared groups between this device and the server.
 *
 * The counterpart of `SyncEngine.swift`, deliberately the same shape: push what
 * changed here, pull what changed there, resolve ties by the server clock. The
 * device stays the thing you read and write, so every screen works with the
 * network off.
 *
 * Only groups with `isShared` are touched. Everything else stays on the phone.
 */
class SyncEngine(
    context: Context,
    private val dao: LedgerDao,
    private val client: SupabaseClient = SupabaseClient(context),
) {
    sealed interface Status {
        data object Unavailable : Status
        data object SignedOut : Status
        data object Idle : Status
        data object Syncing : Status
        data class Failed(val message: String) : Status
    }

    data class InvitePreview(
        val groupId: String,
        val groupName: String,
        val groupKind: String,
        val memberCount: Int,
        val claimsMemberName: String?,
        val alreadyMember: Boolean,
    )

    private val prefs = context.applicationContext
        .getSharedPreferences("splitfree.sync", Context.MODE_PRIVATE)
    private val lock = Mutex()

    private val _status = MutableStateFlow<Status>(
        if (!SupabaseConfig.isConfigured) Status.Unavailable
        else if (client.isSignedIn) Status.Idle
        else Status.SignedOut
    )
    val status: StateFlow<Status> = _status.asStateFlow()

    private val _lastSyncedAt = MutableStateFlow(prefs.getLong(KEY_LAST_SYNCED, 0L).takeIf { it > 0 })
    val lastSyncedAt: StateFlow<Long?> = _lastSyncedAt.asStateFlow()

    val isConfigured: Boolean get() = SupabaseConfig.isConfigured
    val isSignedIn: Boolean get() = client.isSignedIn
    val accountEmail: String? get() = client.email

    /** Providers the project has enabled, learned from the server on first use. */
    private val _providers = MutableStateFlow<Set<String>>(emptySet())
    val providers: StateFlow<Set<String>> = _providers.asStateFlow()

    suspend fun refreshProviders() {
        if (_providers.value.isEmpty() && SupabaseConfig.isConfigured) {
            _providers.value = client.enabledProviders()
        }
    }

    /** The server time of the last successful pull, as the server phrased it. */
    private var cursor: String?
        get() = prefs.getString(KEY_CURSOR, null)
        set(value) { prefs.edit().putString(KEY_CURSOR, value).apply() }

    // MARK: - Account

    fun refreshAccountState() {
        _status.value = when {
            !SupabaseConfig.isConfigured -> Status.Unavailable
            client.isSignedIn -> Status.Idle
            else -> Status.SignedOut
        }
    }

    suspend fun signOut() {
        client.signOut()
        cursor = null
        prefs.edit().remove(KEY_LAST_SYNCED).apply()
        _lastSyncedAt.value = null
        _status.value = Status.SignedOut

        // Signing out leaves the data where it is. Shared groups become ordinary
        // local groups rather than vanishing: deleting somebody's expense history
        // as a side effect of signing out would be indefensible.
        for (group in dao.allGroups().filter { it.isShared }) {
            dao.upsertGroup(group.copy(isShared = false, syncedFingerprint = ""))
        }
        dao.deleteAllTombstones()
    }

    // MARK: - Sign-in

    suspend fun sendEmailCode(email: String) = client.sendEmailCode(email)

    suspend fun verifyEmailCode(email: String, code: String) {
        client.verifyEmailCode(email, code)
        refreshAccountState()
    }

    /**
     * Hands a provider sign-in to a Custom Tab.
     *
     * An in-app browser tab rather than a WebView: it shares the real browser's
     * cookie jar, so somebody already signed in to Google taps once instead of
     * typing a password, and the address bar is visible, so they can see whose
     * sign-in page they are actually on.
     */
    fun openOAuth(context: Context, provider: String) {
        val intent = androidx.browser.customtabs.CustomTabsIntent.Builder().build()
        intent.launchUrl(context, android.net.Uri.parse(client.oauthUrl(provider)))
    }

    /** Finishes the round trip when the browser sends us back. */
    suspend fun completeOAuth(callback: String) {
        client.completeOAuth(callback)
        client.refreshUserDetails()
        refreshAccountState()
    }

    // MARK: - Sync

    /** Runs a full cycle. Overlapping calls collapse into the one already running. */
    suspend fun syncNow() {
        if (!SupabaseConfig.isConfigured) { _status.value = Status.Unavailable; return }
        if (!client.isSignedIn) { _status.value = Status.SignedOut; return }
        if (!lock.tryLock()) return

        _status.value = Status.Syncing
        try {
            pushTombstones()
            pushChanges()
            pull()

            val now = System.currentTimeMillis()
            prefs.edit().putLong(KEY_LAST_SYNCED, now).apply()
            _lastSyncedAt.value = now
            _status.value = Status.Idle
        } catch (error: Exception) {
            _status.value = if (error.message == SupabaseClient.SIGNED_OUT) {
                Status.SignedOut
            } else {
                Status.Failed(error.message ?: "Sync failed.")
            }
        } finally {
            lock.unlock()
        }
    }

    /**
     * Turns a local group into a shared one and uploads it, keeping every id the
     * device already uses so its expenses stay attached to the right people.
     */
    suspend fun shareGroup(groupId: String) {
        if (!client.isSignedIn) throw SupabaseException(SupabaseClient.SIGNED_OUT)
        val group = dao.group(groupId) ?: return
        val members = membersOf(group)
        val ids = idMap(group, members)

        val payload = JSONArray()
        for (person in members) {
            payload.put(
                JSONObject()
                    .put("member_id", ids.server(person.id))
                    .put("display_name", person.fullName)
                    .put("color_index", person.colorIndex)
                    .put("is_me", person.isCurrentUser)
            )
        }

        client.rpc(
            "adopt_local_group",
            JSONObject()
                .put("p_group_id", group.id)
                .put("p_name", group.name)
                .put("p_kind", group.kind)
                .put("p_color_index", group.colorIndex)
                .put("p_currency_code", group.defaultCurrencyCode)
                .put("p_simplify_debts", group.simplifyDebts)
                .put("p_members", payload)
                .put("p_is_direct", group.isDirect)
        )

        dao.upsertGroup(group.copy(isShared = true, syncedFingerprint = ""))
        // Everything inside it now needs uploading, whenever it was last edited.
        for (expense in dao.allExpenses().filter { it.groupId == group.id }) {
            dao.upsertExpense(expense.copy(syncedFingerprint = ""))
        }
        for (settlement in dao.allSettlements().filter { it.groupId == group.id }) {
            dao.upsertSettlement(settlement.copy(syncedFingerprint = ""))
        }
        syncNow()
    }

    // MARK: - Invites

    suspend fun createInviteLink(groupId: String, claimingMemberId: String?): String {
        val arguments = JSONObject().put("p_group_id", groupId)
        if (claimingMemberId != null) arguments.put("p_member_id", claimingMemberId)
        val token = client.rpc("create_invite", arguments).trim().trim('"')
        if (token.isBlank()) throw SupabaseException("The server did not return an invite.")
        // The token goes in the fragment rather than the path or the query.
        // Browsers never send a fragment to the server, so an invite opened on
        // the web leaves no copy of the token in anybody's access log.
        return "https://devesh-aggarwal.github.io/splitfree/join.html#$token"
    }

    suspend fun previewInvite(token: String): InvitePreview {
        val json = JSONObject(client.rpc("preview_invite", JSONObject().put("p_token", token)))
        return InvitePreview(
            groupId = json.optString("group_id"),
            groupName = json.optString("group_name"),
            groupKind = json.optString("group_kind", "other"),
            memberCount = json.optInt("member_count"),
            claimsMemberName = json.optString("claims_member_name").takeIf { it.isNotBlank() && it != "null" },
            alreadyMember = json.optBoolean("already_member"),
        )
    }

    suspend fun redeemInvite(token: String): String {
        val json = JSONObject(client.rpc("redeem_invite", JSONObject().put("p_token", token)))
        val groupId = json.optString("group_id")
        // The group and everything in it arrive on the next pull. Reaching for it
        // now rather than waiting for a timer is what makes joining feel like the
        // group appeared instantly.
        syncNow()
        return groupId
    }

    // MARK: - Push

    private suspend fun pushTombstones() {
        val pending = dao.pendingTombstones()
        for (tombstone in pending) {
            try {
                val arguments = JSONObject()
                    .put("p_entity", tombstone.entity)
                    .put("p_id", tombstone.entityId)
                if (tombstone.groupId != null) arguments.put("p_group_id", tombstone.groupId)
                client.rpc("mark_deleted", arguments)
                dao.updateTombstone(tombstone.copy(isPushed = true))
            } catch (error: SupabaseException) {
                // The server will not accept this tombstone and never will: the
                // row was never uploaded, or the group is gone. Retrying it on
                // every sync forever helps nobody.
                dao.updateTombstone(tombstone.copy(isPushed = true))
            }
        }
        // Keep pushed tombstones for a month, so a late edit to something you
        // deleted is recognised and ignored rather than resurrecting it.
        dao.pruneTombstones(System.currentTimeMillis() - 30L * 24 * 3600 * 1000)
    }

    private suspend fun pushChanges() {
        val groups = dao.allGroups().filter { it.isShared }
        if (groups.isEmpty()) return

        val expenses = dao.allExpenses()
        val payers = dao.allPayers().groupBy { it.expenseId }
        val shares = dao.allShares().groupBy { it.expenseId }
        val settlements = dao.allSettlements()

        val groupRows = JSONArray()
        val memberRows = JSONArray()
        val pushedGroups = mutableListOf<Pair<GroupEntity, String>>()

        for (group in groups) {
            val members = membersOf(group)
            val ids = idMap(group, members)
            val fingerprint = SyncFingerprint.forGroup(group, members) { ids.server(it.id) }
            if (fingerprint == group.syncedFingerprint) continue

            groupRows.put(
                JSONObject()
                    .put("id", group.id)
                    .put("name", group.name)
                    .put("kind", group.kind)
                    .put("color_index", group.colorIndex)
                    .put("default_currency_code", group.defaultCurrencyCode)
                    .put("simplify_debts", group.simplifyDebts)
                    .put("notes", group.notes)
                    .put("is_archived", group.isArchived)
                    .put("is_direct", group.isDirect)
            )
            // The roster travels with its group. It is small, and sending it
            // whole avoids tracking which individual member rows changed.
            for (person in members) {
                memberRows.put(
                    JSONObject()
                        .put("group_id", group.id)
                        .put("member_id", ids.server(person.id))
                        .put("display_name", person.fullName)
                        .put("color_index", person.colorIndex)
                )
            }
            pushedGroups += group to fingerprint
        }

        if (groupRows.length() > 0) client.upsert("groups", groupRows, "id")
        if (memberRows.length() > 0) client.upsert("group_members", memberRows, "group_id,member_id")
        for ((group, fingerprint) in pushedGroups) {
            dao.upsertGroup(group.copy(syncedFingerprint = fingerprint))
        }

        // Expenses
        val expenseRows = JSONArray()
        val pushedExpenses = mutableListOf<Pair<ExpenseEntity, String>>()
        for (group in groups) {
            val ids = idMap(group, membersOf(group))
            for (expense in expenses.filter { it.groupId == group.id }) {
                val items = dao.items(expense.id)
                val fingerprint = SyncFingerprint.forExpense(
                    expense,
                    payers[expense.id].orEmpty(),
                    shares[expense.id].orEmpty(),
                    items,
                ) { ids.server(it) }
                if (fingerprint == expense.syncedFingerprint) continue

                val row = expenseRow(
                    expense, group, ids,
                    payers[expense.id].orEmpty(), shares[expense.id].orEmpty(), items,
                ) ?: continue
                expenseRows.put(row)
                pushedExpenses += expense to fingerprint
            }
        }
        if (expenseRows.length() > 0) client.upsert("expenses", expenseRows, "id")
        for ((expense, fingerprint) in pushedExpenses) {
            dao.upsertExpense(expense.copy(syncedFingerprint = fingerprint))
        }

        // Settlements
        val settlementRows = JSONArray()
        val pushedSettlements = mutableListOf<Pair<SettlementEntity, String>>()
        for (group in groups) {
            val ids = idMap(group, membersOf(group))
            for (settlement in settlements.filter { it.groupId == group.id }) {
                val fingerprint = SyncFingerprint.forSettlement(settlement) { ids.server(it) }
                if (fingerprint == settlement.syncedFingerprint) continue
                if (settlement.amountMinorUnits <= 0) continue

                settlementRows.put(
                    JSONObject()
                        .put("id", settlement.id)
                        .put("group_id", group.id)
                        .put("from_member_id", ids.server(settlement.fromParticipantId))
                        .put("to_member_id", ids.server(settlement.toParticipantId))
                        .put("amount_minor_units", settlement.amountMinorUnits)
                        .put("currency_code", settlement.currencyCode)
                        .put("date", timestamp(settlement.date))
                        .put("method", settlement.method)
                        .put("notes", settlement.notes)
                        .put("base_currency_code", settlement.baseCurrencyCode)
                        .put("exchange_rate_to_base", settlement.exchangeRateToBase)
                )
                pushedSettlements += settlement to fingerprint
            }
        }
        if (settlementRows.length() > 0) client.upsert("settlements", settlementRows, "id")
        for ((settlement, fingerprint) in pushedSettlements) {
            dao.upsertSettlement(settlement.copy(syncedFingerprint = fingerprint))
        }
    }

    /**
     * Builds the row for an expense, or null if it would violate the invariant
     * the database enforces.
     *
     * Refusing to send a split that does not add up is better than letting the
     * server reject the batch: one malformed expense would otherwise stop every
     * other expense in the same push from ever landing.
     */
    private fun expenseRow(
        expense: ExpenseEntity,
        group: GroupEntity,
        ids: IdMap,
        payers: List<PayerEntity>,
        shares: List<ShareEntity>,
        items: List<LineItemEntity>,
    ): JSONObject? {
        if (expense.amountMinorUnits <= 0) return null
        if (payers.sumOf { it.amountMinorUnits } != expense.amountMinorUnits) return null
        if (shares.sumOf { it.amountMinorUnits } != expense.amountMinorUnits) return null

        val payerArray = JSONArray()
        for (payer in payers) {
            payerArray.put(
                JSONObject()
                    .put("participantId", ids.server(payer.participantId))
                    .put("amountMinorUnits", payer.amountMinorUnits)
            )
        }
        val shareArray = JSONArray()
        for (share in shares) {
            shareArray.put(
                JSONObject()
                    .put("participantId", ids.server(share.participantId))
                    .put("amountMinorUnits", share.amountMinorUnits)
                    .put("weight", share.weight)
            )
        }
        val itemArray = JSONArray()
        for (item in items) {
            itemArray.put(
                JSONObject()
                    .put("id", item.id)
                    .put("name", item.name)
                    .put("amountMinorUnits", item.amountMinorUnits)
                    .put("quantity", item.quantity)
                    .put("sortOrder", item.sortOrder)
                    .put("assignees", JSONArray(item.assignees.map { ids.server(it) }))
            )
        }

        return JSONObject()
            .put("id", expense.id)
            .put("group_id", group.id)
            .put("title", expense.title)
            .put("notes", expense.notes)
            .put("amount_minor_units", expense.amountMinorUnits)
            .put("currency_code", expense.currencyCode)
            .put("date", timestamp(expense.date))
            .put("category", expense.category)
            .put("split_method", expense.splitMethod)
            .put("tax_minor_units", expense.taxMinorUnits)
            .put("tip_minor_units", expense.tipMinorUnits)
            .put("base_currency_code", expense.baseCurrencyCode)
            .put("exchange_rate_to_base", expense.exchangeRateToBase)
            .put("payers", payerArray)
            .put("shares", shareArray)
            .put("items", itemArray)
    }

    // MARK: - Pull

    private suspend fun pull() {
        val since = cursor ?: "-infinity"
        val payload = JSONObject(client.rpc("pull_changes", JSONObject().put("since", since)))

        // Order matters: groups before members before the rows that reference
        // them, so nothing arrives pointing at something that is not there yet.
        applyGroups(payload.optJSONArray("groups"))
        applyMembers(payload.optJSONArray("members"))
        applyExpenses(payload.optJSONArray("expenses"))
        applySettlements(payload.optJSONArray("settlements"))

        payload.optString("server_time").takeIf { it.isNotBlank() }?.let { cursor = it }
    }

    private suspend fun applyGroups(rows: JSONArray?) {
        for (row in rows.objects()) {
            val id = row.optString("id")
            if (id.isBlank()) continue
            val existing = dao.group(id)

            if (!row.isNull("deleted_at")) {
                if (existing != null) dao.deleteGroup(id)
                continue
            }
            if (dao.tombstoneCount(id) > 0) continue

            if (existing != null) {
                // A local edit that has not been pushed yet wins for now; the
                // next push sends it and the server decides the final order.
                val members = membersOf(existing)
                val ids = idMap(existing, members)
                val fingerprint = SyncFingerprint.forGroup(existing, members) { ids.server(it.id) }
                if (fingerprint != existing.syncedFingerprint) continue
            }

            val updated = (existing ?: GroupEntity(id = id)).copy(
                name = row.optString("name"),
                kind = row.optString("kind", "other"),
                colorIndex = row.optInt("color_index"),
                defaultCurrencyCode = row.optString("default_currency_code", "USD"),
                simplifyDebts = row.optBoolean("simplify_debts", true),
                notes = row.optString("notes"),
                isArchived = row.optBoolean("is_archived"),
                isDirect = row.optBoolean("is_direct"),
                isShared = true,
                updatedAt = epochMillis(row.optString("updated_at")) ?: System.currentTimeMillis(),
            )
            dao.upsertGroup(updated)
            // Stamped after the roster is applied, below, so it reflects what
            // was actually stored.
        }
    }

    private suspend fun applyMembers(rows: JSONArray?) {
        val me = dao.currentUser() ?: return
        val myUserId = client.userId
        val touchedGroups = mutableSetOf<String>()

        for (row in rows.objects()) {
            val groupId = row.optString("group_id")
            val memberId = row.optString("member_id")
            if (groupId.isBlank() || memberId.isBlank()) continue
            val group = dao.group(groupId) ?: continue
            touchedGroups += groupId

            val userId = row.optString("user_id").takeIf { it.isNotBlank() && it != "null" }

            // This slot is me. Record which id the group uses for me rather than
            // making a second copy of myself.
            if (userId != null && userId == myUserId) {
                dao.upsertGroup(group.copy(myMemberId = memberId))
                dao.addMembers(listOf(GroupMemberEntity(groupId = groupId, participantId = me.id)))
                if (me.remoteUserId == null) dao.upsertParticipant(me.copy(remoteUserId = userId))
                continue
            }

            if (!row.isNull("deleted_at")) {
                dao.removeMember(groupId, memberId)
                continue
            }

            val existing = dao.participant(memberId)
            val person = (existing ?: ParticipantEntity(id = memberId)).copy(
                name = existing?.name?.takeIf { it.isNotBlank() } ?: row.optString("display_name"),
                colorIndex = existing?.colorIndex ?: row.optInt("color_index"),
                remoteUserId = userId,
            )
            dao.upsertParticipant(person)
            dao.addMembers(listOf(GroupMemberEntity(groupId = groupId, participantId = person.id)))
        }

        // Now that the roster is settled, record what the server's version of
        // each group hashes to.
        for (groupId in touchedGroups) {
            val group = dao.group(groupId) ?: continue
            val members = membersOf(group)
            val ids = idMap(group, members)
            dao.upsertGroup(
                group.copy(
                    syncedFingerprint = SyncFingerprint.forGroup(group, members) { ids.server(it.id) }
                )
            )
        }
    }

    private suspend fun applyExpenses(rows: JSONArray?) {
        val payers = dao.allPayers().groupBy { it.expenseId }
        val shares = dao.allShares().groupBy { it.expenseId }

        for (row in rows.objects()) {
            val id = row.optString("id")
            if (id.isBlank()) continue
            val existing = dao.expense(id)

            if (!row.isNull("deleted_at")) {
                if (existing != null) dao.deleteExpense(id)
                continue
            }
            if (dao.tombstoneCount(id) > 0) continue

            val groupId = row.optString("group_id")
            if (groupId.isBlank()) continue
            val group = dao.group(groupId) ?: continue
            val ids = idMap(group, membersOf(group))

            if (existing != null && existing.syncedFingerprint.isNotBlank()) {
                val fingerprint = SyncFingerprint.forExpense(
                    existing,
                    payers[id].orEmpty(),
                    shares[id].orEmpty(),
                    dao.items(id),
                ) { ids.server(it) }
                if (fingerprint != existing.syncedFingerprint) continue
            }

            val expense = (existing ?: ExpenseEntity(id = id)).copy(
                groupId = groupId,
                title = row.optString("title"),
                notes = row.optString("notes"),
                amountMinorUnits = row.optLong("amount_minor_units"),
                currencyCode = row.optString("currency_code", "USD"),
                date = epochMillis(row.optString("date")) ?: System.currentTimeMillis(),
                category = row.optString("category", "general"),
                splitMethod = row.optString("split_method", "equal"),
                taxMinorUnits = row.optLong("tax_minor_units"),
                tipMinorUnits = row.optLong("tip_minor_units"),
                baseCurrencyCode = row.optString("base_currency_code", "USD"),
                exchangeRateToBase = row.optDouble("exchange_rate_to_base", 1.0),
                updatedAt = epochMillis(row.optString("updated_at")) ?: System.currentTimeMillis(),
            )

            // Rebuilt rather than merged: a person removed from the split
            // upstream has no row to match against, and merging would leave them
            // behind with a stale share.
            val newPayers = row.optJSONArray("payers").objects().mapNotNull { entry ->
                val participantId = ids.local(entry.optString("participantId")) ?: return@mapNotNull null
                PayerEntity(
                    id = newId(),
                    expenseId = id,
                    participantId = participantId,
                    amountMinorUnits = entry.optLong("amountMinorUnits"),
                )
            }
            val newShares = row.optJSONArray("shares").objects().mapNotNull { entry ->
                val participantId = ids.local(entry.optString("participantId")) ?: return@mapNotNull null
                ShareEntity(
                    id = newId(),
                    expenseId = id,
                    participantId = participantId,
                    amountMinorUnits = entry.optLong("amountMinorUnits"),
                    weight = entry.optDouble("weight", 0.0),
                )
            }
            val newItems = row.optJSONArray("items").objects().map { entry ->
                LineItemEntity(
                    id = entry.optString("id").ifBlank { newId() },
                    expenseId = id,
                    name = entry.optString("name"),
                    amountMinorUnits = entry.optLong("amountMinorUnits"),
                    quantity = entry.optInt("quantity", 1),
                    sortOrder = entry.optInt("sortOrder"),
                    assigneeIds = entry.optJSONArray("assignees").strings()
                        .mapNotNull { ids.local(it) }
                        .joinToString(","),
                )
            }

            val fingerprint = SyncFingerprint.forExpense(expense, newPayers, newShares, newItems) {
                ids.server(it)
            }
            dao.saveExpense(expense.copy(syncedFingerprint = fingerprint), newPayers, newShares, newItems)
        }
    }

    private suspend fun applySettlements(rows: JSONArray?) {
        for (row in rows.objects()) {
            val id = row.optString("id")
            if (id.isBlank()) continue
            val existing = dao.allSettlements().firstOrNull { it.id == id }

            if (!row.isNull("deleted_at")) {
                if (existing != null) dao.deleteSettlement(id)
                continue
            }
            if (dao.tombstoneCount(id) > 0) continue

            val groupId = row.optString("group_id")
            if (groupId.isBlank()) continue
            val group = dao.group(groupId) ?: continue
            val ids = idMap(group, membersOf(group))
            val from = ids.local(row.optString("from_member_id")) ?: continue
            val to = ids.local(row.optString("to_member_id")) ?: continue

            if (existing != null && existing.syncedFingerprint.isNotBlank()) {
                val fingerprint = SyncFingerprint.forSettlement(existing) { ids.server(it) }
                if (fingerprint != existing.syncedFingerprint) continue
            }

            val settlement = (existing ?: SettlementEntity(
                id = id,
                fromParticipantId = from,
                toParticipantId = to,
                amountMinorUnits = 0,
            )).copy(
                groupId = groupId,
                fromParticipantId = from,
                toParticipantId = to,
                amountMinorUnits = row.optLong("amount_minor_units"),
                currencyCode = row.optString("currency_code", "USD"),
                date = epochMillis(row.optString("date")) ?: System.currentTimeMillis(),
                method = row.optString("method", "cash"),
                notes = row.optString("notes"),
                baseCurrencyCode = row.optString("base_currency_code", "USD"),
                exchangeRateToBase = row.optDouble("exchange_rate_to_base", 1.0),
                updatedAt = epochMillis(row.optString("updated_at")) ?: System.currentTimeMillis(),
            )
            dao.upsertSettlement(
                settlement.copy(
                    syncedFingerprint = SyncFingerprint.forSettlement(settlement) { ids.server(it) }
                )
            )
        }
    }

    // MARK: - Identity

    private suspend fun membersOf(group: GroupEntity): List<ParticipantEntity> {
        val ids = dao.memberIds(group.id).toSet()
        return dao.allParticipants().filter { it.id in ids }
    }

    /**
     * Translation between local participant ids and the ids the server uses for
     * the same people in one group.
     *
     * These are almost always identical. They diverge for exactly one person:
     * you, in a group somebody else created, where the slot already existed and
     * kept the id they gave it.
     *
     * Resolved once per group into plain maps rather than looked up per row.
     * Besides sparing the database a query per allocation, it is what lets the
     * fingerprint functions stay ordinary non-suspending code.
     */
    private class IdMap(val toServer: Map<String, String>, val toLocal: Map<String, String>) {
        fun server(localId: String): String = toServer[localId] ?: localId
        fun local(serverId: String): String? = toLocal[serverId]
    }

    private suspend fun idMap(group: GroupEntity, members: List<ParticipantEntity>): IdMap {
        val me = dao.currentUser()
        val toServer = mutableMapOf<String, String>()
        val toLocal = mutableMapOf<String, String>()
        for (person in members) {
            val serverId = if (person.isCurrentUser) group.myMemberId ?: person.id else person.id
            toServer[person.id] = serverId
            toLocal[serverId] = person.id
        }
        // The slot may have arrived before the roster did.
        val mine = group.myMemberId
        if (me != null && mine != null) {
            toServer[me.id] = mine
            toLocal[mine] = me.id
        }
        return IdMap(toServer, toLocal)
    }

    // MARK: - Helpers

    companion object {
        private const val KEY_CURSOR = "cursor"
        private const val KEY_LAST_SYNCED = "lastSyncedAt"

        /** Pulls the token out of a link, whichever form it arrived in. */
        fun inviteToken(url: String): String? {
            val fragment = url.substringAfter('#', "").takeIf { it.isNotBlank() } ?: return null
            if (url.startsWith("splitfree://join")) return fragment
            if (url.contains("/splitfree/join")) return fragment
            return null
        }

        private val formatter: SimpleDateFormat
            get() = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }

        fun timestamp(epochMillis: Long): String = formatter.format(java.util.Date(epochMillis))

        /**
         * Parses a Postgres `timestamptz`, which arrives with up to six
         * fractional digits and an offset written as `+00:00`. Neither is
         * something `SimpleDateFormat` handles without help.
         */
        fun epochMillis(value: String?): Long? {
            if (value.isNullOrBlank() || value == "null") return null
            return runCatching {
                var text = value.trim()
                // Normalise the offset to something parseable, then the fraction
                // to exactly three digits.
                text = Regex("([+-])(\\d{2}):(\\d{2})$").replace(text) { "${it.groupValues[1]}${it.groupValues[2]}${it.groupValues[3]}" }
                if (text.endsWith("Z")) text = text.dropLast(1) + "+0000"
                text = Regex("\\.(\\d+)").replace(text) { "." + it.groupValues[1].padEnd(3, '0').take(3) }
                val pattern = if (text.contains('.')) "yyyy-MM-dd'T'HH:mm:ss.SSSZ" else "yyyy-MM-dd'T'HH:mm:ssZ"
                SimpleDateFormat(pattern, Locale.ROOT).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                    isLenient = false
                }.parse(text)?.time
            }.getOrNull()
        }
    }
}

// MARK: - JSON conveniences

private fun JSONArray?.objects(): List<JSONObject> {
    if (this == null) return emptyList()
    return (0 until length()).mapNotNull { optJSONObject(it) }
}

private fun JSONArray?.strings(): List<String> {
    if (this == null) return emptyList()
    return (0 until length()).map { optString(it) }.filter { it.isNotBlank() }
}
