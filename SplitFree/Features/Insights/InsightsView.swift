import Charts
import SwiftData
import SwiftUI

/// Where the money actually went.
///
/// Every figure is your own share, converted to your base currency at the rate
/// captured when each expense was entered — so the totals don't drift as
/// exchange rates move.
struct InsightsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)]) private var expenses: [Expense]
    @Query private var groups: [SpendingGroup]

    @State private var range: InsightsRange = .sixMonths
    @State private var basis: SpendBasis = .yourShare
    @State private var selectedMonth: Date?
    @State private var groupFilter: SpendingGroup?

    private var user: Participant { Ledger.currentUser(in: context) }
    private var baseCode: String { settings.baseCurrencyCode }

    private var report: SpendingReport {
        SpendingReport(
            expenses: expenses,
            user: user,
            baseCode: baseCode,
            range: range,
            basis: basis,
            group: groupFilter
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    filters

                    if report.isEmpty {
                        EmptyStateView(
                            symbol: "chart.pie",
                            title: String(localized: "Nothing to chart yet"),
                            message: String(localized: "Add a few expenses and this fills in with where your money goes.")
                        )
                    } else {
                        headlineTiles
                        // A single bar is not a chart — the headline figure
                        // already says everything it could.
                        if report.monthly.count > 1 {
                            monthlyChart
                        }
                        categoryChart
                        peopleChart
                        if groupFilter == nil && report.byGroup.count > 1 {
                            groupChart
                        }
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 4)
            }
            .screenBackground()
            .navigationTitle(Text("Insights"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker(selection: $groupFilter.animation(Motion.smooth)) {
                            Text("All groups").tag(SpendingGroup?.none)
                            ForEach(groups.filter { !$0.isArchived }) { group in
                                Text(group.displayName).tag(SpendingGroup?.some(group))
                            }
                        } label: {
                            Text("Group")
                        }
                    } label: {
                        Image(systemName: groupFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
        }
    }

    // MARK: - Filters

    /// One row of controls above the charts, per the interaction rules.
    private var filters: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InsightsRange.allCases) { option in
                        ChipButton(title: option.title, systemImage: nil, isSelected: range == option) {
                            withAnimation(Motion.smooth) {
                                range = option
                                selectedMonth = nil
                            }
                            Haptics.selectionChanged()
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()

            Picker(selection: $basis.animation(Motion.smooth)) {
                ForEach(SpendBasis.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                Text("Basis")
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Headline

    private var headlineTiles: some View {
        VStack(spacing: 12) {
            Card(padding: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(basis.headlineCaption)
                        .font(Typography.overline)
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(Palette.tertiaryText)
                    Text(Money(minorUnits: report.total, currencyCode: baseCode).formatted())
                        .font(Typography.displayMoney)
                        .foregroundStyle(Palette.primaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let delta = report.deltaPercent {
                            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                            Text(String(format: "%.0f%%", abs(delta)))
                                .font(.caption.weight(.semibold))
                            Text("vs the previous period")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryText)
                        } else {
                            Text(range.subtitle)
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                    .foregroundStyle(report.deltaPercent.map { $0 >= 0 ? Palette.negative : Palette.positive } ?? Palette.secondaryText)
                }
            }

            HStack(spacing: 12) {
                StatTile(
                    caption: String(localized: "Expenses"),
                    value: "\(report.count)",
                    footnote: report.averageText(baseCode: baseCode)
                )
                StatTile(
                    caption: String(localized: "You paid out"),
                    value: Money(minorUnits: report.paidByYou, currencyCode: baseCode).formatted(),
                    footnote: String(localized: "across all bills")
                )
            }
        }
    }

    // MARK: - Monthly

    /// One series, so one hue and no legend — the axis names the months.
    private var monthlyChart: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    String(localized: "Month by month"),
                    subtitle: selectedMonth.flatMap { month in
                        report.monthly.first { $0.month == month }.map { point in
                            "\(point.label) · \(Money(minorUnits: point.amount, currencyCode: baseCode).formatted())"
                        }
                    } ?? String(localized: "Drag across the chart to inspect a month.")
                )

                Chart(report.monthly) { point in
                    BarMark(
                        x: .value(String(localized: "Month"), point.month, unit: .month),
                        y: .value(String(localized: "Amount"), point.majorAmount)
                    )
                    .foregroundStyle(
                        selectedMonth == nil || selectedMonth == point.month
                            ? ChartPalette.primary
                            : ChartPalette.primary.opacity(0.28)
                    )
                    .cornerRadius(4)
                }
                .chartXSelection(value: $selectedMonth)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(ChartPalette.grid)
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(compactMoney(amount))
                                    .font(.caption2)
                                    .foregroundStyle(Palette.tertiaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: report.monthly.count > 8 ? 2 : 1)) { value in
                        AxisValueLabel(format: .dateTime.month(.narrow))
                            .foregroundStyle(Palette.tertiaryText)
                            .font(.caption2)
                    }
                }
                .frame(height: 170)
                .accessibilityLabel(Text("Spending by month"))
            }
        }
    }

    // MARK: - Categories

    /// Ranked horizontal bars rather than a pie: with ten-ish categories a pie
    /// can't be read, and every bar carries its own name and figure — which
    /// doubles as the table view.
    private var categoryChart: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    String(localized: "Where it went"),
                    subtitle: String(format: String(localized: "Top %lld categories", comment: "Count"), report.byCategory.count)
                )

                VStack(spacing: 10) {
                    ForEach(report.byCategory) { slice in
                        RankedBarRow(
                            leading: {
                                AnyView(
                                    Image(systemName: slice.category?.symbol ?? "ellipsis")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ChartPalette.primary)
                                        .frame(width: 20)
                                )
                            },
                            title: slice.label,
                            amount: slice.amount,
                            fraction: report.fraction(of: slice.amount),
                            currencyCode: baseCode
                        )
                    }
                }
            }
        }
    }

    // MARK: - People

    private var peopleChart: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    String(localized: "Who you spend with"),
                    subtitle: String(localized: "Total of the bills you shared with each person.")
                )
                VStack(spacing: 10) {
                    ForEach(report.byPerson) { slice in
                        RankedBarRow(
                            leading: {
                                AnyView(
                                    Group {
                                        if let person = slice.participant {
                                            AvatarView(participant: person, size: 20)
                                        } else {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(Palette.tertiaryText)
                                                .frame(width: 20)
                                        }
                                    }
                                )
                            },
                            title: slice.label,
                            amount: slice.amount,
                            fraction: report.fraction(of: slice.amount, in: report.byPerson),
                            currencyCode: baseCode
                        )
                    }
                }
            }
        }
    }

    private var groupChart: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(String(localized: "By group"))
                VStack(spacing: 10) {
                    ForEach(report.byGroup) { slice in
                        RankedBarRow(
                            leading: {
                                AnyView(
                                    Image(systemName: slice.group?.kind.symbol ?? "square.grid.2x2")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ChartPalette.primary)
                                        .frame(width: 20)
                                )
                            },
                            title: slice.label,
                            amount: slice.amount,
                            fraction: report.fraction(of: slice.amount, in: report.byGroup),
                            currencyCode: baseCode
                        )
                    }
                }
            }
        }
    }

    private func compactMoney(_ amount: Double) -> String {
        let symbol = Currency.symbol(for: baseCode)
        if abs(amount) >= 1000 {
            return "\(symbol)\(Int(amount / 1000))k"
        }
        return "\(symbol)\(Int(amount))"
    }
}

