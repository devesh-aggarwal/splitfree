package com.splitfree.ui.screens

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.splitfree.GroupKind
import com.splitfree.PaymentMethod
import com.splitfree.core.Currencies
import com.splitfree.core.ExpenseCategory
import com.splitfree.core.Money
import com.splitfree.core.SplitCalculator
import com.splitfree.core.SplitMethod
import com.splitfree.data.ExpenseEntity
import com.splitfree.data.GroupEntity
import com.splitfree.data.ParticipantEntity
import com.splitfree.icon
import com.splitfree.ui.LedgerViewModel
import com.splitfree.ui.components.*
import com.splitfree.ui.theme.Metrics
import com.splitfree.ui.theme.MoneyType
import com.splitfree.ui.theme.splitColors

/**
 * A money input that edits minor units directly.
 *
 * Typing appends digits from the right, the way a card terminal behaves, so
 * "1250" becomes $12.50 without anyone hunting for the decimal point. The text
 * shown is always a valid formatted amount.
 */
@Composable
fun MoneyField(
    minorUnits: Long,
    currencyCode: String,
    onChange: (Long) -> Unit,
    modifier: Modifier = Modifier,
    style: TextStyle = MoneyType.display,
    align: TextAlign = TextAlign.Center,
) {
    val colors = splitColors
    val focusManager = LocalFocusManager.current
    var digits by remember(currencyCode) { mutableStateOf(if (minorUnits == 0L) "" else minorUnits.toString()) }
    var focused by remember { mutableStateOf(false) }

    LaunchedEffect(minorUnits) {
        val expected = if (minorUnits == 0L) "" else minorUnits.toString()
        if (expected != digits) digits = expected
    }

    BasicTextField(
        value = digits,
        onValueChange = { raw ->
            val filtered = raw.filter { it.isDigit() }.take(12)
            digits = filtered
            onChange(filtered.toLongOrNull() ?: 0L)
        },
        modifier = modifier.onFocusChanged { focused = it.isFocused },
        textStyle = style.copy(
            color = if (minorUnits == 0L) colors.tertiaryText else colors.primaryText,
            textAlign = align,
        ),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
        cursorBrush = androidx.compose.ui.graphics.SolidColor(Color.Transparent),
        singleLine = true,
        decorationBox = {
            // The rendered amount replaces the raw digits, so the field draws
            // its own caret: without one there is no sign the keypad is live.
            val boxAlignment = when (align) {
                TextAlign.Start, TextAlign.Left -> Alignment.CenterStart
                TextAlign.End, TextAlign.Right -> Alignment.CenterEnd
                else -> Alignment.Center
            }
            Box(Modifier.fillMaxWidth(), contentAlignment = boxAlignment) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        Money(minorUnits, currencyCode).formatted(),
                        style = style,
                        color = if (minorUnits == 0L) colors.tertiaryText else colors.primaryText,
                    )
                    if (focused) {
                        val blink by rememberInfiniteTransition(label = "caret").animateFloat(
                            initialValue = 1f,
                            targetValue = 0f,
                            animationSpec = infiniteRepeatable(tween(500), RepeatMode.Reverse),
                            label = "caretAlpha",
                        )
                        Spacer(Modifier.width(2.dp))
                        Box(
                            Modifier
                                .width(2.5.dp)
                                .height(with(LocalDensity.current) { style.fontSize.toDp() })
                                .alpha(blink)
                                .background(colors.accent, RoundedCornerShape(1.25.dp)),
                        )
                    }
                }
            }
        },
    )
}

// MARK: - Group editor

