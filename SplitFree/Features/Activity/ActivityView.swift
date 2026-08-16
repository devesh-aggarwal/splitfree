import SwiftData
import SwiftUI

/// Everything that's happened, newest first.
struct ActivityView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\ActivityEntry.createdAt, order: .reverse)])
    private var entries: [ActivityEntry]
    @Query private var expenses: [Expense]

    @State private var selectedExpense: Expense?
    @State private var filter: ActivityFilter = .all

    enum ActivityFilter: String, CaseIterable, Identifiable {
        case all, expenses, payments, groups

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: String(localized: "All")
            case .expenses: String(localized: "Expenses")
            case .payments: String(localized: "Payments")
            case .groups: String(localized: "Groups")
            }
        }

        func matches(_ kind: ActivityKind) -> Bool {
            switch self {
            case .all:
                true
            case .expenses:
                [.expenseAdded, .expenseEdited, .expenseDeleted, .recurringGenerated, .transactionsImported, .commentAdded].contains(kind)
            case .payments:
                [.settlementAdded, .settlementDeleted].contains(kind)
            case .groups:
                [.groupCreated, .groupArchived, .memberAdded, .memberRemoved].contains(kind)
            }
        }
    }

    private var visibleEntries: [ActivityEntry] {
        entries.filter { filter.matches($0.kind) }
    }

    private var grouped: [(title: String, entries: [ActivityEntry])] {
        let calendar = Calendar.current
        var buckets: [(String, [ActivityEntry])] = []
        var current: (String, [ActivityEntry])?

        for entry in visibleEntries {
            let title = Self.dayTitle(for: entry.createdAt, calendar: calendar)
            if current?.0 == title {
                current?.1.append(entry)
            } else {
                if let current { buckets.append(current) }
                current = (title, [entry])
            }
        }
        if let current { buckets.append(current) }
        return buckets
    }

    private static func dayTitle(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()), date > weekAgo {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if !entries.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ActivityFilter.allCases) { option in
                                    ChipButton(
                                        title: option.title,
                                        systemImage: nil,
                                        isSelected: filter == option
                                    ) {
                                        withAnimation(Motion.snappy) { filter = option }
                                        Haptics.selectionChanged()
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                        .scrollClipDisabled()
                    }

                    if visibleEntries.isEmpty {
                        EmptyStateView(
                            symbol: "clock.arrow.circlepath",
                            title: entries.isEmpty
                                ? String(localized: "Nothing has happened yet")
                                : String(localized: "Nothing in this filter"),
                            message: entries.isEmpty
                                ? String(localized: "Every expense, payment and group change shows up here as a running history.")
                                : String(localized: "Try a different filter.")
                        )
                    } else {
                        ForEach(grouped, id: \.title) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(Typography.overline)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                    .foregroundStyle(Palette.tertiaryText)
                                    .padding(.horizontal, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Card(padding: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                                            Button { open(entry) } label: {
                                                ActivityRow(entry: entry)
                                            }
                                            .buttonStyle(RowButtonStyle())
                                            .disabled(entry.expenseID == nil)

                                            if index < section.entries.count - 1 {
                                                Divider().overlay(Palette.separator).padding(.leading, 62)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 4)
                .animation(Motion.smooth, value: visibleEntries.count)
            }
            .screenBackground()
            .navigationTitle(Text("Activity"))
            .toolbar {
                if !entries.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(role: .destructive) { clearAll() } label: {
                                Label("Clear history", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(item: $selectedExpense) { ExpenseDetailView(expense: $0) }
        }
    }

    private func open(_ entry: ActivityEntry) {
        guard let id = entry.expenseID,
              let expense = expenses.first(where: { $0.id == id })
        else { return }
        selectedExpense = expense
    }

    /// Clears the feed only - expenses, payments and balances are untouched.
    private func clearAll() {
        withAnimation(Motion.smooth) {
            for entry in entries { context.delete(entry) }
        }
        try? context.save()
        Haptics.warning()
    }
}

struct ActivityRow: View {
    var entry: ActivityEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind.symbol)
                .font(.system(size: 17))
                .foregroundStyle(entry.kind.tint)
                .frame(width: 34, height: 34)
                .background(entry.kind.tint.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.headline)
                    .font(Typography.rowSubtitle)
                    .foregroundStyle(Palette.primaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    if !entry.groupName.isEmpty {
                        Text(entry.groupName)
                        Text("·")
                    }
                    Text(entry.createdAt.formatted(.dateTime.hour().minute()))
                }
                .font(.caption2)
                .foregroundStyle(Palette.tertiaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(Metrics.cardPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
