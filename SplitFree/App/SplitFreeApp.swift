import SwiftData
import SwiftUI

@main
struct SplitFreeApp: App {
    @State private var settings = AppSettings()
    @State private var exchangeRates = ExchangeRateService()
    @State private var lockState = AppLockState()
    @State private var sync = SyncEngine()

    private let container: ModelContainer

    init() {
        container = SplitFreeApp.makeContainer()
        Haptics.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(exchangeRates)
                .environment(lockState)
                .environment(sync)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(Palette.accent)
        }
        .modelContainer(container)
    }

    /// Builds the store, preferring CloudKit-backed sync and degrading to a
    /// local-only store when the app isn't signed with an iCloud entitlement
    /// (simulator, unsigned builds, or a user who turned sync off).
    ///
    /// The final fallback is an in-memory store: the app must always launch,
    /// even if the on-disk store is unreadable.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Participant.self,
            SpendingGroup.self,
            Expense.self,
            ExpensePayer.self,
            ExpenseShare.self,
            ExpenseLineItem.self,
            ExpenseComment.self,
            Settlement.self,
            RecurringRule.self,
            SplitTemplate.self,
            ActivityEntry.self,
            SyncTombstone.self,
        ])

        let syncEnabled = UserDefaults.standard.object(forKey: "settings.cloudSyncEnabled") as? Bool ?? true

        if syncEnabled {
            let cloudConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
                return container
            }
        }

        let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [localConfig]) {
            return container
        }

        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // If even an in-memory store can't be built the schema itself is broken,
        // which is a programmer error rather than a runtime condition.
        return try! ModelContainer(for: schema, configurations: [memoryConfig])
    }
}
