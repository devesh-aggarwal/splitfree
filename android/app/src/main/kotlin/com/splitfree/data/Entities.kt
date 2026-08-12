package com.splitfree.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.TypeConverter
import java.util.UUID

/**
 * Room entities.
 *
 * Ids are String UUIDs rather than autoincrementing integers, because they
 * travel in the `.splitfree` interchange file and have to keep their identity
 * when a ledger moves between an iPhone and an Android phone. An expense created
 * on iOS keeps the same id here, which is what lets re-importing merge rather
 * than duplicate.
 *
 * Every record carries `updatedAt` (epoch millis) for last-write-wins merging.
 */

fun newId(): String = UUID.randomUUID().toString()

@Entity(tableName = "participants")
data class ParticipantEntity(
    @PrimaryKey val id: String = newId(),
    val name: String = "",
    val email: String = "",
    val phone: String = "",
    val colorIndex: Int = 0,
    val isCurrentUser: Boolean = false,
    val isArchived: Boolean = false,
    val avatarPath: String? = null,
    val venmoHandle: String = "",
    val paypalHandle: String = "",
    val cashAppHandle: String = "",
    val upiHandle: String = "",
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    /**
     * A fingerprint of this row's contents as the server last saw them.
     *
     * Sync decides what to push by comparing it against the row's current
     * fingerprint. A hash rather than a dirty flag, because a flag has to be
     * remembered at every write site and one forgotten line means an edit that
     * silently never syncs. The algorithm matches the iOS app byte for byte, so
     * a group that moves between an iPhone and a Pixel does not re-upload itself
     * on every sync.
     */
    val syncedFingerprint: String = "",
    /** The Supabase user id, once this person has claimed their slot. */
    val remoteUserId: String? = null,
) {
    /** "You" for the current user, otherwise their name. */
    val fullName: String get() = name.ifBlank { "Someone" }

    val initials: String
        get() = fullName.split(" ").take(2)
            .mapNotNull { it.firstOrNull()?.uppercase() }
            .joinToString("")

    val firstName: String get() = fullName.split(" ").first()

    val hasAnyPaymentHandle: Boolean
        get() = venmoHandle.isNotBlank() || paypalHandle.isNotBlank() ||
            cashAppHandle.isNotBlank() || upiHandle.isNotBlank()
}

@Entity(tableName = "groups")
data class GroupEntity(
    @PrimaryKey val id: String = newId(),
    val name: String = "",
    val kind: String = "other",
    val colorIndex: Int = 0,
    val defaultCurrencyCode: String = "USD",
    /** Defaults on: fewer payments is what almost everyone wants. */
    val simplifyDebts: Boolean = true,
    val notes: String = "",
    val isArchived: Boolean = false,
    val isPinned: Boolean = false,
    val sortOrder: Long = 0,
    val coverPath: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    /**
     * A fingerprint of this row's contents as the server last saw them.
     *
     * Sync decides what to push by comparing it against the row's current
     * fingerprint. A hash rather than a dirty flag, because a flag has to be
     * remembered at every write site and one forgotten line means an edit that
     * silently never syncs. The algorithm matches the iOS app byte for byte, so
     * a group that moves between an iPhone and a Pixel does not re-upload itself
     * on every sync.
     */
    val syncedFingerprint: String = "",
    /**
     * A two-person group that stands for a friendship. Presented as a friend
     * rather than as a group, and hidden from the groups list. It exists so that
     * expenses shared with one person can travel: the sync engine only carries
     * groups, so a friendship with no group behind it could never reach anybody
     * else's phone.
     */
    val isDirect: Boolean = false,
    /**
     * Whether this group is synced through an account. Off unless somebody
     * explicitly shares it, which is what keeps the local-only promise true for
     * every group they never shared.
     */
    val isShared: Boolean = false,
    /**
     * Which member slot on the server represents *you* in this group. Normally
     * your own participant id, but a group you joined keeps the id whoever
     * created it chose, and the expenses already written against that slot have
     * to land on you rather than on a duplicate stranger.
     */
    val myMemberId: String? = null,
) {
    val displayName: String get() = name.ifBlank { "Untitled group" }
}

