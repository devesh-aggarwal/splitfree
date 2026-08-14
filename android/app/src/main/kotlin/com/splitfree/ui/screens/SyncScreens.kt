package com.splitfree.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.splitfree.sync.Invite
import com.splitfree.sync.SyncEngine
import com.splitfree.ui.LedgerViewModel
import com.splitfree.ui.components.Chip
import com.splitfree.ui.components.PrimaryButton
import com.splitfree.ui.components.SecondaryButton
import com.splitfree.ui.components.SectionHeader
import com.splitfree.ui.components.SplitCard
import com.splitfree.ui.theme.Metrics
import com.splitfree.ui.theme.splitColors
import kotlinx.coroutines.launch

/** A join code, big enough to read out, with the link behind the share button. */
@Composable
fun JoinCodeBlock(viewModel: LedgerViewModel, invite: Invite) {
    val colors = splitColors
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            color = colors.accent.copy(alpha = 0.12f),
        ) {
            Text(
                invite.formattedCode,
                modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp),
                textAlign = TextAlign.Center,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.SemiBold,
                fontSize = 24.sp,
                color = colors.primaryText,
            )
        }
        SecondaryButton("Send a link") { viewModel.shareText(invite.url) }
    }
}

/**
 * Sharing a group, by link or by code.
 *
 * There is no sign-in. The device gets an identity the first time it shares
 * something, because row level security needs something to key on and nothing
 * else does.
 */
@Composable
fun ShareGroupScreen(viewModel: LedgerViewModel, groupId: String, onDone: () -> Unit) {
    val colors = splitColors
    val ledger by viewModel.ledger.collectAsState()
    val scope = rememberCoroutineScope()

    val group = ledger.groups.firstOrNull { it.id == groupId }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var invite by remember { mutableStateOf<Invite?>(null) }
    var inviteeId by remember { mutableStateOf<String?>(null) }

    if (group == null) {
        onDone()
        return
    }

    val unclaimed = ledger.members(group.id)
        .filter { it.id != ledger.currentUser?.id && it.remoteUserId == null }

    fun run(block: suspend () -> Unit) {
        scope.launch {
            working = true
            error = null
            runCatching { block() }.onFailure { error = it.message ?: "Something went wrong." }
            working = false
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
        Text("Share group", style = MaterialTheme.typography.headlineLarge, color = colors.primaryText)

        if (!group.isShared) {
            SplitCard {
                SectionHeader(group.displayName, "Everyone you invite sees every expense in this group.")
                Spacer(Modifier.height(12.dp))
                PrimaryButton("Share this group", enabled = !working) {
                    run {
                        viewModel.sync.shareGroup(group.id)
                        invite = viewModel.sync.createInvite(group.id, null)
                    }
                }
            }
        } else {
            SplitCard {
                SectionHeader("Invite someone", "Anyone with the code can join. It expires in 14 days.")
                Spacer(Modifier.height(12.dp))

                if (unclaimed.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Chip("A new person", selected = inviteeId == null) { inviteeId = null }
                        unclaimed.forEach { person ->
                            Chip(person.fullName, selected = inviteeId == person.id) { inviteeId = person.id }
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }

                PrimaryButton(
                    if (invite == null) "Create an invite" else "Create another",
                    enabled = !working,
                ) {
                    run { invite = viewModel.sync.createInvite(group.id, inviteeId) }
                }

                invite?.let {
                    Spacer(Modifier.height(14.dp))
                    JoinCodeBlock(viewModel, it)
                }
            }

            SplitCard {
                SectionHeader(
                    "Stop sharing on this device",
                    "The group stays on your phone. Everyone else keeps their copy.",
                )
                Spacer(Modifier.height(12.dp))
                SecondaryButton("Stop sharing") { run { viewModel.stopSharing(group.id) } }
            }
        }

        error?.let {
            SplitCard { Text(it, color = colors.negative, style = MaterialTheme.typography.bodyMedium) }
        }

        SecondaryButton("Done") { onDone() }
        Spacer(Modifier.height(40.dp))
    }
}

/** Accepting an invite, whether it arrived as a link or as a typed code. */
@Composable
fun JoinGroupScreen(viewModel: LedgerViewModel, token: String, onDone: () -> Unit) {
    val colors = splitColors
    val scope = rememberCoroutineScope()

    var code by remember { mutableStateOf(token) }
    var preview by remember { mutableStateOf<SyncEngine.InvitePreview?>(null) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun lookUp(raw: String) {
        working = true
        error = null
        runCatching { viewModel.sync.previewInvite(raw) }
            .onSuccess { preview = it; code = raw }
            .onFailure { error = it.message ?: "That code couldn't be checked." }
        working = false
    }

    LaunchedEffect(token) { if (token.isNotBlank()) lookUp(token) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .padding(Metrics.screenPadding),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Join a group", style = MaterialTheme.typography.headlineLarge, color = colors.primaryText)

        val found = preview
        if (found == null) {
            SplitCard {
                SectionHeader("Enter the code a friend sent you")
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = code,
                    onValueChange = { code = it.uppercase() },
                    label = { Text("ABCDE-FGHIJ") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(12.dp))
                PrimaryButton("Find the group", enabled = code.isNotBlank() && !working) {
                    scope.launch { lookUp(code) }
                }
            }
        } else {
            SplitCard {
                Text(found.groupName, style = MaterialTheme.typography.titleLarge, color = colors.primaryText)
                Spacer(Modifier.height(6.dp))
                Text(
                    if (found.memberCount == 1) "1 member" else "${found.memberCount} members",
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.secondaryText,
                )
                found.claimsMemberName?.let { name ->
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "You'll join as $name.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.primaryText,
                    )
                }
                Spacer(Modifier.height(14.dp))
                PrimaryButton(
                    if (found.alreadyMember) "Open the group" else "Join",
                    enabled = !working,
                ) {
                    scope.launch {
                        working = true
                        runCatching { viewModel.sync.redeemInvite(code) }
                            .onSuccess { onDone() }
                            .onFailure { error = it.message ?: "Couldn't join." }
                        working = false
                    }
                }
            }
        }

        if (working) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp))
                Spacer(Modifier.width(10.dp))
                Text("Working", color = colors.secondaryText)
            }
        }

        error?.let {
            SplitCard { Text(it, color = colors.negative, style = MaterialTheme.typography.bodyMedium) }
        }

        SecondaryButton("Cancel") { onDone() }
        Spacer(Modifier.height(40.dp))
    }
}

