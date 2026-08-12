import Foundation
import SwiftData

/// A record that something was deleted.
///
/// Deleting locally stays a real delete: the row goes, and none of the app's
/// queries need to learn to skip it. What sync needs is separate knowledge that
/// the deletion happened, because a friend's phone that was offline at the time
/// will otherwise keep showing the expense forever. That knowledge lives here.
///
/// Tombstones are pushed as `deleted_at` on the server row, then kept for a
/// while rather than dropped immediately, so a late-arriving edit to something
/// you already deleted doesn't resurrect it.
@Model
final class SyncTombstone {
    var id: UUID = UUID()
    /// One of `SyncEntity`.
    var entityRaw: String = ""
    /// The id of the row that was deleted.
    var entityID: UUID = UUID()
    /// Which group it belonged to, so a member tombstone knows where it applies.
    var groupID: UUID?
    var deletedAt: Date = Date()
    /// Cleared once the server has the tombstone.
    var isPushed: Bool = false

    init(entity: SyncEntity, entityID: UUID, groupID: UUID? = nil) {
        self.id = UUID()
        self.entityRaw = entity.rawValue
        self.entityID = entityID
        self.groupID = groupID
        self.deletedAt = Date()
    }

    var entity: SyncEntity { SyncEntity(rawValue: entityRaw) ?? .expense }
}

enum SyncEntity: String, Codable, Sendable {
    case group
    case member
    case expense
    case settlement
}
