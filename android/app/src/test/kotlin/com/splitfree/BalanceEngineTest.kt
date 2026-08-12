package com.splitfree

import com.splitfree.core.BalanceEngine
import com.splitfree.core.Currencies
import com.splitfree.core.CurrencyFormatting
import com.splitfree.core.ExchangeRateTable
import com.splitfree.core.ExpenseCategory
import com.splitfree.core.ExpenseLedgerEntry
import com.splitfree.core.Money
import com.splitfree.core.SettlementLedgerEntry
import com.splitfree.core.SplitCalculator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.util.UUID

/** Mirrors the iOS `BalanceEngineTests`. */
class BalanceEngineTest {

    private fun id() = UUID.randomUUID().toString()

    private fun expense(
        currency: String = "USD",
        paidBy: List<Pair<String, Long>>,
        owedBy: List<Pair<String, Long>>,
    ) = ExpenseLedgerEntry(currency, paidBy, owedBy)

    @Test
    fun `one person paying for two produces a single debt`() {
        val me = id()
        val ana = id()
        val sheet = BalanceEngine.balanceSheet(
            listOf(expense(paidBy = listOf(me to 1000L), owedBy = listOf(me to 500L, ana to 500L))),
            emptyList(),
            simplify = false,
        )
        assertEquals(1, sheet.debts.size)
        val debt = sheet.debts.first()
        assertEquals(ana, debt.from)
        assertEquals(me, debt.to)
        assertEquals(500L, debt.amountMinorUnits)
    }

    @Test
    fun `debts in both directions net out into one`() {
        val me = id()
        val ana = id()
        val sheet = BalanceEngine.balanceSheet(
            listOf(
                expense(paidBy = listOf(me to 1000L), owedBy = listOf(me to 500L, ana to 500L)),
                expense(paidBy = listOf(ana to 600L), owedBy = listOf(me to 300L, ana to 300L)),
            ),
            emptyList(),
            simplify = false,
        )
        assertEquals(1, sheet.debts.size)
        val debt = sheet.debts.first()
        assertEquals(ana, debt.from)
        assertEquals(me, debt.to)
        assertEquals(200L, debt.amountMinorUnits)
    }

    @Test
    fun `a settlement cancels the debt it pays off`() {
        val me = id()
        val ana = id()
        val sheet = BalanceEngine.balanceSheet(
            listOf(expense(paidBy = listOf(me to 1000L), owedBy = listOf(me to 500L, ana to 500L))),
            listOf(SettlementLedgerEntry(ana, me, 500, "USD")),
            simplify = false,
        )
        assertTrue(sheet.isFullySettled)
    }

    @Test
    fun `a part payment leaves the remainder outstanding`() {
        val me = id()
        val ana = id()
        val sheet = BalanceEngine.balanceSheet(
            listOf(expense(paidBy = listOf(me to 1000L), owedBy = listOf(me to 500L, ana to 500L))),
            listOf(SettlementLedgerEntry(ana, me, 200, "USD")),
            simplify = false,
        )
        assertEquals(300L, sheet.debts.first().amountMinorUnits)
    }

    @Test
    fun `simplifying a circular debt removes the middle leg entirely`() {
        val a = id()
        val b = id()
        val c = id()
        // A pays for B, B pays for C, C pays for A, all $10.
        val expenses = listOf(
            expense(paidBy = listOf(a to 1000L), owedBy = listOf(b to 1000L)),
            expense(paidBy = listOf(b to 1000L), owedBy = listOf(c to 1000L)),
            expense(paidBy = listOf(c to 1000L), owedBy = listOf(a to 1000L)),
        )
        assertEquals(3, BalanceEngine.balanceSheet(expenses, emptyList(), false).debts.size)
        assertTrue(BalanceEngine.balanceSheet(expenses, emptyList(), true).debts.isEmpty())
    }

