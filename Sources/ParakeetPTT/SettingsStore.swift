import Foundation

struct SettingsStore {
    enum Keys {
        static let autoPaste = "autoPaste"
    }

    var autoPaste: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.autoPaste) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.autoPaste)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.autoPaste)
        }
    }
}
