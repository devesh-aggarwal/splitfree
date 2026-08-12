import SwiftData
import SwiftUI

struct AccountView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(AppLockState.self) private var lock

    @Query private var expenses: [Expense]
    @Query private var groups: [SpendingGroup]
    @Query private var participants: [Participant]
    @Query private var rules: [RecurringRule]

    @State private var isPresentingProfile = false
    @State private var isPresentingCurrency = false
    @State private var isPresentingImport = false
    @State private var isPresentingRecurring = false
    @State private var isPresentingAbout = false
    @State private var exportURL: URL?
    @State private var showsResetConfirmation = false

    private var user: Participant { Ledger.currentUser(in: context) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profileCard
                    freeForeverCard
                    preferencesCard
                    dataCard
                    aboutCard
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 4)
            }
            .screenBackground()
            .navigationTitle(Text("Account"))
            .sheet(isPresented: $isPresentingProfile) { ProfileEditorView() }
            .sheet(isPresented: $isPresentingCurrency) {
                CurrencyPickerSheet(selection: Binding(
                    get: { settings.baseCurrencyCode },
                    set: { settings.baseCurrencyCode = $0 }
                ))
            }
            .sheet(isPresented: $isPresentingImport) { ImportTransactionsView() }
            .sheet(isPresented: $isPresentingRecurring) { RecurringRulesView() }
            .sheet(isPresented: $isPresentingAbout) { AboutView() }
            .confirmationDialog(
                Text("Erase everything?"),
                isPresented: $showsResetConfirmation,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) { eraseEverything() } label: {
                    Text("Erase all data")
                }
            } message: {
                Text("Every group, expense, payment and friend will be deleted from this device. This can't be undone — export a CSV first if you want a copy.")
            }
        }
    }

    // MARK: - Profile

    private var profileCard: some View {
        Button { isPresentingProfile = true } label: {
            Card {
                HStack(spacing: 14) {
                    AvatarView(participant: user, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.fullName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.primaryText)
                        Text(user.email.isEmpty ? String(localized: "Tap to add your details") : user.email)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
        }
        .buttonStyle(RowButtonStyle())
    }

    /// The product promise, stated plainly and where people look for the
    /// upgrade prompt in every other app.
    private var freeForeverCard: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.accent)
                    Text("Everything is included")
                        .font(.headline)
                        .foregroundStyle(Palette.primaryText)
                }
                Text("No subscription, no upgrade screen, no adverts, no limits on expenses, and nothing held back for a paid tier. Your data stays on your device and in your own iCloud.")
                    .font(Typography.rowSubtitle)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button { isPresentingAbout = true } label: {
                    Text("What's included")
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Preferences

    private var preferencesCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                row(
                    symbol: "dollarsign.circle",
                    title: String(localized: "Your currency"),
                    subtitle: String(localized: "Totals across groups are shown in this."),
                    value: "\(Currency.flag(for: settings.baseCurrencyCode)) \(settings.baseCurrencyCode)"
                ) { isPresentingCurrency = true }

                divider

                toggleRow(
                    symbol: "arrow.left.arrow.right",
                    title: String(localized: "Convert other currencies"),
                    subtitle: exchangeRates.table.isOffline
                        ? String(localized: "Using built-in rates. Pull to refresh on the Groups tab.")
                        : String(format: String(localized: "Rates updated %@", comment: "Relative time"), exchangeRates.table.ageDescription),
                    isOn: Binding(
                        get: { settings.convertToBaseCurrency },
                        set: { settings.convertToBaseCurrency = $0 }
                    )
                )

                divider

                toggleRow(
                    symbol: "arrow.triangle.merge",
                    title: String(localized: "Simplify debts by default"),
                    subtitle: String(localized: "New groups start with balances collapsed into the fewest payments."),
                    isOn: Binding(
                        get: { settings.simplifyDebtsByDefault },
                        set: { settings.simplifyDebtsByDefault = $0 }
                    )
                )

                divider

                appearanceRow

                divider

                toggleRow(
                    symbol: "hand.tap",
                    title: String(localized: "Haptics"),
                    subtitle: String(localized: "A small nudge when something is saved or settled."),
                    isOn: Binding(
                        get: { settings.hapticsEnabled },
                        set: { settings.hapticsEnabled = $0 }
                    )
                )

                divider

                toggleRow(
                    symbol: "faceid",
                    title: String(format: String(localized: "Require %@", comment: "Biometry name"), lock.biometryName),
                    subtitle: lock.isBiometryAvailable
                        ? String(localized: "Lock the app when you leave it.")
                        : String(localized: "Not available on this device."),
                    isOn: Binding(
                        get: { settings.requiresBiometricUnlock },
                        set: { settings.requiresBiometricUnlock = $0 }
                    )
                )
                .disabled(!lock.isBiometryAvailable)

                divider

                toggleRow(
                    symbol: "icloud",
                    title: String(localized: "iCloud sync"),
                    subtitle: String(localized: "Keeps your ledger on all your devices. Takes effect next launch."),
                    isOn: Binding(
                        get: { settings.cloudSyncEnabled },
                        set: { settings.cloudSyncEnabled = $0 }
                    )
                )
            }
        }
    }

    private var appearanceRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 24)
            Text("Appearance")
                .font(Typography.rowTitle)
                .foregroundStyle(Palette.primaryText)
            Spacer()
            Picker(selection: Binding(
                get: { settings.appearance },
                set: { settings.appearance = $0 }
            )) {
                ForEach(AppSettings.Appearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                Text("Appearance")
            }
            .pickerStyle(.menu)
            .tint(Palette.accent)
        }
        .padding(Metrics.cardPadding)
    }

    // MARK: - Data

    private var dataCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                row(
                    symbol: "arrow.triangle.2.circlepath",
                    title: String(localized: "Recurring expenses"),
                    subtitle: rules.isEmpty
                        ? String(localized: "Rent, bills, shared subscriptions.")
                        : String(localized: "^[\(rules.filter(\.isActive).count) rule](inflect: true) running", comment: "Count"),
                    value: nil
                ) { isPresentingRecurring = true }

                divider

                row(
                    symbol: "square.and.arrow.down",
                    title: String(localized: "Import transactions"),
                    subtitle: String(localized: "Read a bank or card CSV into expenses."),
                    value: nil
                ) { isPresentingImport = true }

                divider

                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Palette.secondaryText)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export everything")
                            .font(Typography.rowTitle)
                            .foregroundStyle(Palette.primaryText)
                        Text("^[\(expenses.count) expense](inflect: true) as a CSV file.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Spacer()
                    ShareLink(
                        item: GroupExporter.csvForEverything(in: context),
                        preview: SharePreview("SplitFree.csv")
                    ) {
                        Text("Export")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .padding(Metrics.cardPadding)

                divider

                Button(role: .destructive) {
                    showsResetConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .foregroundStyle(Palette.negative)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Erase all data")
                                .font(Typography.rowTitle)
                                .foregroundStyle(Palette.negative)
                            Text("Start over from scratch.")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(Metrics.cardPadding)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                row(
                    symbol: "info.circle",
                    title: String(localized: "About SplitFree"),
                    subtitle: String(localized: "Version \(appVersion)"),
                    value: nil
                ) { isPresentingAbout = true }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Row helpers

    private var divider: some View {
        Divider().overlay(Palette.separator).padding(.leading, 52)
    }

    private func row(
        symbol: String,
        title: String,
        subtitle: String,
        value: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.primaryText)
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                if let value {
                    Text(value)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.secondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryText)
            }
            .padding(Metrics.cardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(
        symbol: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 24)
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.primaryText)
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
            }
            .tint(Palette.accent)
        }
        .padding(Metrics.cardPadding)
    }

    // MARK: - Actions

    /// Deletes the whole store, then recreates the current user so the app has
    /// a valid starting state rather than an empty one.
    private func eraseEverything() {
        for expense in Ledger.allExpenses(in: context) { context.delete(expense) }
        for settlement in Ledger.allSettlements(in: context) { context.delete(settlement) }
        for group in groups { context.delete(group) }
        for rule in rules { context.delete(rule) }
        for person in participants { context.delete(person) }
        if let entries = try? context.fetch(FetchDescriptor<ActivityEntry>()) {
            for entry in entries { context.delete(entry) }
        }
        if let templates = try? context.fetch(FetchDescriptor<SplitTemplate>()) {
            for template in templates { context.delete(template) }
        }
        try? context.save()
        Ledger.currentUser(in: context)
        Haptics.warning()
    }
}

// MARK: - Profile editor

struct ProfileEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FriendEditorView(friend: Ledger.currentUser(in: context))
    }
}
