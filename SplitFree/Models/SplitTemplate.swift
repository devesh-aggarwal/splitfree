import Foundation
import SwiftData

/// A reusable split — "Rent: Ana 60%, me 40%" — so a recurring shape doesn't
/// have to be re-entered every time.
@Model
final class SplitTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var splitMethodRaw: String = SplitMethod.equal.rawValue
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    var useCount: Int = 0
    /// Nil for a template available everywhere.
    var group: SpendingGroup?
    /// Set when this template should be pre-selected for new expenses in its group.
    var isDefaultForGroup: Bool = false

    /// JSON-encoded `RecurringSplitPlan` — same shape as a recurring rule's plan.
    var planData: Data?

    init(name: String, splitMethod: SplitMethod, group: SpendingGroup?) {
        self.id = UUID()
        self.name = name
        self.splitMethodRaw = splitMethod.rawValue
        self.group = group
        self.createdAt = Date()
    }
}

extension SplitTemplate {
    var splitMethod: SplitMethod {
        get { SplitMethod(rawValue: splitMethodRaw) ?? .equal }
        set { splitMethodRaw = newValue.rawValue }
    }

    var plan: RecurringSplitPlan {
        get {
            guard let planData,
                  let decoded = try? JSONDecoder().decode(RecurringSplitPlan.self, from: planData)
            else { return RecurringSplitPlan() }
            return decoded
        }
        set { planData = try? JSONEncoder().encode(newValue) }
    }

    var displayName: String {
        name.isEmpty ? String(localized: "Untitled split") : name
    }

    /// "3 people · Percentages"
    var summary: String {
        let count = plan.shares.count
        let people = String(
            localized: "^[\(count) person](inflect: true)",
            comment: "Number of people in a split"
        )
        return "\(people) · \(splitMethod.title)"
    }
}
