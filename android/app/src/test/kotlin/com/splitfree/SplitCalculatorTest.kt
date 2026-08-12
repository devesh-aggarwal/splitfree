package com.splitfree

import com.splitfree.core.SplitCalculator
import com.splitfree.core.SplitCalculator.Entry
import com.splitfree.core.SplitCalculator.ItemAssignment
import com.splitfree.core.SplitMethod
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * The rule every one of these exists to protect: the allocated amounts must sum
 * exactly to the total, for every split method, participant count and currency
 * precision.
 *
 * These mirror the iOS `SplitCalculatorTests` case for case. If a change makes
 * one suite fail and not the other, the two apps have drifted and the same bill
 * would split differently on each phone.
 */
class SplitCalculatorTest {

    private fun ids(count: Int) = (0 until count).map { UUID.randomUUID().toString() }

    @Test
    fun `an even split always sums to the total for any group size`() {
        for (total in listOf(0L, 1L, 7L, 100L, 1000L, 8450L, 999_999L)) {
            for (count in 1..12) {
                val people = ids(count)
                val allocations = SplitCalculator.equal(total, people)
                assertEquals(
                    "total $total across $count people",
                    total,
                    allocations.sumOf { it.amountMinorUnits },
                )
                assertEquals(count, allocations.size)
            }
        }
    }

    @Test
    fun `ten dollars three ways is 334 333 333, not a lost cent`() {
        val amounts = SplitCalculator.equal(1000, ids(3)).map { it.amountMinorUnits }
        assertEquals(listOf(334L, 333L, 333L), amounts)
    }

    @Test
    fun `a negative total splits symmetrically`() {
        val amounts = SplitCalculator.distributeEvenly(-1000, 3)
        assertEquals(listOf(-334L, -333L, -333L), amounts)
        assertEquals(-1000L, amounts.sum())
    }

    @Test
    fun `splitting among nobody produces nothing rather than crashing`() {
        assertTrue(SplitCalculator.equal(500, emptyList()).isEmpty())
        assertTrue(SplitCalculator.distributeEvenly(500, 0).isEmpty())
    }

    @Test
    fun `weighted splits sum exactly with leftovers on the largest remainders`() {
        val people = ids(3)
        val allocations = SplitCalculator.weighted(1000, people.map { it to 1.0 })
        assertEquals(1000L, allocations.sumOf { it.amountMinorUnits })
        assertEquals(listOf(334L, 333L, 333L), allocations.map { it.amountMinorUnits })
    }

    @Test
    fun `shares divide in the stated proportion`() {
        val people = ids(2)
        val allocations =
            SplitCalculator.weighted(900, listOf(people[0] to 2.0, people[1] to 1.0))
        assertEquals(listOf(600L, 300L), allocations.map { it.amountMinorUnits })
    }

    @Test
    fun `percentages that don't divide cleanly still sum to the total`() {
        val people = ids(3)
        val allocations = SplitCalculator.weighted(
            10_000,
            listOf(people[0] to 33.33, people[1] to 33.33, people[2] to 33.34),
        )
        assertEquals(10_000L, allocations.sumOf { it.amountMinorUnits })
    }

    @Test
    fun `all-zero weights allocate nothing instead of dividing by zero`() {
        val allocations = SplitCalculator.weighted(1000, ids(3).map { it to 0.0 })
        assertTrue(allocations.all { it.amountMinorUnits == 0L })
    }

    @Test
    fun `plus minus adds personal extras on top of an even split of the rest`() {
        val people = ids(3)
        // A $30 bill where one person had a $6 dessert: the other $24 splits
        // three ways at $8 each, and the dessert lands on them alone.
        val allocations = SplitCalculator.adjustment(
            3000,
            listOf(people[0] to 600L, people[1] to 0L, people[2] to 0L),
        )
        assertEquals(listOf(1400L, 800L, 800L), allocations.map { it.amountMinorUnits })
        assertEquals(3000L, allocations.sumOf { it.amountMinorUnits })
    }

