package com.splitfree.interchange

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * The `.splitfree` interchange format: a whole ledger, or one group of it, as
 * JSON that both the iOS and Android apps read and write.
 *
 * This is how the two platforms interoperate without a server. Export a group,
 * send the file however you like, and the other person imports it. Because every
 * record carries the UUID it was created with, importing the same ledger twice
 * merges instead of duplicating, and a file that comes back with new expenses in
 * it merges those in too.
 *
 * Merging is last-write-wins on [updatedAt]. That is the honest limit of a
 * file-based exchange: two people editing the same expense while offline will
 * resolve to whichever edit was made later, not to a merge of both.
 *
 * The schema is deliberately boring. Every field is a primitive or a list of
 * primitives, dates are ISO 8601 strings, and money is minor units plus a
 * currency code, exactly as it is stored on both platforms.
 */
@Serializable
data class LedgerFile(
    val format: String = FORMAT,
    val version: Int = VERSION,
    val exportedAt: String,
    val exportedBy: ExportedBy? = null,
    val participants: List<ParticipantDTO> = emptyList(),
    val groups: List<GroupDTO> = emptyList(),
    val expenses: List<ExpenseDTO> = emptyList(),
    val settlements: List<SettlementDTO> = emptyList(),
) {
    companion object {
        const val FORMAT = "splitfree.ledger"
        const val VERSION = 1
        const val FILE_EXTENSION = "splitfree"
        const val MIME_TYPE = "application/json"

        val json = Json {
            prettyPrint = true
            ignoreUnknownKeys = true
            encodeDefaults = true
            explicitNulls = false
        }

        fun decode(text: String): Result<LedgerFile> = runCatching {
            val file = json.decodeFromString<LedgerFile>(text)
            require(file.format == FORMAT) { "Not a SplitFree ledger file" }
            require(file.version <= VERSION) {
                "This file was written by a newer version of SplitFree"
            }
            file
        }
    }

    fun encode(): String = json.encodeToString(serializer(), this)
}

@Serializable
data class ExportedBy(val id: String, val name: String)

@Serializable
data class ParticipantDTO(
    val id: String,
    val name: String,
    val email: String = "",
    val phone: String = "",
    val colorIndex: Int = 0,
    val updatedAt: String,
    val venmoHandle: String = "",
    val paypalHandle: String = "",
    val cashAppHandle: String = "",
    val upiHandle: String = "",
)

@Serializable
data class GroupDTO(
    val id: String,
    val name: String,
    /** trip, home, couple, event, project, other. */
    val kind: String = "other",
    val colorIndex: Int = 0,
    val defaultCurrencyCode: String = "USD",
    val simplifyDebts: Boolean = true,
    val notes: String = "",
    val isArchived: Boolean = false,
    val createdAt: String,
    val updatedAt: String,
    val memberIds: List<String> = emptyList(),
)

@Serializable
data class ExpenseDTO(
    val id: String,
    val groupId: String? = null,
    val title: String = "",
    val notes: String = "",
    val amountMinorUnits: Long,
    val currencyCode: String,
    /** ISO 8601. */
    val date: String,
    val createdAt: String,
    val updatedAt: String,
    val category: String = "general",
    val splitMethod: String = "equal",
    val taxMinorUnits: Long = 0,
    val tipMinorUnits: Long = 0,
    val baseCurrencyCode: String = "USD",
    val exchangeRateToBase: Double = 1.0,
    val payers: List<PayerDTO> = emptyList(),
    val shares: List<ShareDTO> = emptyList(),
    val items: List<LineItemDTO> = emptyList(),
) {
    /**
     * A file is only trustworthy if the shares still add up. An importer should
     * reject or repair anything that fails this.
     */
    val isBalanced: Boolean
        get() = shares.sumOf { it.amountMinorUnits } == amountMinorUnits &&
            payers.sumOf { it.amountMinorUnits } == amountMinorUnits
}

@Serializable
data class PayerDTO(
    @SerialName("participantId") val participantId: String,
    val amountMinorUnits: Long,
)

@Serializable
data class ShareDTO(
    @SerialName("participantId") val participantId: String,
    val amountMinorUnits: Long,
    val weight: Double = 0.0,
)

@Serializable
data class LineItemDTO(
    val id: String,
    val name: String = "",
    val amountMinorUnits: Long = 0,
    val quantity: Int = 1,
    val sortOrder: Int = 0,
    val assigneeIds: List<String> = emptyList(),
)

@Serializable
data class SettlementDTO(
    val id: String,
    val groupId: String? = null,
    val fromParticipantId: String,
    val toParticipantId: String,
    val amountMinorUnits: Long,
    val currencyCode: String,
    val date: String,
    val createdAt: String,
    val updatedAt: String,
    val method: String = "cash",
    val notes: String = "",
    val baseCurrencyCode: String = "USD",
    val exchangeRateToBase: Double = 1.0,
)

/** What an import actually did, so the UI can report it honestly. */
data class ImportSummary(
    val participantsAdded: Int = 0,
    val participantsUpdated: Int = 0,
    val groupsAdded: Int = 0,
    val groupsUpdated: Int = 0,
    val expensesAdded: Int = 0,
    val expensesUpdated: Int = 0,
    val settlementsAdded: Int = 0,
    val settlementsUpdated: Int = 0,
    val skippedUnbalanced: Int = 0,
) {
    val totalAdded: Int
        get() = participantsAdded + groupsAdded + expensesAdded + settlementsAdded

    val totalUpdated: Int
        get() = participantsUpdated + groupsUpdated + expensesUpdated + settlementsUpdated

    val changedAnything: Boolean get() = totalAdded > 0 || totalUpdated > 0
}
