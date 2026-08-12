import SwiftUI

/// Assigns each line on a bill to the people who actually had it.
///
/// The mental model is the receipt itself: one row per item, and under each row
/// the faces of everyone sharing it. Tapping a face adds or removes them, and
/// the per-person totals at the bottom move as you go.
struct ItemizationSheet: View {
    @Bindable var draft: ExpenseDraft

    @Environment(\.dismiss) private var dismiss
    @State private var focusedItemID: UUID?
    @FocusState private var isEditingText: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if draft.lineItems.isEmpty {
                        EmptyStateView(
                            symbol: "list.bullet.rectangle",
                            title: String(localized: "No items yet"),
                            message: String(localized: "Add each line from the bill, then tap the people who shared it."),
                            actionTitle: String(localized: "Add the first item")
                        ) { addItem() }
                    } else {
                        ForEach($draft.lineItems) { $item in
                            itemCard($item)
                        }

                        Button { addItem() } label: {
                            Label("Add an item", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    extrasCard
                    totalsCard
                    Color.clear.frame(height: 60)
                }
                .padding(Metrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(Text("Itemize"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { apply() } label: { Text("Done").fontWeight(.semibold) }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button { isEditingText = false } label: { Text("Done") }
                    }
                }
            }
        }
    }

    // MARK: - Item card

    private func itemCard(_ item: Binding<ExpenseDraft.DraftLineItem>) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField(text: item.name) {
                        Text("Item")
                    }
                    .font(Typography.rowTitle)
                    .focused($isEditingText)

