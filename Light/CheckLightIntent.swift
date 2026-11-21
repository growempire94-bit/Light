import AppIntents

/// Action for the Shortcuts app ("Команды").
///
/// Backup for the case when iOS or the user closed the app: create a personal
/// automation "When iPhone joins Wi‑Fi <home network>" → "Проверить свет".
/// iOS will relaunch the app in the background; it sees that the light was
/// off before and the home Wi‑Fi is back, and plays the alarm.
struct CheckLightIntent: AppIntent {
    static let title: LocalizedStringResource = "Проверить свет"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            PowerMonitor.shared.start()
            PowerMonitor.shared.refresh(refetchSSID: true)
        }
        // Give the Wi‑Fi monitor a moment to report the current network.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await MainActor.run {
            PowerMonitor.shared.refresh()
        }
        return .result()
    }
}
