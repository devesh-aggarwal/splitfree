import SwiftData
import SwiftUI

/// Lists every payment that would square a group, newest debt first, with a
/// one-tap way to record each.
struct SettleUpView: View {
    var group: SpendingGroup?
    var sheet: BalanceSheet

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var activePayment: PaymentTarget?

    private var user: Participant { Ledger.currentUser(in: context) }

    private struct PaymentTarget: Identifiable {
        var id = UUID()
        var from: Participant
        var to: Participant
        var amountMinorUnits: Int
        var currencyCode: String
    }

    private var yourDebts: [Debt] {
        sheet.debts.filter { $0.from == user.id || $0.to == user.id }
    }

    private var otherDebts: [Debt] {
        sheet.debts.filter { $0.from != user.id && $0.to != user.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if sheet.debts.isEmpty {
                        EmptyStateView(
                            symbol: "checkmark.seal.fill",
                            title: String(localized: "Everyone's settled up"),
                            message: String(localized: "There's nothing to pay. Nice work.")
                        )
                    } else {
                        if !yourDebts.isEmpty {
                            section(
                                title: String(localized: "Your payments"),
                                subtitle: String(localized: "Tap one to record it."),
                                debts: yourDebts
                            )
                        }
                        if !otherDebts.isEmpty {
                            section(
                                title: String(localized: "Between others"),
                                subtitle: String(localized: "You're not part of these."),
                                debts: otherDebts
                            )
                        }

                        Button {
                            startCustomPayment()
                        } label: {
                            Label("Record a different payment", systemImage: "plus.circle")
                        }
                        .buttonStyle(PrimaryButtonStyle(isProminent: false))
                    }
                }
                .padding(Metrics.screenPadding)
            }
            .screenBackground()
            .navigationTitle(Text("Settle up"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done").fontWeight(.semibold) }
                }
            }
            .sheet(item: $activePayment) { target in
                RecordPaymentView(
                    from: target.from,
                    to: target.to,
                    suggestedMinorUnits: target.amountMinorUnits,
                    currencyCode: target.currencyCode,
                    group: group
                )
            }
        }
    }

    private func section(title: String, subtitle: String, debts: [Debt]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title, subtitle: subtitle)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(debts.enumerated()), id: \.element.id) { index, debt in
                        Button {
                            start(debt)
                        } label: {
                            settleRow(debt)
                        }
                        .buttonStyle(RowButtonStyle())
                        if index < debts.count - 1 {
                            Divider().overlay(Palette.separator).padding(.leading, Metrics.cardPadding)
                        }
                    }
                }
            }
        }
    }

    private func settleRow(_ debt: Debt) -> some View {
        let from = participant(debt.from)
        let to = participant(debt.to)

        return HStack(spacing: 12) {
            if let from { AvatarView(participant: from, size: 36) }
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.tertiaryText)
            if let to { AvatarView(participant: to, size: 36) }

            VStack(alignment: .leading, spacing: 2) {
                Text(sentence(for: debt, from: from, to: to))
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.primaryText)
                    .multilineTextAlignment(.leading)
                Text(debt.money.formatted())
                    .font(Typography.captionMoney)
                    .foregroundStyle(tint(for: debt))
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.tertiaryText)
        }
        .padding(Metrics.cardPadding)
        .contentShape(Rectangle())
    }

    private func sentence(for debt: Debt, from: Participant?, to: Participant?) -> String {
        let fromName = from?.displayName ?? String(localized: "Someone")
        let toName = to?.displayName ?? String(localized: "someone")
        if debt.from == user.id {
            return String(format: String(localized: "You pay %@", comment: "Payee"), toName)
        }
        if debt.to == user.id {
            return String(format: String(localized: "%@ pays you", comment: "Payer"), fromName)
        }
        return String(format: String(localized: "%1$@ pays %2$@", comment: "Payer, payee"), fromName, toName)
    }

    private func tint(for debt: Debt) -> Color {
        if debt.to == user.id { return Palette.positive }
        if debt.from == user.id { return Palette.negative }
        return Palette.neutral
    }

    private func participant(_ id: UUID) -> Participant? {
        if let group { return group.memberList.first { $0.id == id } }
        return Ledger.allParticipants(in: context).first { $0.id == id }
    }

    private func start(_ debt: Debt) {
        guard let from = participant(debt.from), let to = participant(debt.to) else { return }
        activePayment = PaymentTarget(
            from: from,
            to: to,
            amountMinorUnits: debt.amountMinorUnits,
            currencyCode: debt.currencyCode
        )
    }

    private func startCustomPayment() {
        let members = group?.memberList ?? Ledger.allParticipants(in: context)
        guard let other = members.first(where: { !$0.isCurrentUser }) else { return }
        activePayment = PaymentTarget(
            from: user,
            to: other,
            amountMinorUnits: 0,
            currencyCode: group?.defaultCurrencyCode ?? Currency.deviceDefaultCode
        )
    }
}

