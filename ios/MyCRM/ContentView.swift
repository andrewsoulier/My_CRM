import MyCRMShared
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var locationReporter: LocationReporter
    @State private var baseURLText: String = AppConfig.baseURL?.absoluteString ?? "http://100.x.y.z:8787"
    @State private var tokenText: String = AppConfig.apiToken ?? ""
    @State private var healthText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac CRM") {
                    TextField("Base URL (Tailscale)", text: $baseURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("API token", text: $tokenText)
                    Button("Save connection") {
                        AppConfig.baseURL = URL(string: baseURLText.trimmingCharacters(in: .whitespacesAndNewlines))
                        AppConfig.apiToken = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
                        healthText = "Saved."
                    }
                    Button("Test /health") {
                        Task {
                            do {
                                let ok = try await APIClient().health()
                                healthText = ok ? "Server OK" : "Server responded not ok"
                            } catch {
                                healthText = error.localizedDescription
                            }
                        }
                    }
                    if !healthText.isEmpty {
                        Text(healthText)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Location") {
                    LabeledContent("Permission", value: authLabel)
                    LabeledContent("Updating", value: locationReporter.isUpdating ? "Yes" : "No")
                    if let sample = locationReporter.lastSample {
                        LabeledContent("Last fix", value: String(format: "%.5f, %.5f", sample.latitude, sample.longitude))
                    }
                    Text(locationReporter.lastUploadMessage)
                        .foregroundStyle(.secondary)
                    Button("Request Always permission") {
                        locationReporter.requestPermissions()
                    }
                    Button(locationReporter.isUpdating ? "Stop reporting" : "Start reporting") {
                        if locationReporter.isUpdating {
                            locationReporter.stop()
                        } else {
                            locationReporter.start()
                        }
                    }
                }

                Section("Roadmap") {
                    Text("v1: location → CRM messages")
                    Text("Next: chat UI in this app")
                    Text("Next: custom keyboard extension")
                    Text("Next: iMessage extension")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("My CRM")
        }
    }

    private var authLabel: String {
        switch locationReporter.authorizationStatus {
        case .notDetermined: return "Not determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "When In Use"
        @unknown default: return "Unknown"
        }
    }
}
