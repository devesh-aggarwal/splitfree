import SwiftData
import SwiftUI

/// Sending someone a link that connects the two of you.
///
/// Underneath, a friendship is a two-person group. That is not a detail the
/// screen mentions, but it is why this works at all: sync carries groups, so a
/// friendship with nothing behind it could never reach the other phone, and the
/// friend list would be names that quietly do nothing.
struct InviteFriendView: View {
    /// An existing friend to connect with, or nil to invite someone new.
    var friend: Participant?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync

    @State private var name = ""
    @State private var invite: Invite?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var isNaming: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let invite {
                    readySection(invite)
                } else {
                    nameSection
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Palette.negative)
                    }
                }
            }
            .navigationTitle(String(localized: "Invite a friend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .disabled(isWorking)
            .onAppear {
                name = friend?.fullName ?? ""
                isNaming = friend == nil
            }
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            TextField(String(localized: "Their name"), text: $name)
                .focused($isNaming)
                .submitLabel(.go)
                .onSubmit { Task { await makeLink() } }

            Button {
                Task { await makeLink() }
            } label: {
                HStack {
                    Text("Create invite link")
                    Spacer()
                    if isWorking { ProgressView() }
                }
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        } footer: {
            Text("Once they join, what the two of you share stays in step on both phones.")
        }
    }

    private func readySection(_ invite: Invite) -> some View {
        Section {
            JoinCodeView(invite: invite)
        } header: {
            Text("Send this to them")
        } footer: {
            Text("Anyone with the code can connect with you. It expires in 14 days.")
        }
    }

    // MARK: Actions

    private func makeLink() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            // Reuse the person if they're already in the friend list, so an
            // invite doesn't create a second copy of someone you already owe.
            let person: Participant
            if let friend {
                person = friend
            } else if let existing = Ledger.allParticipants(in: context).first(where: {
                !$0.isCurrentUser && $0.fullName.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
            }) {
                person = existing
            } else {
                let fresh = Participant(name: trimmed, colorIndex: Ledger.allParticipants(in: context).count)
                context.insert(fresh)
                person = fresh
            }

            let group = Ledger.makeDirectPairGroup(with: person, in: context)
            try? context.save()

            if !group.isShared {
                try await sync.shareGroup(group, context: context)
            }
            // The invite reserves their slot, so anything already recorded
            // against their name becomes theirs when they accept.
            invite = try await sync.createInvite(for: group, claiming: person)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }
}
