import Foundation

/// Persistent settings for which triggers activate Menu3.
final class TriggerSettings: ObservableObject {
    static let shared = TriggerSettings()

    private let defaults = UserDefaults.standard

    private enum Key: String {
        case middleClick = "trigger.middleClick"
        case threeFingerTap = "trigger.threeFingerTap"
        case threeFingerPress = "trigger.threeFingerPress"
        case optionThreeFingerTap = "trigger.optionThreeFingerTap"
        case optionThreeFingerPress = "trigger.optionThreeFingerPress"
        case screenshotEnabled = "feature.screenshotEnabled"
    }

    @Published var middleClick: Bool {
        didSet { defaults.set(middleClick, forKey: Key.middleClick.rawValue) }
    }

    @Published var threeFingerTap: Bool {
        didSet { defaults.set(threeFingerTap, forKey: Key.threeFingerTap.rawValue) }
    }

    @Published var threeFingerPress: Bool {
        didSet { defaults.set(threeFingerPress, forKey: Key.threeFingerPress.rawValue) }
    }

    @Published var optionThreeFingerTap: Bool {
        didSet { defaults.set(optionThreeFingerTap, forKey: Key.optionThreeFingerTap.rawValue) }
    }

    @Published var optionThreeFingerPress: Bool {
        didSet { defaults.set(optionThreeFingerPress, forKey: Key.optionThreeFingerPress.rawValue) }
    }

    @Published var screenshotEnabled: Bool {
        didSet {
            defaults.set(screenshotEnabled, forKey: Key.screenshotEnabled.rawValue)
        }
    }

    private init() {
        let d = UserDefaults.standard
        // Defaults: middle click + three-finger tap ON
        if d.object(forKey: Key.middleClick.rawValue) == nil {
            d.set(true, forKey: Key.middleClick.rawValue)
        }
        if d.object(forKey: Key.threeFingerTap.rawValue) == nil {
            d.set(true, forKey: Key.threeFingerTap.rawValue)
        }

        middleClick = d.bool(forKey: Key.middleClick.rawValue)
        threeFingerTap = d.bool(forKey: Key.threeFingerTap.rawValue)
        threeFingerPress = d.bool(forKey: Key.threeFingerPress.rawValue)
        optionThreeFingerTap = d.bool(forKey: Key.optionThreeFingerTap.rawValue)
        optionThreeFingerPress = d.bool(forKey: Key.optionThreeFingerPress.rawValue)
        screenshotEnabled = d.bool(forKey: Key.screenshotEnabled.rawValue)
    }
}
