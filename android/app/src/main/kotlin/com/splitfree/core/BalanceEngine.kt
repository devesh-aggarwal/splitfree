package com.splitfree.core

/** One person owing another a specific amount in a specific currency. */
data class Debt(
    val from: String,
    val to: String,
    val amountMinorUnits: Long,
    val currencyCode: String,
) {
    val id: String get() = "$from-$to-$currencyCode"
    val money: Money get() = Money(amountMinorUnits, currencyCode)
}

/** A person's position, which may span several currencies. */
data class NetPosition(val byCurrency: Map<String, Long> = emptyMap()) {

    val isSettled: Boolean get() = byCurrency.values.all { it == 0L }

    val nonZeroCurrencies: List<String>
        get() = byCurrency.filterValues { it != 0L }.keys.sorted()

    fun amount(currencyCode: String): Long = byCurrency[currencyCode] ?: 0

    fun adding(minorUnits: Long, currencyCode: String): NetPosition =
        NetPosition(byCurrency + (currencyCode to (byCurrency[currencyCode] ?: 0) + minorUnits))

    /**
     * Collapses every currency into one figure using the supplied rates.
     * Only meaningful for headline totals, never for settling up.
     */
    fun converted(baseCode: String, rates: ExchangeRateTable): Money {
        val total = byCurrency.entries.sumOf { (code, amount) ->
            rates.convert(amount, code, baseCode)
        }
        return Money(total, baseCode)
    }
}

/** Everything the UI needs to describe who owes whom. */
data class BalanceSheet(
    val positions: Map<String, NetPosition> = emptyMap(),
    /** Concrete "A pays B" instructions, already netted between each pair. */
    val debts: List<Debt> = emptyList(),
) {
    fun position(id: String): NetPosition = positions[id] ?: NetPosition()
    val isFullySettled: Boolean get() = debts.isEmpty()
    fun debts(involving: String): List<Debt> = debts.filter { it.from == involving || it.to == involving }
}

/**
 * Input shapes the engine reads. Deliberately plain data so the engine has no
 * dependency on Room, and the same code runs in unit tests with no database.
 */
data class ExpenseLedgerEntry(
    val currencyCode: String,
    /** participant id to amount paid. */
    val payers: List<Pair<String, Long>>,
    /** participant id to amount owed. */
    val shares: List<Pair<String, Long>>,
)

data class SettlementLedgerEntry(
    val from: String,
    val to: String,
    val amountMinorUnits: Long,
    val currencyCode: String,
)

/**
 * Derives balances from expenses and settlements.
 *
 * Two modes, matching what people expect:
 * - **Detailed** keeps the actual pairwise history. If you paid for Ana's dinner
 *   and Ben paid for yours, you owe Ben and Ana owes you.
 * - **Simplified** collapses the graph so the group settles in the fewest
 *   possible payments, even if that means paying someone you never dined with.
 *
 * Ported from the iOS `BalanceEngine`, including the deterministic tie-breaking,
 * so both platforms produce the same payment list for the same ledger.
 */
object BalanceEngine {

    private data class PairKey(val from: String, val to: String, val currencyCode: String)

    data class Transfer(val from: String, val to: String, val amount: Long)

    private data class Party(val id: String, var amount: Long)

    fun balanceSheet(
        expenses: List<ExpenseLedgerEntry>,
        settlements: List<SettlementLedgerEntry>,
        simplify: Boolean,
    ): BalanceSheet {
        var ledger = pairwiseLedger(expenses, settlements)
        ledger = netMutualDebts(ledger)

        val positions = HashMap<String, NetPosition>()
        for ((key, amount) in ledger) {
            if (amount == 0L) continue
            positions[key.from] = (positions[key.from] ?: NetPosition()).adding(-amount, key.currencyCode)
            positions[key.to] = (positions[key.to] ?: NetPosition()).adding(amount, key.currencyCode)
        }

        val debts = if (simplify) {
            simplifiedDebts(positions)
        } else {
            ledger.filterValues { it > 0 }
                .map { (key, amount) -> Debt(key.from, key.to, amount, key.currencyCode) }
                .sortedWith(compareBy<Debt> { it.currencyCode }.thenByDescending { it.amountMinorUnits })
        }

        return BalanceSheet(positions, debts)
    }

    /** A person's overall standing across every group and one-off expense. */
    fun overallPosition(
        participantId: String,
        expenses: List<ExpenseLedgerEntry>,
        settlements: List<SettlementLedgerEntry>,
    ): NetPosition {
        var position = NetPosition()
        for (expense in expenses) {
            val paid = expense.payers.filter { it.first == participantId }.sumOf { it.second }
            val owed = expense.shares.filter { it.first == participantId }.sumOf { it.second }
            val net = paid - owed
            if (net != 0L) position = position.adding(net, expense.currencyCode)
        }
        for (settlement in settlements) {
            when (participantId) {
                settlement.from -> position = position.adding(settlement.amountMinorUnits, settlement.currencyCode)
                settlement.to -> position = position.adding(-settlement.amountMinorUnits, settlement.currencyCode)
            }
        }
        return position
    }

