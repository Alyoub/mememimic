import UIKit

@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notify = UINotificationFeedbackGenerator()

    /// Settings → Vibration.
    static var enabled = true

    static func tap() { if enabled { light.impactOccurred() } }
    static func tick() { if enabled { rigid.impactOccurred(intensity: 0.7) } }
    static func thump() { if enabled { heavy.impactOccurred() } }
    static func select() { if enabled { selection.selectionChanged() } }
    static func success() { if enabled { notify.notificationOccurred(.success) } }
    static func warning() { if enabled { notify.notificationOccurred(.warning) } }
}
