import SwiftData
import SwiftUI

/// Manage the expenses that create themselves.
struct RecurringRulesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @Query(sort: [SortDescriptor(\RecurringRule.nextOccurrence)]) private var rules: [RecurringRule]

    @State private var expandedID: UUID?

    private var active: [RecurringRule] { rules.filter(\.isActive) }
    private var paused: [RecurringRule] { rules.filter { !$0.isActive } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if rules.isEmpty {
                        EmptyStateView(
                            symbol: "arrow.triangle.2.circlepath",
                            title: String(localized: "No recurring expenses"),
                            message: String(localized: "When you add an expense, turn on “Repeat this expense” and it'll be created for you on schedule — rent, bills, the shared streaming account.")
                        )
                    } else {
                        InfoBanner(
                            symbol: "clock",
                            text: String(localized: "Recurring expenses are created when you open SplitFree, dated correctly even if you were away for weeks.")
                        )

                        if !active.isEmpty {
                            section(String(localized: "Running"), rules: active)
                        }
                        if !paused.isEmpty {
                            section(String(localized: "Paused"), rules: paused)
                        }
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(Metrics.screenPadding)
            }
            .screenBackground()
            .navigationTitle(Text("Recurring"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done").fontWeight(.semibold) }
                }
            }
        }
    }

    private func section(_ title: String, rules: [RecurringRule]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title)
            ForEach(rules) { rule in
                ruleCard(rule)
            }
        }
    }

    private func ruleCard(_ rule: RecurringRule) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    CategoryBadge(category: rule.category, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.displayTitle)
                            .font(Typography.rowTitle)
                            .foregroundStyle(Palette.primaryText)
                            .lineLimit(1)
                        Text(rule.scheduleSummary)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                        if let group = rule.group {
                            Text(group.displayName)
                                .font(.caption2)
                                .foregroundStyle(Palette.tertiaryText)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(rule.amount.formatted())
                        .font(Typography.rowMoney)
                        .foregroundStyle(Palette.primaryText)
                        .monospacedDigit()
                }

                if expandedID == rule.id {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider().overlay(Palette.separator)

                        Text("Coming up")
                            .font(Typography.overline)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.tertiaryText)

                        ForEach(RecurrenceService.upcomingDates(for: rule, limit: 4), id: \.self) { date in
                            HStack(spacing: 8) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.tertiaryText)
                                Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).year()))
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.secondaryText)
                                Spacer()
                            }
                        }

                        if rule.generatedCount > 0 {
                            Text("^[\(rule.generatedCount) expense](inflect: true) created so far.")
                                .font(.caption2)
                                .foregroundStyle(Palette.tertiaryText)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: 10) {
                    Button {
                        withAnimation(Motion.snappy) {
                            expandedID = expandedID == rule.id ? nil : rule.id
                        }
                    } label: {
                        Label(
                            expandedID == rule.id ? String(localized: "Hide") : String(localized: "Details"),
                            systemImage: expandedID == rule.id ? "chevron.up" : "chevron.down"
                        )
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        withAnimation(Motion.snappy) { rule.isActive.toggle() }
                        try? context.save()
                        Haptics.tick()
                    } label: {
                        Label(
                            rule.isActive ? String(localized: "Pause") : String(localized: "Resume"),
                            systemImage: rule.isActive ? "pause.circle" : "play.circle"
                        )
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Spacer()

                    Button(role: .destructive) {
                        withAnimation(Motion.smooth) { context.delete(rule) }
                        try? context.save()
                        Haptics.warning()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.negative)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Delete this rule"))
                }
            }
        }
    }
}

// MARK: - About

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let included: [(String, String)] = [
        ("person.3.fill", String(localized: "Unlimited groups and friends")),
        ("infinity", String(localized: "Unlimited expenses — no monthly cap")),
        ("equal", String(localized: "Equal, exact, percentage, share and plus/minus splits")),
        ("list.bullet.rectangle", String(localized: "Itemize a bill line by line")),
        ("doc.viewfinder", String(localized: "Scan a receipt and read the items off it")),
        ("arrow.triangle.merge", String(localized: "Simplify debts into the fewest payments")),
        ("arrow.triangle.2.circlepath", String(localized: "Recurring expenses")),
        ("dollarsign.circle", String(localized: "150+ currencies with live conversion")),
        ("chart.pie.fill", String(localized: "Charts and spending totals")),
        ("magnifyingglass", String(localized: "Search across everything, receipts included")),
        ("bookmark.fill", String(localized: "Save default splits and reuse them")),
        ("square.and.arrow.down", String(localized: "Import a bank CSV")),
        ("square.and.arrow.up", String(localized: "Export everything as CSV, any time")),
        ("icloud", String(localized: "iCloud sync across your devices")),
        ("wifi.slash", String(localized: "Works completely offline")),
        ("creditcard", String(localized: "Hand off to Venmo, PayPal, Cash App or UPI")),
        ("faceid", String(localized: "Face ID lock")),
        ("globe", String(localized: "Nine languages")),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.pie.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Palette.accent)
                            .padding(22)
                            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                        Text("SplitFree")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Palette.primaryText)

                        Text("Splitting bills shouldn't cost money.")
                            .font(Typography.rowSubtitle)
                            .foregroundStyle(Palette.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(String(localized: "What you get"))
                            ForEach(Array(included.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: 11) {
                                    Image(systemName: item.0)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Palette.accent)
                                        .frame(width: 24)
                                    Text(item.1)
                                        .font(Typography.rowSubtitle)
                                        .foregroundStyle(Palette.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(String(localized: "Your data"))
                            Text("SplitFree has no accounts and no servers. Everything lives in the app's own store on your device, and syncs through your private iCloud database if you turn sync on — which only you can read.\n\nThere is no analytics SDK, no advertising, and no third party receiving anything about how you spend. The one network request the app can make is to fetch exchange rates, and it works without that too.")
                                .font(Typography.rowSubtitle)
                                .foregroundStyle(Palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Color.clear.frame(height: 20)
                }
                .padding(Metrics.screenPadding)
            }
            .screenBackground()
            .navigationTitle(Text("About"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done").fontWeight(.semibold) }
                }
            }
        }
    }
}
