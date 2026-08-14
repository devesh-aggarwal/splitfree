import SwiftData
import SwiftUI

/// Sharing a group, by link or by code.
///
/// There is no sign-in. The device gets an identity the first time it shares
/// something, silently, because row level security needs something to key on and
/// nothing else does.
struct ShareGroupView: View {
    @Bindable var group: SpendingGroup

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var invite: Invite?
    @State private var invitee: Participant?

    var body: some View {
        NavigationStack {
            Form {
                if group.isShared {
                    inviteSection
                    stopSection
                } else {
                    startSection
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Palette.negative)
                    }
                }
            }
            .navigationTitle(String(localized: "Share group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .disabled(isWorking)
        }
    }

    // MARK: Sections

    private var startSection: some View {
        Section {
            Button {
                Task { await share() }
            } label: {
                HStack {
                    Text("Share this group")
                    Spacer()
                    if isWorking { ProgressView() }
                }
            }
        } footer: {
            Text("Everyone you invite sees every expense in this group.")
        }
    }

    private var inviteSection: some View {
        Section {
            // Inviting someone *as* an existing member is the case that matters:
            // the trip already has four expenses against "Marco", and Marco
            // should walk into those rather than a blank slot beside them.
            if !unclaimedMembers.isEmpty {
                Picker(String(localized: "Invite as"), selection: $invitee) {
                    Text("A new person").tag(Participant?.none)
                    ForEach(unclaimedMembers) { person in
                        Text(person.fullName).tag(Participant?.some(person))
                    }
                }
            }

            Button {
                Task { await makeInvite() }
            } label: {
                HStack {
                    Text(invite == nil ? "Create an invite" : "Create another")
                    Spacer()
                    if isWorking { ProgressView() }
                }
            }

            if let invite {
                JoinCodeView(invite: invite)
            }
        } header: {
            Text("Invite someone")
        } footer: {
            Text("Anyone with the code can join. It expires in 14 days.")
        }
    }

    private var stopSection: some View {
        Section {
            Button(role: .destructive) {
                group.isShared = false
                group.syncedFingerprint = ""
                try? context.save()
                Haptics.warning()
            } label: {
                Text("Stop sharing on this device")
            }
        } footer: {
            Text("The group stays on your phone. Everyone else keeps their copy.")
        }
    }

    private var unclaimedMembers: [Participant] {
        group.memberList.filter { !$0.isCurrentUser && $0.remoteUserID == nil }
    }

    // MARK: Actions

    private func share() async {
        await perform {
            try await sync.shareGroup(group, context: context)
            invite = try await sync.createInvite(for: group, claiming: nil)
        }
    }

    private func makeInvite() async {
        await perform { invite = try await sync.createInvite(for: group, claiming: invitee) }
    }

    private func perform(_ work: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await work()
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }
}

/// A join code, big enough to read out, with the link behind the share button.
struct JoinCodeView: View {
    let invite: Invite

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(invite.formattedCode)
                .font(.system(.title, design: .monospaced).weight(.semibold))
                .kerning(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ShareLink(item: invite.url) {
                Label(String(localized: "Send a link"), systemImage: "square.and.arrow.up")
            }
        }
        .padding(.vertical, 4)
    }
}

/// Accepting an invite, whether it arrived as a link or as a typed code.
struct JoinGroupView: View {
    /// Pre-filled when the sheet was opened by a link.
    var token: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync

    @State private var code = ""
    @State private var preview: SyncEngine.InvitePreview?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    previewSection(preview)
                } else {
                    codeSection
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Palette.negative)
                    }
                }
            }
            .navigationTitle(String(localized: "Join a group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .disabled(isWorking)
            .task {
                if let token { await look(up: token) } else { isTyping = true }
            }
        }
    }

    private var codeSection: some View {
        Section {
            TextField(String(localized: "ABCDE-FGHIJ"), text: $code)
                .font(.system(.title3, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($isTyping)
                .submitLabel(.go)
                .onSubmit { Task { await look(up: code) } }

            Button {
                Task { await look(up: code) }
            } label: {
                HStack {
                    Text("Find the group")
                    Spacer()
                    if isWorking { ProgressView() }
                }
            }
            .disabled(code.filter(\.isLetter).isEmpty && code.filter(\.isNumber).isEmpty)
        } footer: {
            Text("Enter the code a friend sent you.")
        }
    }

    private func previewSection(_ preview: SyncEngine.InvitePreview) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(preview.groupName, systemImage: preview.groupKind.symbol)
                    .font(.title3.weight(.semibold))
                Text(String(localized: "^[\(preview.memberCount) member](inflect: true)", comment: "Number of people in a group"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let name = preview.claimsMemberName {
                    Text(String(
                        format: String(localized: "You'll join as %@.", comment: "Member name"),
                        name
                    ))
                    .font(.subheadline)
                }
            }
            .padding(.vertical, 4)

            Button {
                Task { await join() }
            } label: {
                HStack {
                    Text(preview.alreadyMember ? "Open the group" : "Join")
                    Spacer()
                    if isWorking { ProgressView() }
                }
            }
        } footer: {
            Text("Everyone in this group sees every expense in it.")
        }
    }

    // MARK: Actions

    private func look(up raw: String) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            preview = try await sync.previewInvite(token: raw)
            code = raw
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }

    private func join() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await sync.redeemInvite(token: code, context: context)
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }
}

/// An invite token on its way to the join sheet.
struct InviteToken: Identifiable {
    let id: String
    init(_ token: String) { self.id = token }
}
