import PhotosUI
import SwiftData
import SwiftUI

/// Describes what the editor should open with.
struct ExpenseEditorContext: Identifiable {
    enum Mode {
        case create(group: SpendingGroup?, participants: [Participant])
        case edit(Expense)
    }

    var id = UUID()
    var mode: Mode
}

/// The add/edit expense screen.
///
/// The layout is a funnel: the amount is the biggest thing on screen, then what
/// it was for, then who's involved. Paying and splitting are single summary rows
/// that open focused sheets, so the common case - one person paid, split evenly -
/// is a three-field form.
struct ExpenseEditorView: View {
    let context: ExpenseEditorContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(ExchangeRateService.self) private var exchangeRates

    @Query private var allGroups: [SpendingGroup]
    @Query private var allParticipants: [Participant]

    @State private var draft: ExpenseDraft?
    @State private var activeSheet: EditorSheet?
    @State private var showsMoreOptions = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showsDeleteConfirmation = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case amount, title, notes }

    private enum EditorSheet: Identifiable {
        case currency, category, participants, paidBy, split, itemize, scanReceipt, group

        var id: String { String(describing: self) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    editorForm(draft)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .screenBackground()
            .navigationTitle(isEditing ? Text("Edit expense") : Text("New expense"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear(perform: prepareDraft)
        }
        .presentationDragIndicator(.visible)
    }

    private var isEditing: Bool {
        if case .edit = context.mode { return true }
        return false
    }

    // MARK: - Form

    @ViewBuilder
    private func editorForm(_ draft: ExpenseDraft) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                amountCard(draft)
                detailsCard(draft)
                peopleCard(draft)
                splitCard(draft)

                DisclosureGroup(isExpanded: $showsMoreOptions) {
                    moreOptions(draft)
                        .padding(.top, 12)
                } label: {
                    Text("More options")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
                .padding(Metrics.cardPadding)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(Palette.separator.opacity(0.6), lineWidth: 0.5)
                )

                if isEditing {
                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Label("Delete expense", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Palette.negative, isProminent: false))
                }

                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet, draft: draft)
        }
        .confirmationDialog(
            Text("Delete this expense?"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let expense = draft.editingExpense {
                    Ledger.delete(expense: expense, in: modelContext)
                    try? modelContext.save()
                    Haptics.success()
                }
                dismiss()
            } label: {
                Text("Delete")
            }
        } message: {
            Text("Balances will be recalculated for everyone involved.")
        }
        .onChange(of: photoItem) { _, item in
            Task { await loadReceiptPhoto(item, into: draft) }
        }
    }

    // MARK: - Amount

    @ViewBuilder
    private func amountCard(_ draft: ExpenseDraft) -> some View {
        @Bindable var draft = draft
        Card(padding: 20) {
            VStack(spacing: 12) {
                Button {
                    activeSheet = .currency
                } label: {
                    HStack(spacing: 5) {
                        Text(Currency.flag(for: draft.currencyCode))
                        Text(draft.currencyCode)
                            .font(.footnote.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Palette.surfaceSunken, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Currency: \(Currency.name(for: draft.currencyCode))"))

                MoneyField(
                    minorUnits: $draft.amountMinorUnits,
                    currencyCode: draft.currencyCode,
                    font: Typography.money(46, weight: .bold),
                    focusesOnAppear: !isEditing
                )

                if draft.currencyCode != settings.baseCurrencyCode, draft.amountMinorUnits > 0 {
                    convertedHint(draft)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func convertedHint(_ draft: ExpenseDraft) -> some View {
        let converted = exchangeRates.table.convert(
            minorUnits: draft.amountMinorUnits,
            from: draft.currencyCode,
            to: settings.baseCurrencyCode
        )
        if converted > 0 {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                Text("≈ \(Money(minorUnits: converted, currencyCode: settings.baseCurrencyCode).formatted())")
                if exchangeRates.table.isOffline {
                    Text("· \(String(localized: "offline rate"))")
                }
            }
            .font(.caption)
            .foregroundStyle(Palette.tertiaryText)
        }
    }

    // MARK: - Details

    @ViewBuilder
    private func detailsCard(_ draft: ExpenseDraft) -> some View {
        @Bindable var draft = draft
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button { activeSheet = .category } label: {
                        CategoryBadge(category: draft.category, size: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Category: \(draft.category.title)"))

                    TextField(text: $draft.title) {
                        Text("What was it for?")
                    }
                    .font(Typography.rowTitle)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.done)
                }
                .padding(Metrics.cardPadding)

                Divider().overlay(Palette.separator).padding(.leading, 68)

                DatePicker(selection: $draft.date, displayedComponents: .date) {
                    Label {
                        Text("Date")
                    } icon: {
                        Image(systemName: "calendar")
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .font(Typography.rowTitle)
                }
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.vertical, 10)

                Divider().overlay(Palette.separator).padding(.leading, 52)

                Button { activeSheet = .group } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(Palette.secondaryText)
                            .frame(width: 22)
                        Text("Group")
                            .font(Typography.rowTitle)
                            .foregroundStyle(Palette.primaryText)
                        Spacer()
                        Text(draft.group?.displayName ?? String(localized: "No group"))
                            .font(Typography.rowSubtitle)
                            .foregroundStyle(Palette.secondaryText)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                    .padding(Metrics.cardPadding)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - People

    @ViewBuilder
    private func peopleCard(_ draft: ExpenseDraft) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(String(localized: "Split between")) {
                    Button {
                        activeSheet = .participants
                    } label: {
                        Text("Edit")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                if draft.includedParticipants.isEmpty {
                    Text("Choose who shared this expense.")
                        .font(Typography.rowSubtitle)
                        .foregroundStyle(Palette.secondaryText)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(draft.candidates) { person in
                                PersonToggleChip(
                                    participant: person,
                                    isOn: draft.isIncluded(person),
                                    amount: draft.isIncluded(person)
                                        ? Money(
                                            minorUnits: draft.allocatedAmount(for: person.id),
                                            currencyCode: draft.currencyCode
                                          ).formatted()
                                        : nil
                                ) {
                                    withAnimation(Motion.quick) {
                                        draft.toggleInclusion(person)
                                    }
                                    Haptics.selectionChanged()
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollClipDisabled()
                }
            }
        }
    }

    // MARK: - Paid by & split

    @ViewBuilder
    private func splitCard(_ draft: ExpenseDraft) -> some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                summaryRow(
                    symbol: "creditcard.fill",
                    title: String(localized: "Paid by"),
                    value: draft.payerSummaryText,
                    warning: draft.payerRemainder != 0
                        ? String(
                            format: String(localized: "%@ unassigned", comment: "Remaining payer amount"),
                            Money(minorUnits: abs(draft.payerRemainder), currencyCode: draft.currencyCode).formatted()
                          )
                        : nil
                ) { activeSheet = .paidBy }

                Divider().overlay(Palette.separator).padding(.leading, 52)

                summaryRow(
                    symbol: draft.splitMethod.symbol,
                    title: String(localized: "Split"),
                    value: draft.splitSummaryText,
                    warning: draft.validationIssue.flatMap { issue in
                        issue == .negativeTotal ? nil : issue.message
                    }
                ) { activeSheet = .split }
            }
        }
    }

    @ViewBuilder
    private func summaryRow(
        symbol: String,
        title: String,
        value: String,
        warning: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.primaryText)
                    Text(value)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                    if let warning {
                        Label(warning, systemImage: "exclamationmark.circle.fill")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.negative)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryText)
            }
            .padding(Metrics.cardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - More options

    @ViewBuilder
    private func moreOptions(_ draft: ExpenseDraft) -> some View {
        @Bindable var draft = draft
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(Typography.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.tertiaryText)
                TextField(text: $draft.notes, axis: .vertical) {
                    Text("Add a note")
                }
                .font(Typography.rowSubtitle)
                .lineLimit(2...5)
                .focused($focusedField, equals: .notes)
                .padding(10)
                .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Receipt")
                    .font(Typography.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.tertiaryText)

                if let data = draft.receiptImageData, let image = UIImage(data: data) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                activeSheet = .itemize
                            } label: {
                                Label("Itemize", systemImage: "list.bullet.rectangle")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            Button(role: .destructive) {
                                draft.receiptImageData = nil
                                draft.receiptText = ""
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .buttonStyle(SecondaryButtonStyle(tint: Palette.negative))
                        }
                        Spacer()
                    }
                } else {
                    HStack(spacing: 10) {
                        Button {
                            activeSheet = .scanReceipt
                        } label: {
                            Label("Scan", systemImage: "doc.viewfinder")
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Choose photo", systemImage: "photo")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Palette.accent.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $draft.isRecurring.animation(Motion.quick)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Repeat this expense")
                            .font(Typography.rowTitle)
                        Text("SplitFree will add it automatically.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                .tint(Palette.accent)

                if draft.isRecurring {
                    Picker(selection: $draft.recurrenceFrequency) {
                        ForEach(RecurrenceFrequency.allCases) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    } label: {
                        Text("Frequency")
                    }
                    .pickerStyle(.menu)
                    .tint(Palette.accent)
                }
            }

            Button {
                activeSheet = .itemize
            } label: {
                HStack {
                    Label("Itemize the bill", systemImage: "list.bullet.rectangle")
                    Spacer()
                    if !draft.lineItems.isEmpty {
                        Text("^[\(draft.lineItems.count) item](inflect: true)")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryText)
                }
                .font(Typography.rowTitle)
                .foregroundStyle(Palette.primaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: EditorSheet, draft: ExpenseDraft) -> some View {
        @Bindable var draft = draft
        switch sheet {
        case .currency:
            CurrencyPickerSheet(selection: $draft.currencyCode)
        case .category:
            CategoryPickerSheet(selection: draft.category) { draft.setCategory($0) }
        case .participants:
            ParticipantPickerSheet(draft: draft, allParticipants: allParticipants)
        case .paidBy:
            PaidBySheet(draft: draft)
        case .split:
            SplitEditorSheet(draft: draft)
        case .itemize:
            ItemizationSheet(draft: draft)
        case .scanReceipt:
            ReceiptScanSheet { image, text, items in
                applyScan(image: image, text: text, items: items, to: draft)
            }
        case .group:
            GroupPickerSheet(selection: draft.group, groups: allGroups.filter { !$0.isArchived && !$0.isDirect }) { group in
                apply(group: group, to: draft)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Text("Cancel") }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                save()
            } label: {
                Text("Save").fontWeight(.semibold)
            }
            .disabled(draft?.canSave != true)
        }
        ToolbarItem(placement: .keyboard) {
            HStack {
                Spacer()
                Button {
                    focusedField = nil
                    UIApplication.dismissKeyboard()
                } label: { Text("Done") }
            }
        }
    }

    // MARK: - Actions

    private func prepareDraft() {
        guard draft == nil else { return }
        let user = Ledger.currentUser(in: modelContext)

        switch context.mode {
        case .create(let group, let participants):
            var people = participants
            if let group {
                people = group.memberList
            }
            if people.isEmpty {
                // A groupless expense starts with just you; the picker adds friends.
                people = [user]
            }
            if !people.contains(where: { $0.id == user.id }) {
                people.insert(user, at: 0)
            }
            let newDraft = ExpenseDraft(
                currentUser: user,
                group: group,
                candidates: people,
                currencyCode: group?.defaultCurrencyCode ?? settings.baseCurrencyCode
            )
            applyDefaultTemplateIfAvailable(to: newDraft, group: group)
            draft = newDraft
            focusedField = .amount

        case .edit(let expense):
            let candidates = expense.group?.memberList ?? allParticipants
            draft = ExpenseDraft(editing: expense, currentUser: user, candidates: candidates)
        }
    }

    /// If the group has a saved default split, start from it.
    private func applyDefaultTemplateIfAvailable(to draft: ExpenseDraft, group: SpendingGroup?) {
        guard let group,
              let template = group.templateList.first(where: \.isDefaultForGroup)
        else { return }
        SplitTemplateApplier.apply(template, to: draft)
    }

    private func apply(group: SpendingGroup?, to draft: ExpenseDraft) {
        draft.group = group
        if let group {
            draft.candidates = group.memberList
            draft.includedIDs = Set(group.memberList.map(\.id))
            draft.currencyCode = group.defaultCurrencyCode
        } else {
            var people = draft.candidates.filter { $0.id == draft.currentUser.id }
            if people.isEmpty { people = [draft.currentUser] }
            draft.candidates = people
            draft.includedIDs = Set(people.map(\.id))
        }
        if draft.singlePayerID == nil || !draft.includedIDs.contains(draft.singlePayerID!) {
            draft.singlePayerID = draft.currentUser.id
        }
    }

    private func applyScan(image: UIImage?, text: String, items: [ExpenseDraft.DraftLineItem], to draft: ExpenseDraft) {
        if let image { draft.receiptImageData = image.compressedForStorage() }
        draft.receiptText = text
        if !items.isEmpty {
            draft.lineItems = items
            if draft.amountMinorUnits == 0 {
                draft.adoptItemizedTotal()
            }
        }
        Haptics.success()
    }

    private func loadReceiptPhoto(_ item: PhotosPickerItem?, into draft: ExpenseDraft) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        draft.receiptImageData = image.compressedForStorage()

        // Run the same recognition the scanner uses, so a photo from the
        // library itemizes itself instead of opening an empty manual sheet.
        // Hand-entered items are never overwritten.
        let result = await ReceiptParser.parse(image: image, currencyCode: draft.currencyCode)
        draft.receiptText = result.rawText
        if draft.lineItems.isEmpty, !result.items.isEmpty {
            draft.lineItems = result.items.map {
                ExpenseDraft.DraftLineItem(
                    name: $0.name,
                    amountMinorUnits: $0.amountMinorUnits,
                    quantity: $0.quantity
                )
            }
            if draft.amountMinorUnits == 0 {
                draft.adoptItemizedTotal()
            }
            Haptics.success()
        }
    }

    private func save() {
        guard let draft, draft.canSave else { return }
        draft.save(in: modelContext, settings: settings, rates: exchangeRates.table)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Person chip

/// A tappable avatar chip showing whether someone is in the split and, if so,
/// what they'd owe. Seeing the number update as you tap is the whole point.
struct PersonToggleChip: View {
    var participant: Participant
    var isOn: Bool
    var amount: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                AvatarView(participant: participant, size: 46, showsRing: isOn)
                    .overlay(alignment: .bottomTrailing) {
                        if isOn {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white, Palette.accent)
                                .offset(x: 2, y: 2)
                        }
                    }
                    .opacity(isOn ? 1 : 0.42)
                    .saturation(isOn ? 1 : 0.2)

                Text(participant.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isOn ? Palette.primaryText : Palette.tertiaryText)
                    .lineLimit(1)

                Text(amount ?? " ")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.secondaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .opacity(isOn ? 1 : 0)
            }
            .frame(width: 68)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(participant.fullName))
        .accessibilityValue(Text(isOn ? (amount ?? String(localized: "Included")) : String(localized: "Not included")))
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

extension UIImage {
    /// Downscales and JPEG-compresses so a receipt photo doesn't bloat the store
    /// (and, with sync on, the user's iCloud quota).
    func compressedForStorage(maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
