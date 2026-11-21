import SwiftUI
import UserNotifications

@main
struct LightApp: App {
    @StateObject private var monitor = PowerMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Start immediately: the app may also be launched in the background
        // (for example by a Shortcuts automation), without any UI.
        PowerMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                monitor.refresh(refetchSSID: true)
            }
        }
    }
}