@Composable
fun GroupEditorScreen(viewModel: LedgerViewModel, groupId: String?, onDone: () -> Unit) {
    val colors = splitColors
    val ledger by viewModel.ledger.collectAsState()
    val settings by viewModel.settings.collectAsState()
    val existing = ledger.group(groupId)

    var name by remember(existing?.id) { mutableStateOf(existing?.name ?: "") }
    var kind by remember(existing?.id) { mutableStateOf(GroupKind.fromWire(existing?.kind ?: "trip")) }
    var colorIndex by remember(existing?.id) { mutableStateOf(existing?.colorIndex ?: 4) }
    var currency by remember(existing?.id) {
        mutableStateOf(existing?.defaultCurrencyCode ?: settings.baseCurrencyCode)
    }
    var simplify by remember(existing?.id) {
        mutableStateOf(existing?.simplifyDebts ?: settings.simplifyDebtsByDefault)
    }
    var memberIds by remember(existing?.id) {
        mutableStateOf(
            ledger.memberships.filter { it.groupId == groupId }.map { it.participantId }.toSet()
        )
    }
    var newMember by remember { mutableStateOf("") }
    var showCurrency by remember { mutableStateOf(false) }

    val friends = ledger.participants.filter { !it.isCurrentUser && !it.isArchived }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .padding(Metrics.screenPadding),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onDone) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = colors.primaryText) }
            Text(
                if (existing == null) "New group" else "Group settings",
                style = MaterialTheme.typography.titleLarge,
                color = colors.primaryText,
                modifier = Modifier.weight(1f),
            )
            TextButton(
                onClick = {
                    viewModel.saveGroup(existing, name, kind, colorIndex, currency, simplify, memberIds.toList())
                    onDone()
                },
                enabled = name.isNotBlank(),
            ) { Text(if (existing == null) "Create" else "Save", fontWeight = FontWeight.SemiBold) }
        }

        SplitCard {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Group name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        SplitCard {
            Overline("Type")
            Spacer(Modifier.height(10.dp))
            FlowRowSimple(GroupKind.entries) { option ->
                Chip(option.label, kind == option, icon = option.kindIcon()) { kind = option }
            }
            Spacer(Modifier.height(16.dp))
            Overline("Color")
            Spacer(Modifier.height(10.dp))
            LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                items(colors.avatarColors.size) { index ->
                    Box(
                        modifier = Modifier
                            .size(32.dp)
                            .clip(CircleShape)
                            .background(colors.groupColor(index))
                            .clickable { colorIndex = index },
                        contentAlignment = Alignment.Center,
                    ) {
                        if (colorIndex == index) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(16.dp))
                    }
                }
            }
        }

        SplitCard {
            SectionHeader("Members", "${memberIds.size + 1} selected")
            Spacer(Modifier.height(12.dp))
            ledger.currentUser?.let { me ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(me, size = 34.dp)
                    Spacer(Modifier.width(10.dp))
                    Text("You", color = colors.primaryText, modifier = Modifier.weight(1f))
                    Text("always included", style = MaterialTheme.typography.bodySmall, color = colors.tertiaryText)
                }
            }
            friends.forEach { friend ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            memberIds = if (friend.id in memberIds) memberIds - friend.id else memberIds + friend.id
                        }
                        .padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Avatar(friend, size = 34.dp, dimmed = friend.id !in memberIds)
                    Spacer(Modifier.width(10.dp))
                    Text(friend.fullName, color = colors.primaryText, modifier = Modifier.weight(1f))
                    Icon(
                        if (friend.id in memberIds) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                        null,
                        tint = if (friend.id in memberIds) colors.accent else colors.separator,
                    )
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = newMember,
                    onValueChange = { newMember = it },
                    label = { Text("Add someone new") },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                if (newMember.isNotBlank()) {
                    TextButton(onClick = {
                        viewModel.addFriend(newMember) { created -> memberIds = memberIds + created.id }
                        newMember = ""
                    }) { Text("Add") }
                }
            }
        }

        SplitCard {
            Row(
                modifier = Modifier.fillMaxWidth().clickable { showCurrency = true }.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Default currency", color = colors.primaryText, fontWeight = FontWeight.Medium)
                    Text(
                        "New expenses in this group start here.",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.secondaryText,
                    )
                }
                Text("${Currencies.flag(currency)} $currency", color = colors.secondaryText)
            }
            HorizontalDivider(color = colors.separator)
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Simplify debts", color = colors.primaryText, fontWeight = FontWeight.Medium)
                    Text(
                        "Collapse balances into the fewest payments.",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.secondaryText,
                    )
                }
                Switch(
                    checked = simplify,
                    onCheckedChange = { simplify = it },
                    colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                )
            }
        }

        if (existing != null) {
            TextButton(onClick = { viewModel.deleteGroup(existing); onDone() }) {
                Text("Delete group", color = colors.negative)
            }
        }
        Spacer(Modifier.height(40.dp))
    }

    if (showCurrency) {
        CurrencyPickerSheet(currency, { currency = it; showCurrency = false }, { showCurrency = false })
    }
}

