package com.splitfree.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
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

/**
 * Creating an account, which is optional and always has been.
 *
 * Leads with what signing in is *for* rather than with a form, because most
 * people arriving here have been using the app happily without an account and
 * deserve to know what changes before they hand over an email.
 */
@Composable
fun SignInScreen(viewModel: LedgerViewModel, onDone: () -> Unit) {
    val colors = splitColors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var email by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var awaitingCode by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    // The magic link comes back through MainActivity, whichever screen is up.
    val syncStatus by viewModel.sync.status.collectAsState()
    val providers by viewModel.sync.providers.collectAsState()
    LaunchedEffect(Unit) { viewModel.sync.refreshProviders() }
    LaunchedEffect(syncStatus) {
        if (viewModel.sync.isSignedIn) onDone()
    }

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
        Text("Sign in", style = MaterialTheme.typography.headlineLarge, color = colors.primaryText)

        SplitCard(padding = PaddingValues(18.dp)) {
            Text(
                "An account is only for sharing",
                fontWeight = FontWeight.SemiBold,
                color = colors.primaryText,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "Nothing changes for the groups you keep to yourself. Signing in lets you share " +
                    "a specific group with a friend, so their phone and yours stay in step.",
                style = MaterialTheme.typography.bodyMedium,
                color = colors.primaryText,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "A shared group is stored on SplitFree's server so your friend's phone can reach " +
                    "it. Groups you don't share never leave this device.",
                style = MaterialTheme.typography.bodyMedium,
                color = colors.secondaryText,
            )
        }

        if (!awaitingCode) {
            SplitCard {
                SectionHeader("With your email", "No password to forget.")
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = { Text("you@example.com") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(12.dp))
                PrimaryButton("Email me a link", enabled = isPlausibleEmail(email) && !working) {
                    run {
                        viewModel.sync.sendEmailCode(email.trim())
                        awaitingCode = true
                    }
                }
            }

            if (providers.contains("google")) {
                SplitCard {
                    SectionHeader("Or", "Sign in with an account you already have.")
                    Spacer(Modifier.height(12.dp))
                    SecondaryButton("Continue with Google") {
                        viewModel.sync.openOAuth(context, "google")
                    }
                }
            }
        } else {
            SplitCard {
                SectionHeader(
                    "Check your email",
                    "Tap the link we sent to ${email.trim()}. If the email shows a six-digit " +
                        "code instead, type it below.",
                )
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = code,
                    onValueChange = { code = it.filter(Char::isDigit).take(6) },
                    label = { Text("123456") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(12.dp))
                PrimaryButton("Sign in", enabled = code.length == 6 && !working) {
                    run {
                        viewModel.sync.verifyEmailCode(email.trim(), code)
                        viewModel.syncNow()
                        onDone()
                    }
                }
                Spacer(Modifier.height(8.dp))
                SecondaryButton("Use a different email") {
                    awaitingCode = false
                    code = ""
                    error = null
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

        Spacer(Modifier.height(40.dp))
    }
}

private fun isPlausibleEmail(value: String): Boolean {
    val parts = value.trim().split("@")
    return parts.size == 2 && parts[1].contains(".") && !value.trim().endsWith(".")
}

/**
 * Turning a group into a shared one, and handing out links to join it.
 *
 * Sharing is per group and always deliberate. There is no global "sync
 * everything" switch, because the honest version of this feature is that a
 * shared group leaves the device and an unshared one does not, and one switch
 * would blur exactly the line people care about.
 */
@Composable
fun ShareGroupScreen(viewModel: LedgerViewModel, groupId: String, onSignIn: () -> Unit, onDone: () -> Unit) {
    val colors = splitColors
    val ledger by viewModel.ledger.collectAsState()
    val scope = rememberCoroutineScope()

    val group = ledger.groups.firstOrNull { it.id == groupId }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var link by remember { mutableStateOf<String?>(null) }
    var inviteeId by remember { mutableStateOf<String?>(null) }

    fun run(block: suspend () -> Unit) {
        scope.launch {
            working = true
            error = null
            runCatching { block() }.onFailure { error = it.message ?: "Something went wrong." }
            working = false
        }
    }

    if (group == null) {
        onDone()
        return
    }

    // Members who haven't signed in yet, so their slot is still up for grabs.
    val unclaimed = ledger.members(group.id)
        .filter { it.id != ledger.currentUser?.id && it.remoteUserId == null }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .padding(Metrics.screenPadding),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Share group", style = MaterialTheme.typography.headlineLarge, color = colors.primaryText)

        if (!viewModel.sync.isSignedIn) {
            SplitCard {
                SectionHeader(
                    "Sharing needs an account",
                    "Your friend's phone has to be able to reach this group, which means it has " +
                        "to live somewhere both of you can get to.",
                )
                Spacer(Modifier.height(12.dp))
                PrimaryButton("Sign in") { onSignIn() }
            }
        } else if (!group.isShared) {
            SplitCard {
                SectionHeader(
                    group.displayName,
                    "Sharing uploads this group and everything in it: its expenses, who paid, who " +
                        "owes, notes, and any payments you've recorded. Everyone you invite can " +
                        "see all of it. Your other groups stay on this device.",
                )
                Spacer(Modifier.height(12.dp))
                PrimaryButton("Share this group", enabled = !working) {
                    run { viewModel.sync.shareGroup(group.id) }
                }
            }
        } else {
            SplitCard {
                SectionHeader("This group is shared", "Changes travel both ways when you're online.")
            }

            SplitCard {
                SectionHeader(
                    "Invite someone",
                    "Anyone with the link can join this group and see everything in it. " +
                        "It stops working after 14 days.",
                )
                Spacer(Modifier.height(12.dp))

                if (unclaimed.isNotEmpty()) {
                    // Inviting somebody *as* an existing member is the case that
                    // matters: the trip already has four expenses against
                    // "Marco", and Marco should walk into those rather than a
                    // blank slot beside them.
                    Text("Invite as", color = colors.secondaryText, style = MaterialTheme.typography.bodySmall)
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Chip("A new person", selected = inviteeId == null) { inviteeId = null }
                        unclaimed.forEach { person ->
                            Chip(person.fullName, selected = inviteeId == person.id) { inviteeId = person.id }
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }

                PrimaryButton("Create invite link", enabled = !working) {
                    run { link = viewModel.sync.createInviteLink(group.id, inviteeId) }
                }

                link?.let { url ->
                    Spacer(Modifier.height(12.dp))
                    Text(url, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                    Spacer(Modifier.height(8.dp))
                    SecondaryButton("Send the link") { viewModel.shareText(url) }
                }
            }

            SplitCard {
                SectionHeader(
                    "Stop sharing on this device",
                    "This group goes back to being local to your phone. It stays on the server " +
                        "for everyone else you invited, and their copies keep working.",
                )
                Spacer(Modifier.height(12.dp))
                SecondaryButton("Stop sharing") { run { viewModel.stopSharing(group.id) } }
            }
        }

        error?.let {
            SplitCard { Text(it, color = colors.negative, style = MaterialTheme.typography.bodyMedium) }
        }

        Spacer(Modifier.height(40.dp))
    }
}

/**
 * Accepting an invite. Shows what the link points at before joining, so nobody
 * has to tap "Join" on a group they can't see.
 */
@Composable
fun JoinGroupScreen(viewModel: LedgerViewModel, token: String, onSignIn: () -> Unit, onDone: () -> Unit) {
    val colors = splitColors
    val scope = rememberCoroutineScope()

    var preview by remember { mutableStateOf<SyncEngine.InvitePreview?>(null) }
    var working by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(token, viewModel.sync.isSignedIn) {
        working = true
        error = null
        runCatching { viewModel.sync.previewInvite(token) }
            .onSuccess { preview = it }
            .onFailure { error = it.message ?: "That link couldn't be checked." }
        working = false
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .padding(Metrics.screenPadding),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Join group", style = MaterialTheme.typography.headlineLarge, color = colors.primaryText)

        preview?.let { invite ->
            SplitCard {
                Text(invite.groupName, style = MaterialTheme.typography.titleLarge, color = colors.primaryText)
                Spacer(Modifier.height(6.dp))
                Text(
                    if (invite.memberCount == 1) "1 member" else "${invite.memberCount} members",
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.secondaryText,
                )
                invite.claimsMemberName?.let { name ->
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "You'll join as $name, so the expenses already recorded against that name " +
                            "become yours.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.primaryText,
                    )
                }
            }

            SplitCard {
                if (viewModel.sync.isSignedIn) {
                    SectionHeader(
                        if (invite.alreadyMember) "You're already in this group" else "Join",
                        "Everyone in this group can see every expense in it, including the ones you add.",
                    )
                    Spacer(Modifier.height(12.dp))
                    PrimaryButton(if (invite.alreadyMember) "Open the group" else "Join", enabled = !working) {
                        scope.launch {
                            working = true
                            runCatching { viewModel.sync.redeemInvite(token) }
                                .onSuccess { onDone() }
                                .onFailure { error = it.message ?: "Couldn't join." }
                            working = false
                        }
                    }
                } else {
                    SectionHeader(
                        "Sign in to join",
                        "Joining a shared group needs an account, so the group knows who you are.",
                    )
                    Spacer(Modifier.height(12.dp))
                    PrimaryButton("Sign in") { onSignIn() }
                }
            }
        }

        if (working && preview == null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp))
                Spacer(Modifier.width(10.dp))
                Text("Checking the link", color = colors.secondaryText)
            }
        }

        error?.let {
            SplitCard { Text(it, color = colors.negative, style = MaterialTheme.typography.bodyMedium) }
        }

        HorizontalDivider(color = colors.separator)
        SecondaryButton("Not now") { onDone() }

        Spacer(Modifier.height(40.dp))
    }
}


