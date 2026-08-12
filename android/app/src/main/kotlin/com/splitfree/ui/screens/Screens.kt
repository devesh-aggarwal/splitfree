package com.splitfree.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.splitfree.GroupKind
import com.splitfree.core.Currencies
import com.splitfree.core.ExpenseCategory
import com.splitfree.core.Money
import com.splitfree.data.BalanceSummary
import com.splitfree.data.GroupEntity
import com.splitfree.data.Ledger
import com.splitfree.data.ParticipantEntity
import com.splitfree.icon
import com.splitfree.sync.SyncEngine
import com.splitfree.ui.LedgerViewModel
import com.splitfree.ui.components.*
import com.splitfree.ui.theme.AppearanceSetting
import com.splitfree.ui.theme.Metrics
import com.splitfree.ui.theme.MoneyType
import com.splitfree.ui.theme.splitColors
import kotlinx.coroutines.launch
import java.io.File

/** Rolls a summary into the one figure the headline shows. */
@Composable
private fun headlineAmount(summary: BalanceSummary, baseCode: String): Money {
    val codes = summary.net.nonZeroCurrencies
    return if (codes.size == 1) {
        Money(summary.net.amount(codes.first()), codes.first())
    } else {
        summary.net.converted(baseCode, com.splitfree.core.ExchangeRateTable.bundled)
    }
}

// MARK: - Onboarding

@Composable
fun OnboardingScreen(viewModel: LedgerViewModel) {
    val colors = splitColors
    var name by remember { mutableStateOf("") }
    var currency by remember { mutableStateOf(Currencies.deviceDefault()) }
    var showCurrencyPicker by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .padding(Metrics.screenPadding)
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Spacer(Modifier.height(60.dp))
        Box(
            modifier = Modifier
                .size(140.dp)
                .clip(androidx.compose.foundation.shape.CircleShape)
                .background(colors.accentSoft),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.PieChart, null, tint = colors.accent, modifier = Modifier.size(60.dp))
        }
        Spacer(Modifier.height(24.dp))
        Text(
            "Split anything, fairly",
            style = MaterialTheme.typography.headlineLarge,
            color = colors.primaryText,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(10.dp))
        Text(
            "Track shared expenses with friends, flatmates and travel companions. " +
                "Everyone's balance stays exact, down to the last cent.",
            style = MaterialTheme.typography.bodyMedium,
            color = colors.secondaryText,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(28.dp))

        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text("Your name") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
        )
        Spacer(Modifier.height(12.dp))
        SplitCard(onClick = { showCurrencyPicker = true }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(Currencies.flag(currency), fontSize = 24.sp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(Currencies.name(currency), color = colors.primaryText, fontWeight = FontWeight.SemiBold)
                    Text(
                        "$currency · ${Currencies.symbol(currency)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.secondaryText,
                    )
                }
                Icon(Icons.Filled.ChevronRight, null, tint = colors.tertiaryText)
            }
        }
        Spacer(Modifier.height(24.dp))
        Button(
            onClick = { viewModel.completeOnboarding(name, currency) },
            enabled = name.isNotBlank(),
            modifier = Modifier.fillMaxWidth().height(52.dp),
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
        ) { Text("Start splitting", fontWeight = FontWeight.SemiBold) }
        Spacer(Modifier.height(40.dp))
    }

    if (showCurrencyPicker) {
        CurrencyPickerSheet(
            selected = currency,
            onPick = { currency = it; showCurrencyPicker = false },
            onDismiss = { showCurrencyPicker = false },
        )
    }
}

// MARK: - Groups

@Composable
fun GroupsScreen(
    viewModel: LedgerViewModel,
    onOpenGroup: (String) -> Unit,
    onNewGroup: () -> Unit,
) {
    val colors = splitColors
    val ledger by viewModel.ledger.collectAsState()
    val settings by viewModel.settings.collectAsState()
    // Friendships are two-person groups underneath, but they belong on the
    // Friends tab. Showing them here would list every friend twice.
    val active = ledger.groups.filter { !it.isArchived && !it.isDirect }

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(colors.background),
        contentPadding = PaddingValues(Metrics.screenPadding),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Groups", style = MaterialTheme.typography.headlineLarge, color = colors.primaryText)
                Spacer(Modifier.weight(1f))
                // Text, not another "+": the floating button owns that glyph.
                TextButton(onClick = onNewGroup) {
                    Text("New group", color = colors.accent, fontWeight = FontWeight.SemiBold)
                }
            }
        }

        item { OverallBalanceCard(ledger.overallSummary(), settings.baseCurrencyCode) }

        if (active.isEmpty()) {
            item {
                EmptyState(
                    icon = Icons.Filled.Groups,
                    title = "No groups yet",
                    message = "Groups keep a trip, a flat, or a running tab in one place. " +
                        "Everyone's balance updates as you add expenses.",
                    actionLabel = "Create a group",
                    onAction = onNewGroup,
                )
            }
        } else {
            items(active, key = { it.id }) { group ->
                GroupRow(
                    group = group,
                    members = ledger.members(group.id),
                    summary = ledger.summaryFor(group),
                    baseCode = settings.baseCurrencyCode,
                    onClick = { onOpenGroup(group.id) },
                )
            }
        }
        item { Spacer(Modifier.height(72.dp)) }
    }
}

