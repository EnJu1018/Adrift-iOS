import CoreLocation
import Foundation

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastLocation: CLLocation?
    @Published var errorMessage: String?

    private let manager = CLLocationManager()

    var accuracyType: String {
        manager.accuracyAuthorization == .reducedAccuracy ? "approximate" : "precise"
    }

    func freshLocation() async throws -> CLLocation {
        requestAuthorization()
        for _ in 0..<100 {
            try Task.checkCancellation()
            if let location = lastLocation, abs(location.timestamp.timeIntervalSinceNow) < 30,
               location.horizontalAccuracy >= 0 {
                return location
            }
            if authorizationStatus == .denied || authorizationStatus == .restricted {
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw APIError.server(message: errorMessage ?? "無法取得最新位置，請稍後再試", statusCode: 0)
    }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestAuthorization() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            requestLocation()
        } else {
            errorMessage = "請到設定允許定位，才能顯示目前位置。"
        }
    }

    func requestLocation() {
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            requestLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            errorMessage = "請到設定允許定位，才能顯示目前位置。"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "無法取得目前定位"
    }
}