    /**
     * Builds "X owes Y" edges expense by expense.
     *
     * Within a single expense we settle the people who underpaid against the
     * people who overpaid using the same greedy match as debt simplification.
     * That keeps the edge count small while staying faithful to who actually
     * benefited from whose money.
     */
    private fun pairwiseLedger(
        expenses: List<ExpenseLedgerEntry>,
        settlements: List<SettlementLedgerEntry>,
    ): Map<PairKey, Long> {
        val ledger = HashMap<PairKey, Long>()

        for (expense in expenses) {
            val nets = HashMap<String, Long>()
            for ((id, amount) in expense.payers) nets[id] = (nets[id] ?: 0) + amount
            for ((id, amount) in expense.shares) nets[id] = (nets[id] ?: 0) - amount

            for (transfer in greedyTransfers(nets)) {
                val key = PairKey(transfer.from, transfer.to, expense.currencyCode)
                ledger[key] = (ledger[key] ?: 0) + transfer.amount
            }
        }

        // A payment from A to B cancels A's debt to B.
        for (settlement in settlements) {
            if (settlement.from == settlement.to) continue
            val key = PairKey(settlement.from, settlement.to, settlement.currencyCode)
            ledger[key] = (ledger[key] ?: 0) - settlement.amountMinorUnits
        }

        return ledger
    }

    /** Collapses A to B and B to A into one net edge, always pointing forward. */
    private fun netMutualDebts(ledger: Map<PairKey, Long>): Map<PairKey, Long> {
        val working = HashMap(ledger)
        for (key in working.keys.toList()) {
            val forward = working[key] ?: continue
            if (forward == 0L) continue
            val reverseKey = PairKey(key.to, key.from, key.currencyCode)
            val backward = working[reverseKey] ?: continue
            if (backward == 0L) continue
            val net = forward - backward
            if (net > 0) {
                working[key] = net
                working[reverseKey] = 0
            } else {
                working[key] = 0
                working[reverseKey] = -net
            }
        }

        // Flip any negative edge rather than showing "A owes B -$5".
        val flipped = HashMap<PairKey, Long>()
        for ((key, amount) in working) {
            if (amount == 0L) continue
            if (amount < 0) {
                val reverseKey = PairKey(key.to, key.from, key.currencyCode)
                flipped[reverseKey] = (flipped[reverseKey] ?: 0) + -amount
            } else {
                flipped[key] = (flipped[key] ?: 0) + amount
            }
        }
        return flipped.filterValues { it != 0L }
    }

    /**
     * Rebuilds the debt graph as the fewest payments that settle everyone.
     *
     * Repeatedly matches the largest debtor with the largest creditor. For *n*
     * people with a non-zero balance this always terminates in at most *n - 1*
     * transfers, because each step zeroes out at least one person.
     */
    private fun simplifiedDebts(positions: Map<String, NetPosition>): List<Debt> {
        val currencies = positions.values.flatMap { it.byCurrency.keys }.toSortedSet()

        val result = ArrayList<Debt>()
        for (currency in currencies) {
            val nets = HashMap<String, Long>()
            for ((id, position) in positions) {
                val amount = position.amount(currency)
                if (amount != 0L) nets[id] = amount
            }
            result += greedyTransfers(nets).map { Debt(it.from, it.to, it.amount, currency) }
        }
        return result.sortedWith(
            compareBy<Debt> { it.currencyCode }.thenByDescending { it.amountMinorUnits }
        )
    }

    /**
     * Greedy largest-debtor-to-largest-creditor matching.
     *
     * [nets] maps a person to their signed balance; positive means they are owed.
     * Sorting by id as a tiebreaker keeps the output stable, so the settle-up
     * screen doesn't reshuffle between launches or between phones.
     */
    fun greedyTransfers(nets: Map<String, Long>): List<Transfer> {
        val byAmountThenId = compareByDescending<Party> { it.amount }.thenBy { it.id }

        val creditors = nets.filterValues { it > 0 }
            .map { Party(it.key, it.value) }
            .sortedWith(byAmountThenId)
            .toMutableList()
        val debtors = nets.filterValues { it < 0 }
            .map { Party(it.key, -it.value) }
            .sortedWith(byAmountThenId)
            .toMutableList()

        val transfers = ArrayList<Transfer>()
        var creditorIndex = 0
        var debtorIndex = 0

        while (creditorIndex < creditors.size && debtorIndex < debtors.size) {
            val amount = minOf(creditors[creditorIndex].amount, debtors[debtorIndex].amount)
            if (amount > 0) {
                transfers += Transfer(debtors[debtorIndex].id, creditors[creditorIndex].id, amount)
            }
            creditors[creditorIndex].amount -= amount
            debtors[debtorIndex].amount -= amount
            if (creditors[creditorIndex].amount == 0L) creditorIndex++
            if (debtors[debtorIndex].amount == 0L) debtorIndex++
        }

        return transfers
    }

    /** How many payments simplification would save, for the toggle's subtitle. */
    fun simplificationSaving(
        expenses: List<ExpenseLedgerEntry>,
        settlements: List<SettlementLedgerEntry>,
    ): Pair<Int, Int> {
        val detailed = balanceSheet(expenses, settlements, simplify = false).debts.size
        val simplified = balanceSheet(expenses, settlements, simplify = true).debts.size
        return detailed to simplified
    }
}
