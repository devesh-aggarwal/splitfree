import Foundation
import SwiftData

/// A person who can pay for or owe part of an expense - you, or one of your friends.
///
/// Exactly one `Participant` has `isCurrentUser == true`; it is created on first launch
/// and can never be deleted.
@Model
final class Participant {
    var id: UUID = UUID()
    var name: String = ""
    var email: String = ""
    var phone: String = ""
    /// Index into `Palette.avatarColors` - keeps avatars stable and CloudKit-cheap.
    var colorIndex: Int = 0
    /// Optional profile photo, downscaled before storage.
    @Attribute(.externalStorage) var avatarData: Data?
    var isCurrentUser: Bool = false
    var createdAt: Date = Date()
    var isArchived: Bool = false
    var updatedAt: Date = Date()

    /// A fingerprint of this row's contents as the server last saw them.
    ///
    /// Sync decides what to push by comparing it against the row's current
    /// fingerprint. A hash is used rather than a dirty flag or a timestamp
    /// because both of those have to be *remembered* at every write site, and
    /// one forgotten line means an edit that silently never syncs. A hash cannot
    /// be forgotten: if the contents differ, it differs.
    var syncedFingerprint: String = ""

    /// The Supabase user id, once this person has claimed their slot by signing
    /// in. Nil for someone who was only ever typed into a group by a friend.
    var remoteUserID: String?

    /// Payment handles used to build deep links on the settle-up screen.
    var venmoHandle: String = ""
    var paypalHandle: String = ""
    var cashAppHandle: String = ""
    var upiHandle: String = ""

    @Relationship(inverse: \SpendingGroup.members) var groups: [SpendingGroup]? = []

    // CloudKit refuses to load a store where any relationship lacks an inverse,
    // and it fails at load time rather than complaining at build time - so
    // without these the app silently falls back to a local-only store and iCloud
    // sync never happens at all. They exist to be the other end of a
    // relationship, not because anything reads them.
    @Relationship(inverse: \ExpensePayer.participant) var payerEntries: [ExpensePayer]? = []
    @Relationship(inverse: \ExpenseShare.participant) var shareEntries: [ExpenseShare]? = []
    @Relationship(inverse: \ExpenseComment.author) var authoredComments: [ExpenseComment]? = []
    @Relationship(inverse: \ExpenseLineItem.assignees) var assignedLineItems: [ExpenseLineItem]? = []
    @Relationship(inverse: \Settlement.fromParticipant) var settlementsSent: [Settlement]? = []
    @Relationship(inverse: \Settlement.toParticipant) var settlementsReceived: [Settlement]? = []

    init(
        name: String,
        email: String = "",
        phone: String = "",
        colorIndex: Int = 0,
        isCurrentUser: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.phone = phone
        self.colorIndex = colorIndex
        self.isCurrentUser = isCurrentUser
        self.createdAt = Date()
    }
}

extension Participant {
    /// "You" for the current user, otherwise their first name - matches how the
    /// rest of the UI refers to people in sentences.
    var displayName: String {
        if isCurrentUser { return String(localized: "You", comment: "Refers to the current user") }
        return name.isEmpty ? String(localized: "Someone") : name
    }

    /// Always the real name, even for the current user. Used in lists and pickers.
    var fullName: String {
        name.isEmpty ? String(localized: "Someone") : name
    }

    var firstName: String {
        fullName.split(separator: " ").first.map(String.init) ?? fullName
    }

    /// Up to two letters, e.g. "Priya Raman" → "PR".
    var initials: String {
        let parts = fullName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    var hasAnyPaymentHandle: Bool {
        !venmoHandle.isEmpty || !paypalHandle.isEmpty || !cashAppHandle.isEmpty || !upiHandle.isEmpty
    }

    var groupList: [SpendingGroup] { groups ?? [] }
}
