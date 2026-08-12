import SwiftData
import SwiftUI

/// Everyone you split with, and where you stand with each of them.
struct FriendsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates

    @Query(sort: [SortDescriptor(\Participant.name)]) private var participants: [Participant]
    @Query private var expenses: [Expense]
    @Query private var settlements: [Settlement]

    @State private var filter: BalanceFilter = .all
    @State private var isPresentingNewFriend = false
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

    private var friends: [Participant] {
        participants.filter { !$0.isCurrentUser && !$0.isArchived }
    }

    private var visibleFriends: [Participant] {
        let snapshot = snapshot
        return friends
            .filter { filter.matches(summary: snapshot.summary(withFriend: $0)) }
            .sorted { lhs, rhs in
                // People you owe or who owe you float above settled friends.
                let left = snapshot.summary(withFriend: lhs)
                let right = snapshot.summary(withFriend: rhs)
                if left.isSettled != right.isSettled { return !left.isSettled }
                return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    OverallBalanceCard(summary: snapshot.overall)

                    if !friends.isEmpty {
                        BalanceFilterBar(selection: $filter)
                    }

                    if friends.isEmpty {
                        EmptyStateView(
                            symbol: "person.2.fill",
                            title: String(localized: "No friends yet"),
                            message: String(localized: "Add the people you split with. You can settle up with them directly, without a group."),
                            actionTitle: String(localized: "Add a friend")
                        ) { isPresentingNewFriend = true }
                    } else if visibleFriends.isEmpty {
                        EmptyStateView(
                            symbol: filter.emptySymbol,
                            title: filter.emptyTitle,
                            message: filter.emptyMessage,
                            actionTitle: String(localized: "Show everyone")
                        ) { withAnimation(Motion.snappy) { filter = .all } }
                    } else {
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(visibleFriends.enumerated()), id: \.element.id) { index, friend in
                                    NavigationLink(value: friend) {
                                        FriendRow(friend: friend, summary: snapshot.summary(withFriend: friend))
                                    }
                                    .buttonStyle(RowButtonStyle())
                                    .contextMenu {
                                        Button {
                                            editorContext = ExpenseEditorContext(
                                                mode: .create(group: nil, participants: [user, friend])
                                            )
                                        } label: {
                                            Label("Add an expense", systemImage: "plus.circle")
                                        }
                                    }

                                    if index < visibleFriends.count - 1 {
                                        Divider().overlay(Palette.separator).padding(.leading, 66)
                                    }
                                }
                            }
                        }
                    }

                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 4)
                .animation(Motion.smooth, value: visibleFriends.map(\.id))
            }
            .screenBackground()
            .navigationTitle(Text("Friends"))
            .navigationDestination(for: Participant.self) { friend in
                FriendDetailView(friend: friend)
            }
            .searchable(text: $searchQuery, prompt: Text("Search expenses"))
            .overlay {
                if !searchQuery.isEmpty {
                    SearchResultsView(query: searchQuery)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingNewFriend = true } label: {
                        Text("Add friend")
                    }
                }
            }
            .sheet(isPresented: $isPresentingNewFriend) {
                FriendEditorView(friend: nil)
            }
            .sheet(item: $editorContext) { ExpenseEditorView(context: $0) }
        }
    }
}

struct FriendRow: View {
    var friend: Participant
    var summary: BalanceSummary

    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates

    var body: some View {
        let money = summary.net.headline(
            baseCode: settings.baseCurrencyCode,
            rates: exchangeRates.table,
            convert: settings.convertToBaseCurrency
        )

        HStack(spacing: 12) {
            AvatarView(participant: friend, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.fullName)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                if !friend.email.isEmpty {
                    Text(friend.email)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                if summary.isSettled {
                    Text("settled up")
                        .font(.subheadline)
                        .foregroundStyle(Palette.neutral)
                } else {
                    Text(money.minorUnits > 0 ? String(localized: "owes you") : String(localized: "you owe"))
                        .font(.caption2)
                        .foregroundStyle(Palette.tertiaryText)
                    Text(money.formattedAbsolute())
                        .font(Typography.rowMoney)
                        .foregroundStyle(Color.forBalance(money.minorUnits))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.tertiaryText)
        }
        .padding(Metrics.cardPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
