import SwiftData
import SwiftUI

struct GroupDetailView: View {
    @Bindable var group: SpendingGroup

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(\.dismiss) private var dismiss

    @State private var editorContext: ExpenseEditorContext?
    @State private var selectedExpense: Expense?
    @State private var isPresentingSettleUp = false
    @State private var isPresentingEditGroup = false
    @State private var isPresentingShare = false
    @State private var isPresentingMembers = false
    @State private var isPresentingNotes = false
    @State private var showsBalances = true
    @State private var categoryFilter: ExpenseCategory?

    private var user: Participant { Ledger.currentUser(in: context) }

    private var sheet: BalanceSheet {
        BalanceEngine.balanceSheet(
            expenses: group.expenseList,
            settlements: group.settlementList,
            simplify: group.simplifyDebts
        )
    }

    private var summary: BalanceSummary {
        BalanceSummary.make(for: user, sheet: sheet)
    }

    private var timeline: [LedgerEntry] {
        guard let categoryFilter else { return group.timeline }
        return group.timeline.filter { entry in
            if case .expense(let expense) = entry { return expense.category == categoryFilter }
            return false
        }
    }

    private var sections: [TimelineGrouping.Section] {
        TimelineGrouping.sections(from: timeline)
    }

    private var usedCategories: [ExpenseCategory] {
        Array(Set(group.expenseList.map(\.category))).sorted { $0.title < $1.title }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                header
                actionRow

                if !sheet.debts.isEmpty {
                    balancesCard
                }

                if !group.notes.isEmpty {
                    notesCard
                }

                if usedCategories.count > 1 {
                    categoryFilterBar
                }

                if group.expenseList.isEmpty && group.settlementList.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        title: String(localized: "No expenses yet"),
                        message: String(localized: "Add the first one and everyone's balance appears here."),
                        actionTitle: String(localized: "Add an expense")
                    ) {
                        editorContext = ExpenseEditorContext(mode: .create(group: group, participants: group.memberList))
                    }
                } else {
                    timelineSections
                }

                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 4)
            .animation(Motion.smooth, value: sections.count)
        }
        .screenBackground()
        .hidesFloatingAction()
        .navigationTitle(Text(group.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $editorContext) { ExpenseEditorView(context: $0) }
        .sheet(isPresented: $isPresentingShare) { ShareGroupView(group: group) }
        .sheet(item: $selectedExpense) { expense in
            ExpenseDetailView(expense: expense)
        }
        .sheet(isPresented: $isPresentingSettleUp) {
            SettleUpView(group: group, sheet: sheet)
        }
        .sheet(isPresented: $isPresentingEditGroup) {
            GroupEditorView(group: group)
        }
        .sheet(isPresented: $isPresentingMembers) {
            GroupMembersView(group: group)
        }
        .sheet(isPresented: $isPresentingNotes) {
            GroupNotesView(group: group)
        }
    }

    // MARK: - Header

    private var header: some View {
        let money = summary.net.headline(
            baseCode: settings.baseCurrencyCode,
            rates: exchangeRates.table,
            convert: settings.convertToBaseCurrency
        )

        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 13) {
                    GroupBadge(group: group, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.kind.title)
                            .font(Typography.overline)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .foregroundStyle(Palette.tertiaryText)
                        Button { isPresentingMembers = true } label: {
                            HStack(spacing: 6) {
                                AvatarStack(participants: group.memberList, size: 24, maxVisible: 6)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Palette.tertiaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                Divider().overlay(Palette.separator)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.isSettled ? String(localized: "Everyone's settled up") : (money.minorUnits > 0 ? String(localized: "You get back") : String(localized: "You owe")))
                        .font(Typography.overline)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(Palette.tertiaryText)
                    if !summary.isSettled {
                        Text(money.formattedAbsolute())
                            .font(Typography.titleMoney)
                            .foregroundStyle(Color.forBalance(money.minorUnits))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                editorContext = ExpenseEditorContext(mode: .create(group: group, participants: group.memberList))
            } label: {
                Label("Add expense", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                isPresentingSettleUp = true
            } label: {
                Label("Settle up", systemImage: "checkmark.circle")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Palette.accent, isProminent: false))
            .disabled(sheet.debts.isEmpty)
        }
    }

    // MARK: - Balances

    private var balancesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    String(localized: "Balances"),
                    subtitle: group.simplifyDebts
                        ? String(localized: "Simplified into the fewest payments")
                        : nil
                ) {
                    Button {
                        withAnimation(Motion.snappy) { showsBalances.toggle() }
                    } label: {
                        Image(systemName: showsBalances ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }

                if showsBalances {
                    VStack(spacing: 10) {
                        ForEach(sheet.debts) { debt in
                            DebtRow(debt: debt, group: group, user: user)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    Toggle(isOn: $group.simplifyDebts.animation(Motion.smooth)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Simplify debts")
                                .font(.subheadline.weight(.medium))
                            Text(simplifySubtitle)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                    .tint(Palette.accent)
                    .padding(.top, 4)
                    .onChange(of: group.simplifyDebts) { _, _ in
                        try? context.save()
                        Haptics.tick()
                    }
                }
            }
        }
    }

    /// The other mode's payment count, so the toggle can say what it would buy
    /// you. Only the opposite sheet is computed — the current one is already to
    /// hand.
    private var simplifySubtitle: String {
        let current = sheet.debts.count
        let alternative = BalanceEngine.balanceSheet(
            expenses: group.expenseList,
            settlements: group.settlementList,
            simplify: !group.simplifyDebts
        ).debts.count

        let simplified = group.simplifyDebts ? current : alternative
        let detailed = group.simplifyDebts ? alternative : current

        if detailed == simplified {
            return String(localized: "Already the fewest possible payments.")
        }
        return String(
            format: String(localized: "%1$lld payments instead of %2$lld.", comment: "Simplified count, detailed count"),
            simplified,
            detailed
        )
    }

    // MARK: - Notes

    private var notesCard: some View {
        Button { isPresentingNotes = true } label: {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Group notes", systemImage: "note.text")
                        .font(Typography.overline)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.tertiaryText)
                    Text(group.notes)
                        .font(Typography.rowSubtitle)
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .buttonStyle(RowButtonStyle())
    }

    // MARK: - Timeline

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipButton(title: String(localized: "All"), systemImage: nil, isSelected: categoryFilter == nil) {
                    withAnimation(Motion.snappy) { categoryFilter = nil }
                }
                ForEach(usedCategories) { category in
                    ChipButton(
                        title: category.title,
                        systemImage: category.symbol,
                        isSelected: categoryFilter == category,
                        tint: category.color
                    ) {
                        withAnimation(Motion.snappy) {
                            categoryFilter = categoryFilter == category ? nil : category
                        }
                        Haptics.selectionChanged()
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private var timelineSections: some View {
        ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(section.title)
                        .font(Typography.overline)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(Palette.tertiaryText)
                    Spacer()
                    if section.totalMinorUnits > 0 {
                        Text(Money(minorUnits: section.totalMinorUnits, currencyCode: section.currencyCode).formatted())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }
                .padding(.horizontal, 4)

                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                            entryRow(entry)
                            if index < section.entries.count - 1 {
                                Divider().overlay(Palette.separator).padding(.leading, 100)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: LedgerEntry) -> some View {
        switch entry {
        case .expense(let expense):
            Button { selectedExpense = expense } label: {
                ExpenseRow(expense: expense, user: user)
            }
            .buttonStyle(RowButtonStyle())
            .contextMenu {
                Button {
                    editorContext = ExpenseEditorContext(mode: .edit(expense))
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    withAnimation(Motion.smooth) {
                        Ledger.delete(expense: expense, in: context)
                        try? context.save()
                    }
                    Haptics.warning()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

        case .settlement(let settlement):
            SettlementRow(settlement: settlement, user: user)
                .contextMenu {
                    Button(role: .destructive) {
                        withAnimation(Motion.smooth) {
                            Ledger.delete(settlement: settlement, in: context)
                            try? context.save()
                        }
                        Haptics.warning()
                    } label: {
                        Label("Undo this payment", systemImage: "arrow.uturn.backward")
                    }
                }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { isPresentingShare = true } label: {
                    Label(
                        group.isShared ? "Sharing and invites" : "Share with friends",
                        systemImage: group.isShared ? "person.2.badge.gearshape" : "person.badge.plus"
                    )
                }
                Button { isPresentingEditGroup = true } label: {
                    Label("Group settings", systemImage: "gearshape")
                }
                Button { isPresentingMembers = true } label: {
                    Label("Members", systemImage: "person.2")
                }
                Button { isPresentingNotes = true } label: {
                    Label("Group notes", systemImage: "note.text")
                }
                Divider()
                ShareLink(item: GroupExporter.csv(for: group), preview: SharePreview(group.displayName)) {
                    Label("Export as CSV", systemImage: "square.and.arrow.up")
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
                    dismiss()
                } label: {
                    Label("Delete group", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Debt row

/// "Ana owes you $18.20" with a one-tap way to record the payment.
struct DebtRow: View {
    var debt: Debt
    var group: SpendingGroup?
    var user: Participant

    @Environment(\.modelContext) private var context
    @State private var isPresentingSettle = false

    private var from: Participant? { lookup(debt.from) }
    private var to: Participant? { lookup(debt.to) }

    private func lookup(_ id: UUID) -> Participant? {
        if let group { return group.memberList.first { $0.id == id } }
        return Ledger.allParticipants(in: context).first { $0.id == id }
    }

    private var involvesUser: Bool { debt.from == user.id || debt.to == user.id }

    var body: some View {
        HStack(spacing: 10) {
            if let from { AvatarView(participant: from, size: 30) }
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.tertiaryText)
            if let to { AvatarView(participant: to, size: 30) }

            VStack(alignment: .leading, spacing: 1) {
                Text(sentence)
                    .font(.subheadline)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Text(debt.money.formatted())
                .font(Typography.rowMoney)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard involvesUser else { return }
            isPresentingSettle = true
        }
        .sheet(isPresented: $isPresentingSettle) {
            if let from, let to {
                RecordPaymentView(
                    from: from,
                    to: to,
                    suggestedMinorUnits: debt.amountMinorUnits,
                    currencyCode: debt.currencyCode,
                    group: group
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        if debt.to == user.id { return Palette.positive }
        if debt.from == user.id { return Palette.negative }
        return Palette.neutral
    }

    private var sentence: String {
        let fromName = from?.displayName ?? String(localized: "Someone")
        let toName = to?.displayName ?? String(localized: "someone")
        if debt.from == user.id {
            return String(format: String(localized: "You owe %@", comment: "Payee name"), toName)
        }
        if debt.to == user.id {
            return String(format: String(localized: "%@ owes you", comment: "Payer name"), fromName)
        }
        return String(
            format: String(localized: "%1$@ owes %2$@", comment: "Payer, payee"),
            fromName,
            toName
        )
    }
}