/** Connecting with one person rather than a whole group. */
@Composable
fun InviteFriendScreen(viewModel: LedgerViewModel, onDone: () -> Unit) {
    val colors = splitColors
    val scope = rememberCoroutineScope()

    var name by remember { mutableStateOf("") }
    var invite by remember { mutableStateOf<Invite?>(null) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .padding(Metrics.screenPadding),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Invite a friend", style = MaterialTheme.typography.headlineLarge, color = colors.primaryText)

        val ready = invite
        if (ready == null) {
            SplitCard {
                SectionHeader(
                    "Who are you inviting?",
                    "Once they join, what the two of you share stays in step on both phones.",
                )
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Their name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(12.dp))
                PrimaryButton("Create an invite", enabled = name.isNotBlank() && !working) {
                    scope.launch {
                        working = true
                        error = null
                        runCatching { viewModel.inviteFriend(name.trim()) }
                            .onSuccess { invite = it }
                            .onFailure { error = it.message ?: "Couldn't create the invite." }
                        working = false
                    }
                }
            }
        } else {
            SplitCard {
                SectionHeader("Send this to them", "Anyone with the code can connect with you.")
                Spacer(Modifier.height(12.dp))
                JoinCodeBlock(viewModel, ready)
            }
        }

        error?.let {
            SplitCard { Text(it, color = colors.negative, style = MaterialTheme.typography.bodyMedium) }
        }

        SecondaryButton("Done") { onDone() }
        Spacer(Modifier.height(40.dp))
    }
}
