import SwiftData
import SwiftUI

/// One expense in a timeline: date, category, what it was, who paid, and what it
/// means for you.
struct ExpenseRow: View {
    var expense: Expense
    var user: Participant
    var showsGroupName: Bool = false

    private var net: Int { expense.net(for: user) }
    private var isInvolved: Bool {
        expense.involvedParticipants.contains { $0.id == user.id }
    }

    var body: some View {
        HStack(spacing: 13) {
            DateBlock(date: expense.date)

            CategoryBadge(category: expense.category, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(expense.displayTitle)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    // "Ana paid $48.00" is the point of the line, so the group
                    // name gives way first when space runs out.
                    Text(expense.payerSummary)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if showsGroupName, let group = expense.group {
                        Text("·").foregroundStyle(Palette.tertiaryText)
                        Text(group.displayName)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.tertiaryText)
                            .lineLimit(1)
                    }
                }

                if expense.receiptImageData != nil || !expense.commentList.isEmpty || expense.generatedByRuleID != nil {
                    HStack(spacing: 8) {
                        if expense.receiptImageData != nil {
                            Image(systemName: "paperclip")
                        }
                        if !expense.commentList.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "bubble.left.fill")
                                Text("\(expense.commentList.count)")
                            }
                        }
                        if expense.generatedByRuleID != nil {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                if !isInvolved {
                    Text("not involved")
                        .font(.caption2)
                        .foregroundStyle(Palette.tertiaryText)
                    Text(expense.total.formatted())
                        .font(Typography.captionMoney)
                        .foregroundStyle(Palette.tertiaryText)
                } else if net == 0 {
                    Text("settled")
                        .font(.caption2)
                        .foregroundStyle(Palette.neutral)
                } else {
                    Text(net > 0 ? String(localized: "you lent") : String(localized: "you borrowed"))
                        .font(.caption2)
                        .foregroundStyle(Palette.tertiaryText)
                    Text(Money(minorUnits: abs(net), currencyCode: expense.currencyCode).formatted())
                        .font(Typography.rowMoney)
                        .foregroundStyle(Color.forBalance(net))
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, Metrics.cardPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The little month/day stack down the left of a timeline row.
struct DateBlock: View {
    var date: Date

    var body: some View {
        VStack(spacing: -1) {
            Text(date.formatted(.dateTime.month(.abbreviated)))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.tertiaryText)
                .textCase(.uppercase)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(width: 30)
        .accessibilityHidden(true)
    }
}

/// A settle-up payment in a timeline.
struct SettlementRow: View {
    var settlement: Settlement
    var user: Participant

    private var net: Int { settlement.net(for: user) }

    var body: some View {
        HStack(spacing: 13) {
            DateBlock(date: settlement.date)

            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Palette.positiveSoft)
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: settlement.method.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.positive)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(settlement.summary)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(2)
                Text(settlement.method.title)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            Spacer(minLength: 4)

            if net != 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(net > 0 ? String(localized: "you paid") : String(localized: "you received"))
                        .font(.caption2)
                        .foregroundStyle(Palette.tertiaryText)
                    Text(settlement.amount.formatted())
                        .font(Typography.rowMoney)
                        .foregroundStyle(Palette.neutral)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, Metrics.cardPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Groups a timeline by month, which is how people scan back through spending.
@MainActor
enum TimelineGrouping {
    struct Section: Identifiable {
        var id: Date
        var title: String
        var entries: [LedgerEntry]
        var totalMinorUnits: Int
        var currencyCode: String
    }

    static func sections(from entries: [LedgerEntry], calendar: Calendar = .current) -> [Section] {
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.date(from: calendar.dateComponents([.year, .month], from: entry.date)) ?? entry.date
        }

        return grouped.keys.sorted(by: >).map { month in
            let items = (grouped[month] ?? []).sorted { $0.date > $1.date }
            let expenses = items.compactMap { entry -> Expense? in
                if case .expense(let expense) = entry { return expense }
                return nil
            }
            // Only sum a single currency; a mixed month shows no total rather
            // than a misleading one.
            let codes = Set(expenses.map(\.currencyCode))
            let total = codes.count == 1 ? expenses.reduce(0) { $0 + $1.amountMinorUnits } : 0
            return Section(
                id: month,
                title: Self.title(for: month, calendar: calendar),
                entries: items,
                totalMinorUnits: total,
                currencyCode: codes.count == 1 ? (codes.first ?? "USD") : ""
            )
        }
    }

    private static func title(for month: Date, calendar: Calendar) -> String {
        let now = Date()
        if calendar.isDate(month, equalTo: now, toGranularity: .month) {
            return String(localized: "This month")
        }
        if let lastMonth = calendar.date(byAdding: .month, value: -1, to: now),
           calendar.isDate(month, equalTo: lastMonth, toGranularity: .month) {
            return String(localized: "Last month")
        }
        if calendar.isDate(month, equalTo: now, toGranularity: .year) {
            return month.formatted(.dateTime.month(.wide))
        }
        return month.formatted(.dateTime.month(.wide).year())
    }
}
