import SwiftData
import SwiftUI

// MARK: - Currency

struct CurrencyPickerSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var query = ""

    private var suggested: [Currency] {
        guard query.isEmpty else { return [] }
        return Currency.suggestedCodes(recent: settings.recentCurrencyCodes).map(Currency.currency(for:))
    }

    private var results: [Currency] {
        Currency.search(query)
    }

    var body: some View {
        NavigationStack {
            List {
                if !suggested.isEmpty {
                    Section {
                        ForEach(suggested) { currency in
                            row(currency)
                        }
                    } header: {
                        Text("Suggested")
                    }
                }
                Section {
                    ForEach(results) { currency in
                        row(currency)
                    }
                } header: {
                    Text("^[\(results.count) currency](inflect: true)")
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: Text("Search currencies"))
            .navigationTitle(Text("Currency"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
            }
        }
    }

    private func row(_ currency: Currency) -> some View {
        Button {
            selection = currency.code
            settings.noteCurrencyUsed(currency.code)
            Haptics.tick()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(currency.flag).font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(currency.name)
                        .foregroundStyle(Palette.primaryText)
                    Text("\(currency.code) · \(currency.symbol)")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
                Spacer()
                if currency.code == selection {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category

struct CategoryPickerSheet: View {
    var selection: ExpenseCategory
    var onSelect: (ExpenseCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 12)]

    private var groups: [CategoryGroup] {
        query.isEmpty ? CategoryGroup.allCases : []
    }

    private var searchResults: [ExpenseCategory] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return ExpenseCategory.allCases.filter { $0.title.lowercased().contains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    if !searchResults.isEmpty {
                        grid(searchResults)
                    }
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title)
                                .font(Typography.sectionTitle)
                                .foregroundStyle(Palette.primaryText)
                            grid(group.categories)
                        }
                    }
                    if !query.isEmpty && searchResults.isEmpty {
                        Text("No categories match “\(query)”.")
                            .font(Typography.rowSubtitle)
                            .foregroundStyle(Palette.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(Metrics.screenPadding)
            }
            .screenBackground()
            .searchable(text: $query, prompt: Text("Search categories"))
            .navigationTitle(Text("Category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
            }
        }
    }

    private func grid(_ categories: [ExpenseCategory]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(categories) { category in
                Button {
                    onSelect(category)
                    Haptics.tick()
                    dismiss()
                } label: {
                    VStack(spacing: 7) {
                        CategoryBadge(category: category, size: 46)
                        Text(category.title)
                            .font(.caption)
                            .foregroundStyle(Palette.primaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(height: 30, alignment: .top)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                            .fill(category == selection ? category.color.opacity(0.12) : Color.clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                            .strokeBorder(category == selection ? category.color : .clear, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Group

struct GroupPickerSheet: View {
    var selection: SpendingGroup?
    var groups: [SpendingGroup]
    var onSelect: (SpendingGroup?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Palette.surfaceSunken)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: "person.2")
                                        .foregroundStyle(Palette.secondaryText)
                                }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("No group")
                                    .foregroundStyle(Palette.primaryText)
                                Text("A one-off between friends")
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            Spacer()
                            if selection == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Palette.accent)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if !groups.isEmpty {
                    Section {
                        ForEach(groups) { group in
                            Button {
                                onSelect(group)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    GroupBadge(group: group, size: 40)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(group.displayName)
                                            .foregroundStyle(Palette.primaryText)
                                        Text("^[\(group.memberList.count) member](inflect: true)")
                                            .font(.caption)
                                            .foregroundStyle(Palette.secondaryText)
                                    }
                                    Spacer()
                                    if selection?.id == group.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Palette.accent)
                                            .fontWeight(.bold)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Your groups")
                    }
                }
            }
            .navigationTitle(Text("Group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
            }
        }
    }
}

// MARK: - Participants

/// Chooses who's in the expense. For a group expense this is the member list;
/// for a groupless one it's the whole friend list, with an inline way to add
/// someone new without leaving the sheet.
struct ParticipantPickerSheet: View {
    @Bindable var draft: ExpenseDraft
    var allParticipants: [Participant]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var newFriendName = ""

    private var selectable: [Participant] {
        let base = draft.group != nil ? draft.candidates : allParticipants
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = trimmed.isEmpty
            ? base
            : base.filter { $0.fullName.lowercased().contains(trimmed) }
        return filtered.sorted { lhs, rhs in
            if lhs.isCurrentUser != rhs.isCurrentUser { return lhs.isCurrentUser }
            return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
        }
    }

    private var canAddNewFriend: Bool {
        draft.group == nil
            && !query.trimmingCharacters(in: .whitespaces).isEmpty
            && !selectable.contains { $0.fullName.lowercased() == query.lowercased() }
    }

    var body: some View {
        NavigationStack {
            List {
                if canAddNewFriend {
                    Section {
                        Button {
                            addFriend(named: query)
                        } label: {
                            Label {
                                Text("Add “\(query)” as a friend")
                            } icon: {
                                Image(systemName: "person.badge.plus")
                            }
                            .foregroundStyle(Palette.accent)
                        }
                    }
                }

                Section {
                    ForEach(selectable) { person in
                        Button {
                            withAnimation(Motion.quick) { toggle(person) }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(participant: person, size: 38)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.isCurrentUser ? String(localized: "You") : person.fullName)
                                        .foregroundStyle(Palette.primaryText)
                                    if !person.email.isEmpty {
                                        Text(person.email)
                                            .font(.caption)
                                            .foregroundStyle(Palette.secondaryText)
                                    }
                                }
                                Spacer()
                                Image(systemName: draft.isIncluded(person) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 21))
                                    .foregroundStyle(draft.isIncluded(person) ? Palette.accent : Palette.separator)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(draft.group != nil ? String(localized: "Group members") : String(localized: "Friends"))
                } footer: {
                    if draft.group != nil {
                        Text("Only people in this group can be part of the expense.")
                    }
                }
            }
            .searchable(text: $query, prompt: Text("Search or add a friend"))
            .navigationTitle(Text("Split between"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done").fontWeight(.semibold) }
                }
            }
        }
    }

    private func toggle(_ person: Participant) {
        // Someone from the friend list who isn't a candidate yet joins on first tap.
        if !draft.candidates.contains(where: { $0.id == person.id }) {
            draft.candidates.append(person)
            draft.includedIDs.insert(person.id)
        } else {
            draft.toggleInclusion(person)
        }
        Haptics.selectionChanged()
    }

    private func addFriend(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let person = Participant(name: trimmed, colorIndex: Palette.colorIndex(for: trimmed))
        context.insert(person)
        try? context.save()
        draft.candidates.append(person)
        draft.includedIDs.insert(person.id)
        query = ""
        Haptics.success()
    }
}

// MARK: - Paid by

/// Who put money in. Single payer is one tap; multiple payers reveals an amount
/// field per person with a live "still to assign" figure.
struct PaidBySheet: View {
    @Bindable var draft: ExpenseDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Toggle(isOn: $draft.usesMultiplePayers.animation(Motion.snappy)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Multiple people paid")
                                .font(Typography.rowTitle)
                            Text("Split the bill across more than one card.")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                    .tint(Palette.accent)
                    .padding(Metrics.cardPadding)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

                    if draft.usesMultiplePayers {
                        multiplePayerList
                    } else {
                        singlePayerList
                    }
                }
                .padding(Metrics.screenPadding)
            }
            .screenBackground()
            .navigationTitle(Text("Paid by"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done").fontWeight(.semibold) }
                        .disabled(draft.usesMultiplePayers && draft.payerRemainder != 0)
                }
            }
        }
    }

    private var singlePayerList: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(draft.candidates.enumerated()), id: \.element.id) { index, person in
                    Button {
                        draft.singlePayerID = person.id
                        Haptics.selectionChanged()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(participant: person, size: 38)
                            Text(person.isCurrentUser ? String(localized: "You") : person.fullName)
                                .font(Typography.rowTitle)
                                .foregroundStyle(Palette.primaryText)
                            Spacer()
                            if draft.singlePayerID == person.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 21))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        .padding(Metrics.cardPadding)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < draft.candidates.count - 1 {
                        Divider().overlay(Palette.separator).padding(.leading, 62)
                    }
                }
            }
        }
    }

    private var multiplePayerList: some View {
        VStack(spacing: 14) {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(draft.candidates.enumerated()), id: \.element.id) { index, person in
                        HStack(spacing: 12) {
                            AvatarView(participant: person, size: 38)
                            Text(person.isCurrentUser ? String(localized: "You") : person.fullName)
                                .font(Typography.rowTitle)
                                .foregroundStyle(Palette.primaryText)
                            Spacer()
                            InlineMoneyField(
                                minorUnits: Binding(
                                    get: { draft.multiplePayerAmounts[person.id] ?? 0 },
                                    set: { draft.multiplePayerAmounts[person.id] = $0 }
                                ),
                                currencyCode: draft.currencyCode
                            )
                        }
                        .padding(Metrics.cardPadding)

                        if index < draft.candidates.count - 1 {
                            Divider().overlay(Palette.separator).padding(.leading, 62)
                        }
                    }
                }
            }

            RemainderBanner(
                remainder: draft.payerRemainder,
                currencyCode: draft.currencyCode,
                totalLabel: String(localized: "of \(draft.amountMinorUnits == 0 ? "" : Money(minorUnits: draft.amountMinorUnits, currencyCode: draft.currencyCode).formatted())")
            )
        }
    }
}

/// The persistent "does this add up?" strip used by every screen that
/// distributes a total. Green when balanced, red when not.
struct RemainderBanner: View {
    var remainder: Int
    var currencyCode: String
    var totalLabel: String?

    private var isBalanced: Bool { remainder == 0 }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isBalanced ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(isBalanced ? String(localized: "Everything adds up") : message)
                    .font(.subheadline.weight(.semibold))
                if let totalLabel, !totalLabel.isEmpty, !isBalanced {
                    Text(totalLabel)
                        .font(.caption)
                        .opacity(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isBalanced ? Palette.positive : Palette.negative)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isBalanced ? Palette.positiveSoft : Palette.negativeSoft),
            in: RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
        )
        .animation(Motion.quick, value: isBalanced)
    }

    private var message: String {
        let money = Money(minorUnits: abs(remainder), currencyCode: currencyCode).formatted()
        return remainder > 0
            ? String(format: String(localized: "%@ left to assign", comment: "Remaining"), money)
            : String(format: String(localized: "%@ too much assigned", comment: "Over"), money)
    }
}