/**
 * Sending someone a link that connects the two of you.
 *
 * Underneath, a friendship is a two-person group. The screen never says so, but
 * it is why this works: sync carries groups, so a friendship with nothing behind
 * it could never reach the other phone and the friend list would be names that
 * quietly do nothing.
 */
@Composable
fun InviteFriendScreen(viewModel: LedgerViewModel, onSignIn: () -> Unit, onDone: () -> Unit) {
    val colors = splitColors
    val scope = rememberCoroutineScope()

    var name by remember { mutableStateOf("") }
    var link by remember { mutableStateOf<String?>(null) }
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

        if (!viewModel.sync.isSignedIn) {
            SplitCard {
                SectionHeader(
                    "Connecting needs an account",
                    "Their phone has to be able to reach what the two of you share, which " +
                        "means it has to live somewhere you can both get to.",
                )
                Spacer(Modifier.height(12.dp))
                PrimaryButton("Sign in") { onSignIn() }
            }
        } else if (link == null) {
            SplitCard {
                SectionHeader(
                    "Who are you inviting?",
                    "Once they accept, expenses between the two of you appear on both phones " +
                        "and your balance stays in step. Your groups are separate and stay " +
                        "where they are.",
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
                PrimaryButton("Create invite link", enabled = name.isNotBlank() && !working) {
                    scope.launch {
                        working = true
                        error = null
                        runCatching { viewModel.inviteFriend(name.trim()) }
                            .onSuccess { link = it }
                            .onFailure { error = it.message ?: "Couldn't create the link." }
                        working = false
                    }
                }
            }
        } else {
            SplitCard {
                SectionHeader(
                    "Ready to send",
                    "Anyone with this link can connect with you and see what the two of you " +
                        "share. It stops working after 14 days.",
                )
                Spacer(Modifier.height(12.dp))
                Text(link!!, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                Spacer(Modifier.height(12.dp))
                PrimaryButton("Send the link") { viewModel.shareText(link!!) }
            }
        }

        error?.let {
            SplitCard { Text(it, color = colors.negative, style = MaterialTheme.typography.bodyMedium) }
        }

        SecondaryButton("Done") { onDone() }
        Spacer(Modifier.height(40.dp))
    }
}