/** A simple wrapping row; Compose's FlowRow is still experimental in this setup. */
@Composable
private fun <T> FlowRowSimple(items: List<T>, content: @Composable (T) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { content(it) }
            }
        }
    }
}

// MARK: - Group detail

@Composable
fun GroupDetailScreen(
    viewModel: LedgerViewModel,
    groupId: String,
    onBack: () -> Unit,
    onAddExpense: (String) -> Unit,
    onEditExpense: (String) -> Unit,
    onEditGroup: (String) -> Unit,
    onShare: (String) -> Unit = {},
) {
    val colors = splitColors
    val ledger by viewModel.ledger.collectAsState()
    val group = ledger.group(groupId) ?: return
    val members = ledger.members(groupId)
    val sheet = ledger.sheetFor(group)
    val summary = ledger.summaryFor(group)
    val expenses = ledger.expensesIn(groupId).sortedByDescending { it.entity.date }
    val settlements = ledger.settlementsIn(groupId).sortedByDescending { it.date }
    val me = ledger.currentUser?.id
    var settleTarget by remember { mutableStateOf<Triple<String, String, Long>?>(null) }

    val money = if (summary.net.nonZeroCurrencies.size == 1) {
        val code = summary.net.nonZeroCurrencies.first()
        Money(summary.net.amount(code), code)
    } else Money(0, group.defaultCurrencyCode)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .padding(Metrics.screenPadding),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = colors.primaryText) }
            Text(
                group.displayName,
                style = MaterialTheme.typography.titleLarge,
                color = colors.primaryText,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = { onShare(groupId) }) {
                Icon(
                    if (group.isShared) Icons.Filled.CloudDone else Icons.Filled.PersonAdd,
                    if (group.isShared) "Sharing and invites" else "Share with friends",
                    tint = if (group.isShared) colors.positive else colors.primaryText,
                )
            }
            IconButton(onClick = { onEditGroup(groupId) }) {
                Icon(Icons.Filled.Settings, "Group settings", tint = colors.primaryText)
            }
        }

        SplitCard(padding = PaddingValues(18.dp)) {
            AvatarStack(members, maxVisible = 6)
            Spacer(Modifier.height(14.dp))
            HorizontalDivider(color = colors.separator)
            Spacer(Modifier.height(14.dp))
            Overline(
                when {
                    summary.isSettled -> "Everyone's settled up"
                    money.minorUnits > 0 -> "You get back"
                    else -> "You owe"
                }
            )
            if (!summary.isSettled) {
                Text(
                    money.formattedAbsolute(),
                    style = MoneyType.title,
                    color = colors.forBalance(money.minorUnits),
                )
            }
        }

        Button(
            onClick = { onAddExpense(groupId) },
            modifier = Modifier.fillMaxWidth().height(50.dp),
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
        ) {
            Icon(Icons.Filled.Add, null)
            Spacer(Modifier.width(8.dp))
            Text("Add expense", fontWeight = FontWeight.SemiBold)
        }

        if (sheet.debts.isNotEmpty()) {
            SplitCard {
                SectionHeader(
                    "Balances",
                    if (group.simplifyDebts) "Simplified into the fewest payments" else null,
                )
                Spacer(Modifier.height(10.dp))
                sheet.debts.forEach { debt ->
                    val from = ledger.participant(debt.from)
                    val to = ledger.participant(debt.to)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(enabled = me == debt.from || me == debt.to) {
                                settleTarget = Triple(debt.from, debt.to, debt.amountMinorUnits)
                            }
                            .padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        from?.let { Avatar(it, size = 30.dp) }
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowForward, null,
                            tint = colors.tertiaryText,
                            modifier = Modifier.padding(horizontal = 6.dp).size(14.dp),
                        )
                        to?.let { Avatar(it, size = 30.dp) }
                        Spacer(Modifier.width(10.dp))
                        Text(
                            when (me) {
                                debt.from -> "You owe ${ledger.displayName(debt.to)}"
                                debt.to -> "${ledger.displayName(debt.from)} owes you"
                                else -> "${ledger.displayName(debt.from)} owes ${ledger.displayName(debt.to)}"
                            },
                            color = colors.primaryText,
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        Text(
                            debt.money.formatted(),
                            style = MoneyType.row,
                            color = when (me) {
                                debt.to -> colors.positive
                                debt.from -> colors.negative
                                else -> colors.neutral
                            },
                        )
                    }
                }
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Simplify debts", color = colors.primaryText, fontWeight = FontWeight.Medium)
                        Text(
                            "Collapse balances into the fewest payments.",
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.secondaryText,
                        )
                    }
                    Switch(
                        checked = group.simplifyDebts,
                        onCheckedChange = { viewModel.setGroupSimplify(group, it) },
                        colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                    )
                }
            }
        }

        if (expenses.isEmpty() && settlements.isEmpty()) {
            EmptyState(
                icon = Icons.Filled.Inbox,
                title = "No expenses yet",
                message = "Add the first one and everyone's balance appears here.",
                actionLabel = "Add an expense",
                onAction = { onAddExpense(groupId) },
            )
        } else {
            SplitCard(padding = PaddingValues(0.dp)) {
                expenses.forEach { expense ->
                    val net = me?.let { expense.netFor(it) } ?: 0L
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onEditExpense(expense.id) }
                            .padding(Metrics.cardPadding),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CategoryBadge(
                            colors.categoryColor(ExpenseCategory.fromWire(expense.entity.category).group),
                            ExpenseCategory.fromWire(expense.entity.category).icon(),
                            size = 42.dp,
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(expense.entity.displayTitle, color = colors.primaryText, fontWeight = FontWeight.Medium)
                            Text(
                                expense.payers.firstOrNull()?.let {
                                    "${ledger.displayName(it.participantId)} paid ${expense.total.formatted()}"
                                } ?: "No one paid yet",
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.secondaryText,
                            )
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                if (net > 0) "you lent" else if (net < 0) "you borrowed" else "settled",
                                style = MaterialTheme.typography.labelSmall,
                                color = colors.tertiaryText,
                            )
                            if (net != 0L) {
                                Text(
                                    Money(kotlin.math.abs(net), expense.entity.currencyCode).formatted(),
                                    style = MoneyType.row,
                                    color = colors.forBalance(net),
                                )
                            }
                        }
                    }
                    HorizontalDivider(color = colors.separator)
                }
                settlements.forEach { settlement ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(Metrics.cardPadding),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CategoryBadge(colors.positive, Icons.Filled.Payments, size = 42.dp)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                "${ledger.displayName(settlement.fromParticipantId)} paid " +
                                    "${ledger.displayName(settlement.toParticipantId)} " +
                                    Money(settlement.amountMinorUnits, settlement.currencyCode).formatted(),
                                color = colors.primaryText,
                            )
                            Text(
                                PaymentMethod.fromWire(settlement.method).label,
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.secondaryText,
                            )
                        }
                    }
                    HorizontalDivider(color = colors.separator)
                }
            }
        }
        Spacer(Modifier.height(40.dp))
    }

    settleTarget?.let { (fromId, toId, amount) ->
        RecordPaymentDialog(
            viewModel = viewModel,
            fromName = ledger.displayName(fromId),
            toName = ledger.displayName(toId),
            suggested = amount,
            currencyCode = group.defaultCurrencyCode,
            onConfirm = { value, method ->
                viewModel.recordSettlement(fromId, toId, value, group.defaultCurrencyCode, method, groupId)
                settleTarget = null
            },
            onDismiss = { settleTarget = null },
        )
    }
}