    @Test
    fun `simplification never needs more than one payment fewer than there are people`() {
        val people = (0 until 5).map { id() }
        val expenses = people.mapIndexed { index, payer ->
            val total = 1000L * (index + 1)
            val shares = SplitCalculator.equal(total, people)
            expense(
                paidBy = listOf(payer to total),
                owedBy = shares.map { it.participantId to it.amountMinorUnits },
            )
        }
        val simplified = BalanceEngine.balanceSheet(expenses, emptyList(), true)
        assertTrue(simplified.debts.size <= people.size - 1)
    }

    @Test
    fun `simplified debts settle everyone - net positions all reach zero`() {
        val people = (0 until 4).map { id() }
        val expenses = listOf(
            expense(
                paidBy = listOf(people[0] to 7000L, people[1] to 3000L),
                owedBy = people.map { it to 2500L },
            )
        )
        val sheet = BalanceEngine.balanceSheet(expenses, emptyList(), true)

        val net = HashMap<String, Long>()
        for (person in people) {
            net[person] = BalanceEngine.overallPosition(person, expenses, emptyList()).amount("USD")
        }
        for (debt in sheet.debts) {
            net[debt.from] = (net[debt.from] ?: 0) + debt.amountMinorUnits
            net[debt.to] = (net[debt.to] ?: 0) - debt.amountMinorUnits
        }
        assertTrue("left over: $net", net.values.all { it == 0L })
    }

    @Test
    fun `debts in different currencies are never mixed together`() {
        val me = id()
        val ana = id()
        val sheet = BalanceEngine.balanceSheet(
            listOf(
                expense("USD", listOf(me to 1000L), listOf(ana to 1000L)),
                expense("EUR", listOf(ana to 900L), listOf(me to 900L)),
            ),
            emptyList(),
            simplify = false,
        )
        assertEquals(2, sheet.debts.size)
        assertEquals(setOf("USD", "EUR"), sheet.debts.map { it.currencyCode }.toSet())
    }

    @Test
    fun `the same inputs always produce the same payment list`() {
        val people = (0 until 4).map { id() }
        val expenses = listOf(
            expense(paidBy = listOf(people[0] to 12_000L), owedBy = people.map { it to 3000L })
        )
        val first = BalanceEngine.balanceSheet(expenses, emptyList(), true).debts
        val second = BalanceEngine.balanceSheet(expenses, emptyList(), true).debts
        assertEquals(first, second)
    }

    @Test
    fun `greedy matching zeroes out the balances it is given`() {
        val a = id()
        val b = id()
        val c = id()
        val nets = mapOf(a to 500L, b to -300L, c to -200L)
        val transfers = BalanceEngine.greedyTransfers(nets)

        val result = HashMap(nets)
        for (transfer in transfers) {
            result[transfer.from] = (result[transfer.from] ?: 0) + transfer.amount
            result[transfer.to] = (result[transfer.to] ?: 0) - transfer.amount
        }
        assertTrue(result.values.all { it == 0L })
        assertEquals(2, transfers.size)
    }
}

/** Mirrors the iOS `MoneyTests`. */
class MoneyTest {

    @Test
    fun `decimal amounts convert to minor units without drift`() {
        assertEquals(1250L, Money.fromDecimal(BigDecimal("12.50"), "USD").minorUnits)
        assertEquals(7L, Money.fromDecimal(BigDecimal("0.07"), "USD").minorUnits)
        assertEquals(123_456L, Money.fromDecimal(BigDecimal("1234.56"), "EUR").minorUnits)
    }

    @Test
    fun `zero-decimal currencies never gain a fractional unit`() {
        assertEquals(0, Currencies.fractionDigits("JPY"))
        assertEquals(1500L, Money.fromDecimal(BigDecimal("1500"), "JPY").minorUnits)
    }

    @Test
    fun `three-decimal currencies keep their extra precision`() {
        assertEquals(3, Currencies.fractionDigits("KWD"))
        assertEquals(1234L, Money.fromDecimal(BigDecimal("1.234"), "KWD").minorUnits)
    }

