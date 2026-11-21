import CoreLocation
import Foundation
import NetworkExtension

enum WiFiInfo {
    /// Name of the current Wi‑Fi network, or nil if iOS doesn't tell us.
    /// iOS only reveals the SSID when the app has the "Access Wi‑Fi Information"
    /// entitlement AND precise location permission.
    static func fetchSSID(_ completion: @escaping (String?) -> Void) {
        NEHotspotNetwork.fetchCurrent { network in
            let ssid = network?.ssid
            DispatchQueue.main.async { completion(ssid) }
        }
    }
}

/// Location permission is needed only so iOS shows us the Wi‑Fi name.
final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationPermission()

    @Published private(set) var status: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isPrecise = false

    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
        update()
    }

    var isAuthorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.update()
            PowerMonitor.shared.refresh(refetchSSID: true)
        }
    }

    private func update() {
        status = manager.authorizationStatus
        isPrecise = manager.accuracyAuthorization == .fullAccuracy
    }
}