@Composable
fun OverallBalanceCard(summary: BalanceSummary, baseCode: String) {
    val colors = splitColors
    val money = headlineAmount(summary, baseCode)
    SplitCard(padding = PaddingValues(20.dp)) {
        Overline(
            when {
                summary.isSettled -> "Total balance"
                money.minorUnits > 0 -> "Overall, you get back"
                else -> "Overall, you owe"
            }
        )
        Spacer(Modifier.height(6.dp))
        if (summary.isSettled) {
            Text(
                "You're all settled up",
                style = MoneyType.title,
                color = colors.neutral,
            )
        } else {
            Text(
                money.formattedAbsolute(),
                style = MoneyType.display,
                color = colors.forBalance(money.minorUnits),
            )
        }
        // Only worth breaking out when money moves both ways; otherwise the chip
        // just repeats the headline.
        if (!summary.owedToYou.isSettled && !summary.youOwe.isSettled) {
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                BalanceChip("you get back", summary.owedToYou.converted(baseCode, com.splitfree.core.ExchangeRateTable.bundled), colors.positive)
                BalanceChip("you owe", summary.youOwe.converted(baseCode, com.splitfree.core.ExchangeRateTable.bundled), colors.negative)
            }
        }
    }
}

@Composable
private fun BalanceChip(label: String, money: Money, tint: androidx.compose.ui.graphics.Color) {
    val colors = splitColors
    Surface(
        shape = androidx.compose.foundation.shape.RoundedCornerShape(10.dp),
        color = tint.copy(alpha = 0.11f),
    ) {
        Column(Modifier.padding(horizontal = 11.dp, vertical = 7.dp)) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = colors.secondaryText)
            Text(money.formattedAbsolute(), style = MoneyType.caption, color = tint)
        }
    }
}

@Composable
private fun GroupRow(
    group: GroupEntity,
    members: List<ParticipantEntity>,
    summary: BalanceSummary,
    baseCode: String,
    onClick: () -> Unit,
) {
    val colors = splitColors
    val money = headlineAmount(summary, baseCode)
    SplitCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(14.dp))
                    .background(colors.groupColor(group.colorIndex)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(GroupKind.fromWire(group.kind).kindIcon(), null, tint = androidx.compose.ui.graphics.Color.White)
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(group.displayName, color = colors.primaryText, fontWeight = FontWeight.Medium)
                Spacer(Modifier.height(5.dp))
                AvatarStack(members, maxVisible = 5)
            }
            Column(horizontalAlignment = Alignment.End) {
                if (summary.isSettled) {
                    Text("settled up", color = colors.neutral, style = MaterialTheme.typography.bodyMedium)
                } else {
                    Text(
                        if (money.minorUnits > 0) "you get back" else "you owe",
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.tertiaryText,
                    )
                    Text(
                        money.formattedAbsolute(),
                        style = MoneyType.row,
                        color = colors.forBalance(money.minorUnits),
                    )
                }
            }
        }
    }
}

@Composable
fun GroupKind.kindIcon() = when (this) {
    GroupKind.TRIP -> Icons.Filled.Flight
    GroupKind.HOME -> Icons.Filled.Home
    GroupKind.COUPLE -> Icons.Filled.Favorite
    GroupKind.EVENT -> Icons.Filled.Celebration
    GroupKind.PROJECT -> Icons.Filled.WorkOutline
    GroupKind.OTHER -> Icons.Filled.GridView
}

// MARK: - Friends

