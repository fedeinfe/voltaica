import Foundation
import Observation
import SwiftUI

/// Purely visual choices. They live in user defaults rather than in the policy, because the
/// daemon has no business knowing what the menu bar looks like.
@Observable
final class Preferences {
    @MainActor static let shared = Preferences()

    @ObservationIgnored private let defaults = UserDefaults.standard

    var showPercentage: Bool {
        didSet { defaults.set(showPercentage, forKey: Keys.showPercentage) }
    }
    var colouredIcon: Bool {
        didSet { defaults.set(colouredIcon, forKey: Keys.colouredIcon) }
    }
    var showHardwarePercentage: Bool {
        didSet { defaults.set(showHardwarePercentage, forKey: Keys.showHardwarePercentage) }
    }
    var hasSeenOnboarding: Bool {
        didSet { defaults.set(hasSeenOnboarding, forKey: Keys.hasSeenOnboarding) }
    }

    private enum Keys {
        static let showPercentage = "showPercentage"
        static let colouredIcon = "colouredIcon"
        static let showHardwarePercentage = "showHardwarePercentage"
        static let hasSeenOnboarding = "hasSeenOnboarding"
    }

    init() {
        defaults.register(defaults: [
            Keys.showPercentage: true,
            Keys.colouredIcon: false,
            Keys.showHardwarePercentage: true,
            Keys.hasSeenOnboarding: false
        ])
        showPercentage = defaults.bool(forKey: Keys.showPercentage)
        colouredIcon = defaults.bool(forKey: Keys.colouredIcon)
        showHardwarePercentage = defaults.bool(forKey: Keys.showHardwarePercentage)
        hasSeenOnboarding = defaults.bool(forKey: Keys.hasSeenOnboarding)
    }
}
