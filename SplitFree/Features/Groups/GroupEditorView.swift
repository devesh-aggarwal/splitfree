import PhotosUI
import SwiftData
import SwiftUI

/// Create or edit a group.
struct GroupEditorView: View {
    var group: SpendingGroup?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @Query private var allParticipants: [Participant]

    @State private var name = ""
    @State private var kind: GroupKind = .trip
    @State private var colorIndex = 0
    @State private var currencyCode = Currency.deviceDefaultCode
    @State private var simplifyDebts = false
    @State private var coverImageData: Data?
    @State private var memberIDs: Set<UUID> = []
    @State private var photoItem: PhotosPickerItem?
    @State private var showsCurrencyPicker = false
    @State private var newMemberName = ""

    private var isEditing: Bool { group != nil }

    private var user: Participant { Ledger.currentUser(in: context) }

    private var selectableFriends: [Participant] {
        allParticipants
            .filter { !$0.isCurrentUser && !$0.isArchived }
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    identityCard
                    styleCard
                    membersCard
                    settingsCard
                    Color.clear.frame(height: 20)
                }
                .padding(Metrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(isEditing ? Text("Group settings") : Text("New group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text(isEditing ? "Save" : "Create").fontWeight(.semibold) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadExisting)
            .onChange(of: photoItem) { _, item in
                Task { await loadCover(item) }
            }
            .sheet(isPresented: $showsCurrencyPicker) {
                CurrencyPickerSheet(selection: $currencyCode)
            }
        }
    }

    // MARK: - Cards

    private var identityCard: some View {
        Card {
            VStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let coverImageData, let image = UIImage(data: coverImageData) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            LinearGradient(
                                colors: [
                                    Palette.groupColor(colorIndex).opacity(0.9),
                                    Palette.groupColor(colorIndex).opacity(0.6),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .overlay {
                                Image(systemName: kind.symbol)
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(Palette.accent, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                    }
                    .offset(x: 5, y: 5)
                }

                TextField(text: $name) {
                    Text("Group name")
                }
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
            .autocorrectionDisabled()

                if coverImageData != nil {
                    Button(role: .destructive) {
                        coverImageData = nil
                        photoItem = nil
                    } label: {
                        Text("Remove photo")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.negative)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var styleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Type")
                    .font(Typography.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.tertiaryText)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(GroupKind.allCases) { option in
                        Button {
                            withAnimation(Motion.quick) { kind = option }
                            Haptics.selectionChanged()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: option.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(option.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(kind == option ? .white : Palette.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(kind == option ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.surfaceSunken))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Color")
                    .font(Typography.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.tertiaryText)
                    .padding(.top, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(Palette.groupColors.enumerated()), id: \.offset) { index, color in
                            Button {
                                withAnimation(Motion.quick) { colorIndex = index }
                                Haptics.selectionChanged()
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if colorIndex == index {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Color \(index + 1)"))
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var membersCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    String(localized: "Members"),
                    subtitle: String(format: String(localized: "%lld selected", comment: "Member count"), memberIDs.count + 1)
                )

                HStack(spacing: 10) {
                    AvatarView(participant: user, size: 34)
                    Text("You")
                        .font(Typography.rowSubtitle)
                        .foregroundStyle(Palette.primaryText)
                    Spacer()
                    Text("always included")
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }

                if !selectableFriends.isEmpty {
                    Divider().overlay(Palette.separator)

                    ForEach(selectableFriends) { friend in
                        Button {
                            withAnimation(Motion.quick) { toggle(friend) }
                            Haptics.selectionChanged()
                        } label: {
                            HStack(spacing: 10) {
                                AvatarView(participant: friend, size: 34)
                                    .opacity(memberIDs.contains(friend.id) ? 1 : 0.5)
                                Text(friend.fullName)
                                    .font(Typography.rowSubtitle)
                                    .foregroundStyle(Palette.primaryText)
                                Spacer()
                                Image(systemName: memberIDs.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(memberIDs.contains(friend.id) ? Palette.accent : Palette.separator)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().overlay(Palette.separator)

                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(Palette.accent)
                    TextField(text: $newMemberName) {
                        Text("Add someone new")
                    }
                    .font(Typography.rowSubtitle)
                    .textInputAutocapitalization(.words)
                    .onSubmit { addNewMember() }
                    if !newMemberName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button { addNewMember() } label: {
                            Text("Add").font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
        }
    }

    private var settingsCard: some View {
        Card {
            VStack(spacing: 14) {
                Button { showsCurrencyPicker = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Default currency")
                                .font(Typography.rowTitle)
                                .foregroundStyle(Palette.primaryText)
                            Text("New expenses in this group start here.")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        Text("\(Currency.flag(for: currencyCode)) \(currencyCode)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.secondaryText)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().overlay(Palette.separator)

                Toggle(isOn: $simplifyDebts) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Simplify debts")
                            .font(Typography.rowTitle)
                        Text("Collapse balances into the fewest payments.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                .tint(Palette.accent)
            }
        }
    }

    // MARK: - Actions

    private func toggle(_ friend: Participant) {
        if memberIDs.contains(friend.id) {
            memberIDs.remove(friend.id)
        } else {
            memberIDs.insert(friend.id)
        }
    }

    private func addNewMember() {
        let trimmed = newMemberName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let person = Participant(name: trimmed, colorIndex: Palette.colorIndex(for: trimmed))
        context.insert(person)
        try? context.save()
        memberIDs.insert(person.id)
        newMemberName = ""
        Haptics.success()
    }

    private func loadExisting() {
        if let group {
            name = group.name
            kind = group.kind
            colorIndex = group.colorIndex
            currencyCode = group.defaultCurrencyCode
            simplifyDebts = group.simplifyDebts
            coverImageData = group.coverImageData
            memberIDs = Set(group.memberList.filter { !$0.isCurrentUser }.map(\.id))
        } else {
            currencyCode = settings.baseCurrencyCode
            simplifyDebts = settings.simplifyDebtsByDefault
            colorIndex = Int.random(in: 0..<Palette.groupColors.count)
        }
    }

    private func loadCover(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        coverImageData = image.compressedForStorage(maxDimension: 900, quality: 0.75)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var members = [user]
        members.append(contentsOf: allParticipants.filter { memberIDs.contains($0.id) })

        if let group {
            group.name = trimmed
            group.kind = kind
            group.colorIndex = colorIndex
            group.defaultCurrencyCode = currencyCode
            group.simplifyDebts = simplifyDebts
            group.coverImageData = coverImageData
            group.members = members
        } else {
            let newGroup = SpendingGroup(
                name: trimmed,
                kind: kind,
                colorIndex: colorIndex,
                members: members,
                defaultCurrencyCode: currencyCode
            )
            newGroup.simplifyDebts = simplifyDebts
            newGroup.coverImageData = coverImageData
            newGroup.sortOrder = -Int(Date().timeIntervalSince1970)
            context.insert(newGroup)

            Ledger.log(
                .groupCreated,
                headline: String(
                    format: String(localized: "You created the group %@", comment: "Group name"),
                    trimmed
                ),
                detail: String(localized: "^[\(members.count) member](inflect: true)", comment: "Count"),
                groupID: newGroup.id,
                groupName: trimmed,
                in: context
            )
        }

        try? context.save()
        Haptics.success()
        dismiss()
    }
}

// MARK: - Members

struct GroupMembersView: View {
    @Bindable var group: SpendingGroup

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allParticipants: [Participant]
    @State private var newName = ""
    @State private var blockedRemoval: Participant?

    private var sheet: BalanceSheet {
        BalanceEngine.balanceSheet(
            expenses: group.expenseList,
            settlements: group.settlementList,
            simplify: false
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(group.memberList) { member in
                        HStack(spacing: 12) {
                            AvatarView(participant: member, size: 38)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(member.isCurrentUser ? String(localized: "You") : member.fullName)
                                    .foregroundStyle(Palette.primaryText)
                                let position = sheet.position(for: member.id)
                                if position.isSettled {
                                    Text("settled up")
                                        .font(.caption)
                                        .foregroundStyle(Palette.neutral)
                                } else if let code = position.nonZeroCurrencies.first {
                                    let amount = position.amount(in: code)
                                    Text(
                                        amount > 0
                                            ? String(format: String(localized: "gets back %@", comment: "Amount"), Money(minorUnits: amount, currencyCode: code).formatted())
                                            : String(format: String(localized: "owes %@", comment: "Amount"), Money(minorUnits: -amount, currencyCode: code).formatted())
                                    )
                                    .font(.caption)
                                    .foregroundStyle(Color.forBalance(amount))
                                }
                            }
                            Spacer()
                        }
                        .swipeActions {
                            if !member.isCurrentUser {
                                Button(role: .destructive) {
                                    remove(member)
                                } label: {
                                    Label("Remove", systemImage: "person.badge.minus")
                                }
                            }
                        }
                    }
                } header: {
                    Text("^[\(group.memberList.count) member](inflect: true)")
                } footer: {
                    Text("Someone can only be removed once they're settled up in this group.")
                }

                Section {
                    ForEach(addableFriends) { friend in
                        Button {
                            add(friend)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(participant: friend, size: 34)
                                Text(friend.fullName)
                                    .foregroundStyle(Palette.primaryText)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Image(systemName: "person.badge.plus").foregroundStyle(Palette.accent)
                        TextField(text: $newName) { Text("Add someone new") }
                            .textInputAutocapitalization(.words)
                            .onSubmit { addNew() }
                    }
                } header: {
                    Text("Add to this group")
                }
            }
            .navigationTitle(Text("Members"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done").fontWeight(.semibold) }
                }
            }
            .alert(
                Text("Can't remove them yet"),
                isPresented: Binding(get: { blockedRemoval != nil }, set: { if !$0 { blockedRemoval = nil } })
            ) {
                Button { blockedRemoval = nil } label: { Text("OK") }
            } message: {
                Text("\(blockedRemoval?.fullName ?? "") still has an open balance in this group. Settle up first.")
            }
        }
    }

    private var addableFriends: [Participant] {
        let existing = Set(group.memberList.map(\.id))
        return allParticipants
            .filter { !existing.contains($0.id) && !$0.isArchived }
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    private func add(_ friend: Participant) {
        withAnimation(Motion.snappy) {
            group.members?.append(friend)
        }
        Ledger.log(
            .memberAdded,
            headline: String(
                format: String(localized: "%1$@ joined %2$@", comment: "Person, group"),
                friend.fullName,
                group.displayName
            ),
            groupID: group.id,
            groupName: group.name,
            in: context
        )
        try? context.save()
        Haptics.success()
    }

    private func addNew() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let person = Participant(name: trimmed, colorIndex: Palette.colorIndex(for: trimmed))
        context.insert(person)
        add(person)
        newName = ""
    }

    private func remove(_ member: Participant) {
        guard Ledger.canRemove(member, from: group) else {
            blockedRemoval = member
            Haptics.error()
            return
        }
        withAnimation(Motion.snappy) {
            Ledger.remove(member, from: group, in: context)
        }
        try? context.save()
        Haptics.tick()
    }
}

// MARK: - Notes

/// The group whiteboard — the address of the rental, the wifi password, who's
/// bringing what.
struct GroupNotesView: View {
    @Bindable var group: SpendingGroup

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $group.notes)
                    .font(Typography.rowSubtitle)
                    .scrollContentBackground(.hidden)
                    .padding(Metrics.screenPadding)
                    .focused($isFocused)
                    .overlay(alignment: .topLeading) {
                        if group.notes.isEmpty {
                            Text("Anything the group should remember — the rental address, the wifi password, who's driving.")
                                .font(Typography.rowSubtitle)
                                .foregroundStyle(Palette.tertiaryText)
                                .padding(.horizontal, Metrics.screenPadding + 5)
                                .padding(.top, Metrics.screenPadding + 8)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .screenBackground()
            .navigationTitle(Text("Group notes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        try? context.save()
                        dismiss()
                    } label: {
                        Text("Done").fontWeight(.semibold)
                    }
                }
            }
            .onAppear { isFocused = true }
        }
    }
}
