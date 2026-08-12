import SwiftData
import SwiftUI

/// The home screen: your overall position, then every group you're part of.
struct GroupsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates

    @Query(sort: [SortDescriptor(\SpendingGroup.sortOrder)])
    private var allGroups: [SpendingGroup]
    @Query private var expenses: [Expense]
    @Query private var settlements: [Settlement]

    @State private var filter: BalanceFilter = .all
    @State private var isPresentingNewGroup = false
    @State private var showsArchived = false
    @State private var searchQuery = ""
    @State private var editorContext: ExpenseEditorContext?

    private var user: Participant { Ledger.currentUser(in: context) }

    private var snapshot: LedgerSnapshot {
        LedgerSnapshot(
            user: user,
            expenses: expenses,
            settlements: settlements,
            simplifyByDefault: settings.simplifyDebtsByDefault
        )
    }

    /// `SortDescriptor` can't order on a `Bool`, so pinning is applied here.
    private var groups: [SpendingGroup] {
        allGroups.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private var activeGroups: [SpendingGroup] {
        groups.filter { !$0.isArchived }
    }

    private var archivedGroups: [SpendingGroup] {
        groups.filter(\.isArchived)
    }

    private var visibleGroups: [SpendingGroup] {
        let snapshot = snapshot
        return activeGroups.filter { group in
            filter.matches(summary: snapshot.summary(for: group))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16, pinnedViews: []) {
                    OverallBalanceCard(summary: snapshot.overall)

                    if !activeGroups.isEmpty {
                        BalanceFilterBar(selection: $filter)
                    }

                    if activeGroups.isEmpty {
                        EmptyStateView(
                            symbol: "person.3.fill",
                            title: String(localized: "No groups yet"),
                            message: String(localized: "Groups keep a trip, a flat, or a running tab in one place. Everyone's balance updates as you add expenses."),
                            actionTitle: String(localized: "Create a group")
                        ) { isPresentingNewGroup = true }
                    } else if visibleGroups.isEmpty {
                        EmptyStateView(
                            symbol: filter.emptySymbol,
                            title: filter.emptyTitle,
                            message: filter.emptyMessage,
                            actionTitle: String(localized: "Show all groups")
                        ) { withAnimation(Motion.snappy) { filter = .all } }
                    } else {
                        ForEach(visibleGroups) { group in
                            NavigationLink(value: group) {
                                GroupRow(group: group, summary: snapshot.summary(for: group))
                            }
                            .buttonStyle(RowButtonStyle())
                            .contextMenu { contextMenu(for: group) }
                        }
                    }

                    if !archivedGroups.isEmpty {
                        archivedSection
                    }

                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 4)
                .animation(Motion.smooth, value: visibleGroups.map(\.id))
            }
            .screenBackground()
            .navigationTitle(Text("Groups"))
            .navigationDestination(for: SpendingGroup.self) { group in
                GroupDetailView(group: group)
            }
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Search expenses"))
            .searchScopes($filter) { EmptyView() }
            .overlay {
                if !searchQuery.isEmpty {
                    SearchResultsView(query: searchQuery)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Text, not another "+". The floating button owns the plus
                    // glyph, and two of them side by side reads as a duplicate.
                    Button { isPresentingNewGroup = true } label: {
                        Text("New group")
                    }
                }
            }
            .sheet(isPresented: $isPresentingNewGroup) {
                GroupEditorView(group: nil)
            }
            .sheet(item: $editorContext) { context in
                ExpenseEditorView(context: context)
            }
            .refreshable {
                await exchangeRates.refresh()
            }
        }
    }

    // MARK: - Archived

    private var archivedSection: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(Motion.snappy) { showsArchived.toggle() }
            } label: {
                HStack {
                    Label("Archived", systemImage: "archivebox")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.secondaryText)
                    Text("\(archivedGroups.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.tertiaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryText)
                        .rotationEffect(.degrees(showsArchived ? 90 : 0))
                }
                .padding(.top, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsArchived {
                ForEach(archivedGroups) { group in
                    NavigationLink(value: group) {
                        GroupRow(group: group, summary: snapshot.summary(for: group))
                            .opacity(0.65)
                    }
                    .buttonStyle(RowButtonStyle())
                    .contextMenu { contextMenu(for: group) }
                }
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for group: SpendingGroup) -> some View {
        Button {
            editorContext = ExpenseEditorContext(mode: .create(group: group, participants: group.memberList))
        } label: {
            Label("Add an expense", systemImage: "plus.circle")
        }
        Button {
            group.isPinned.toggle()
            try? context.save()
            Haptics.tick()
        } label: {
            Label(group.isPinned ? "Unpin" : "Pin to top", systemImage: group.isPinned ? "pin.slash" : "pin")
        }
        Button {
            group.isArchived.toggle()
            try? context.save()
            Haptics.tick()
        } label: {
            Label(group.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
        }
        Divider()
        Button(role: .destructive) {
            Ledger.delete(group: group, in: context)
            try? context.save()
            Haptics.warning()
        } label: {
            Label("Delete group", systemImage: "trash")
        }
    }
}

// MARK: - Overall balance

/// The headline card. Reads as a sentence first and a number second, because
/// "you get back $214.30" is the answer people actually came for.
struct OverallBalanceCard: View {
    var summary: BalanceSummary

    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates

    private var headline: Money {
        summary.net.headline(
            baseCode: settings.baseCurrencyCode,
            rates: exchangeRates.table,
            convert: settings.convertToBaseCurrency
        )
    }

    private var tint: Color { .forBalance(headline.minorUnits) }

    var body: some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(captionText)
                        .font(Typography.overline)
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(Palette.tertiaryText)
                    Spacer()
                    if summary.isMultiCurrency && settings.convertToBaseCurrency {
                        Label("converted", systemImage: "arrow.left.arrow.right")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }

                if summary.isSettled {
                    Text("You're all settled up")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.neutral)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                } else {
                    Text(headline.formattedAbsolute())
                        .font(Typography.displayMoney)
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }

                // Only worth breaking out when money is moving both ways —
                // otherwise the chip just repeats the headline.
                if !summary.owedToYou.isSettled && !summary.youOwe.isSettled {
                    HStack(spacing: 10) {
                        BalanceChip(
                            label: String(localized: "you get back"),
                            position: summary.owedToYou,
                            tint: Palette.positive
                        )
                        BalanceChip(
                            label: String(localized: "you owe"),
                            position: summary.youOwe,
                            tint: Palette.negative
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var captionText: String {
        if summary.isSettled { return String(localized: "Total balance") }
        return headline.minorUnits > 0
            ? String(localized: "Overall, you get back")
            : String(localized: "Overall, you owe")
    }
}

struct BalanceChip: View {
    var label: String
    var position: NetPosition
    var tint: Color

    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates

    var body: some View {
        let money = position.headline(
            baseCode: settings.baseCurrencyCode,
            rates: exchangeRates.table,
            convert: settings.convertToBaseCurrency
        )
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Palette.secondaryText)
            Text(money.formattedAbsolute())
                .font(Typography.captionMoney)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Filter

enum BalanceFilter: String, CaseIterable, Identifiable, Hashable {
    case all, outstanding, owesYou, youOwe, settled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .outstanding: String(localized: "Outstanding")
        case .owesYou: String(localized: "Owes you")
        case .youOwe: String(localized: "You owe")
        case .settled: String(localized: "Settled")
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .outstanding: "exclamationmark.circle"
        case .owesYou: "arrow.down.left.circle"
        case .youOwe: "arrow.up.right.circle"
        case .settled: "checkmark.circle"
        }
    }

    func matches(summary: BalanceSummary) -> Bool {
        switch self {
        case .all: true
        case .outstanding: !summary.isSettled
        case .owesYou: !summary.owedToYou.isSettled
        case .youOwe: !summary.youOwe.isSettled
        case .settled: summary.isSettled
        }
    }

    var emptySymbol: String {
        switch self {
        case .settled: "checkmark.circle"
        default: "line.3.horizontal.decrease.circle"
        }
    }

    var emptyTitle: String {
        switch self {
        case .outstanding: String(localized: "Everything's settled")
        case .owesYou: String(localized: "Nobody owes you right now")
        case .youOwe: String(localized: "You don't owe anyone")
        case .settled: String(localized: "No settled groups")
        case .all: String(localized: "Nothing here")
        }
    }

    var emptyMessage: String {
        switch self {
        case .outstanding: String(localized: "Every group is square. Enjoy it while it lasts.")
        case .owesYou: String(localized: "No outstanding balances in your favour.")
        case .youOwe: String(localized: "You're square with everyone.")
        case .settled: String(localized: "Every group still has an open balance.")
        case .all: String(localized: "Nothing matches this filter.")
        }
    }
}

struct BalanceFilterBar: View {
    @Binding var selection: BalanceFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BalanceFilter.allCases) { filter in
                    ChipButton(
                        title: filter.title,
                        systemImage: filter.symbol,
                        isSelected: selection == filter
                    ) {
                        withAnimation(Motion.snappy) { selection = filter }
                        Haptics.selectionChanged()
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }
}

// MARK: - Group row

struct GroupRow: View {
    var group: SpendingGroup
    var summary: BalanceSummary

    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates

    var body: some View {
        let money = summary.net.headline(
            baseCode: settings.baseCurrencyCode,
            rates: exchangeRates.table,
            convert: settings.convertToBaseCurrency
        )

        Card {
            HStack(spacing: 14) {
                GroupBadge(group: group, size: 48)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(group.displayName)
                            .font(Typography.rowTitle)
                            .foregroundStyle(Palette.primaryText)
                            .lineLimit(1)
                        if group.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.tertiaryText)
                        }
                    }
                    AvatarStack(participants: group.memberList, size: 24, maxVisible: 5)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    if summary.isSettled {
                        Text("settled up")
                            .font(.subheadline)
                            .foregroundStyle(Palette.neutral)
                    } else {
                        Text(money.minorUnits > 0 ? String(localized: "you get back") : String(localized: "you owe"))
                            .font(.caption2)
                            .foregroundStyle(Palette.tertiaryText)
                        Text(money.formattedAbsolute())
                            .font(Typography.rowMoney)
                            .foregroundStyle(Color.forBalance(money.minorUnits))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
