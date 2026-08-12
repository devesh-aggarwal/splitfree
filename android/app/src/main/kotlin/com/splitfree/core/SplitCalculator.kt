package com.splitfree.core

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToLong

/** How a total was divided between the people involved. */
enum class SplitMethod {
    EQUAL, EXACT, PERCENT, SHARES, ADJUSTMENT, ITEMIZED;

    /** Stable string used by the database and the interchange format. */
    val wireName: String
        get() = when (this) {
            EQUAL -> "equal"
            EXACT -> "exact"
            PERCENT -> "percent"
            SHARES -> "shares"
            ADJUSTMENT -> "adjustment"
            ITEMIZED -> "itemized"
        }

    companion object {
        fun fromWire(value: String): SplitMethod =
            entries.firstOrNull { it.wireName == value } ?: EQUAL
    }
}

/**
 * Turns "how should this be divided" into exact per-person minor-unit amounts.
 *
 * Every function here guarantees the allocated amounts sum **exactly** to the
 * total. Remainders are never dropped or rounded away; they are handed out one
 * minor unit at a time by the largest-remainder method, so a $10.00 bill split
 * three ways comes out 3.34 / 3.33 / 3.33 rather than 3.33 x 3 and a lost cent.
 *
 * Ported line for line from the iOS `SplitCalculator`, including tie-breaking
 * order, so both apps produce byte-identical splits for the same input.
 */
object SplitCalculator {

    /** A person's raw input in the split editor, before it resolves to cents. */
    data class Entry(
        val participantId: String,
        val isIncluded: Boolean = true,
        /**
         * Meaning depends on the method: exact minor units, percent, share
         * count, or a plus/minus adjustment in minor units.
         */
        val value: Double = 0.0,
    )

    data class Allocation(
        val participantId: String,
        val amountMinorUnits: Long,
        /** The input that produced this amount, preserved for round-tripping. */
        val weight: Double,
    )

    data class ItemAssignment(
        /** Line total in minor units (unit price x quantity). */
        val amountMinorUnits: Long,
        /** Who had it. Empty means everyone in `fallbackParticipants`. */
        val participantIds: List<String>,
    )

    // MARK: - Equal

    /**
     * Splits an integer into [count] parts that sum exactly to [total].
     * Negative totals split symmetrically, so refunds behave the same way.
     */
    fun distributeEvenly(total: Long, count: Int): List<Long> {
        if (count <= 0) return emptyList()
        val sign = if (total < 0) -1L else 1L
        val magnitude = abs(total)
        val base = magnitude / count
        val remainder = (magnitude % count).toInt()
        return (0 until count).map { index ->
            sign * (base + if (index < remainder) 1 else 0)
        }
    }

    /**
     * Splits [total] as evenly as possible. The first `total % n` people in the
     * given order each absorb one extra minor unit.
     */
    fun equal(total: Long, among: List<String>): List<Allocation> {
        if (among.isEmpty()) return emptyList()
        return among.zip(distributeEvenly(total, among.size)) { id, amount ->
            Allocation(id, amount, 1.0)
        }
    }

    // MARK: - Weighted (percent, shares)

    /**
     * Distributes [total] in proportion to the weights using the
     * largest-remainder method: each person gets floor(total x w / sum(w)), then
     * the leftover minor units go one each to the largest fractional remainders.
     *
     * Returns all zeros when every weight is zero, rather than dividing by zero.
     */
    fun weighted(total: Long, weights: List<Pair<String, Double>>): List<Allocation> {
        if (weights.isEmpty()) return emptyList()
        val totalWeight = weights.sumOf { maxOf(0.0, it.second) }
        if (totalWeight <= 0.0) {
            return weights.map { Allocation(it.first, 0, it.second) }
        }

        val sign = if (total < 0) -1L else 1L
        val magnitude = abs(total).toDouble()

        val floors = LongArray(weights.size)
        val remainders = ArrayList<Pair<Int, Double>>(weights.size)

        weights.forEachIndexed { index, entry ->
            val exact = magnitude * maxOf(0.0, entry.second) / totalWeight
            val floored = floor(exact)
            floors[index] = floored.toLong()
            remainders.add(index to (exact - floored))
        }

        var leftover = abs(total) - floors.sum()
        // Largest fractional part first; ties fall back to input order so the
        // result is deterministic across runs, devices and platforms.
        remainders.sortWith(compareByDescending<Pair<Int, Double>> { it.second }.thenBy { it.first })

        var cursor = 0
        while (leftover > 0 && remainders.isNotEmpty()) {
            floors[remainders[cursor % remainders.size].first] += 1
            leftover -= 1
            cursor += 1
        }

        return weights.mapIndexed { index, entry ->
            Allocation(entry.first, sign * floors[index], entry.second)
        }
    }

    // MARK: - Adjustment

    /**
     * Splits what's left after each person's personal extra comes off the top,
     * then adds those extras back. Someone who ordered a $6 dessert on a shared
     * bill enters +6.00 and pays their even share of the rest plus the dessert.
     */
    fun adjustment(total: Long, entries: List<Pair<String, Long>>): List<Allocation> {
        if (entries.isEmpty()) return emptyList()
        val adjustmentSum = entries.sumOf { it.second }
        val shared = total - adjustmentSum
        val evenParts = distributeEvenly(shared, entries.size)
        return entries.mapIndexed { index, entry ->
            Allocation(entry.first, evenParts[index] + entry.second, entry.second.toDouble())
        }
    }