@Composable
fun FriendsScreen(viewModel: LedgerViewModel, onInviteFriend: () -> Unit = {}) {
    val colors = splitColors
    val ledger by viewModel.ledger.collectAsState()
    val settings by viewModel.settings.collectAsState()
    var newName by remember { mutableStateOf("") }
    var showAdd by remember { mutableStateOf(false) }

    val friends = ledger.participants.filter { !it.isCurrentUser && !it.isArchived }

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(colors.background),
        contentPadding = PaddingValues(Metrics.screenPadding),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Friends", style = MaterialTheme.typography.headlineLarge, color = colors.primaryText)
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { showAdd = true }) {
                    Text("Add", color = colors.secondaryText)
                }
                TextButton(onClick = onInviteFriend) {
                    Text("Invite", color = colors.accent, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        item { OverallBalanceCard(ledger.overallSummary(), settings.baseCurrencyCode) }

        if (friends.isEmpty()) {
            item {
                EmptyState(
                    icon = Icons.Filled.People,
                    title = "No friends yet",
                    message = "Send someone a link and what the two of you share stays in step " +
                        "on both phones. Or add a name yourself to keep track on your own.",
                    actionLabel = "Invite a friend",
                    onAction = onInviteFriend,
                )
            }
        } else {
            items(friends, key = { it.id }) { friend ->
                val summary = ledger.summaryWith(friend.id)
                val money = headlineAmount(summary, settings.baseCurrencyCode)
                SplitCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(friend)
                        Spacer(Modifier.width(12.dp))
                        Text(friend.fullName, color = colors.primaryText, modifier = Modifier.weight(1f))
                        Column(horizontalAlignment = Alignment.End) {
                            if (summary.isSettled) {
                                Text("settled up", color = colors.neutral, style = MaterialTheme.typography.bodyMedium)
                            } else {
                                Text(
                                    if (money.minorUnits > 0) "owes you" else "you owe",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = colors.tertiaryText,
                                )
                                Text(
                                    money.formattedAbsolute(),
                                    style = MoneyType.row,
                                    color = colors.forBalance(money.minorUnits),
                                )
                            }
                        }
                    }
                }
            }
        }
        item { Spacer(Modifier.height(72.dp)) }
    }

    if (showAdd) {
        AlertDialog(
            onDismissRequest = { showAdd = false },
            title = { Text("Add a friend") },
            text = {
                OutlinedTextField(
                    value = newName,
                    onValueChange = { newName = it },
                    label = { Text("Name") },
                    singleLine = true,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.addFriend(newName)
                    newName = ""
                    showAdd = false
                }) { Text("Add") }
            },
            dismissButton = { TextButton(onClick = { showAdd = false }) { Text("Cancel") } },
        )
    }
}

// MARK: - Activity

