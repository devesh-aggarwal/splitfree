import SwiftData
import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    case groups, friends, activity, insights, account

    var title: String {
        switch self {
        case .groups: String(localized: "Groups")
        case .friends: String(localized: "Friends")
        case .activity: String(localized: "Activity")
        case .insights: String(localized: "Insights")
        case .account: String(localized: "Account")
        }
    }

    var symbol: String {
        switch self {
        case .groups: "person.3.fill"
        case .friends: "person.2.fill"
        case .activity: "clock.arrow.circlepath"
        case .insights: "chart.pie.fill"
        case .account: "person.crop.circle.fill"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(AppLockState.self) private var lock
    @Environment(SyncEngine.self) private var sync

    @State private var selectedTab: AppTab = .groups
    @State private var isPresentingExpenseEditor = false
    @State private var expenseEditorContext: ExpenseEditorContext?
    @State private var recurringSummary: RecurrenceService.CatchUpResult?
    @State private var hidesFloatingAction = false
    @State private var inviteToken: InviteToken?

    /// Onboarding would otherwise be the only screen the screenshot script ever
    /// photographs, since AppSettings is built before the seeder can run.
    private var isScreenshotRun: Bool {
        #if DEBUG
        DemoData.isRequested
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if settings.requiresBiometricUnlock && !lock.isUnlocked {
                LockScreen()
            } else if !settings.hasCompletedOnboarding && !isScreenshotRun {
                OnboardingView()
            } else {
                mainInterface
            }
        }
        .task { await bootstrap() }
        .onOpenURL { url in
            if let token = SyncEngine.inviteToken(from: url) { inviteToken = InviteToken(token) }
        }
        .sheet(item: $inviteToken) { token in
            JoinGroupView(token: token.id)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.noteEnteredBackground()
            case .active:
                lock.noteBecameActive(lockEnabled: settings.requiresBiometricUnlock)
                Task { await catchUpRecurring() }
                // Coming back to the app is the moment a friend's change is most
                // worth having, and the cheapest time to ask for it.
                Task { await sync.syncNow(context: context) }
            default:
                break
            }
        }
    }

    private var mainInterface: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    tabContent(for: tab)
                        .tabItem { Label(tab.title, systemImage: tab.symbol) }
                        .tag(tab)
                }
            }

            if showsFloatingAction {
                AddExpenseButton {
                    expenseEditorContext = ExpenseEditorContext(mode: .create(group: nil, participants: []))
                }
                .padding(.trailing, Metrics.screenPadding)
                .padding(.bottom, 68)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onPreferenceChange(HidesFloatingActionKey.self) { hidden in
            hidesFloatingAction = hidden
        }
        .animation(Motion.snappy, value: selectedTab)
        .animation(Motion.snappy, value: hidesFloatingAction)
        .sheet(item: $expenseEditorContext) { editorContext in
            ExpenseEditorView(context: editorContext)
        }
        .overlay(alignment: .top) {
            if let recurringSummary, recurringSummary.createdCount > 0 {
                RecurringToast(result: recurringSummary) {
                    withAnimation(Motion.snappy) { self.recurringSummary = nil }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// The floating button belongs to the two list roots. A pushed detail screen
    /// carries its own "Add expense" button, so it opts out.
    private var showsFloatingAction: Bool {
        (selectedTab == .groups || selectedTab == .friends) && !hidesFloatingAction
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .groups: GroupsListView()
        case .friends: FriendsListView()
        case .activity: ActivityView()
        case .insights: InsightsView()
        case .account: AccountView()
        }
    }

    #if DEBUG
    /// Puts the app on the screen the screenshot script asked for.
    private func applyScreenshotArguments() {
        guard DemoData.isRequested else { return }
        if let tab = DemoData.startTab, let match = AppTab(rawValue: tab) {
            selectedTab = match
        }
    }
    #endif

    private func bootstrap() async {
        Ledger.currentUser(in: context)
        #if DEBUG
        applyScreenshotArguments()
        #endif
        lock.lockIfNeeded(enabled: settings.requiresBiometricUnlock)
        await exchangeRates.refreshIfNeeded()
        await catchUpRecurring()
        await sync.refreshState()
        await sync.syncNow(context: context)
    }

    /// Creates any recurring expenses that came due while the app was closed.
    private func catchUpRecurring() async {
        let result = RecurrenceService.catchUp(in: context, baseCurrencyCode: settings.baseCurrencyCode)
        settings.lastRecurringCheck = Date()
        guard result.createdCount > 0 else { return }
        withAnimation(Motion.snappy) { recurringSummary = result }
        try? await Task.sleep(for: .seconds(5))
        withAnimation(Motion.snappy) { recurringSummary = nil }
    }
}

/// The floating action button. Deliberately a single, unmissable affordance -
/// adding an expense is the thing people open this app to do.
struct AddExpenseButton: View {
    var action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button {
            Haptics.commit()
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Palette.accentGradient, in: Circle())
                .shadow(color: Palette.accent.opacity(0.35), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.92 : 1)
        .animation(Motion.quick, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(Text("Add an expense"))
    }
}

/// Confirms that recurring expenses were created in the background.
struct RecurringToast: View {
    var result: RecurrenceService.CatchUpResult
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("^[\(result.createdCount) recurring expense](inflect: true) added")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.primaryText)
                if !result.summary.isEmpty {
                    Text(result.summary)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
    }
}