    // MARK: - Exact

    /**
     * Passes typed amounts through unchanged. Any shortfall or overage is the
     * caller's problem to surface; [exactRemainder] reports it.
     */
    fun exact(entries: List<Pair<String, Long>>): List<Allocation> =
        entries.map { Allocation(it.first, it.second, it.second.toDouble()) }

    fun exactRemainder(total: Long, entries: List<Pair<String, Long>>): Long =
        total - entries.sumOf { it.second }

    // MARK: - Itemized

    /**
     * Builds shares from receipt line items, then spreads tax and tip across
     * people in proportion to what they actually ordered.
     *
     * The final amounts reconcile against [total], so the shares always add up
     * even when the receipt's own arithmetic doesn't.
     */
    fun itemized(
        total: Long,
        items: List<ItemAssignment>,
        taxMinorUnits: Long,
        tipMinorUnits: Long,
        fallbackParticipants: List<String>,
    ): List<Allocation> {
        if (fallbackParticipants.isEmpty()) return emptyList()

        val subtotals = LinkedHashMap<String, Long>()
        fallbackParticipants.forEach { subtotals[it] = 0 }

        for (item in items) {
            val people = item.participantIds.ifEmpty { fallbackParticipants }
            if (people.isEmpty()) continue
            val parts = distributeEvenly(item.amountMinorUnits, people.size)
            people.forEachIndexed { index, person ->
                subtotals[person] = (subtotals[person] ?: 0) + parts[index]
            }
        }

        val itemsTotal = subtotals.values.sum()
        val extras = taxMinorUnits + tipMinorUnits

        // Tax and tip ride along in proportion to each person's item subtotal.
        // With nothing itemized yet, fall back to an even spread.
        val extraAllocations: Map<String, Long> = when {
            itemsTotal != 0L && extras != 0L ->
                weighted(extras, fallbackParticipants.map { it to (subtotals[it] ?: 0).toDouble() })
                    .associate { it.participantId to it.amountMinorUnits }
            extras != 0L ->
                fallbackParticipants.zip(distributeEvenly(extras, fallbackParticipants.size)).toMap()
            else -> emptyMap()
        }

        val amounts = fallbackParticipants.map { id ->
            id to ((subtotals[id] ?: 0) + (extraAllocations[id] ?: 0))
        }.toMutableList()

        // Reconcile against the stated total. Receipts round; we must not.
        val drift = total - amounts.sumOf { it.second }
        if (drift != 0L) {
            val correction = distributeEvenly(drift, amounts.size)
            for (index in amounts.indices) {
                amounts[index] = amounts[index].first to (amounts[index].second + correction[index])
            }
        }

        return amounts.map { Allocation(it.first, it.second, it.second.toDouble()) }
    }

    // MARK: - Unified entry point

    fun resolve(
        method: SplitMethod,
        total: Long,
        entries: List<Entry>,
        items: List<ItemAssignment> = emptyList(),
        taxMinorUnits: Long = 0,
        tipMinorUnits: Long = 0,
    ): List<Allocation> {
        val included = entries.filter { it.isIncluded }
        val ids = included.map { it.participantId }
        if (ids.isEmpty()) return emptyList()

        return when (method) {
            SplitMethod.EQUAL -> equal(total, ids)
            SplitMethod.PERCENT, SplitMethod.SHARES ->
                weighted(total, included.map { it.participantId to it.value })
            SplitMethod.EXACT ->
                exact(included.map { it.participantId to it.value.roundToLong() })
            SplitMethod.ADJUSTMENT ->
                adjustment(total, included.map { it.participantId to it.value.roundToLong() })
            SplitMethod.ITEMIZED ->
                itemized(total, items, taxMinorUnits, tipMinorUnits, ids)
        }
    }

    // MARK: - Validation

    sealed interface ValidationIssue {
        data object NoOneSelected : ValidationIssue
        data class AmountsDontAddUp(val remainder: Long, val currencyCode: String) : ValidationIssue
        data class PercentagesDontAddUp(val remainder: Double) : ValidationIssue
        data object NoShares : ValidationIssue
        data object NonPositiveTotal : ValidationIssue
    }

    fun validate(
        method: SplitMethod,
        total: Long,
        currencyCode: String,
        entries: List<Entry>,
    ): ValidationIssue? {
        val included = entries.filter { it.isIncluded }
        if (included.isEmpty()) return ValidationIssue.NoOneSelected

        return when (method) {
            SplitMethod.EQUAL, SplitMethod.ADJUSTMENT, SplitMethod.ITEMIZED -> null
            SplitMethod.EXACT -> {
                val remainder = total - included.sumOf { it.value.roundToLong() }
                if (remainder == 0L) null
                else ValidationIssue.AmountsDontAddUp(remainder, currencyCode)
            }
            SplitMethod.PERCENT -> {
                val remainder = 100.0 - included.sumOf { it.value }
                // Tolerate float noise from repeated typing, but not real gaps.
                if (abs(remainder) < 0.05) null
                else ValidationIssue.PercentagesDontAddUp(remainder)
            }
            SplitMethod.SHARES ->
                if (included.sumOf { maxOf(0.0, it.value) } > 0) null else ValidationIssue.NoShares
        }
    }
}
