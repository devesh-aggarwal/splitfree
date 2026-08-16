import Foundation
import SwiftData

enum RecurrenceFrequency: String, CaseIterable, Codable, Identifiable, Sendable {
    case daily, weekly, biweekly, monthly, quarterly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: String(localized: "Daily")
        case .weekly: String(localized: "Weekly")
        case .biweekly: String(localized: "Every 2 weeks")
        case .monthly: String(localized: "Monthly")
        case .quarterly: String(localized: "Every 3 months")
        case .yearly: String(localized: "Yearly")
        }
    }

    /// Advances a date by one period, clamping to the end of shorter months so a
    /// rule created on the 31st still fires in February.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component
        let value: Int
        switch self {
        case .daily: (component, value) = (.day, 1)
        case .weekly: (component, value) = (.day, 7)
        case .biweekly: (component, value) = (.day, 14)
        case .monthly: (component, value) = (.month, 1)
        case .quarterly: (component, value) = (.month, 3)
        case .yearly: (component, value) = (.year, 1)
        }
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }
}

/// A frozen copy of who paid and who owes, so a recurring rule keeps producing
/// the same split even if the group's membership changes later.
struct RecurringSplitPlan: Codable, Hashable, Sendable {
    struct Entry: Codable, Hashable, Sendable {
        var participantID: UUID
        var amountMinorUnits: Int
        var weight: Double
    }

    var payers: [Entry] = []
    var shares: [Entry] = []
}

/// A rule that materialises an `Expense` on a schedule - rent, utilities,
/// a shared subscription.
@Model
final class RecurringRule {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var amountMinorUnits: Int = 0
    var currencyCode: String = "USD"
    var categoryRaw: String = ExpenseCategory.general.rawValue
    var splitMethodRaw: String = SplitMethod.equal.rawValue
    var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue

    var startDate: Date = Date()
    /// The next date an expense should be created for. Advances as we catch up.
    var nextOccurrence: Date = Date()
    var endDate: Date?
    var isActive: Bool = true
    var createdAt: Date = Date()
    var lastGeneratedAt: Date?
    var generatedCount: Int = 0

    var group: SpendingGroup?

    /// JSON-encoded `RecurringSplitPlan`. Stored as data so the plan survives
    /// even if a participant is later removed from the group.
    var splitPlanData: Data?

    init(
        title: String,
        amountMinorUnits: Int,
        currencyCode: String,
        frequency: RecurrenceFrequency,
        startDate: Date,
        group: SpendingGroup?,
        category: ExpenseCategory = .general,
        splitMethod: SplitMethod = .equal
    ) {
        self.id = UUID()
        self.title = title
        self.amountMinorUnits = amountMinorUnits
        self.currencyCode = currencyCode
        self.frequencyRaw = frequency.rawValue
        self.startDate = startDate
        self.nextOccurrence = startDate
        self.group = group
        self.categoryRaw = category.rawValue
        self.splitMethodRaw = splitMethod.rawValue
        self.createdAt = Date()
    }
}

extension RecurringRule {
    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }

    var splitMethod: SplitMethod {
        get { SplitMethod(rawValue: splitMethodRaw) ?? .equal }
        set { splitMethodRaw = newValue.rawValue }
    }

    var splitPlan: RecurringSplitPlan {
        get {
            guard let splitPlanData,
                  let decoded = try? JSONDecoder().decode(RecurringSplitPlan.self, from: splitPlanData)
            else { return RecurringSplitPlan() }
            return decoded
        }
        set { splitPlanData = try? JSONEncoder().encode(newValue) }
    }

    var amount: Money { Money(minorUnits: amountMinorUnits, currencyCode: currencyCode) }

    var displayTitle: String {
        title.isEmpty ? String(localized: "Untitled recurring expense") : title
    }

    var hasEnded: Bool {
        guard let endDate else { return false }
        return nextOccurrence > endDate
    }

    /// "Monthly · next on 1 Sep"
    var scheduleSummary: String {
        let dateText = nextOccurrence.formatted(.dateTime.day().month(.abbreviated))
        return "\(frequency.title) · \(String(format: String(localized: "next %@", comment: "Next occurrence date"), dateText))"
    }
}