// MARK: - Record a payment

/// Confirms a settle-up. The amount is pre-filled with the outstanding balance
/// but stays editable, because part payments are normal.
struct RecordPaymentView: View {
    var from: Participant
    var to: Participant
    var suggestedMinorUnits: Int
    var currencyCode: String
    var group: SpendingGroup?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates

    @State private var amountMinorUnits: Int = 0
    @State private var method: PaymentMethod = .cash
    @State private var date = Date()
    @State private var notes = ""
    @State private var payer: Participant
    @State private var payee: Participant
    @State private var hasLoaded = false

    init(
        from: Participant,
        to: Participant,
        suggestedMinorUnits: Int,
        currencyCode: String,
        group: SpendingGroup?
    ) {
        self.from = from
        self.to = to
        self.suggestedMinorUnits = suggestedMinorUnits
        self.currencyCode = currencyCode
        self.group = group
        _payer = State(initialValue: from)
        _payee = State(initialValue: to)
    }

    private var paymentOptions: [PaymentLinks.Option] {
        PaymentLinks.options(
            for: payee,
            amount: Money(minorUnits: amountMinorUnits, currencyCode: currencyCode),
            note: group?.displayName ?? String(localized: "SplitFree")
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    directionCard
                    amountCard
                    if !paymentOptions.isEmpty {
                        handoffCard
                    }
                    detailsCard
                    Color.clear.frame(height: 20)
                }
                .padding(Metrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(Text("Record a payment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Record").fontWeight(.semibold) }
                        .disabled(amountMinorUnits <= 0 || payer.id == payee.id)
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                amountMinorUnits = suggestedMinorUnits
                hasLoaded = true
            }
        }
    }

    private var directionCard: some View {
        Card {
            HStack(spacing: 14) {
                VStack(spacing: 6) {
                    AvatarView(participant: payer, size: 52)
                    Text(payer.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(1)
                }

                Button {
                    withAnimation(Motion.snappy) {
                        let temporary = payer
                        payer = payee
                        payee = temporary
                    }
                    Haptics.tick()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                        Text("swap")
                            .font(.caption2)
                    }
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                VStack(spacing: 6) {
                    AvatarView(participant: payee, size: 52)
                    Text(payee.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var amountCard: some View {
        Card(padding: 20) {
            VStack(spacing: 10) {
                Text("Amount")
                    .font(Typography.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.tertiaryText)
                MoneyField(
                    minorUnits: $amountMinorUnits,
                    currencyCode: currencyCode,
                    font: Typography.money(38, weight: .bold)
                )
                if suggestedMinorUnits > 0 && amountMinorUnits != suggestedMinorUnits {
                    Button {
                        withAnimation(Motion.quick) { amountMinorUnits = suggestedMinorUnits }
                        Haptics.tick()
                    } label: {
                        Text("Settle the full \(Money(minorUnits: suggestedMinorUnits, currencyCode: currencyCode).formatted())")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Hands off to a payment app, then comes back here to confirm. We can't
    /// know whether the transfer actually happened, so the record is always the
    /// user's explicit confirmation, never an assumption.
    private var handoffCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    String(localized: "Pay with"),
                    subtitle: String(localized: "Opens the app with the details filled in. Come back to record it.")
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(paymentOptions) { option in
                            Button {
                                method = option.method
                                openURL(option.url)
                                Haptics.commit()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: option.method.symbol)
                                    Text(option.title)
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Palette.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var detailsCard: some View {
        Card {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Method")
                        .font(Typography.overline)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.tertiaryText)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PaymentMethod.allCases) { option in
                                ChipButton(
                                    title: option.title,
                                    systemImage: option.symbol,
                                    isSelected: method == option
                                ) {
                                    withAnimation(Motion.quick) { method = option }
                                    Haptics.selectionChanged()
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .scrollClipDisabled()
                }

                Divider().overlay(Palette.separator)

                DatePicker(selection: $date, displayedComponents: .date) {
                    Text("Date").font(Typography.rowTitle)
                }

                Divider().overlay(Palette.separator)

                TextField(text: $notes, axis: .vertical) {
                    Text("Add a note")
                }
                .font(Typography.rowSubtitle)
                .lineLimit(1...3)
            }
        }
    }

    private func save() {
        guard amountMinorUnits > 0, payer.id != payee.id else { return }
        Ledger.recordSettlement(
            from: payer,
            to: payee,
            amountMinorUnits: amountMinorUnits,
            currencyCode: currencyCode,
            date: date,
            method: method,
            notes: notes,
            group: group,
            baseCurrencyCode: settings.baseCurrencyCode,
            rate: exchangeRates.table.rate(from: currencyCode, to: settings.baseCurrencyCode) ?? 1,
            in: context
        )
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
