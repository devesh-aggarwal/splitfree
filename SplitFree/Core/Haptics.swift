import UIKit

/// Thin wrapper over UIKit feedback generators.
///
/// Haptics here are used sparingly and only to confirm something changed in the
/// world: an expense saved, a debt settled, a split rebalanced. Never for mere
/// navigation.
@MainActor
enum Haptics {
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// A value changed under the user's finger, like toggling a person into a split.
    static func selectionChanged() {
        selection.selectionChanged()
    }

    /// A light confirmation, like adding a line item or stepping a share count.
    static func tick() {
        impactLight.impactOccurred()
    }

    /// A firmer confirmation: a sheet committed.
    static func commit() {
        impactMedium.impactOccurred()
    }

    /// Something snapped into place: the split now balances exactly.
    static func snap() {
        impactRigid.impactOccurred()
    }

    static func success() {
        notification.notificationOccurred(.success)
    }

    static func warning() {
        notification.notificationOccurred(.warning)
    }

    static func error() {
        notification.notificationOccurred(.error)
    }

    /// Warms the haptic engine so the first tap isn't late.
    static func prepare() {
        impactLight.prepare()
        selection.prepare()
    }
}
