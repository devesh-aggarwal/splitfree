package com.splitfree.interchange

import com.splitfree.data.ExpenseEntity
import com.splitfree.data.GroupEntity
import com.splitfree.data.GroupMemberEntity
import com.splitfree.data.Ledger
import com.splitfree.data.LedgerDao
import com.splitfree.data.LineItemEntity
import com.splitfree.data.ParticipantEntity
import com.splitfree.data.PayerEntity
import com.splitfree.data.SettlementEntity
import com.splitfree.data.ShareEntity
import java.time.Instant
import java.time.format.DateTimeFormatter

/**
 * Reads and writes the `.splitfree` file, and merges an imported ledger into
 * the local one.
 *
 * This is the interoperability seam with the iOS app. Both platforms write the
 * same JSON, keyed by the same UUIDs, so a group exported from an iPhone imports
 * here with its history and balances intact.
 *
 * Merging is last-write-wins per record on `updatedAt`. Two people editing the
 * same expense offline resolve to the later edit, not to a combination of both.
 * New records on either side always survive, which is the common case: each
 * person adds their own expenses and the files merge cleanly.
 */
object LedgerExchange {

    private fun millisToIso(millis: Long): String =
        DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(millis))

    private fun isoToMillis(text: String): Long =
        runCatching { Instant.parse(text).toEpochMilli() }.getOrDefault(0L)

    // MARK: - Export

    /**
     * Exports the whole ledger, or just one group and the people in it when
     * [groupId] is given. Sharing one trip shouldn't hand over every other group
     * you're in.
     */
    fun export(ledger: Ledger, groupId: String? = null): LedgerFile {
        val groups = ledger.groups.filter { groupId == null || it.id == groupId }
        val groupIds = groups.map { it.id }.toSet()

        val expenses = ledger.expenses.filter {
            groupId == null || it.entity.groupId in groupIds
        }
        val settlements = ledger.settlements.filter {
            groupId == null || it.groupId in groupIds
        }

        // Only the people who actually appear, so a shared trip doesn't leak
        // your whole contact list.
        val referenced: Set<String> = if (groupId == null) {
            ledger.participants.map { it.id }.toSet()
        } else {
            buildSet {
                addAll(ledger.memberships.filter { it.groupId in groupIds }.map { it.participantId })
                expenses.forEach { addAll(it.involvedParticipantIds) }
                settlements.forEach { add(it.fromParticipantId); add(it.toParticipantId) }
            }
        }

        return LedgerFile(
            exportedAt = millisToIso(System.currentTimeMillis()),
            exportedBy = ledger.currentUser?.let { ExportedBy(it.id, it.fullName) },
            participants = ledger.participants.filter { it.id in referenced }.map {
                ParticipantDTO(
                    id = it.id,
                    name = it.fullName,
                    email = it.email,
                    phone = it.phone,
                    colorIndex = it.colorIndex,
                    updatedAt = millisToIso(it.updatedAt),
                    venmoHandle = it.venmoHandle,
                    paypalHandle = it.paypalHandle,
                    cashAppHandle = it.cashAppHandle,
                    upiHandle = it.upiHandle,
                )
            },
            groups = groups.map { group ->
                GroupDTO(
                    id = group.id,
                    name = group.name,
                    kind = group.kind,
                    colorIndex = group.colorIndex,
                    defaultCurrencyCode = group.defaultCurrencyCode,
                    simplifyDebts = group.simplifyDebts,
                    notes = group.notes,
                    isArchived = group.isArchived,
                    createdAt = millisToIso(group.createdAt),
                    updatedAt = millisToIso(group.updatedAt),
                    memberIds = ledger.memberships.filter { it.groupId == group.id }
                        .map { it.participantId },
                )
            },
            expenses = expenses.map { expense ->
                val e = expense.entity
                ExpenseDTO(
                    id = e.id,
                    groupId = e.groupId,
                    title = e.title,
                    notes = e.notes,
                    amountMinorUnits = e.amountMinorUnits,
                    currencyCode = e.currencyCode,
                    date = millisToIso(e.date),
                    createdAt = millisToIso(e.createdAt),
                    updatedAt = millisToIso(e.updatedAt),
                    category = e.category,
                    splitMethod = e.splitMethod,
                    taxMinorUnits = e.taxMinorUnits,
                    tipMinorUnits = e.tipMinorUnits,
                    baseCurrencyCode = e.baseCurrencyCode,
                    exchangeRateToBase = e.exchangeRateToBase,
                    payers = expense.payers.map { PayerDTO(it.participantId, it.amountMinorUnits) },
                    shares = expense.shares.map {
                        ShareDTO(it.participantId, it.amountMinorUnits, it.weight)
                    },
                    items = expense.items.map {
                        LineItemDTO(it.id, it.name, it.amountMinorUnits, it.quantity, it.sortOrder, it.assignees)
                    },
                )
            },
            settlements = settlements.map {
                SettlementDTO(
                    id = it.id,
                    groupId = it.groupId,
                    fromParticipantId = it.fromParticipantId,
                    toParticipantId = it.toParticipantId,
                    amountMinorUnits = it.amountMinorUnits,
                    currencyCode = it.currencyCode,
                    date = millisToIso(it.date),
                    createdAt = millisToIso(it.createdAt),
                    updatedAt = millisToIso(it.updatedAt),
                    method = it.method,
                    notes = it.notes,
                    baseCurrencyCode = it.baseCurrencyCode,
                    exchangeRateToBase = it.exchangeRateToBase,
                )
            },
        )
    }

    // MARK: - Import

    /**
     * Merges [file] into the local database.
     *
     * The incoming person's own participant record is never allowed to overwrite
     * ours: two devices each think of themselves as "the current user", and
     * importing must not produce a ledger with two of them.
     */
    suspend fun import(file: LedgerFile, dao: LedgerDao): ImportSummary {
        var summary = ImportSummary()

        val localParticipants = dao.allParticipants().associateBy { it.id }
        val localCurrentUserId = dao.currentUser()?.id

        for (dto in file.participants) {
            val existing = localParticipants[dto.id]
            val incomingUpdatedAt = isoToMillis(dto.updatedAt)
            if (existing != null && existing.updatedAt >= incomingUpdatedAt) continue

            val merged = ParticipantEntity(
                id = dto.id,
                name = dto.name,
                email = dto.email,
                phone = dto.phone,
                colorIndex = dto.colorIndex,
                // Whoever is "you" on this device stays "you".
                isCurrentUser = dto.id == localCurrentUserId,
                isArchived = existing?.isArchived ?: false,
                avatarPath = existing?.avatarPath,
                venmoHandle = dto.venmoHandle,
                paypalHandle = dto.paypalHandle,
                cashAppHandle = dto.cashAppHandle,
                upiHandle = dto.upiHandle,
                createdAt = existing?.createdAt ?: incomingUpdatedAt,
                updatedAt = incomingUpdatedAt,
            )
            dao.upsertParticipant(merged)
            summary = if (existing == null) {
                summary.copy(participantsAdded = summary.participantsAdded + 1)
            } else {
                summary.copy(participantsUpdated = summary.participantsUpdated + 1)
            }
        }

        val localGroups = dao.allGroups().associateBy { it.id }
        for (dto in file.groups) {
            val existing = localGroups[dto.id]
            val incomingUpdatedAt = isoToMillis(dto.updatedAt)
            if (existing == null || existing.updatedAt < incomingUpdatedAt) {
                dao.upsertGroup(
                    GroupEntity(
                        id = dto.id,
                        name = dto.name,
                        kind = dto.kind,
                        colorIndex = dto.colorIndex,
                        defaultCurrencyCode = dto.defaultCurrencyCode,
                        simplifyDebts = dto.simplifyDebts,
                        notes = dto.notes,
                        isArchived = dto.isArchived,
                        isPinned = existing?.isPinned ?: false,
                        sortOrder = existing?.sortOrder ?: 0,
                        coverPath = existing?.coverPath,
                        createdAt = isoToMillis(dto.createdAt),
                        updatedAt = incomingUpdatedAt,
                    )
                )
                summary = if (existing == null) {
                    summary.copy(groupsAdded = summary.groupsAdded + 1)
                } else {
                    summary.copy(groupsUpdated = summary.groupsUpdated + 1)
                }
            }
            // Membership is a union: someone added on either device stays in.
            val currentMembers = dao.memberIds(dto.id).toSet()
            val additions = dto.memberIds.filter { it !in currentMembers }
            if (additions.isNotEmpty()) {
                dao.addMembers(additions.map { GroupMemberEntity(dto.id, it) })
            }
        }

        val localExpenses = dao.allExpenses().associateBy { it.id }
        for (dto in file.expenses) {
            // A file whose shares don't add up would corrupt every balance that
            // touches it. Skip it and say so, rather than importing bad math.
            if (!dto.isBalanced) {
                summary = summary.copy(skippedUnbalanced = summary.skippedUnbalanced + 1)
                continue
            }
            val existing = localExpenses[dto.id]
            val incomingUpdatedAt = isoToMillis(dto.updatedAt)
            if (existing != null && existing.updatedAt >= incomingUpdatedAt) continue

            dao.saveExpense(
                ExpenseEntity(
                    id = dto.id,
                    groupId = dto.groupId,
                    title = dto.title,
                    notes = dto.notes,
                    amountMinorUnits = dto.amountMinorUnits,
                    currencyCode = dto.currencyCode,
                    date = isoToMillis(dto.date),
                    category = dto.category,
                    splitMethod = dto.splitMethod,
                    taxMinorUnits = dto.taxMinorUnits,
                    tipMinorUnits = dto.tipMinorUnits,
                    baseCurrencyCode = dto.baseCurrencyCode,
                    exchangeRateToBase = dto.exchangeRateToBase,
                    receiptPath = existing?.receiptPath,
                    receiptText = existing?.receiptText ?: "",
                    createdAt = isoToMillis(dto.createdAt),
                    updatedAt = incomingUpdatedAt,
                ),
                dto.payers.map {
                    PayerEntity(expenseId = dto.id, participantId = it.participantId, amountMinorUnits = it.amountMinorUnits)
                },
                dto.shares.map {
                    ShareEntity(
                        expenseId = dto.id,
                        participantId = it.participantId,
                        amountMinorUnits = it.amountMinorUnits,
                        weight = it.weight,
                    )
                },
                dto.items.map {
                    LineItemEntity(
                        id = it.id,
                        expenseId = dto.id,
                        name = it.name,
                        amountMinorUnits = it.amountMinorUnits,
                        quantity = it.quantity,
                        sortOrder = it.sortOrder,
                        assigneeIds = it.assigneeIds.joinToString(","),
                    )
                },
            )
            summary = if (existing == null) {
                summary.copy(expensesAdded = summary.expensesAdded + 1)
            } else {
                summary.copy(expensesUpdated = summary.expensesUpdated + 1)
            }
        }

        val localSettlements = dao.allSettlements().associateBy { it.id }
        for (dto in file.settlements) {
            val existing = localSettlements[dto.id]
            val incomingUpdatedAt = isoToMillis(dto.updatedAt)
            if (existing != null && existing.updatedAt >= incomingUpdatedAt) continue

            dao.upsertSettlement(
                SettlementEntity(
                    id = dto.id,
                    groupId = dto.groupId,
                    fromParticipantId = dto.fromParticipantId,
                    toParticipantId = dto.toParticipantId,
                    amountMinorUnits = dto.amountMinorUnits,
                    currencyCode = dto.currencyCode,
                    date = isoToMillis(dto.date),
                    method = dto.method,
                    notes = dto.notes,
                    baseCurrencyCode = dto.baseCurrencyCode,
                    exchangeRateToBase = dto.exchangeRateToBase,
                    createdAt = isoToMillis(dto.createdAt),
                    updatedAt = incomingUpdatedAt,
                )
            )
            summary = if (existing == null) {
                summary.copy(settlementsAdded = summary.settlementsAdded + 1)
            } else {
                summary.copy(settlementsUpdated = summary.settlementsUpdated + 1)
            }
        }

        return summary
    }
}