@Composable
private fun RecordPaymentDialog(
    viewModel: LedgerViewModel,
    fromName: String,
    toName: String,
    suggested: Long,
    currencyCode: String,
    onConfirm: (Long, PaymentMethod) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = splitColors
    var amount by remember { mutableStateOf(suggested) }
    var method by remember { mutableStateOf(PaymentMethod.CASH) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Record a payment") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("$fromName pays $toName", color = colors.secondaryText)
                MoneyField(amount, currencyCode, { amount = it }, style = MoneyType.title)
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(PaymentMethod.entries) { option ->
                        Chip(option.label, method == option) { method = option }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(amount, method) }, enabled = amount > 0) { Text("Record") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// MARK: - Expense editor

@Composable
fun ExpenseEditorScreen(
    viewModel: LedgerViewModel,
    expenseId: String?,
    initialGroupId: String?,
    onDone: () -> Unit,
) {
    val colors = splitColors
    val ledger by viewModel.ledger.collectAsState()
    val settings by viewModel.settings.collectAsState()
    val existing = ledger.expenses.firstOrNull { it.id == expenseId }
    val me = ledger.currentUser

    var groupId by remember(expenseId) { mutableStateOf(existing?.entity?.groupId ?: initialGroupId) }
    val group = ledger.group(groupId)
    val candidates = remember(groupId, ledger) {
        if (groupId != null) ledger.members(groupId!!)
        else ledger.participants.filter { !it.isArchived }
    }

    var amount by remember(expenseId) { mutableStateOf(existing?.entity?.amountMinorUnits ?: 0L) }
    var title by remember(expenseId) { mutableStateOf(existing?.entity?.title ?: "") }
    var currency by remember(expenseId) {
        mutableStateOf(existing?.entity?.currencyCode ?: group?.defaultCurrencyCode ?: settings.baseCurrencyCode)
    }
    var category by remember(expenseId) {
        mutableStateOf(ExpenseCategory.fromWire(existing?.entity?.category ?: "general"))
    }
    var manualCategory by remember(expenseId) { mutableStateOf(existing != null) }
    var method by remember(expenseId) {
        mutableStateOf(SplitMethod.fromWire(existing?.entity?.splitMethod ?: "equal"))
    }
    var payerId by remember(expenseId, me) {
        mutableStateOf(existing?.payers?.firstOrNull()?.participantId ?: me?.id)
    }
    var included by remember(expenseId, candidates) {
        mutableStateOf(
            existing?.shares?.map { it.participantId }?.toSet() ?: candidates.map { it.id }.toSet()
        )
    }
    var values by remember(expenseId) {
        mutableStateOf(
            existing?.shares?.associate { it.participantId to it.weight } ?: emptyMap<String, Double>()
        )
    }
    var showCurrency by remember { mutableStateOf(false) }
    var showCategory by remember { mutableStateOf(false) }
    var showGroupPicker by remember { mutableStateOf(false) }

    fun defaultValue(): Double = when (method) {
        SplitMethod.PERCENT -> if (included.isEmpty()) 0.0 else 100.0 / included.size
        SplitMethod.EQUAL, SplitMethod.SHARES, SplitMethod.ITEMIZED -> 1.0
        SplitMethod.EXACT, SplitMethod.ADJUSTMENT -> 0.0
    }

    val entries = candidates.map { person ->
        SplitCalculator.Entry(person.id, person.id in included, values[person.id] ?: defaultValue())
    }
    val allocations = SplitCalculator.resolve(method, amount, entries)
    val issue = SplitCalculator.validate(method, amount, currency, entries)
    val canSave = amount > 0 && included.isNotEmpty() && payerId != null && issue == null

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .padding(Metrics.screenPadding),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDone) { Text("Cancel") }
            Text(
                if (existing == null) "New expense" else "Edit expense",
                style = MaterialTheme.typography.titleMedium,
                color = colors.primaryText,
                modifier = Modifier.weight(1f),
                textAlign = TextAlign.Center,
            )
            TextButton(
                enabled = canSave,
                onClick = {
                    viewModel.saveExpense(
                        existing = existing?.entity,
                        title = title,
                        amountMinorUnits = amount,
                        currencyCode = currency,
                        dateMillis = existing?.entity?.date ?: System.currentTimeMillis(),
                        category = category,
                        groupId = groupId,
                        splitMethod = method,
                        payerIds = mapOf(payerId!! to amount),
                        entries = entries,
                    )
                    onDone()
                },
            ) { Text("Save", fontWeight = FontWeight.SemiBold) }
        }

        SplitCard(padding = PaddingValues(20.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
            ) {
                Surface(
                    shape = CircleShape,
                    color = colors.surfaceSunken,
                    modifier = Modifier.clickable { showCurrency = true },
                ) {
                    Text(
                        "${Currencies.flag(currency)} $currency",
                        modifier = Modifier.padding(horizontal = 11.dp, vertical = 6.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.secondaryText,
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            MoneyField(amount, currency, { amount = it }, modifier = Modifier.fillMaxWidth())
        }

        SplitCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(modifier = Modifier.clickable { showCategory = true }) {
                    CategoryBadge(colors.categoryColor(category.group), category.icon(), size = 40.dp)
                }
                Spacer(Modifier.width(12.dp))
                OutlinedTextField(
                    value = title,
                    onValueChange = {
                        title = it
                        if (!manualCategory) {
                            ExpenseCategory.suggestion(it)?.let { suggested -> category = suggested }
                        }
                    },
                    label = { Text("What was it for?") },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
            }
            HorizontalDivider(color = colors.separator, modifier = Modifier.padding(vertical = 8.dp))
            Row(
                modifier = Modifier.fillMaxWidth().clickable { showGroupPicker = true }.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Groups, null, tint = colors.secondaryText)
                Spacer(Modifier.width(12.dp))
                Text("Group", color = colors.primaryText, modifier = Modifier.weight(1f))
                Text(group?.displayName ?: "No group", color = colors.secondaryText)
                Icon(Icons.Filled.ChevronRight, null, tint = colors.tertiaryText)
            }
        }

        SplitCard {
            SectionHeader("Paid by")
            Spacer(Modifier.height(10.dp))
            LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                items(candidates, key = { it.id }) { person ->
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.clickable { payerId = person.id }.width(64.dp),
                    ) {
                        Avatar(person, size = 44.dp, showsRing = payerId == person.id, dimmed = payerId != person.id)
                        Text(
                            if (person.id == me?.id) "You" else person.firstName,
                            style = MaterialTheme.typography.labelSmall,
                            color = colors.secondaryText,
                            maxLines = 1,
                        )
                    }
                }
            }
        }

        SplitCard {
            SectionHeader("Split", method.label())
            Spacer(Modifier.height(10.dp))
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(SplitMethod.entries) { option ->
                    Chip(option.label(), method == option) {
                        method = option
                        values = emptyMap()
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
            candidates.forEach { person ->
                val allocated = allocations.firstOrNull { it.participantId == person.id }?.amountMinorUnits ?: 0L
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier.clickable {
                            included = if (person.id in included && included.size > 1) included - person.id
                            else included + person.id
                        }
                    ) { Avatar(person, size = 36.dp, dimmed = person.id !in included) }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            if (person.id == me?.id) "You" else person.fullName,
                            color = if (person.id in included) colors.primaryText else colors.tertiaryText,
                        )
                        if (person.id in included) {
                            Text(
                                Money(allocated, currency).formatted(),
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.secondaryText,
                            )
                        }
                    }
                    if (person.id in included && method != SplitMethod.EQUAL && method != SplitMethod.ITEMIZED) {
                        SplitValueField(
                            method = method,
                            currencyCode = currency,
                            value = values[person.id] ?: defaultValue(),
                            onChange = { values = values + (person.id to it) },
                        )
                    }
                }
            }
            if (issue != null && amount > 0) {
                Spacer(Modifier.height(8.dp))
                RemainderBanner(
                    remainder = (issue as? SplitCalculator.ValidationIssue.AmountsDontAddUp)?.remainder ?: 1L,
                    currencyCode = currency,
                )
            } else if (amount > 0) {
                Spacer(Modifier.height(8.dp))
                RemainderBanner(remainder = 0, currencyCode = currency)
            }
        }

        if (existing != null) {
            TextButton(onClick = { viewModel.deleteExpense(existing.entity); onDone() }) {
                Text("Delete expense", color = colors.negative)
            }
        }
        Spacer(Modifier.height(40.dp))
    }

    if (showCurrency) {
        CurrencyPickerSheet(currency, { currency = it; showCurrency = false }, { showCurrency = false })
    }
    if (showCategory) {
        CategoryPickerSheet(category, { category = it; manualCategory = true; showCategory = false }) {
            showCategory = false
        }
    }
    if (showGroupPicker) {
        GroupPickerSheet(ledger.groups.filter { !it.isArchived && !it.isDirect }, groupId, {
            groupId = it
            showGroupPicker = false
        }) { showGroupPicker = false }
    }
}

