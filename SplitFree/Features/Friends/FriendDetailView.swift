import PhotosUI
import SwiftData
import SwiftUI

/// One friend: your balance with them, every expense you share, and a way to
/// settle up directly.
struct FriendDetailView: View {
    @Bindable var friend: Participant

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(\.dismiss) private var dismiss

    @Query private var allExpenses: [Expense]
    @Query private var allSettlements: [Settlement]

    @State private var editorContext: ExpenseEditorContext?
    @State private var selectedExpense: Expense?
    @State private var isPresentingSettle = false
    @State private var isPresentingEdit = false
    @State private var isPresentingInvite = false

    /// A fresh invite can be created any time until the friend accepts one,
    /// so losing the first link is never fatal.
    private var canInvite: Bool {
        SupabaseConfig.isConfigured && friend.remoteUserID == nil
    }

    private var user: Participant { Ledger.currentUser(in: context) }

    private var sharedExpenses: [Expense] {
        allExpenses.filter { expense in
            let ids = Set(expense.involvedParticipants.map(\.id))
            return ids.contains(user.id) && ids.contains(friend.id)
        }
    }

    private var sharedSettlements: [Settlement] {
        allSettlements.filter { settlement in
            let ids = [settlement.fromParticipant?.id, settlement.toParticipant?.id].compactMap { $0 }
            return ids.contains(user.id) && ids.contains(friend.id)
        }
    }

    private var summary: BalanceSummary {
        LedgerSnapshot(
            user: user,
            expenses: allExpenses,
            settlements: allSettlements,
            simplifyByDefault: settings.simplifyDebtsByDefault
        )
        .summary(withFriend: friend)
    }

    private var sections: [TimelineGrouping.Section] {
        let entries = sharedExpenses.map { LedgerEntry.expense($0) }
            + sharedSettlements.map { LedgerEntry.settlement($0) }
        return TimelineGrouping.sections(from: entries)
    }

