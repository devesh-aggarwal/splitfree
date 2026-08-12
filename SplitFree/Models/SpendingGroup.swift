import Foundation
import SwiftData
import SwiftUI

enum GroupKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case trip
    case home
    case couple
    case event
    case project
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trip: String(localized: "Trip")
        case .home: String(localized: "Home")
        case .couple: String(localized: "Couple")
        case .event: String(localized: "Event")
        case .project: String(localized: "Project")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .trip: "airplane"
        case .home: "house.fill"
        case .couple: "heart.fill"
        case .event: "party.popper.fill"
        case .project: "briefcase.fill"
        case .other: "square.grid.2x2.fill"
        }
    }
}

/// A shared ledger: a trip, a flat, a couple, a one-off event.
@Model
final class SpendingGroup {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = GroupKind.other.rawValue
    var colorIndex: Int = 0
    @Attribute(.externalStorage) var coverImageData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// A fingerprint of this row's contents as the server last saw them.
    ///
    /// Sync decides what to push by comparing it against the row's current
    /// fingerprint. A hash is used rather than a dirty flag or a timestamp
    /// because both of those have to be *remembered* at every write site, and
    /// one forgotten line means an edit that silently never syncs. A hash cannot
    /// be forgotten: if the contents differ, it differs.
    var syncedFingerprint: String = ""

    /// A two-person group that stands for a friendship.
    ///
    /// Presented as a friend rather than as a group, and hidden from the groups
    /// list. It exists so that expenses shared with one person can travel: the
    /// sync engine only carries groups, so a friendship with no group behind it
    /// could never reach anybody else's phone.
    var isDirect: Bool = false
    /// Whether this group is synced through an account. Off by default and set
    /// only when someone explicitly shares the group, which is what keeps the
    /// local-only promise true for everything they never shared.
    var isShared: Bool = false
    /// Member ids removed from this group while it was shared, so the removal
    /// can be pushed as a tombstone. Comma-separated because SwiftData arrays of
    /// scalars are more trouble than they are worth for a list this small.
    var removedMemberIDsRaw: String = ""
    /// Which member slot on the server represents *you* in this group.
    ///
    /// It is normally your own participant id, but when you join a group
    /// somebody else created, the slot already exists and keeps the id they
    /// gave it. Recording that here means the expenses they already wrote
    /// against that slot land on you rather than on a duplicate stranger.
    var myMemberIDRaw: String = ""
    var isArchived: Bool = false
    /// Free-form shared notes — the group "whiteboard".
    var notes: String = ""
    /// When on, balances are collapsed into the fewest possible payments.
    /// Defaults on; the group's settings screen turns it off.
    var simplifyDebts: Bool = true
    /// Currency new expenses in this group default to.
    var defaultCurrencyCode: String = "USD"
    /// Manual ordering on the groups screen.
    var sortOrder: Int = 0
    var isPinned: Bool = false

    var members: [Participant]? = []

    @Relationship(deleteRule: .cascade, inverse: \Expense.group)
    var expenses: [Expense]? = []

    @Relationship(deleteRule: .cascade, inverse: \Settlement.group)
    var settlements: [Settlement]? = []

    @Relationship(deleteRule: .cascade, inverse: \SplitTemplate.group)
    var splitTemplates: [SplitTemplate]? = []

    /// The other end of `RecurringRule.group`. See the note on `Participant`:
    /// CloudKit will not load a store with a one-sided relationship.
    @Relationship(inverse: \RecurringRule.group)
    var recurringRules: [RecurringRule]? = []

    init(
        name: String,
        kind: GroupKind = .other,
        colorIndex: Int = 0,
        members: [Participant] = [],
        defaultCurrencyCode: String = Currency.deviceDefaultCode
    ) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.colorIndex = colorIndex
        self.members = members
        self.defaultCurrencyCode = defaultCurrencyCode
        self.createdAt = Date()
    }
}

extension SpendingGroup {
    var kind: GroupKind {
        get { GroupKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var memberList: [Participant] {
        (members ?? []).sorted { lhs, rhs in
            if lhs.isCurrentUser != rhs.isCurrentUser { return lhs.isCurrentUser }
            return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
        }
    }

    var expenseList: [Expense] { expenses ?? [] }
    var settlementList: [Settlement] { settlements ?? [] }
    var templateList: [SplitTemplate] { splitTemplates ?? [] }

    var displayName: String {
        name.isEmpty ? String(localized: "Untitled group") : name
    }

    /// Expenses and settlements interleaved, newest first — the group timeline.
    var timeline: [LedgerEntry] {
        let entries = expenseList.map { LedgerEntry.expense($0) }
            + settlementList.map { LedgerEntry.settlement($0) }
        return entries.sorted { $0.date > $1.date }
    }

    var tint: Color { Palette.groupColor(colorIndex) }
}

/// A single row in a group or friend timeline. Expenses and settlements are
/// separate models but always render in one chronological list.
enum LedgerEntry: Identifiable {
    case expense(Expense)
    case settlement(Settlement)

    var id: UUID {
        switch self {
        case .expense(let expense): expense.id
        case .settlement(let settlement): settlement.id
        }
    }

    var date: Date {
        switch self {
        case .expense(let expense): expense.date
        case .settlement(let settlement): settlement.date
        }
    }
}
