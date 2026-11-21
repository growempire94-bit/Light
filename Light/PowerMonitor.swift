import Foundation
import Network

enum PowerState: String, Codable {
    case unknown     // ещё не знаем
    case on          // домашний Wi‑Fi виден → свет есть
    case pendingOff  // Wi‑Fi только что пропал, ждём: вдруг это короткий сбой
    case off         // Wi‑Fi пропал надолго → света нет
}

/// Watches the Wi‑Fi interface and turns its changes into power on/off events.
///
/// Idea: the home router is powered from the mains. When the power goes out,
/// the router turns off and the home Wi‑Fi disappears. When power returns,
/// the router boots and the iPhone joins the known network automatically —
/// even if mobile data is on (iOS always prefers a known Wi‑Fi).
/// We watch the Wi‑Fi interface specifically, not "internet in general",
/// so mobile data doesn't affect detection.
final class PowerMonitor: ObservableObject {
    static let shared = PowerMonitor()

    @Published private(set) var state: PowerState = .unknown
    @Published private(set) var stateSince = Date()
    @Published private(set) var wifiConnected = false
    @Published private(set) var onHomeNetwork = false
    @Published private(set) var currentSSID: String?
    @Published private(set) var isRunning = false

    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "light.wifi.monitor")
    private var pendingOffWork: DispatchWorkItem?
    private var periodicTimer: Timer?

    /// "Light is on since" value before a Wi‑Fi drop; restored if the drop was just a blip.
    private var onSinceBeforeDrop: Date?
    /// Discards stale SSID lookups after the network changed.
    private var lookupGeneration = 0
    /// SSID is cached for the current connection: in the background iOS
    /// may stop returning it, and we don't want to "forget" a foreign network.
    private var ssidKnown = false

    private let stateKey = "power.state"
    private let sinceKey = "power.since"
    private let onSinceKey = "power.onSinceBeforeDrop"

    private init() {
        AppSettings.registerDefaults()
        loadState()
    }

    // MARK: - Public API

    func start() {
        guard pathMonitor == nil else {
            refresh()
            return
        }
        isRunning = true
        NotificationManager.requestAuthorization()
        AudioManager.shared.startKeepAlive()

        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            DispatchQueue.main.async {
                self?.wifiChanged(up: up, refetchSSID: true)
            }
        }
        monitor.start(queue: monitorQueue)
        pathMonitor = monitor

        // Safety net in case some update was missed.
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh(refetchSSID: Bool = false) {
        AudioManager.shared.ensureKeepAlive()
        guard let path = pathMonitor?.currentPath else { return }
        wifiChanged(up: path.status == .satisfied, refetchSSID: refetchSSID)
    }

    func testAlarm() {
        AudioManager.shared.startAlarm(duration: 5,
                                       maxVolume: AppSettings.maxVolume,
                                       vibrate: AppSettings.vibrate)
    }

    func stopAlarm() {
        AudioManager.shared.stopAlarm()
    }

    // MARK: - Wi‑Fi handling

    private func wifiChanged(up: Bool, refetchSSID: Bool) {
        let wasUp = wifiConnected
        wifiConnected = up

        guard up else {
            lookupGeneration += 1
            currentSSID = nil
            ssidKnown = false
            evaluate(homeWiFiUp: false)
            return
        }

        if !wasUp {
            // A new Wi‑Fi connection: forget the cached name.
            currentSSID = nil
            ssidKnown = false
        }

        if refetchSSID || !ssidKnown {
            lookupGeneration += 1
            let generation = lookupGeneration
            WiFiInfo.fetchSSID { [weak self] ssid in
                guard let self, generation == self.lookupGeneration, self.wifiConnected else { return }
                if let ssid {
                    self.currentSSID = ssid
                    self.ssidKnown = true
                }
                self.evaluate(homeWiFiUp: self.isHome(self.currentSSID))
            }
        } else {
            evaluate(homeWiFiUp: isHome(currentSSID))
        }
    }

    private func isHome(_ ssid: String?) -> Bool {
        let home = AppSettings.homeSSID
        // No home network configured, or iOS doesn't reveal the name → any Wi‑Fi counts.
        guard !home.isEmpty, let ssid else { return true }
        return SSIDMatcher.matches(ssid, home)
    }

    // MARK: - State machine

    private func evaluate(homeWiFiUp up: Bool) {
        onHomeNetwork = up
        let now = Date()

        if up {
            switch state {
            case .unknown:
                setState(.on, since: now)
            case .on:
                break
            case .pendingOff:
                cancelPendingOff()
                if now.timeIntervalSince(stateSince) >= AppSettings.minOutage {
                    // The outage was long enough, the app just didn't get to record it in time.
                    EventLog.shared.add(.off, date: stateSince)
                    powerRestored(outageStart: stateSince, now: now)
                } else {
                    // A short blip (router reboot, interference) — not a power cut.
                    let since = onSinceBeforeDrop ?? now
                    onSinceBeforeDrop = nil
                    setState(.on, since: since)
                }
            case .off:
                powerRestored(outageStart: stateSince, now: now)
            }
        } else {
            switch state {
            case .unknown, .on:
                onSinceBeforeDrop = state == .on ? stateSince : nil
                setState(.pendingOff, since: now)
                schedulePendingOff()
            case .pendingOff:
                if pendingOffWork == nil {
                    schedulePendingOff()
                }
            case .off:
                break
            }
        }
    }

    private func schedulePendingOff() {
        pendingOffWork?.cancel()
        let delay = max(0, AppSettings.minOutage - Date().timeIntervalSince(stateSince))
        let work = DispatchWorkItem { [weak self] in
            self?.commitOff()
        }
        pendingOffWork = work
        // Wall clock keeps counting while the phone sleeps.
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + delay, execute: work)
    }

    private func cancelPendingOff() {
        pendingOffWork?.cancel()
        pendingOffWork = nil
    }

    private func commitOff() {
        pendingOffWork = nil
        guard state == .pendingOff else { return }
        let since = stateSince
        onSinceBeforeDrop = nil
        setState(.off, since: since)
        EventLog.shared.add(.off, date: since)
        if AppSettings.notifyOnOff {
            NotificationManager.post(title: "Свет пропал",
                                     body: "Домашний Wi‑Fi пропал в \(Format.time(since)).")
        }
    }

    private func powerRestored(outageStart: Date, now: Date) {
        let duration = now.timeIntervalSince(outageStart)
        onSinceBeforeDrop = nil
        setState(.on, since: now)
        EventLog.shared.add(.on, date: now, outageDuration: duration)

        if AppSettings.alarmEnabled {
            AudioManager.shared.startAlarm(duration: AppSettings.alarmDuration,
                                           maxVolume: AppSettings.maxVolume,
                                           vibrate: AppSettings.vibrate)
        }
        NotificationManager.post(title: "💡 Свет появился!",
                                 body: "Домашний Wi‑Fi снова в сети. Света не было \(Format.duration(duration)).")
    }

    // MARK: - Persistence (survives app restarts)

    private func setState(_ newState: PowerState, since: Date) {
        state = newState
        stateSince = since
        let defaults = UserDefaults.standard
        defaults.set(newState.rawValue, forKey: stateKey)
        defaults.set(since.timeIntervalSince1970, forKey: sinceKey)
        if let onSince = onSinceBeforeDrop {
            defaults.set(onSince.timeIntervalSince1970, forKey: onSinceKey)
        } else {
            defaults.removeObject(forKey: onSinceKey)
        }
    }

    private func loadState() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: stateKey),
              let saved = PowerState(rawValue: raw) else { return }
        state = saved
        stateSince = Date(timeIntervalSince1970: defaults.double(forKey: sinceKey))
        if defaults.object(forKey: onSinceKey) != nil {
            onSinceBeforeDrop = Date(timeIntervalSince1970: defaults.double(forKey: onSinceKey))
        }
    }
}
