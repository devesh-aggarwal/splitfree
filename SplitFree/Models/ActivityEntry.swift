import Foundation
import SwiftData
import SwiftUI

enum ActivityKind: String, Codable, CaseIterable, Sendable {
    case expenseAdded
    case expenseEdited
    case expenseDeleted
    case settlementAdded
    case settlementDeleted
    case groupCreated
    case groupArchived
    case memberAdded
    case memberRemoved
    case commentAdded
    case recurringGenerated
    case transactionsImported

    var symbol: String {
        switch self {
        case .expenseAdded: "plus.circle.fill"
        case .expenseEdited: "pencil.circle.fill"
        case .expenseDeleted: "trash.circle.fill"
        case .settlementAdded: "checkmark.circle.fill"
        case .settlementDeleted: "arrow.uturn.backward.circle.fill"
        case .groupCreated: "person.3.fill"
        case .groupArchived: "archivebox.fill"
        case .memberAdded: "person.badge.plus.fill"
        case .memberRemoved: "person.badge.minus.fill"
        case .commentAdded: "bubble.left.fill"
        case .recurringGenerated: "arrow.triangle.2.circlepath.circle.fill"
        case .transactionsImported: "square.and.arrow.down.fill"
        }
    }

    var tint: Color {
        switch self {
        case .expenseAdded, .recurringGenerated, .transactionsImported: Palette.accent
        case .settlementAdded: Palette.positive
        case .expenseDeleted, .settlementDeleted, .memberRemoved: Palette.negative
        case .expenseEdited, .commentAdded: Palette.categoryBlue
        case .groupCreated, .memberAdded: Palette.categoryPurple
        case .groupArchived: Palette.categoryGray
        }
    }
}

/// One line in the activity feed. Text is denormalized at write time so the feed
/// survives the expense or group it refers to being deleted.
@Model
final class ActivityEntry {
    var id: UUID = UUID()
    var kindRaw: String = ActivityKind.expenseAdded.rawValue
    var createdAt: Date = Date()
    /// Bolded headline, e.g. "You added Dinner at Nopa".
    var headline: String = ""
    /// Muted second line, e.g. "You get back $24.00".
    var detail: String = ""
    /// Kept for navigation; nil once the target is gone.
    var expenseID: UUID?
    var groupID: UUID?
    var settlementID: UUID?
    var groupName: String = ""
    var isRead: Bool = false

    init(
        kind: ActivityKind,
        headline: String,
        detail: String = "",
        expenseID: UUID? = nil,
        groupID: UUID? = nil,
        settlementID: UUID? = nil,
        groupName: String = ""
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.headline = headline
        self.detail = detail
        self.expenseID = expenseID
        self.groupID = groupID
        self.settlementID = settlementID
        self.groupName = groupName
        self.createdAt = Date()
    }
}

extension ActivityEntry {
    var kind: ActivityKind {
        get { ActivityKind(rawValue: kindRaw) ?? .expenseAdded }
        set { kindRaw = newValue.rawValue }
    }
}
