import CoreLocation
import Foundation
import MyCRMShared
import UIKit

@MainActor
final class LocationReporter: NSObject, ObservableObject {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastSample: LocationSamplePayload?
    @Published var lastUploadMessage: String = "Not started"
    @Published var isUpdating = false

    private let manager = CLLocationManager()
    private let client = APIClient()
    private var lastUploadAt: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = true
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermissions() {
        manager.requestAlwaysAuthorization()
    }

    func start() {
        guard AppConfig.isConfigured else {
            lastUploadMessage = "Configure server URL and token first."
            return
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            manager.startMonitoringSignificantLocationChanges()
            isUpdating = true
            lastUploadMessage = "Listening for location…"
        default:
            requestPermissions()
            lastUploadMessage = "Waiting for location permission…"
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        isUpdating = false
        lastUploadMessage = "Stopped"
    }

    private func maybeUpload(_ location: CLLocation) async {
        if let lastUploadAt, Date().timeIntervalSince(lastUploadAt) < 30 {
            return
        }
        let sample = LocationSamplePayload(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyM: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            altitudeM: location.verticalAccuracy >= 0 ? location.altitude : nil,
            speedMps: location.speed >= 0 ? location.speed : nil,
            recordedAt: location.timestamp,
            source: "ios",
            deviceId: UIDevice.current.identifierForVendor?.uuidString
        )
        lastSample = sample
        do {
            let response = try await client.uploadLocation(sample)
            lastUploadAt = Date()
            lastUploadMessage =
                "Uploaded #\(response.id); located \(response.messagesLocated) message(s)"
        } catch {
            lastUploadMessage = error.localizedDescription
        }
    }
}

extension LocationReporter: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways
                || manager.authorizationStatus == .authorizedWhenInUse
            {
                self.start()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await self.maybeUpload(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastUploadMessage = error.localizedDescription
        }
    }
}