@Composable
private fun SplitValueField(
    method: SplitMethod,
    currencyCode: String,
    value: Double,
    onChange: (Double) -> Unit,
) {
    val colors = splitColors
    when (method) {
        SplitMethod.EXACT, SplitMethod.ADJUSTMENT -> {
            Surface(shape = RoundedCornerShape(10.dp), color = colors.surfaceSunken) {
                MoneyField(
                    minorUnits = value.toLong(),
                    currencyCode = currencyCode,
                    onChange = { onChange(it.toDouble()) },
                    modifier = Modifier.width(110.dp).padding(horizontal = 8.dp, vertical = 6.dp),
                    style = MoneyType.row,
                    align = TextAlign.End,
                )
            }
        }
        SplitMethod.PERCENT, SplitMethod.SHARES -> {
            var text by remember(value) {
                mutableStateOf(if (value == 0.0) "" else value.trimTrailingZeros())
            }
            Surface(shape = RoundedCornerShape(10.dp), color = colors.surfaceSunken) {
                Row(
                    modifier = Modifier.width(96.dp).padding(horizontal = 8.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    BasicTextField(
                        value = text,
                        onValueChange = {
                            text = it.filter { c -> c.isDigit() || c == '.' }
                            onChange(text.toDoubleOrNull() ?: 0.0)
                        },
                        textStyle = MoneyType.row.copy(color = colors.primaryText, textAlign = TextAlign.End),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        if (method == SplitMethod.PERCENT) "%" else "×",
                        color = colors.secondaryText,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
        else -> Unit
    }
}

private fun Double.trimTrailingZeros(): String =
    if (this == toLong().toDouble()) toLong().toString() else toString()

fun SplitMethod.label(): String = when (this) {
    SplitMethod.EQUAL -> "Equally"
    SplitMethod.EXACT -> "Exact amounts"
    SplitMethod.PERCENT -> "Percentages"
    SplitMethod.SHARES -> "Shares"
    SplitMethod.ADJUSTMENT -> "Plus/minus"
    SplitMethod.ITEMIZED -> "By item"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CategoryPickerSheet(
    selected: ExpenseCategory,
    onPick: (ExpenseCategory) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = splitColors
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.surface) {
        androidx.compose.foundation.lazy.grid.LazyVerticalGrid(
            columns = androidx.compose.foundation.lazy.grid.GridCells.Adaptive(88.dp),
            modifier = Modifier.padding(horizontal = Metrics.screenPadding).fillMaxHeight(0.85f),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            gridItems(ExpenseCategory.entries.toList()) { category ->
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.clickable { onPick(category) }.padding(vertical = 8.dp),
                ) {
                    CategoryBadge(colors.categoryColor(category.group), category.icon(), size = 46.dp)
                    Spacer(Modifier.height(6.dp))
                    Text(
                        category.name.lowercase().replace('_', ' ').replaceFirstChar { it.uppercase() },
                        style = MaterialTheme.typography.labelSmall,
                        color = if (category == selected) colors.accent else colors.primaryText,
                        textAlign = TextAlign.Center,
                        maxLines = 2,
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GroupPickerSheet(
    groups: List<GroupEntity>,
    selected: String?,
    onPick: (String?) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = splitColors
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.surface) {
        Column(Modifier.padding(Metrics.screenPadding)) {
            Row(
                modifier = Modifier.fillMaxWidth().clickable { onPick(null) }.padding(vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("No group", color = colors.primaryText, modifier = Modifier.weight(1f))
                if (selected == null) Icon(Icons.Filled.Check, null, tint = colors.accent)
            }
            groups.forEach { group ->
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { onPick(group.id) }.padding(vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(group.displayName, color = colors.primaryText, modifier = Modifier.weight(1f))
                    if (selected == group.id) Icon(Icons.Filled.Check, null, tint = colors.accent)
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}
