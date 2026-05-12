import Foundation

struct SettingsStore {
    enum Keys {
        static let autoPaste = "autoPaste"
        static let muteAudioWhileListening = "muteAudioWhileListening"
        static let pauseMediaWhileListening = "pauseMediaWhileListening"
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

    var muteAudioWhileListening: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.muteAudioWhileListening) != nil {
                return UserDefaults.standard.bool(forKey: Keys.muteAudioWhileListening)
            }

            if UserDefaults.standard.object(forKey: Keys.pauseMediaWhileListening) == nil {
                return true
            }

            return UserDefaults.standard.bool(forKey: Keys.pauseMediaWhileListening)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.muteAudioWhileListening)
        }
    }
}
