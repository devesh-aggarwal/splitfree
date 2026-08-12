import SwiftData
import SwiftUI

/// Turning a group into a shared one, and handing out links to join it.
///
/// Sharing is per group and always deliberate. There is no global "sync
/// everything" switch, because the honest version of this feature is that a
/// shared group leaves the device and an unshared one does not, and a single
/// switch would blur exactly the line people care about.
struct ShareGroupView: View {
    @Bindable var group: SpendingGroup

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var link: URL?
    @State private var invitee: Participant?
    @State private var isShowingSignIn = false

    var body: some View {
        NavigationStack {
            Form {
                if !sync.isSignedIn {
                    signedOutSection
                } else if group.isShared {
                    sharedSection
                    inviteSection
                    stopSection
                } else {
                    notSharedSection
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
            .sheet(isPresented: $isShowingSignIn) { SignInView() }
        }
    }

    // MARK: Sections

    private var signedOutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sharing needs an account")
                    .font(.headline)
                Text("Your friend's phone has to be able to reach this group, which means it has to live somewhere both of you can get to.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Button(String(localized: "Sign in")) { isShowingSignIn = true }
        }
    }

    private var notSharedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(group.displayName, systemImage: group.kind.symbol)
                    .font(.headline)
                    .foregroundStyle(group.tint)
                Text("""
                     Sharing uploads this group and everything in it: its \
                     expenses, who paid, who owes, notes, and any payments \
                     you've recorded. Everyone you invite can see all of it.
                     """)
                .font(.subheadline)
                Text("Your other groups stay on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Button {
                Task { await share() }
            } label: {
                HStack {
                    Text("Share this group")
                    Spacer()
                    if isWorking { ProgressView() }
                }
            }
        }
    }

    private var sharedSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This group is shared")
                    if let lastSyncedAt = sync.lastSyncedAt {
                        Text(lastSyncedAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.positive)
            }
        }
    }

    private var inviteSection: some View {
        Section {
            // Inviting someone *as* an existing member is the case that matters:
            // the trip already has four expenses against "Marco", and Marco
            // should walk into those rather than a blank slot beside them.
            Picker(String(localized: "Invite as"), selection: $invitee) {
                Text("A new person").tag(Participant?.none)
                ForEach(unclaimedMembers) { person in
                    Text(person.fullName).tag(Participant?.some(person))
                }
            }

            Button {
                Task { await makeLink() }
            } label: {
                HStack {
                    Text("Create invite link")
                    Spacer()
                    if isWorking { ProgressView() }
                }
            }

            if let link {
                ShareLink(item: link) {
                    Label(String(localized: "Send the link"), systemImage: "square.and.arrow.up")
                }
                Text(link.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Invite someone")
        } footer: {
            Text("Anyone with the link can join this group and see everything in it. It stops working after 14 days.")
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
            Text("This group goes back to being local to your phone. It stays on the server for everyone else you invited, and their copies keep working.")
        }
    }

    /// Members who haven't signed in yet, so their slot is still up for grabs.
    private var unclaimedMembers: [Participant] {
        group.memberList.filter { !$0.isCurrentUser && $0.remoteUserID == nil }
    }

    // MARK: Actions

    private func share() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await sync.shareGroup(group, context: context)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }

    private func makeLink() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            link = try await sync.createInviteLink(for: group, claiming: invitee)
            Haptics.success()
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

/// Accepting an invite. Shows what the link points at before joining, so nobody
/// has to tap "Join" on a group they can't see.
struct JoinGroupView: View {
    let token: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync

    @State private var preview: SyncEngine.InvitePreview?
    @State private var isWorking = true
    @State private var errorMessage: String?
    @State private var isShowingSignIn = false

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    previewSection(preview)
                    if sync.isSignedIn {
                        joinSection(preview)
                    } else {
                        Section {
                            Button(String(localized: "Sign in to join")) { isShowingSignIn = true }
                        } footer: {
                            Text("Joining a shared group needs an account, so the group knows who you are.")
                        }
                    }
                } else if isWorking {
                    Section { HStack { ProgressView(); Text("Checking the link").padding(.leading, 8) } }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Palette.negative)
                    }
                }
            }
            .navigationTitle(String(localized: "Join group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Not now")) { dismiss() }
                }
            }
            .task { await load() }
            .sheet(isPresented: $isShowingSignIn) {
                SignInView()
            }
            .onChange(of: sync.isSignedIn) { _, signedIn in
                if signedIn { Task { await load() } }
            }
        }
    }

    private func previewSection(_ preview: SyncEngine.InvitePreview) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(preview.groupName, systemImage: preview.groupKind.symbol)
                    .font(.title3.weight(.semibold))
                Text(memberCountText(preview.memberCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let name = preview.claimsMemberName {
                    Text(String(
                        format: String(localized: "You'll join as %@, so the expenses already recorded against that name become yours.", comment: "Member name"),
                        name
                    ))
                    .font(.subheadline)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func joinSection(_ preview: SyncEngine.InvitePreview) -> some View {
        Section {
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
            Text("Everyone in this group can see every expense in it, including the ones you add.")
        }
    }

    private func memberCountText(_ count: Int) -> String {
        String(localized: "^[\(count) member](inflect: true)", comment: "Number of people in a group")
    }

    private func load() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            preview = try await sync.previewInvite(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func join() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await sync.redeemInvite(token: token, context: context)
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }
}
