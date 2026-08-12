import SwiftData
import SwiftUI

/// Full-text search across every expense: title, notes, category, group,
/// people, line items, and any text read off a scanned receipt.
struct SearchResultsView: View {
    var query: String

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)]) private var expenses: [Expense]
    @State private var selectedExpense: Expense?
    @State private var scope: SearchScope = .all

    private var user: Participant { Ledger.currentUser(in: context) }

    enum SearchScope: String, CaseIterable, Identifiable {
        case all, involvingYou, youPaid, unsettled

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: String(localized: "All")
            case .involvingYou: String(localized: "Involving you")
            case .youPaid: String(localized: "You paid")
            case .unsettled: String(localized: "Unsettled")
            }
        }
    }

    private var terms: [String] {
        query.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var results: [Expense] {
        guard !terms.isEmpty else { return [] }
        let user = user
        return expenses.filter { expense in
            let haystack = expense.searchHaystack
            guard terms.allSatisfy({ haystack.contains($0) }) else { return false }
            switch scope {
            case .all:
                return true
            case .involvingYou:
                return expense.involvedParticipants.contains { $0.id == user.id }
            case .youPaid:
                return expense.amountPaid(by: user) > 0
            case .unsettled:
                return expense.net(for: user) != 0
            }
        }
    }

    /// Sum of the matches, when they're all in the same currency.
    private var resultTotal: (amount: Int, code: String)? {
        let codes = Set(results.map(\.currencyCode))
        guard codes.count == 1, let code = codes.first else { return nil }
        return (results.reduce(0) { $0 + $1.amountMinorUnits }, code)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                Picker(selection: $scope) {
                    ForEach(SearchScope.allCases) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    Text("Scope")
                }
                .pickerStyle(.segmented)
                .padding(.top, 6)

                if results.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: String(localized: "Nothing found"),
                        message: String(format: String(localized: "No expenses match “%@”.", comment: "Search query"), query)
                    )
                } else {
                    HStack {
                        Text("^[\(results.count) result](inflect: true)")
                            .font(Typography.overline)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.tertiaryText)
                        Spacer()
                        if let resultTotal {
                            Text(Money(minorUnits: resultTotal.amount, currencyCode: resultTotal.code).formatted())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                    .padding(.horizontal, 4)

                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, expense in
                                Button { selectedExpense = expense } label: {
                                    ExpenseRow(expense: expense, user: user, showsGroupName: true)
                                }
                                .buttonStyle(RowButtonStyle())
                                if index < results.count - 1 {
                                    Divider().overlay(Palette.separator).padding(.leading, 100)
                                }
                            }
                        }
                    }
                }

                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
        .screenBackground()
        .sheet(item: $selectedExpense) { ExpenseDetailView(expense: $0) }
    }
}
