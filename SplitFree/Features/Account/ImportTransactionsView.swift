import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Import a bank or card CSV: pick the file, check the column mapping, review
/// the rows, then commit.
struct ImportTransactionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates

    @Query private var groups: [SpendingGroup]
    @Query private var participants: [Participant]

    @State private var stage: Stage = .pickFile
    @State private var isPresentingFilePicker = false
    @State private var rawLines: [String] = []
    @State private var parsed = TransactionImporter.ParseResult()
    @State private var rows: [TransactionImporter.Row] = []
    @State private var selectedGroup: SpendingGroup?
    @State private var selectedParticipantIDs: Set<UUID> = []
    @State private var splitEqually = true
    @State private var errorMessage: String?
    @State private var importedCount: Int?

    private enum Stage {
        case pickFile, mapColumns, review, done
    }

    private var user: Participant { Ledger.currentUser(in: context) }

    private var candidates: [Participant] {
        if let selectedGroup { return selectedGroup.memberList }
        return participants.filter { !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .pickFile: introView
                case .mapColumns: mappingView
                case .review: reviewView
                case .done: doneView
                }
            }
            .screenBackground()
            .navigationTitle(Text("Import transactions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(stage == .done ? "Close" : "Cancel") }
                }
                if stage == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { commit() } label: {
                            Text("Import").fontWeight(.semibold)
                        }
                        .disabled(rows.allSatisfy { !$0.isSelected } || selectedParticipantIDs.isEmpty)
                    }
                }
            }
            .fileImporter(
                isPresented: $isPresentingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]
            ) { result in
                handleFile(result)
            }
            .alert(
                Text("Couldn't read that file"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button { errorMessage = nil } label: { Text("OK") }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Stages

    private var introView: some View {
        ScrollView {
            VStack(spacing: 18) {
                EmptyStateView(
                    symbol: "square.and.arrow.down",
                    title: String(localized: "Bring in your statement"),
                    message: String(localized: "Export a CSV from your bank or card app, then pick it here. SplitFree reads it on your device — nothing is uploaded anywhere."),
                    actionTitle: String(localized: "Choose a CSV file")
                ) { isPresentingFilePicker = true }

                InfoBanner(
                    symbol: "lock.fill",
                    text: String(localized: "Most banks call this “Export”, “Download transactions”, or “Statement as CSV”. Money coming in is skipped — only spending becomes an expense.")
                )
                .padding(.horizontal, Metrics.screenPadding)
            }
        }
    }

    private var mappingView: some View {
        Form {
            if let warning = parsed.warning {
                Section {
                    Text(warning)
                        .font(Typography.rowSubtitle)
                        .foregroundStyle(Palette.secondaryText)
                }
            }

            Section {
                columnPicker(String(localized: "Date"), selection: $parsed.mapping.dateIndex)
                columnPicker(String(localized: "Description"), selection: $parsed.mapping.descriptionIndex)
                columnPicker(String(localized: "Amount"), selection: $parsed.mapping.amountIndex)
                columnPicker(String(localized: "Money out"), selection: $parsed.mapping.debitIndex)
                columnPicker(String(localized: "Money in"), selection: $parsed.mapping.creditIndex)
                columnPicker(String(localized: "Currency"), selection: $parsed.mapping.currencyIndex)
            } header: {
                Text("Which column is which?")
            } footer: {
                Text("Use either a single Amount column, or a Money out / Money in pair.")
            }

            Section {
                Button {
                    reparse()
                } label: {
                    Text("Continue").fontWeight(.semibold)
                }
                .disabled(!parsed.mapping.isUsable)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
    }

    private func columnPicker(_ title: String, selection: Binding<Int?>) -> some View {
        Picker(selection: selection) {
            Text("None").tag(Int?.none)
            ForEach(Array(parsed.headers.enumerated()), id: \.offset) { index, header in
                Text(header.isEmpty ? String(format: String(localized: "Column %lld", comment: "Index"), index + 1) : header)
                    .tag(Int?.some(index))
            }
        } label: {
            Text(title)
        }
    }

    private var reviewView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                destinationCard
                summaryCard

                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach($rows) { $row in
                            Button {
                                withAnimation(Motion.quick) { row.isSelected.toggle() }
                                Haptics.selectionChanged()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 21))
                                        .foregroundStyle(row.isSelected ? Palette.accent : Palette.separator)

                                    CategoryBadge(category: row.category, size: 34)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.descriptionText)
                                            .font(Typography.rowSubtitle)
                                            .foregroundStyle(Palette.primaryText)
                                            .lineLimit(1)
                                        Text(row.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                            .font(.caption2)
                                            .foregroundStyle(Palette.tertiaryText)
                                    }

                                    Spacer(minLength: 4)

                                    Text(Money(minorUnits: row.amountMinorUnits, currencyCode: row.currencyCode).formatted())
                                        .font(Typography.captionMoney)
                                        .foregroundStyle(Palette.secondaryText)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, Metrics.cardPadding)
                                .padding(.vertical, 10)
                                .opacity(row.isSelected ? 1 : 0.45)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Color.clear.frame(height: 30)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 4)
        }
    }

    private var destinationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(String(localized: "Where should these go?"))

                Picker(selection: $selectedGroup.animation(Motion.quick)) {
                    Text("No group").tag(SpendingGroup?.none)
                    ForEach(groups.filter { !$0.isArchived }) { group in
                        Text(group.displayName).tag(SpendingGroup?.some(group))
                    }
                } label: {
                    Text("Group")
                }
                .pickerStyle(.menu)
                .tint(Palette.accent)
                .onChange(of: selectedGroup) { _, group in
                    selectedParticipantIDs = Set((group?.memberList ?? [user]).map(\.id))
                }

                Divider().overlay(Palette.separator)

                Text("Split between")
                    .font(Typography.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.tertiaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(candidates) { person in
                            PersonToggleChip(
                                participant: person,
                                isOn: selectedParticipantIDs.contains(person.id),
                                amount: nil
                            ) {
                                withAnimation(Motion.quick) {
                                    if selectedParticipantIDs.contains(person.id) {
                                        if selectedParticipantIDs.count > 1 {
                                            selectedParticipantIDs.remove(person.id)
                                        }
                                    } else {
                                        selectedParticipantIDs.insert(person.id)
                                    }
                                }
                                Haptics.selectionChanged()
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()

                Toggle(isOn: $splitEqually) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Split each one equally")
                            .font(Typography.rowTitle)
                        Text(splitEqually
                            ? String(localized: "Everyone selected shares each transaction.")
                            : String(localized: "Recorded as yours alone — useful for tracking your own spending."))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                .tint(Palette.accent)
            }
        }
    }

    private var summaryCard: some View {
        let selected = rows.filter(\.isSelected)
        let codes = Set(selected.map(\.currencyCode))
        let total = codes.count == 1 ? selected.reduce(0) { $0 + $1.amountMinorUnits } : 0

        return Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("^[\(selected.count) transaction](inflect: true) selected")
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.primaryText)
                    if parsed.skippedCount > 0 {
                        Text("^[\(parsed.skippedCount) row](inflect: true) skipped — no usable date or amount, or money coming in.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                Spacer()
                if codes.count == 1, let code = codes.first {
                    Text(Money(minorUnits: total, currencyCode: code).formatted())
                        .font(Typography.rowMoney)
                        .foregroundStyle(Palette.primaryText)
                        .monospacedDigit()
                }
            }
        }
    }

    private var doneView: some View {
        EmptyStateView(
            symbol: "checkmark.circle.fill",
            title: String(localized: "Imported"),
            message: String(
                localized: "^[\(importedCount ?? 0) expense](inflect: true) added. You can edit any of them like normal.",
                comment: "Count"
            ),
            actionTitle: String(localized: "Done")
        ) { dismiss() }
    }

    // MARK: - Actions

    private func handleFile(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                errorMessage = String(localized: "The file couldn't be opened.")
                return
            }
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            guard !text.isEmpty else {
                errorMessage = String(localized: "The file appears to be empty or in an unsupported encoding.")
                return
            }

            parsed = TransactionImporter.parse(csv: text, defaultCurrency: settings.baseCurrencyCode)
            rawLines = text
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            rows = parsed.rows
            selectedParticipantIDs = [user.id]

            if parsed.mapping.isUsable && !rows.isEmpty {
                stage = .review
            } else {
                stage = .mapColumns
            }
            Haptics.tick()
        }
    }

    private func reparse() {
        var skipped = 0
        rows = TransactionImporter.rows(
            from: Array(rawLines.dropFirst()),
            mapping: parsed.mapping,
            defaultCurrency: settings.baseCurrencyCode,
            skipped: &skipped
        )
        parsed.skippedCount = skipped
        stage = rows.isEmpty ? .mapColumns : .review
        if rows.isEmpty {
            errorMessage = String(localized: "No rows could be read with those columns. Try a different mapping.")
        }
    }

    private func commit() {
        let people = candidates.filter { selectedParticipantIDs.contains($0.id) }
        guard !people.isEmpty else { return }
        let count = TransactionImporter.commit(
            rows: rows,
            group: selectedGroup,
            participants: people,
            payer: user,
            splitEqually: splitEqually,
            baseCurrencyCode: settings.baseCurrencyCode,
            rates: exchangeRates.table,
            in: context
        )
        importedCount = count
        stage = .done
        Haptics.success()
    }
}