                    if item.wrappedValue.quantity > 1 {
                        Text("×\(item.wrappedValue.quantity)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.secondaryText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Palette.surfaceSunken, in: Capsule())
                    }

                    InlineMoneyField(
                        minorUnits: item.amountMinorUnits,
                        currencyCode: draft.currencyCode
                    )
                    .focused($isEditingText)

                    Menu {
                        Stepper(value: item.quantity, in: 1...99) {
                            Text("Quantity: \(item.wrappedValue.quantity)")
                        }
                        Button(role: .destructive) {
                            withAnimation(Motion.snappy) { remove(item.wrappedValue.id) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 19))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(assigneeCaption(for: item.wrappedValue))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                        Spacer()
                        Button {
                            withAnimation(Motion.quick) {
                                if item.wrappedValue.assigneeIDs.isEmpty {
                                    item.wrappedValue.assigneeIDs = draft.includedIDs
                                } else {
                                    item.wrappedValue.assigneeIDs = []
                                }
                            }
                            Haptics.tick()
                        } label: {
                            Text(item.wrappedValue.assigneeIDs.isEmpty ? String(localized: "Pick people") : String(localized: "Everyone"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(draft.includedParticipants) { person in
                                let isOn = item.wrappedValue.assigneeIDs.contains(person.id)
                                    || item.wrappedValue.assigneeIDs.isEmpty
                                Button {
                                    withAnimation(Motion.quick) {
                                        toggle(person.id, in: item)
                                    }
                                    Haptics.selectionChanged()
                                } label: {
                                    AvatarView(participant: person, size: 34, showsRing: isOn)
                                        .opacity(isOn ? 1 : 0.35)
                                        .saturation(isOn ? 1 : 0.1)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(person.fullName))
                                .accessibilityValue(Text(isOn ? String(localized: "Sharing this item") : String(localized: "Not sharing")))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollClipDisabled()
                }
            }
        }
    }

    private func assigneeCaption(for item: ExpenseDraft.DraftLineItem) -> String {
        if item.assigneeIDs.isEmpty {
            return String(localized: "Shared by everyone")
        }
        let names = item.assigneeIDs
            .compactMap { draft.participant(id: $0)?.displayName }
            .sorted()
        if names.count <= 2 { return names.joined(separator: ", ") }
        return String(
            format: String(localized: "%1$@ and %2$lld others", comment: "Name, count"),
            names[0],
            names.count - 1
        )
    }

    // MARK: - Extras

    private var extrasCard: some View {
        Card {
            VStack(spacing: 12) {
                HStack {
                    Label("Tax", systemImage: "percent")
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.primaryText)
                    Spacer()
                    InlineMoneyField(minorUnits: $draft.taxMinorUnits, currencyCode: draft.currencyCode)
                        .focused($isEditingText)
                }
                Divider().overlay(Palette.separator)
                HStack {
                    Label("Tip", systemImage: "hands.clap")
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.primaryText)
                    Spacer()
                    InlineMoneyField(minorUnits: $draft.tipMinorUnits, currencyCode: draft.currencyCode)
                        .focused($isEditingText)
                }

                if draft.taxMinorUnits != 0 || draft.tipMinorUnits != 0 {
                    Text("Tax and tip are shared in proportion to what each person ordered.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Totals

    private var totalsCard: some View {
        VStack(spacing: 12) {
            Card {
                VStack(spacing: 10) {
                    HStack {
                        Text("Items")
                            .font(Typography.rowSubtitle)
                            .foregroundStyle(Palette.secondaryText)
                        Spacer()
                        Text(Money(minorUnits: draft.lineItemsTotalMinorUnits, currencyCode: draft.currencyCode).formatted())
                            .font(Typography.rowMoney)
                            .foregroundStyle(Palette.primaryText)
                    }
                    HStack {
                        Text("Expense total")
                            .font(Typography.rowSubtitle)
                            .foregroundStyle(Palette.secondaryText)
                        Spacer()
                        Text(Money(minorUnits: draft.amountMinorUnits, currencyCode: draft.currencyCode).formatted())
                            .font(Typography.rowMoney)
                            .foregroundStyle(Palette.primaryText)
                    }
                }
            }

            if draft.itemizationRemainder != 0 && draft.lineItemsTotalMinorUnits > 0 {
                VStack(spacing: 10) {
                    RemainderBanner(
                        remainder: draft.itemizationRemainder,
                        currencyCode: draft.currencyCode
                    )
                    Button {
                        withAnimation(Motion.snappy) { draft.adoptItemizedTotal() }
                        Haptics.snap()
                    } label: {
                        Label("Set the total from these items", systemImage: "equal.circle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            if !draft.lineItems.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Each person pays")
                            .font(Typography.overline)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.tertiaryText)
                        ForEach(draft.includedParticipants) { person in
                            HStack(spacing: 10) {
                                AvatarView(participant: person, size: 28)
                                Text(person.displayName)
                                    .font(Typography.rowSubtitle)
                                    .foregroundStyle(Palette.primaryText)
                                Spacer()
                                Text(
                                    Money(
                                        minorUnits: previewAmount(for: person.id),
                                        currencyCode: draft.currencyCode
                                    ).formatted()
                                )
                                .font(Typography.rowMoney)
                                .foregroundStyle(Palette.secondaryText)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            }
                        }
                    }
                }
            }
        }
    }

    /// What each person would owe if this itemization were applied — shown even
    /// while the expense is still using another split method.
    private func previewAmount(for id: UUID) -> Int {
        let allocations = SplitCalculator.itemized(
            total: draft.lineItemsTotalMinorUnits + draft.taxMinorUnits + draft.tipMinorUnits,
            items: draft.itemAssignments,
            taxMinorUnits: draft.taxMinorUnits,
            tipMinorUnits: draft.tipMinorUnits,
            fallbackParticipants: Array(draft.includedIDs)
        )
        return allocations.first { $0.participantID == id }?.amountMinorUnits ?? 0
    }

    // MARK: - Actions

    private func addItem() {
        withAnimation(Motion.snappy) {
            draft.lineItems.append(ExpenseDraft.DraftLineItem())
        }
        Haptics.tick()
    }

    private func remove(_ id: UUID) {
        draft.lineItems.removeAll { $0.id == id }
    }

    private func toggle(_ personID: UUID, in item: Binding<ExpenseDraft.DraftLineItem>) {
        var ids = item.wrappedValue.assigneeIDs
        if ids.isEmpty {
            // "Everyone" was implicit; make it explicit minus this person.
            ids = draft.includedIDs
        }
        if ids.contains(personID) {
            ids.remove(personID)
        } else {
            ids.insert(personID)
        }
        // Back to implicit "everyone" when they're all selected again.
        item.wrappedValue.assigneeIDs = (ids == draft.includedIDs) ? [] : ids
    }

    /// Switching to itemized here is the point of the sheet — otherwise the
    /// items would be recorded but not actually drive who owes what.
    private func apply() {
        draft.lineItems.removeAll { $0.name.isEmpty && $0.amountMinorUnits == 0 }
        if !draft.lineItems.isEmpty {
            if draft.amountMinorUnits == 0 {
                draft.adoptItemizedTotal()
            }
            draft.splitMethod = .itemized
        }
        Haptics.commit()
        dismiss()
    }
}