// MARK: - Pieces

struct StatTile: View {
    var caption: String
    var value: String
    var footnote: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(caption)
                    .font(Typography.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.tertiaryText)
                Text(value)
                    .font(Typography.money(21, weight: .bold))
                    .foregroundStyle(Palette.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

/// A labelled bar. The name and the number are always visible, so the chart
/// carries its own table and colour never has to do the identifying.
struct RankedBarRow: View {
    var leading: () -> AnyView
    var title: String
    var amount: Int
    var fraction: Double
    var currencyCode: String

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                leading()
                Text(title)
                    .font(Typography.rowSubtitle)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Money(minorUnits: amount, currencyCode: currencyCode).formatted())
                    .font(Typography.captionMoney)
                    .foregroundStyle(Palette.secondaryText)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ChartPalette.grid)
                        .frame(height: 7)
                    Capsule()
                        .fill(ChartPalette.primary)
                        .frame(width: max(4, proxy.size.width * fraction), height: 7)
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(
            Text("\(Money(minorUnits: amount, currencyCode: currencyCode).formatted()), \(Int(fraction * 100))%")
        )
    }
}

// MARK: - Range & basis

enum InsightsRange: String, CaseIterable, Identifiable {
    case month, threeMonths, sixMonths, year, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: String(localized: "This month")
        case .threeMonths: String(localized: "3 months")
        case .sixMonths: String(localized: "6 months")
        case .year: String(localized: "This year")
        case .all: String(localized: "All time")
        }
    }

    var subtitle: String {
        switch self {
        case .month: String(localized: "since the start of the month")
        case .threeMonths: String(localized: "over the last three months")
        case .sixMonths: String(localized: "over the last six months")
        case .year: String(localized: "since January")
        case .all: String(localized: "everything you've recorded")
        }
    }

    /// The window this range covers, and the equally sized window before it
    /// used for the change figure.
    func bounds(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, previousStart: Date)? {
        switch self {
        case .month:
            guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let previous = calendar.date(byAdding: .month, value: -1, to: start)
            else { return nil }
            return (start, previous)
        case .threeMonths:
            guard let start = calendar.date(byAdding: .month, value: -3, to: now),
                  let previous = calendar.date(byAdding: .month, value: -6, to: now)
            else { return nil }
            return (start, previous)
        case .sixMonths:
            guard let start = calendar.date(byAdding: .month, value: -6, to: now),
                  let previous = calendar.date(byAdding: .month, value: -12, to: now)
            else { return nil }
            return (start, previous)
        case .year:
            guard let start = calendar.date(from: calendar.dateComponents([.year], from: now)),
                  let previous = calendar.date(byAdding: .year, value: -1, to: start)
            else { return nil }
            return (start, previous)
        case .all:
            return nil
        }
    }
}

enum SpendBasis: String, CaseIterable, Identifiable {
    /// What you personally owed — the honest "what did this cost me" number.
    case yourShare
    /// The full value of every bill you were part of.
    case fullBills

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yourShare: String(localized: "Your share")
        case .fullBills: String(localized: "Full bills")
        }
    }

    var headlineCaption: String {
        switch self {
        case .yourShare: String(localized: "Your share of the spending")
        case .fullBills: String(localized: "Total value of bills you shared")
        }
    }
}