    /// Groups you're both in - useful context for where the balance came from.
    private var sharedGroups: [SpendingGroup] {
        var seen = Set<UUID>()
        var result: [SpendingGroup] = []
        for expense in sharedExpenses {
            guard let group = expense.group, !group.isDirect, seen.insert(group.id).inserted else { continue }
            result.append(group)
        }
        return result
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                header
                actionRow

                if canInvite {
                    inviteCard
                }

                if !sharedGroups.isEmpty {
                    sharedGroupsCard
                }

                if sections.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        title: String(localized: "Nothing shared yet"),
                        message: String(format: String(localized: "Add an expense with %@ and it'll show up here.", comment: "Friend name"), friend.firstName),
                        actionTitle: String(localized: "Add an expense")
                    ) {
                        editorContext = ExpenseEditorContext(mode: .create(group: nil, participants: [user, friend]))
                    }
                } else {
                    timeline
                }

                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 4)
        }
        .screenBackground()
        .hidesFloatingAction()
        .navigationTitle(Text(friend.fullName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { isPresentingEdit = true } label: {
                        Label("Edit friend", systemImage: "pencil")
                    }
                    if canInvite {
                        Button { isPresentingInvite = true } label: {
                            Label("Invite by link", systemImage: "link")
                        }
                    }
                    Divider()
                    Button(role: .destructive) { archive() } label: {
                        Label("Remove friend", systemImage: "person.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editorContext) { ExpenseEditorView(context: $0) }
        .sheet(item: $selectedExpense) { ExpenseDetailView(expense: $0) }
        .sheet(isPresented: $isPresentingEdit) { FriendEditorView(friend: friend) }
        .sheet(isPresented: $isPresentingInvite) { InviteFriendView(friend: friend) }
        .sheet(isPresented: $isPresentingSettle) {
            let net = summary.net
            let code = net.nonZeroCurrencies.first ?? settings.baseCurrencyCode
            let amount = net.amount(in: code)
            RecordPaymentView(
                from: amount < 0 ? user : friend,
                to: amount < 0 ? friend : user,
                suggestedMinorUnits: abs(amount),
                currencyCode: code,
                group: nil
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        let money = summary.net.headline(
            baseCode: settings.baseCurrencyCode,
            rates: exchangeRates.table,
            convert: settings.convertToBaseCurrency
        )

        return Card(padding: 20) {
            VStack(spacing: 12) {
                AvatarView(participant: friend, size: Metrics.avatarLarge)

                Text(friend.fullName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.primaryText)

                if !friend.email.isEmpty || !friend.phone.isEmpty {
                    Text([friend.email, friend.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                }

                Divider().overlay(Palette.separator).padding(.vertical, 2)

                if summary.isSettled {
                    Text("You're settled up")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.neutral)
                } else {
                    VStack(spacing: 3) {
                        Text(
                            money.minorUnits > 0
                                ? String(format: String(localized: "%@ owes you", comment: "Friend name"), friend.firstName)
                                : String(format: String(localized: "You owe %@", comment: "Friend name"), friend.firstName)
                        )
                        .font(Typography.overline)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(Palette.tertiaryText)

                        Text(money.formattedAbsolute())
                            .font(Typography.displayMoney)
                            .foregroundStyle(Color.forBalance(money.minorUnits))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                editorContext = ExpenseEditorContext(mode: .create(group: nil, participants: [user, friend]))
            } label: {
                Label("Add expense", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button { isPresentingSettle = true } label: {
                Label("Settle up", systemImage: "checkmark.circle")
            }
            .buttonStyle(PrimaryButtonStyle(isProminent: false))
            .disabled(summary.isSettled)
        }
    }

    private var inviteCard: some View {
        Button { isPresentingInvite = true } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .foregroundStyle(Palette.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: String(localized: "Invite %@ to SplitFree", comment: "Friend name"), friend.firstName))
                            .font(Typography.rowTitle)
                            .foregroundStyle(Palette.primaryText)
                        Text("Send a link so your shared expenses reach their phone.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
        }
        .buttonStyle(RowButtonStyle())
    }

    private var sharedGroupsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(String(localized: "Groups you share"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sharedGroups) { group in
                            NavigationLink(value: group) {
                                HStack(spacing: 8) {
                                    GroupBadge(group: group, size: 28)
                                    Text(group.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Palette.primaryText)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(Palette.surfaceSunken, in: Capsule())
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

    private var timeline: some View {
        ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 8) {
                Text(section.title)
                    .font(Typography.overline)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                            switch entry {
                            case .expense(let expense):
                                Button { selectedExpense = expense } label: {
                                    ExpenseRow(expense: expense, user: user, showsGroupName: true)
                                }
                                .buttonStyle(RowButtonStyle())
                            case .settlement(let settlement):
                                SettlementRow(settlement: settlement, user: user)
                            }

                            if index < section.entries.count - 1 {
                                Divider().overlay(Palette.separator).padding(.leading, 100)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Archiving rather than deleting keeps their name on past expenses, so
    /// history never develops holes.
    private func archive() {
        friend.isArchived = true
        try? context.save()
        Haptics.tick()
        dismiss()
    }
}

// MARK: - Friend editor

struct FriendEditorView: View {
    var friend: Participant?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var colorIndex = 0
    @State private var avatarData: Data?
    @State private var venmo = ""
    @State private var paypal = ""
    @State private var cashApp = ""
    @State private var upi = ""
    @State private var photoItem: PhotosPickerItem?

    private var isEditing: Bool { friend != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    identityCard
                    contactCard
                    paymentCard
                    Color.clear.frame(height: 20)
                }
                .padding(Metrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(isEditing ? Text("Edit friend") : Text("New friend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text(isEditing ? "Save" : "Add").fontWeight(.semibold) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
        }
    }

    private var identityCard: some View {
        Card {
            VStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let avatarData, let image = UIImage(data: avatarData) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Palette.avatarColor(colorIndex)
                                .overlay {
                                    Text(initialsPreview)
                                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                        }
                    }
                    .frame(width: 78, height: 78)
                    .clipShape(Circle())

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(Palette.accent, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                    }
                }

                TextField(text: $name) { Text("Name") }
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
            .autocorrectionDisabled()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(Palette.avatarColors.enumerated()), id: \.offset) { index, color in
                            Button {
                                withAnimation(Motion.quick) { colorIndex = index }
                                Haptics.selectionChanged()
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if colorIndex == index {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var contactCard: some View {
        Card {
            VStack(spacing: 12) {
                labelledField(String(localized: "Email"), systemImage: "envelope", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                Divider().overlay(Palette.separator)
                labelledField(String(localized: "Phone"), systemImage: "phone", text: $phone)
                    .keyboardType(.phonePad)
            }
        }
    }

    /// Handles are optional. When present, the settle-up screen can hand off to
    /// that app with the amount pre-filled.
    private var paymentCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    String(localized: "Payment handles"),
                    subtitle: String(localized: "Optional. Used to open your payment app with the details filled in.")
                )
                labelledField("Venmo", systemImage: "v.circle", text: $venmo)
                Divider().overlay(Palette.separator)
                labelledField("PayPal.me", systemImage: "p.circle", text: $paypal)
                Divider().overlay(Palette.separator)
                labelledField("Cash App", systemImage: "dollarsign.circle", text: $cashApp)
                Divider().overlay(Palette.separator)
                labelledField(String(localized: "UPI ID"), systemImage: "indianrupeesign.circle", text: $upi)
            }
        }
    }

    private func labelledField(_ title: String, systemImage: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 22)
            TextField(text: text) { Text(title) }
                .font(Typography.rowSubtitle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var initialsPreview: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    private func load() {
        guard let friend else {
            colorIndex = Int.random(in: 0..<Palette.avatarColors.count)
            return
        }
        name = friend.name
        email = friend.email
        phone = friend.phone
        colorIndex = friend.colorIndex
        avatarData = friend.avatarData
        venmo = friend.venmoHandle
        paypal = friend.paypalHandle
        cashApp = friend.cashAppHandle
        upi = friend.upiHandle
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        avatarData = image.compressedForStorage(maxDimension: 400, quality: 0.8)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let target = friend ?? {
            let person = Participant(name: trimmed)
            context.insert(person)
            return person
        }()

        target.name = trimmed
        target.email = email.trimmingCharacters(in: .whitespaces)
        target.phone = phone.trimmingCharacters(in: .whitespaces)
        target.colorIndex = colorIndex
        target.avatarData = avatarData
        target.venmoHandle = venmo.trimmingCharacters(in: .whitespaces)
        target.paypalHandle = paypal.trimmingCharacters(in: .whitespaces)
        target.cashAppHandle = cashApp.trimmingCharacters(in: .whitespaces)
        target.upiHandle = upi.trimmingCharacters(in: .whitespaces)

        try? context.save()
        Haptics.success()
        dismiss()
    }
}
