import Foundation
import Observation
import SwiftUI

/// Device-level preferences, persisted in `UserDefaults`.
///
/// Deliberately separate from the SwiftData store: these describe how *this*
/// device shows the data, not the data itself.
@Observable
@MainActor
final class AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.baseCurrencyCode = defaults.string(forKey: Keys.baseCurrency) ?? Currency.deviceDefaultCode
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
        self.simplifyDebtsByDefault = defaults.object(forKey: Keys.simplifyDefault) as? Bool ?? false
        self.convertToBaseCurrency = defaults.object(forKey: Keys.convertToBase) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        self.requiresBiometricUnlock = defaults.bool(forKey: Keys.biometricLock)
        self.appearanceRaw = defaults.string(forKey: Keys.appearance) ?? Appearance.system.rawValue
        self.recentCurrencyCodes = defaults.stringArray(forKey: Keys.recentCurrencies) ?? []
        self.cloudSyncEnabled = defaults.object(forKey: Keys.cloudSync) as? Bool ?? true
        self.lastRecurringCheck = defaults.object(forKey: Keys.lastRecurringCheck) as? Date
    }

    /// Currency the home-screen totals are expressed in.
    var baseCurrencyCode: String {
        didSet { defaults.set(baseCurrencyCode, forKey: Keys.baseCurrency) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded) }
    }

    /// New groups start with debt simplification on.
    var simplifyDebtsByDefault: Bool {
        didSet { defaults.set(simplifyDebtsByDefault, forKey: Keys.simplifyDefault) }
    }

    /// Roll multi-currency balances into one base-currency figure on summaries.
    var convertToBaseCurrency: Bool {
        didSet { defaults.set(convertToBaseCurrency, forKey: Keys.convertToBase) }
    }

    var hapticsEnabled: Bool {
        didSet {
            defaults.set(hapticsEnabled, forKey: Keys.haptics)
            Haptics.isEnabled = hapticsEnabled
        }
    }

    var requiresBiometricUnlock: Bool {
        didSet { defaults.set(requiresBiometricUnlock, forKey: Keys.biometricLock) }
    }

    var appearanceRaw: String {
        didSet { defaults.set(appearanceRaw, forKey: Keys.appearance) }
    }

    var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    /// Currencies used recently, floated to the top of the picker.
    var recentCurrencyCodes: [String] {
        didSet { defaults.set(recentCurrencyCodes, forKey: Keys.recentCurrencies) }
    }

    var cloudSyncEnabled: Bool {
        didSet { defaults.set(cloudSyncEnabled, forKey: Keys.cloudSync) }
    }

    var lastRecurringCheck: Date? {
        didSet { defaults.set(lastRecurringCheck, forKey: Keys.lastRecurringCheck) }
    }

    func noteCurrencyUsed(_ code: String) {
        var updated = recentCurrencyCodes.filter { $0 != code }
        updated.insert(code, at: 0)
        recentCurrencyCodes = Array(updated.prefix(6))
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: String(localized: "Automatic")
            case .light: String(localized: "Light")
            case .dark: String(localized: "Dark")
            }
        }

        var symbol: String {
            switch self {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max.fill"
            case .dark: "moon.fill"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    private enum Keys {
        static let baseCurrency = "settings.baseCurrency"
        static let onboarded = "settings.hasCompletedOnboarding"
        static let simplifyDefault = "settings.simplifyDebtsByDefault"
        static let convertToBase = "settings.convertToBaseCurrency"
        static let haptics = "settings.hapticsEnabled"
        static let biometricLock = "settings.requiresBiometricUnlock"
        static let appearance = "settings.appearance"
        static let recentCurrencies = "settings.recentCurrencies"
        static let cloudSync = "settings.cloudSyncEnabled"
        static let lastRecurringCheck = "settings.lastRecurringCheck"
    }
}
