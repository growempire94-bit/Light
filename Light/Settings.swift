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

/// Forgiving comparison of Wi‑Fi names: the user may type the name from memory.
/// Ignores case, spaces and punctuation (`_ - .` …) and allows 1–2 wrong letters.
enum SSIDMatcher {
    static func matches(_ ssid: String, _ typed: String) -> Bool {
        let a = normalize(ssid)
        let b = normalize(typed)
        if a.isEmpty || b.isEmpty { return a == b }
        if a == b { return true }
        let shorter = min(a.count, b.count)
        // Short names are risky to match loosely; long ones may have up to 2 typos.
        let allowed = shorter >= 6 ? 2 : (shorter >= 3 ? 1 : 0)
        return distance(a, b) <= allowed
    }

    static func normalize(_ s: String) -> [Character] {
        Array(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Levenshtein distance (insert / delete / replace one character = 1).
    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
