import LocalAuthentication
import Observation
import SwiftUI

/// Optional Face ID / Touch ID gate in front of the app.
///
/// A shared ledger is a record of who you spend time and money with, which is
/// worth protecting. Off by default; when on, it's checked on cold launch and
/// after the app has been backgrounded.
@Observable
@MainActor
final class AppLockState {
    private(set) var isUnlocked = true
    private(set) var lastFailureMessage: String?

    /// Grace period after backgrounding before we re-prompt, so switching apps
    /// to check a bank balance doesn't mean authenticating twice.
    private static let graceInterval: TimeInterval = 60
    private var backgroundedAt: Date?

    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return context.biometryType
    }

    var isBiometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var biometryName: String {
        switch biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: String(localized: "your passcode")
        }
    }

    func lockIfNeeded(enabled: Bool) {
        guard enabled else {
            isUnlocked = true
            return
        }
        isUnlocked = false
    }

    func noteEnteredBackground() {
        backgroundedAt = Date()
    }

    func noteBecameActive(lockEnabled: Bool) {
        guard lockEnabled else {
            isUnlocked = true
            return
        }
        guard let backgroundedAt else { return }
        if Date().timeIntervalSince(backgroundedAt) > Self.graceInterval {
            isUnlocked = false
        }
        self.backgroundedAt = nil
    }

    func authenticate() async {
        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "Use passcode")

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set means nothing to authenticate against - don't
            // strand the user outside their own data.
            isUnlocked = true
            return
        }

        do {
            let reason = String(localized: "Unlock SplitFree", comment: "Face ID prompt")
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            isUnlocked = success
            lastFailureMessage = success ? nil : String(localized: "Authentication failed.")
        } catch {
            lastFailureMessage = error.localizedDescription
        }
    }
}

/// The screen shown while locked.
struct LockScreen: View {
    @Environment(AppLockState.self) private var lock

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(Palette.accentSoft).frame(width: 104, height: 104)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }

                Text("SplitFree is locked")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.primaryText)

                Text("Unlock with \(lock.biometryName) to see your balances.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)

                if let message = lock.lastFailureMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.negative)
                }

                Button {
                    Task { await lock.authenticate() }
                } label: {
                    Text("Unlock")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 48)
                .padding(.top, 8)
            }
            .padding(Metrics.screenPadding)
        }
        .task { await lock.authenticate() }
    }
}