@Composable
fun ActivityScreen(viewModel: LedgerViewModel) {
    val colors = splitColors
    val entries by viewModel.activity.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(colors.background),
        contentPadding = PaddingValues(Metrics.screenPadding),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text("Activity", style = MaterialTheme.typography.headlineLarge, color = colors.primaryText)
        }
        if (entries.isEmpty()) {
            item {
                EmptyState(
                    icon = Icons.Filled.History,
                    title = "Nothing has happened yet",
                    message = "Every expense, payment and group change shows up here as a running history.",
                )
            }
        } else {
            items(entries, key = { it.id }) { entry ->
                SplitCard {
                    Row(verticalAlignment = Alignment.Top) {
                        Icon(
                            Icons.Filled.Circle,
                            null,
                            tint = colors.accent,
                            modifier = Modifier.size(10.dp).padding(top = 2.dp),
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(entry.headline, color = colors.primaryText)
                            if (entry.detail.isNotBlank()) {
                                Text(
                                    entry.detail,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = colors.secondaryText,
                                )
                            }
                            if (entry.groupName.isNotBlank()) {
                                Text(
                                    entry.groupName,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = colors.tertiaryText,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Insights

@Composable
fun InsightsScreen(viewModel: LedgerViewModel) {
    val colors = splitColors
    val ledger by viewModel.ledger.collectAsState()
    val settings by viewModel.settings.collectAsState()
    val me = ledger.currentUser?.id

    val mine = ledger.expenses.filter { me != null && it.isInvolved(me) }
    val byCategory = mine
        .groupBy { ExpenseCategory.fromWire(it.entity.category) }
        .mapValues { (_, list) -> list.sumOf { me?.let { id -> it.amountOwedBy(id) } ?: 0L } }
        .filterValues { it != 0L }
        .toList()
        .sortedByDescending { it.second }
    val total = byCategory.sumOf { it.second }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .padding(Metrics.screenPadding),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Insights", style = MaterialTheme.typography.headlineLarge, color = colors.primaryText)

        if (byCategory.isEmpty()) {
            EmptyState(
                icon = Icons.Filled.PieChart,
                title = "Nothing to chart yet",
                message = "Add a few expenses and this fills in with where your money goes.",
            )
        } else {
            SplitCard(padding = PaddingValues(20.dp)) {
                Overline("Your share of the spending")
                Spacer(Modifier.height(6.dp))
                Text(
                    Money(total, settings.baseCurrencyCode).formatted(),
                    style = MoneyType.display,
                    color = colors.primaryText,
                )
                Text(
                    "across ${mine.size} expenses",
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.secondaryText,
                )
            }

            SplitCard {
                SectionHeader("Where it went", "Top ${byCategory.size} categories")
                Spacer(Modifier.height(12.dp))
                val largest = byCategory.firstOrNull()?.second ?: 1L
                byCategory.take(8).forEach { (category, amount) ->
                    // Ranked bars rather than a pie: every bar carries its own
                    // name and figure, so it doubles as the table view.
                    Column(Modifier.padding(bottom = 10.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                category.icon(),
                                null,
                                tint = com.splitfree.ui.theme.ChartPalette.primary(colors.isDark),
                                modifier = Modifier.size(18.dp),
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                category.name.lowercase().replace('_', ' ')
                                    .replaceFirstChar { it.uppercase() },
                                color = colors.primaryText,
                                modifier = Modifier.weight(1f),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Text(
                                Money(amount, settings.baseCurrencyCode).formatted(),
                                style = MoneyType.caption,
                                color = colors.secondaryText,
                            )
                        }
                        Spacer(Modifier.height(5.dp))
                        LinearProgressIndicator(
                            progress = { (amount.toFloat() / largest.toFloat()).coerceIn(0f, 1f) },
                            modifier = Modifier.fillMaxWidth().height(7.dp)
                                .clip(androidx.compose.foundation.shape.CircleShape),
                            color = com.splitfree.ui.theme.ChartPalette.primary(colors.isDark),
                            trackColor = colors.surfaceSunken,
                            drawStopIndicator = {},
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Account

@Composable
fun AccountScreen(viewModel: LedgerViewModel, onSignIn: () -> Unit = {}) {
    val colors = splitColors
    val ledger by viewModel.ledger.collectAsState()
    val settings by viewModel.settings.collectAsState()
    val syncStatus by viewModel.sync.status.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showCurrencyPicker by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }

    val exportLauncher = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        if (uri != null) scope.launch {
            val text = viewModel.exportLedger()
            context.contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) }
            message = "Ledger exported."
        }
    }

    val importLauncher = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) scope.launch {
            val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            if (text == null) {
                message = "Couldn't read that file."
            } else {
                viewModel.importLedger(text)
                    .onSuccess { summary ->
                        message = if (summary.changedAnything) {
                            "Imported ${summary.totalAdded} new and updated ${summary.totalUpdated}." +
                                if (summary.skippedUnbalanced > 0)
                                    " Skipped ${summary.skippedUnbalanced} that didn't add up." else ""
                        } else "Nothing new in that file."
                    }
                    .onFailure { message = it.message ?: "That file couldn't be read." }
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .padding(Metrics.screenPadding),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Account", style = MaterialTheme.typography.headlineLarge, color = colors.primaryText)

        ledger.currentUser?.let { me ->
            SplitCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(me, size = 56.dp)
                    Spacer(Modifier.width(14.dp))
                    Text(me.fullName, style = MaterialTheme.typography.titleLarge, color = colors.primaryText)
                }
            }
        }

        if (viewModel.sync.isConfigured) {
            SplitCard {
                if (viewModel.sync.isSignedIn) {
                    SectionHeader(
                        viewModel.sync.accountEmail ?: "Signed in",
                        when (val state = syncStatus) {
                            is SyncEngine.Status.Syncing -> "Syncing"
                            is SyncEngine.Status.Failed -> state.message
                            else -> "Shared groups stay in step with your friends."
                        },
                    )
                    Spacer(Modifier.height(12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        SecondaryButton("Sync now") { viewModel.syncNow() }
                        SecondaryButton("Sign out") { viewModel.signOut() }
                    }
                } else {
                    SectionHeader(
                        "Sign in to share groups",
                        "Optional. Everything works without it.",
                    )
                    Spacer(Modifier.height(12.dp))
                    PrimaryButton("Sign in") { onSignIn() }
                }
            }
        }

        SplitCard(padding = PaddingValues(18.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Verified, null, tint = colors.accent)
                Spacer(Modifier.width(8.dp))
                Text("Everything is included", fontWeight = FontWeight.SemiBold, color = colors.primaryText)
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "No subscription, no upgrade screen, no adverts, no limits on expenses, " +
                    "and nothing held back for a paid tier.",
                style = MaterialTheme.typography.bodyMedium,
                color = colors.secondaryText,
            )
        }

        SplitCard {
            SettingRow("Your currency", "Totals across groups are shown in this.",
                "${Currencies.flag(settings.baseCurrencyCode)} ${settings.baseCurrencyCode}") {
                showCurrencyPicker = true
            }
            HorizontalDivider(color = colors.separator)
            SettingToggle(
                "Simplify debts by default",
                "New groups start with balances collapsed into the fewest payments.",
                settings.simplifyDebtsByDefault,
            ) { viewModel.setSimplifyByDefault(it) }
            HorizontalDivider(color = colors.separator)
            SettingToggle(
                "Convert other currencies",
                "Roll multi-currency balances into one figure.",
                settings.convertToBaseCurrency,
            ) { viewModel.setConvertToBase(it) }
            HorizontalDivider(color = colors.separator)
            Column(Modifier.padding(vertical = 12.dp)) {
                Text("Appearance", color = colors.primaryText, fontWeight = FontWeight.Medium)
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AppearanceSetting.entries.forEach { option ->
                        Chip(
                            label = option.name.lowercase().replaceFirstChar { it.uppercase() },
                            selected = settings.appearance == option,
                            onClick = { viewModel.setAppearance(option) },
                        )
                    }
                }
            }
        }

        SplitCard {
            SectionHeader(
                "Send a copy",
                "Export a .splitfree file and send it to a friend. They import it and see the same " +
                    "expenses and balances, on iPhone or Android. It is a snapshot, not a live " +
                    "link: share a group instead if you want changes to keep travelling.",
            )
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SecondaryButton("Export") { exportLauncher.launch("SplitFree.splitfree") }
                SecondaryButton("Import") { importLauncher.launch(arrayOf("application/json", "*/*")) }
            }
        }

        SplitCard {
            Text(
                "By default, everything lives on this device. Sharing a group is the one thing " +
                    "that changes that: a shared group is uploaded to SplitFree's server so your " +
                    "friends' phones can reach it, and everyone in it can read all of it. Groups " +
                    "you never share never leave this phone.\n\n" +
                    "There is no analytics SDK, no advertising, and nobody is sold anything about " +
                    "how you spend. Signing in is optional and the app is fully usable without it.",
                style = MaterialTheme.typography.bodyMedium,
                color = colors.secondaryText,
            )
            Spacer(Modifier.height(12.dp))
            SecondaryButton("Read the privacy policy") {
                viewModel.openUrl("https://splitfree.app/privacy")
            }
        }

        Spacer(Modifier.height(40.dp))
    }

    if (showCurrencyPicker) {
        CurrencyPickerSheet(
            selected = settings.baseCurrencyCode,
            onPick = { viewModel.setBaseCurrency(it); showCurrencyPicker = false },
            onDismiss = { showCurrencyPicker = false },
        )
    }

    message?.let {
        AlertDialog(
            onDismissRequest = { message = null },
            confirmButton = { TextButton(onClick = { message = null }) { Text("OK") } },
            text = { Text(it) },
        )
    }
}

@Composable
private fun SettingRow(title: String, subtitle: String, value: String?, onClick: () -> Unit) {
    val colors = splitColors
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, color = colors.primaryText, fontWeight = FontWeight.Medium)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        }
        if (value != null) Text(value, color = colors.secondaryText)
        Icon(Icons.Filled.ChevronRight, null, tint = colors.tertiaryText)
    }
}

@Composable
private fun SettingToggle(title: String, subtitle: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    val colors = splitColors
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, color = colors.primaryText, fontWeight = FontWeight.Medium)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        }
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
        )
    }
}

// MARK: - Currency picker

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CurrencyPickerSheet(selected: String, onPick: (String) -> Unit, onDismiss: () -> Unit) {
    val colors = splitColors
    var query by remember { mutableStateOf("") }
    val results = remember(query) { Currencies.search(query) }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.surface) {
        Column(Modifier.padding(horizontal = Metrics.screenPadding).fillMaxHeight(0.9f)) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text("Search currencies") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(12.dp))
            LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                items(results, key = { it.code }) { currency ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onPick(currency.code) }
                            .padding(vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(currency.flag, fontSize = 20.sp)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(currency.name, color = colors.primaryText)
                            Text(
                                "${currency.code} · ${currency.symbol}",
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.secondaryText,
                            )
                        }
                        if (currency.code == selected) {
                            Icon(Icons.Filled.Check, null, tint = colors.accent)
                        }
                    }
                }
            }
        }
    }
}