    @Test
    fun `adjustments reconcile to the total even when they exceed it`() {
        val people = ids(2)
        val allocations =
            SplitCalculator.adjustment(1000, listOf(people[0] to 1500L, people[1] to 0L))
        assertEquals(1000L, allocations.sumOf { it.amountMinorUnits })
    }

    @Test
    fun `itemizing charges for what you had plus a share of tax and tip`() {
        val ana = UUID.randomUUID().toString()
        val ben = UUID.randomUUID().toString()
        val items = listOf(
            ItemAssignment(2000, listOf(ana)),
            ItemAssignment(1000, listOf(ben)),
        )
        // 30.00 of items + 3.00 tax + 3.00 tip = 36.00; extras split 2:1.
        val allocations = SplitCalculator.itemized(3600, items, 300, 300, listOf(ana, ben))
        val byId = allocations.associate { it.participantId to it.amountMinorUnits }
        assertEquals(2400L, byId[ana])
        assertEquals(1200L, byId[ben])
        assertEquals(3600L, allocations.sumOf { it.amountMinorUnits })
    }

    @Test
    fun `an unassigned item is shared by everyone`() {
        val people = ids(3)
        val allocations = SplitCalculator.itemized(
            900,
            listOf(ItemAssignment(900, emptyList())),
            0, 0, people,
        )
        assertTrue(allocations.all { it.amountMinorUnits == 300L })
    }

    @Test
    fun `itemized amounts reconcile when the receipt's own arithmetic is off`() {
        val people = ids(2)
        val items = listOf(
            ItemAssignment(1000, listOf(people[0])),
            ItemAssignment(1000, listOf(people[1])),
        )
        // The stated total is 5 cents more than the lines add up to.
        val allocations = SplitCalculator.itemized(2005, items, 0, 0, people)
        assertEquals(2005L, allocations.sumOf { it.amountMinorUnits })
    }

    @Test
    fun `exact amounts that don't add up are reported with the shortfall`() {
        val people = ids(2)
        val entries = listOf(
            Entry(people[0], true, 500.0),
            Entry(people[1], true, 400.0),
        )
        val issue = SplitCalculator.validate(SplitMethod.EXACT, 1000, "USD", entries)
        assertEquals(SplitCalculator.ValidationIssue.AmountsDontAddUp(100, "USD"), issue)
    }

    @Test
    fun `percentages within a rounding hair of 100 are accepted`() {
        val entries = ids(3).map { Entry(it, true, 33.333) }
        assertEquals(null, SplitCalculator.validate(SplitMethod.PERCENT, 1000, "USD", entries))
    }

    @Test
    fun `a split with nobody in it is rejected`() {
        val entries = listOf(Entry(UUID.randomUUID().toString(), false, 1.0))
        assertEquals(
            SplitCalculator.ValidationIssue.NoOneSelected,
            SplitCalculator.validate(SplitMethod.EQUAL, 1000, "USD", entries),
        )
    }

    @Test
    fun `every split method resolves to amounts that sum to the total`() {
        val people = ids(4)
        val total = 12_345L
        for (method in listOf(
            SplitMethod.EQUAL, SplitMethod.PERCENT, SplitMethod.SHARES, SplitMethod.ITEMIZED,
        )) {
            val entries = people.map {
                Entry(it, true, if (method == SplitMethod.PERCENT) 25.0 else 1.0)
            }
            val allocations = SplitCalculator.resolve(method, total, entries)
            assertEquals("$method", total, allocations.sumOf { it.amountMinorUnits })
        }
    }

    @Test
    fun `excluded people get nothing`() {
        val people = ids(3)
        val entries = listOf(
            Entry(people[0], true, 1.0),
            Entry(people[1], true, 1.0),
            Entry(people[2], false, 1.0),
        )
        val allocations = SplitCalculator.resolve(SplitMethod.EQUAL, 1000, entries)
        assertEquals(2, allocations.size)
        assertTrue(allocations.none { it.participantId == people[2] })
        assertEquals(1000L, allocations.sumOf { it.amountMinorUnits })
    }
}
