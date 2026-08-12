package com.splitfree.sync

import com.splitfree.data.ExpenseEntity
import com.splitfree.data.GroupEntity
import com.splitfree.data.LineItemEntity
import com.splitfree.data.ParticipantEntity
import com.splitfree.data.PayerEntity
import com.splitfree.data.SettlementEntity
import com.splitfree.data.ShareEntity

/**
 * A stable hash of a row's syncable contents.
 *
 * FNV-1a over a canonical string. The point of using a named algorithm rather
 * than the platform's own hash is that both must agree: `String.hashCode` on the
 * JVM and `hashValue` in Swift produce different numbers for the same text, and
 * Swift's is seeded per process on top of that. Two devices computing different
 * fingerprints for identical data would re-upload every row on every sync,
 * forever, and nothing would look broken.
 *
 * This file is the exact counterpart of `SyncFingerprint.swift`. Change one and
 * you must change the other.
 */
object SyncFingerprint {
    private const val OFFSET_BASIS = -0x340d631b7bdddcdbL // 0xcbf29ce484222325
    private const val PRIME = 0x100000001b3L

    /**
     * Field separator. Without one, ["ab", "c"] and ["a", "bc"] hash the same
     * and two different rosters look identical. U+0001 cannot appear in a name
     * anyone typed.
     */
    private const val SEPARATOR = "\u0001"

    fun of(parts: List<String>): String {
        var hash = OFFSET_BASIS
        for (byte in parts.joinToString(SEPARATOR).toByteArray(Charsets.UTF_8)) {
            hash = hash xor (byte.toLong() and 0xff)
            hash *= PRIME
        }
        return java.lang.Long.toHexString(hash)
    }

    /**
     * Milliseconds are dropped. Sub-second precision does not survive the round
     * trip through Postgres, and keeping it would make every row look changed.
     */
    fun stamp(epochMillis: Long): String = (epochMillis / 1000).toString()

    /** Six decimal places, matching Swift's `String(format: "%.6f")`. */
    private fun decimal(value: Double): String = String.format(java.util.Locale.ROOT, "%.6f", value)

    /**
     * Includes the roster, because a member added or renamed is a change to the
     * group as far as the server is concerned: the whole roster is pushed with
     * it, so the whole roster has to be part of what marks it dirty.
     */
    fun forGroup(
        group: GroupEntity,
        members: List<ParticipantEntity>,
        memberId: (ParticipantEntity) -> String,
    ): String {
        val parts = mutableListOf(
            group.name,
            group.kind,
            group.colorIndex.toString(),
            group.defaultCurrencyCode,
            if (group.simplifyDebts) "1" else "0",
            group.notes,
            if (group.isArchived) "1" else "0",
        )
        // Sorted the way iOS sorts a group's members, so both platforms feed the
        // hash the same sequence.
        for (person in members.sortedWith(compareByDescending<ParticipantEntity> { it.isCurrentUser }
            .thenBy(String.CASE_INSENSITIVE_ORDER) { it.fullName })) {
            parts += memberId(person)
            parts += person.fullName
            parts += person.colorIndex.toString()
        }
        return of(parts)
    }

    fun forExpense(
        expense: ExpenseEntity,
        payers: List<PayerEntity>,
        shares: List<ShareEntity>,
        items: List<LineItemEntity>,
        memberId: (String) -> String,
    ): String {
        val parts = mutableListOf(
            expense.title,
            expense.notes,
            expense.amountMinorUnits.toString(),
            expense.currencyCode,
            stamp(expense.date),
            expense.category,
            expense.splitMethod,
            expense.taxMinorUnits.toString(),
            expense.tipMinorUnits.toString(),
            expense.baseCurrencyCode,
            decimal(expense.exchangeRateToBase),
        )
        // Sorted by member id, not by row id. Row ids are local: an expense
        // that came down from the server gets fresh payer rows here with ids
        // this device invented, and iOS invented different ones. Sorting on them
        // would make the two platforms hash the same expense differently and
        // push it back and forth forever.
        for (payer in payers.sortedBy { memberId(it.participantId) }) {
            parts += memberId(payer.participantId)
            parts += payer.amountMinorUnits.toString()
        }
        for (share in shares.sortedBy { memberId(it.participantId) }) {
            parts += memberId(share.participantId)
            parts += share.amountMinorUnits.toString()
            parts += decimal(share.weight)
        }
        for (item in items.sortedBy { it.sortOrder }) {
            parts += item.id
            parts += item.name
            parts += item.amountMinorUnits.toString()
            parts += item.quantity.toString()
            parts += item.assignees.map(memberId).sorted().joinToString(",")
        }
        return of(parts)
    }

    fun forSettlement(settlement: SettlementEntity, memberId: (String) -> String): String = of(
        listOf(
            memberId(settlement.fromParticipantId),
            memberId(settlement.toParticipantId),
            settlement.amountMinorUnits.toString(),
            settlement.currencyCode,
            stamp(settlement.date),
            settlement.method,
            settlement.notes,
            settlement.baseCurrencyCode,
            decimal(settlement.exchangeRateToBase),
        )
    )
}