    @Test
    fun `arithmetic is exact`() {
        val a = Money(1000, "USD")
        val b = Money(333, "USD")
        assertEquals(667L, (a - b).minorUnits)
        assertEquals(1333L, (a + b).minorUnits)
        assertEquals(-1000L, (-a).minorUnits)
        assertEquals(1000L, (-a).magnitude.minorUnits)
    }

    @Test
    fun `typed amounts parse regardless of separator convention`() {
        assertEquals(1250L, CurrencyFormatting.parse("12.50", "USD"))
        assertEquals(1250L, CurrencyFormatting.parse("12,50", "USD"))
        assertEquals(123_456L, CurrencyFormatting.parse("1,234.56", "USD"))
        assertEquals(123_456L, CurrencyFormatting.parse("1.234,56", "USD"))
        assertEquals(800L, CurrencyFormatting.parse("$8", "USD"))
        assertEquals(4500L, CurrencyFormatting.parse("€ 45,00", "EUR"))
    }

    @Test
    fun `nonsense input parses to nothing rather than zero`() {
        assertNull(CurrencyFormatting.parse("", "USD"))
        assertNull(CurrencyFormatting.parse("abc", "USD"))
    }

    @Test
    fun `the catalog covers more than 100 currencies with unique codes`() {
        assertTrue(Currencies.catalog.size > 100)
        assertEquals(Currencies.catalog.size, Currencies.catalog.map { it.code }.toSet().size)
        assertTrue(Currencies.catalog.all { it.code.length == 3 })
        assertTrue(Currencies.catalog.all { it.fractionDigits in 0..3 })
    }

    @Test
    fun `an unknown code degrades gracefully instead of crashing`() {
        assertEquals(2, Currencies.fractionDigits("ZZZ"))
        assertTrue(!Currencies.exists("ZZZ"))
        assertEquals("ZZZ", Currencies.currency("ZZZ").code)
    }

    @Test
    fun `cross-rates go through the base currency`() {
        val table = ExchangeRateTable("USD", mapOf("USD" to 1.0, "EUR" to 0.5, "JPY" to 100.0), 0, false)
        assertEquals(0.5, table.rate("USD", "EUR")!!, 1e-9)
        assertEquals(2.0, table.rate("EUR", "USD")!!, 1e-9)
        assertEquals(1000L, table.convert(1000, "USD", "JPY"))
        assertEquals(500L, table.convert(1000, "USD", "EUR"))
        assertNull(table.rate("USD", "XYZ"))
        assertEquals(0L, table.convert(1000, "USD", "XYZ"))
    }

    @Test
    fun `the bundled offline table covers every currency in the picker`() {
        val missing = Currencies.catalog.map { it.code }
            .filter { ExchangeRateTable.bundled.rates[it] == null }
        assertTrue("no offline rate for: $missing", missing.isEmpty())
    }

    @Test
    fun `everyday descriptions map to sensible categories`() {
        assertEquals(ExpenseCategory.DINING_OUT, ExpenseCategory.suggestion("Dinner at Nopa"))
        assertEquals(ExpenseCategory.TAXI, ExpenseCategory.suggestion("Uber to the airport"))
        assertEquals(ExpenseCategory.HOTEL, ExpenseCategory.suggestion("Airbnb in Alfama"))
        assertEquals(ExpenseCategory.RENT, ExpenseCategory.suggestion("August rent"))
        assertEquals(ExpenseCategory.SUBSCRIPTIONS, ExpenseCategory.suggestion("Netflix"))
        assertNull(ExpenseCategory.suggestion("asdfgh"))
        assertNull(ExpenseCategory.suggestion(""))
    }

    @Test
    fun `every category belongs to exactly one group`() {
        val grouped = com.splitfree.core.CategoryGroup.entries.flatMap { it.categories }
        assertEquals(ExpenseCategory.entries.toSet(), grouped.toSet())
        assertEquals(ExpenseCategory.entries.size, grouped.size)
        assertNotNull(ExpenseCategory.fromWire("diningOut"))
        assertEquals(ExpenseCategory.GENERAL, ExpenseCategory.fromWire("nonsense"))
    }
}