@Entity(
    tableName = "group_members",
    primaryKeys = ["groupId", "participantId"],
    indices = [Index("participantId")],
    foreignKeys = [
        ForeignKey(
            entity = GroupEntity::class,
            parentColumns = ["id"],
            childColumns = ["groupId"],
            onDelete = ForeignKey.CASCADE,
        ),
        ForeignKey(
            entity = ParticipantEntity::class,
            parentColumns = ["id"],
            childColumns = ["participantId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
)
data class GroupMemberEntity(
    val groupId: String,
    val participantId: String,
)

@Entity(
    tableName = "expenses",
    indices = [Index("groupId"), Index("date")],
    foreignKeys = [
        ForeignKey(
            entity = GroupEntity::class,
            parentColumns = ["id"],
            childColumns = ["groupId"],
            onDelete = ForeignKey.CASCADE,
        )
    ],
)
data class ExpenseEntity(
    @PrimaryKey val id: String = newId(),
    val groupId: String? = null,
    val title: String = "",
    val notes: String = "",
    val amountMinorUnits: Long = 0,
    val currencyCode: String = "USD",
    val date: Long = System.currentTimeMillis(),
    val category: String = "general",
    val splitMethod: String = "equal",
    val taxMinorUnits: Long = 0,
    val tipMinorUnits: Long = 0,
    val baseCurrencyCode: String = "USD",
    val exchangeRateToBase: Double = 1.0,
    val receiptPath: String? = null,
    val receiptText: String = "",
    val generatedByRuleId: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    /**
     * A fingerprint of this row's contents as the server last saw them.
     *
     * Sync decides what to push by comparing it against the row's current
     * fingerprint. A hash rather than a dirty flag, because a flag has to be
     * remembered at every write site and one forgotten line means an edit that
     * silently never syncs. The algorithm matches the iOS app byte for byte, so
     * a group that moves between an iPhone and a Pixel does not re-upload itself
     * on every sync.
     */
    val syncedFingerprint: String = "",
) {
    val displayTitle: String get() = title.ifBlank { "Untitled expense" }
}

@Entity(
    tableName = "expense_payers",
    indices = [Index("expenseId"), Index("participantId")],
    foreignKeys = [
        ForeignKey(
            entity = ExpenseEntity::class,
            parentColumns = ["id"],
            childColumns = ["expenseId"],
            onDelete = ForeignKey.CASCADE,
        )
    ],
)
data class PayerEntity(
    @PrimaryKey val id: String = newId(),
    val expenseId: String,
    val participantId: String,
    val amountMinorUnits: Long,
)

@Entity(
    tableName = "expense_shares",
    indices = [Index("expenseId"), Index("participantId")],
    foreignKeys = [
        ForeignKey(
            entity = ExpenseEntity::class,
            parentColumns = ["id"],
            childColumns = ["expenseId"],
            onDelete = ForeignKey.CASCADE,
        )
    ],
)
data class ShareEntity(
    @PrimaryKey val id: String = newId(),
    val expenseId: String,
    val participantId: String,
    val amountMinorUnits: Long,
    /** The editor input that produced the amount: a percent, share count or +/-. */
    val weight: Double = 0.0,
)

@Entity(
    tableName = "expense_items",
    indices = [Index("expenseId")],
    foreignKeys = [
        ForeignKey(
            entity = ExpenseEntity::class,
            parentColumns = ["id"],
            childColumns = ["expenseId"],
            onDelete = ForeignKey.CASCADE,
        )
    ],
)
data class LineItemEntity(
    @PrimaryKey val id: String = newId(),
    val expenseId: String,
    val name: String = "",
    val amountMinorUnits: Long = 0,
    val quantity: Int = 1,
    val sortOrder: Int = 0,
    /**
     * Comma-separated participant ids. Empty means "everyone on the expense".
     * A join table would be more normal, but this list is never queried across
     * rows, only read back with its own item.
     */
    @ColumnInfo(name = "assigneeIds") val assigneeIds: String = "",
) {
    val assignees: List<String>
        get() = assigneeIds.split(",").map { it.trim() }.filter { it.isNotEmpty() }

    val lineTotalMinorUnits: Long get() = amountMinorUnits * maxOf(1, quantity)
}

@Entity(
    tableName = "settlements",
    indices = [Index("groupId"), Index("date")],
    foreignKeys = [
        ForeignKey(
            entity = GroupEntity::class,
            parentColumns = ["id"],
            childColumns = ["groupId"],
            onDelete = ForeignKey.CASCADE,
        )
    ],
)
data class SettlementEntity(
    @PrimaryKey val id: String = newId(),
    val groupId: String? = null,
    val fromParticipantId: String,
    val toParticipantId: String,
    val amountMinorUnits: Long,
    val currencyCode: String = "USD",
    val date: Long = System.currentTimeMillis(),
    val method: String = "cash",
    val notes: String = "",
    val baseCurrencyCode: String = "USD",
    val exchangeRateToBase: Double = 1.0,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    /**
     * A fingerprint of this row's contents as the server last saw them.
     *
     * Sync decides what to push by comparing it against the row's current
     * fingerprint. A hash rather than a dirty flag, because a flag has to be
     * remembered at every write site and one forgotten line means an edit that
     * silently never syncs. The algorithm matches the iOS app byte for byte, so
     * a group that moves between an iPhone and a Pixel does not re-upload itself
     * on every sync.
     */
    val syncedFingerprint: String = "",
)

/**
 * A record that something was deleted.
 *
 * Deleting locally stays a real delete, so no query has to learn to skip a row.
 * What sync needs is separate knowledge that the deletion happened, because a
 * friend's phone that was offline at the time would otherwise show the expense
 * forever.
 */
@Entity(tableName = "sync_tombstones", indices = [Index("entityId")])
data class TombstoneEntity(
    @PrimaryKey val id: String = newId(),
    /** "group", "member", "expense" or "settlement". */
    val entity: String,
    val entityId: String,
    val groupId: String? = null,
    val deletedAt: Long = System.currentTimeMillis(),
    val isPushed: Boolean = false,
)

@Entity(tableName = "activity", indices = [Index("createdAt")])
data class ActivityEntity(
    @PrimaryKey val id: String = newId(),
    val kind: String,
    val headline: String,
    val detail: String = "",
    val groupId: String? = null,
    val groupName: String = "",
    val expenseId: String? = null,
    val settlementId: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
)

@Entity(tableName = "recurring_rules", indices = [Index("groupId")])
data class RecurringRuleEntity(
    @PrimaryKey val id: String = newId(),
    val groupId: String? = null,
    val title: String = "",
    val notes: String = "",
    val amountMinorUnits: Long = 0,
    val currencyCode: String = "USD",
    val category: String = "general",
    val splitMethod: String = "equal",
    val frequency: String = "monthly",
    val startDate: Long = System.currentTimeMillis(),
    val nextOccurrence: Long = System.currentTimeMillis(),
    val endDate: Long? = null,
    val isActive: Boolean = true,
    val generatedCount: Int = 0,
    val lastGeneratedAt: Long? = null,
    /** JSON-encoded split plan, so it survives someone leaving the group. */
    val planJson: String = "",
    val createdAt: Long = System.currentTimeMillis(),
)

@Entity(tableName = "split_templates", indices = [Index("groupId")])
data class SplitTemplateEntity(
    @PrimaryKey val id: String = newId(),
    val groupId: String? = null,
    val name: String = "",
    val splitMethod: String = "equal",
    val planJson: String = "",
    val isDefaultForGroup: Boolean = false,
    val useCount: Int = 0,
    val lastUsedAt: Long? = null,
    val createdAt: Long = System.currentTimeMillis(),
)

class Converters {
    @TypeConverter fun listToString(value: List<String>?): String = value?.joinToString(",") ?: ""

    @TypeConverter
    fun stringToList(value: String?): List<String> =
        value?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()
}
