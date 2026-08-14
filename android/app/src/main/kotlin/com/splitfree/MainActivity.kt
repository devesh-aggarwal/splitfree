package com.splitfree

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PieChart
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.splitfree.ui.LedgerViewModel
import com.splitfree.ui.screens.AccountScreen
import com.splitfree.ui.screens.ActivityScreen
import com.splitfree.ui.screens.ExpenseEditorScreen
import com.splitfree.ui.screens.FriendsScreen
import com.splitfree.ui.screens.GroupDetailScreen
import com.splitfree.ui.screens.GroupEditorScreen
import com.splitfree.ui.screens.GroupsScreen
import com.splitfree.ui.screens.InsightsScreen
import com.splitfree.ui.screens.InviteFriendScreen
import com.splitfree.ui.screens.JoinGroupScreen
import com.splitfree.ui.screens.OnboardingScreen
import com.splitfree.ui.screens.ShareGroupScreen
import com.splitfree.ui.theme.SplitFreeTheme
import com.splitfree.ui.theme.splitColors

class MainActivity : ComponentActivity() {

    private val viewModel: LedgerViewModel by viewModels {
        val container = (application as SplitFreeApp).container
        LedgerViewModel.Factory(container.repository, container.settingsStore, container.sync, applicationContext)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleLink(intent?.dataString)
        setContent {
            val settings by viewModel.settings.collectAsState()
            SplitFreeTheme(appearance = settings.appearance) {
                if (settings.hasCompletedOnboarding) {
                    RootScaffold(viewModel, pendingInvite)
                } else {
                    OnboardingScreen(viewModel)
                }
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        handleLink(intent.dataString)
    }

    override fun onResume() {
        super.onResume()
        // Coming back to the app is the moment a friend's change is most worth
        // having, and the cheapest time to ask for it.
        viewModel.syncNow()
    }

    private var pendingInvite: androidx.compose.runtime.MutableState<String?> =
        androidx.compose.runtime.mutableStateOf(null)

    private fun handleLink(url: String?) {
        if (url == null) return
        com.splitfree.sync.SyncEngine.inviteToken(url)?.let { pendingInvite.value = it }
    }
}

private enum class Tab(val route: String, val label: String) {
    GROUPS("groups", "Groups"),
    FRIENDS("friends", "Friends"),
    ACTIVITY("activity", "Activity"),
    INSIGHTS("insights", "Insights"),
    ACCOUNT("account", "Account"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RootScaffold(
    viewModel: LedgerViewModel,
    pendingInvite: androidx.compose.runtime.MutableState<String?>,
) {
    val navController = rememberNavController()
    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val colors = splitColors

    // The floating button belongs to the two list roots. A pushed detail screen
    // carries its own "Add expense" button, and two plus glyphs at once reads as
    // a duplicate.
    val showsFab = currentRoute == Tab.GROUPS.route || currentRoute == Tab.FRIENDS.route
    val showsBottomBar = Tab.entries.any { it.route == currentRoute }

    Scaffold(
        containerColor = colors.background,
        bottomBar = {
            if (showsBottomBar) {
                NavigationBar(containerColor = colors.surface) {
                    Tab.entries.forEach { tab ->
                        val selected = backStack?.destination?.hierarchy?.any { it.route == tab.route } == true
                        NavigationBarItem(
                            selected = selected,
                            onClick = {
                                navController.navigate(tab.route) {
                                    popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(tab.icon(), contentDescription = null) },
                            label = { Text(tab.label) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = colors.accent,
                                selectedTextColor = colors.accent,
                                indicatorColor = colors.accentSoft,
                                unselectedIconColor = colors.secondaryText,
                                unselectedTextColor = colors.secondaryText,
                            ),
                        )
                    }
                }
            }
        },
        floatingActionButton = {
            if (showsFab) {
                FloatingActionButton(
                    onClick = { navController.navigate("expense/new?groupId=") },
                    containerColor = colors.accent,
                    contentColor = Color.White,
                ) {
                    Icon(Icons.Filled.Add, contentDescription = "Add an expense")
                }
            }
        },
    ) { padding ->
        // An invite link can arrive while the app is already open, so this
        // reacts to the token rather than reading it once at start-up.
        androidx.compose.runtime.LaunchedEffect(pendingInvite.value) {
            pendingInvite.value?.let { navController.navigate("join/$it") }
        }
        Box(modifier = Modifier.padding(padding)) {
            NavHost(navController = navController, startDestination = Tab.GROUPS.route) {
                composable(Tab.GROUPS.route) {
                    GroupsScreen(
                        viewModel = viewModel,
                        onOpenGroup = { navController.navigate("group/$it") },
                        onNewGroup = { navController.navigate("group/new/edit") },
                        onJoinGroup = { navController.navigate("join") },
                    )
                }
                composable(Tab.FRIENDS.route) {
                    FriendsScreen(
                        viewModel,
                        onInviteFriend = { navController.navigate("invite-friend") },
                    )
                }
                composable("invite-friend") {
                    InviteFriendScreen(
                        viewModel,
                        onDone = { navController.popBackStack() },
                    )
                }
                composable(Tab.ACTIVITY.route) { ActivityScreen(viewModel) }
                composable(Tab.INSIGHTS.route) { InsightsScreen(viewModel) }
                composable(Tab.ACCOUNT.route) {
                    AccountScreen(viewModel)
                }

                composable("group/{groupId}") { entry ->
                    GroupDetailScreen(
                        viewModel = viewModel,
                        groupId = entry.arguments?.getString("groupId").orEmpty(),
                        onBack = { navController.popBackStack() },
                        onAddExpense = { groupId ->
                            navController.navigate("expense/new?groupId=$groupId")
                        },
                        onEditExpense = { expenseId ->
                            navController.navigate("expense/$expenseId?groupId=")
                        },
                        onShare = { groupId -> navController.navigate("group/$groupId/share") },
                        onEditGroup = { groupId -> navController.navigate("group/$groupId/edit") },
                    )
                }
                composable("group/{groupId}/share") { entry ->
                    ShareGroupScreen(
                        viewModel = viewModel,
                        groupId = entry.arguments?.getString("groupId").orEmpty(),
                        onDone = { navController.popBackStack() },
                    )
                }
                composable("join/{token}") { entry ->
                    JoinGroupScreen(
                        viewModel = viewModel,
                        token = entry.arguments?.getString("token").orEmpty(),
                        onDone = {
                            pendingInvite.value = null
                            navController.popBackStack()
                        },
                    )
                }
                composable("group/new/edit") {
                    GroupEditorScreen(viewModel, groupId = null, onDone = { navController.popBackStack() })
                }
                composable("group/{groupId}/edit") { entry ->
                    GroupEditorScreen(
                        viewModel,
                        groupId = entry.arguments?.getString("groupId"),
                        onDone = { navController.popBackStack() },
                    )
                }
                composable("expense/{expenseId}?groupId={groupId}") { entry ->
                    val expenseId = entry.arguments?.getString("expenseId").orEmpty()
                    ExpenseEditorScreen(
                        viewModel = viewModel,
                        expenseId = expenseId.takeIf { it != "new" },
                        initialGroupId = entry.arguments?.getString("groupId")?.takeIf { it.isNotBlank() },
                        onDone = { navController.popBackStack() },
                    )
                }
            }
        }
    }
}

@Composable
private fun Tab.icon() = when (this) {
    Tab.GROUPS -> Icons.Filled.Groups
    Tab.FRIENDS -> Icons.Filled.People
    Tab.ACTIVITY -> Icons.Filled.History
    Tab.INSIGHTS -> Icons.Filled.PieChart
    Tab.ACCOUNT -> Icons.Filled.Person
}
