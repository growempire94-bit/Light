import Foundation

/// Keys for user settings stored in UserDefaults (also used by @AppStorage in views).
enum SettingsKey {
    static let homeSSID = "homeSSID"
    static let alarmEnabled = "alarmEnabled"
    static let alarmDuration = "alarmDuration"
    static let minOutage = "minOutage"
    static let maxVolume = "maxVolume"
    static let vibrate = "vibrate"
    static let notifyOnOff = "notifyOnOff"
}

/// Read-only access to the settings for non-UI code.
enum AppSettings {
    static let defaults: [String: Any] = [
        SettingsKey.homeSSID: "",
        SettingsKey.alarmEnabled: true,
        SettingsKey.alarmDuration: 60.0,
        SettingsKey.minOutage: 30.0,
        SettingsKey.maxVolume: true,
        SettingsKey.vibrate: true,
        SettingsKey.notifyOnOff: true,
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: defaults)
    }

    private static var store: UserDefaults { .standard }

    /// Home Wi‑Fi name. Empty string means "any Wi‑Fi network counts as home".
    static var homeSSID: String {
        (store.string(forKey: SettingsKey.homeSSID) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var alarmEnabled: Bool { store.bool(forKey: SettingsKey.alarmEnabled) }

    /// Alarm length in seconds. 0 = play until the user stops it.
    static var alarmDuration: TimeInterval { store.double(forKey: SettingsKey.alarmDuration) }

    /// Wi‑Fi drops shorter than this are ignored (router reboot, interference).
    static var minOutage: TimeInterval { store.double(forKey: SettingsKey.minOutage) }

    static var maxVolume: Bool { store.bool(forKey: SettingsKey.maxVolume) }
    static var vibrate: Bool { store.bool(forKey: SettingsKey.vibrate) }
    static var notifyOnOff: Bool { store.bool(forKey: SettingsKey.notifyOnOff) }
}
